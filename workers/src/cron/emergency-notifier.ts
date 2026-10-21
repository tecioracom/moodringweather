// workers/src/cron/emergency-notifier.ts
//
// 緊急通知 3 種(熱中症 / 暴風 / 大雪)の判定と FCM 配信。
// 発火ルールの正本: docs/mri-spec.md §5.3(2026-06-11 改訂で予報 33/35・暴風 20/30・
// 大雪 3/5 に統一)。純ロジックは ../lib/forecast-emergency.ts に分離済み。
// spec.md §12.2.1(永久無料) / §12.10(WBGT) / §12.3(重複抑制)に準拠。
//
// ステータス: 配信経路は実装済み (docs/fcm-activation-plan-v1.3.0.md S7)。
//   配信が実際に発生するのは、Firestore `push_subscriptions` に購読が存在し
//   (クライアント側 S8)、Workers に FIREBASE_SA_JSON / FIRESTORE_PROJECT_ID が投入され
//   (S5)、KV namespace が結線されてから (S4)。それまでは購読 0 件 = 配信 0 件で無害。
//
// 設計方針:
//   - 「対象ユーザー = 購読地点を登録している全員」(無料/Plus 不問。§12.2.1)。
//     本ファイルは課金状態・NotificationPreferences (quietHours / dailyLimit) を一切参照しない。
//   - 配信はクライアント側で l10n 表示できる data payload を必ず同梱する
//     (契約: ../lib/forecast-emergency.ts buildEmergencyDataPayload /
//      Dart 側 lib/domain/safety/emergency_push_payload.dart)
//   - title/body はサーバー側フォールバック表示用(iOS ハイブリッド配信。設計 doc §6)。
//     購読の locale で 4 言語 (ja/en/es/zh) を選び、免責文(spec §12.10.4)を全種別で併記する。
//     文言は lib/l10n/app_*.arb の emergency*Forecast キーと同一 (予報表現。端末表示と揃える)。
//   - 購読は 200 件ページ単位で走査し、1 ページを処理してから次を取る (CPU / メモリ一定)。
//     同一の粗い座標 (小数 1 桁) は 1 回の Cron 内で Open-Meteo 取得を共有する。

import { fetchForecast, type OpenMeteoForecast } from '../lib/open-meteo';
import { calcWbgt } from '../lib/wbgt';
import {
  buildEmergencyDataPayload,
  dailyMax,
  dedupeKeyOf,
  judgeForecastHeat,
  judgeForecastSnow,
  judgeForecastWind,
  maxOverHours,
  targetJstDate,
  type EmergencyCronTrigger,
  type ForecastJudgement,
} from '../lib/forecast-emergency';
import { isCoolingDown, markSent } from '../lib/dedupe';
import { sendFcm, type Notification } from '../lib/fcm';
import { FCM_SCOPE, FIRESTORE_SCOPE, getGoogleAccessToken } from '../lib/google-auth';
import {
  deleteSubscription,
  iterateActiveSubscriptions,
  type PushSubscription,
} from '../lib/push-subscriptions';

export type { EmergencyCronTrigger } from '../lib/forecast-emergency';

export interface Env {
  OPEN_METEO_BASE: string;
  FIRESTORE_PROJECT_ID: string;
  /** サービスアカウント JSON (wrangler secret put FIREBASE_SA_JSON)。Firestore 読み出しと FCM 送信に共用 */
  FIREBASE_SA_JSON: string;
  ALERT_DEDUPE: KVNamespace;
}

export interface UserRecord {
  uid: string;
  lat: number;
  lon: number;
  fcmToken: string;
  platform: 'ios' | 'android';
  /** 表示言語(BCP 47)。iOS ハイブリッド配信の本文言語選択に使う(設計 doc §6) */
  locale: string;
  /** 緊急通知は課金不問 (spec §12.2.1)。参照しないが型互換のため残す。常に false */
}

export interface EmergencyRunResult {
  scanned: number;
  pushed: number;
  /** FCM 404 (UNREGISTERED) で削除した購読数 */
  invalidated: number;
}

export async function runEmergencyCheck(
  env: Env,
  trigger: EmergencyCronTrigger,
  nowUtc: Date = new Date(),
): Promise<EmergencyRunResult> {
  const firestoreToken = await getGoogleAccessToken(env.FIREBASE_SA_JSON, FIRESTORE_SCOPE);
  const fcmToken = await getGoogleAccessToken(env.FIREBASE_SA_JSON, FCM_SCOPE);

  // 同一粗座標の予報を 1 回の Cron 内で共有 (購読は小数 1 桁に丸めた座標を持つ)。
  const forecastCache = new Map<string, Promise<OpenMeteoForecast>>();
  const forecastFor = (lat: number, lon: number): Promise<OpenMeteoForecast> => {
    const key = `${lat.toFixed(1)},${lon.toFixed(1)}`;
    let p = forecastCache.get(key);
    if (!p) {
      p = fetchForecast(lat, lon, env.OPEN_METEO_BASE);
      forecastCache.set(key, p);
    }
    return p;
  };

  const result: EmergencyRunResult = { scanned: 0, pushed: 0, invalidated: 0 };

  for await (const page of loadOptedInUsers(env, firestoreToken, nowUtc)) {
    for (const user of page) {
      result.scanned += 1;
      try {
        const forecast = await forecastFor(user.lat, user.lon);

        // 緊急 3 種はオプトアウト経路を持たない(spec §12.2.1: 常時 ON・永久無料)。
        const alerts: Notification[] = [];
        const heat = evaluateHeatStroke(forecast, trigger, nowUtc, user.locale);
        if (heat) alerts.push(heat);
        const wind = evaluateStrongWind(forecast, user.locale);
        if (wind) alerts.push(wind);
        const snow = evaluateHeavySnow(forecast, user.locale);
        if (snow) alerts.push(snow);

        for (const a of alerts) {
          // dedup は「種別 × 深刻度」(data payload に同梱したキーを使用)。
          // 深刻度が上がるとキーが変わり即時再送される(安全側・Dart 側と同じ規則)。
          const dedupeKey = a.data?.dedupe ?? a.kind;
          if (await isCoolingDown(env.ALERT_DEDUPE, user.uid, dedupeKey)) continue;
          const res = await sendFcm(
            fcmToken,
            env.FIRESTORE_PROJECT_ID,
            { fcmToken: user.fcmToken, platform: user.platform },
            a,
          );
          if (res.ok) {
            await markSent(env.ALERT_DEDUPE, user.uid, dedupeKey);
            result.pushed += 1;
          } else if (res.status === 404) {
            // UNREGISTERED: 端末側でトークンが失効。購読を掃除して以降の送信を止める (設計 §4.2)。
            console.warn('[fcm-unregistered]', user.uid);
            try {
              await deleteSubscription(env.FIRESTORE_PROJECT_ID, firestoreToken, user.uid);
              result.invalidated += 1;
            } catch (e) {
              console.error('[subscription-delete-fail]', user.uid, (e as Error).message);
            }
            break; // 同一ユーザーの残りアラートも送れない
          } else {
            console.error('[fcm-fail]', user.uid, a.kind, res.status, res.body);
          }
        }
      } catch (e) {
        console.error('[user-eval-fail]', user.uid, (e as Error).message);
      }
    }
  }

  return result;
}

// ──────────────────────────────────────────────────────────────────
// 個別判定(しきい値・ゲーティングは forecast-emergency.ts の純関数に委譲)
// ──────────────────────────────────────────────────────────────────

/**
 * 熱中症(予報日最高 WBGT)。mri-spec §5.3.2:
 *   - heat_morning(当日 5:00 JST) → 当日の日最高 WBGT を判定
 *   - heat_evening(前日 17:00 JST)/ heat_special(前日 14:00 JST) → 翌日を判定
 *   - periodic では発火しない(実況 31/33 はクライアント v1.0 ルールが並走)
 */
export function evaluateHeatStroke(
  forecast: OpenMeteoForecast,
  trigger: EmergencyCronTrigger,
  nowUtc: Date = new Date(),
  locale: string = 'ja',
): Notification | null {
  if (trigger === 'periodic') return null;

  const wbgtSeries = forecast.hourly.time.map((_, i) =>
    calcWbgt({
      temperatureC: forecast.hourly.temperature_2m[i],
      relativeHumidity: forecast.hourly.relative_humidity_2m[i],
      shortwaveRadiation: forecast.hourly.shortwave_radiation[i],
      windSpeed: forecast.hourly.wind_speed_10m[i],
    }).wbgt,
  );
  // Open-Meteo は timezone=Asia/Tokyo で取得済み(open-meteo.ts)
  const maxWbgt = dailyMax(
    forecast.hourly.time,
    wbgtSeries,
    targetJstDate(trigger, nowUtc),
  );

  const j = judgeForecastHeat(maxWbgt, trigger);
  if (!j) return null;
  return buildNotification(j, locale);
}

/** 暴風: 直近 24h の平均風速最大値で判定(mri-spec §5.3.3: 20/30 m/s。gusts 不使用)。 */
export function evaluateStrongWind(
  forecast: OpenMeteoForecast,
  locale: string = 'ja',
): Notification | null {
  const peak = maxOverHours(forecast.hourly.wind_speed_10m, 24);
  const j = judgeForecastWind(peak);
  if (!j) return null;
  return buildNotification(j, locale);
}

/** 大雪: 直近 24h の 1 時間降雪量最大値で判定(mri-spec §5.3.3: 3/5 cm/h)。 */
export function evaluateHeavySnow(
  forecast: OpenMeteoForecast,
  locale: string = 'ja',
): Notification | null {
  const peak = maxOverHours(forecast.hourly.snowfall, 24);
  const j = judgeForecastSnow(peak);
  if (!j) return null;
  return buildNotification(j, locale);
}

// ──────────────────────────────────────────────────────────────────
// サーバー側フォールバック文言 (iOS ハイブリッド配信用)。4 言語。
// 正本は lib/l10n/app_{ja,en,es,zh}.arb の emergency*Forecast キー + emergencyDisclaimer。
// **予報の数値なので予報表現 (*Forecast) のみを使う** (現在値用キーは使わない)。
// 数値の整形は Dart 側 resolveEmergencyAlertMessage と同じ「整数に丸め」。
// 暴風の {wind} は単位込み (ARB に単位を書かない。compliance-review-v1.3.0 §9-4)。
// サーバーは利用者の風速の単位を知らないので「{n}\u00A0m/s」を埋める (アプリの
// m/s の設定と同一の文字列。iOS は OS がこの文面を出すため単位の設定は効かない = U9)。
// 同一文字列であることは test/emergency-notifier.test.ts が ARB を読んで検証する。
// ──────────────────────────────────────────────────────────────────

export type FallbackLang = 'ja' | 'en' | 'es' | 'zh';

interface FallbackStrings {
  heatTitle: string;
  heatBodySevere: (wbgt: string) => string;
  heatBodyDanger: (wbgt: string) => string;
  stormTitle: string;
  /** [wind] は単位込み (「22\u00A0m/s」)。 */
  stormBody: (wind: string) => string;
  snowTitle: string;
  snowBody: (snow: string) => string;
  disclaimer: string;
}

const FALLBACK: Record<FallbackLang, FallbackStrings> = {
  ja: {
    heatTitle: "熱中症アラート",
    heatBodySevere: (v) =>
      `予報の日最高 WBGT が約${v}°Cと、熱中症の危険性が非常に高い暑さになる見込みです。屋外活動を控え、こまめに水分補給をしてください。`,
    heatBodyDanger: (v) =>
      `予報の日最高 WBGT が約${v}°Cと、極めて危険な暑さになる見込みです。屋外活動は中止し、室内でも冷房と水分補給を徹底してください。`,
    stormTitle: "暴風アラート",
    stormBody: (v) =>
      `今後 24 時間に平均風速約${v}の暴風が予想されます。屋内にとどまり、窓から離れてください。`,
    snowTitle: "大雪アラート",
    snowBody: (v) =>
      `今後 24 時間に 1 時間あたり約${v}cmの降雪が予想されます。交通の乱れに注意し、不要な外出は控えてください。`,
    disclaimer:
      "本通知は気象データに基づく Mood-Ring Weather の独自推定であり、気象庁・環境省などの公式警報ではありません。最終的な判断は気象庁・環境省の公式情報をご確認ください。",
  },
  en: {
    heatTitle: "Heatstroke alert",
    heatBodySevere: (v) =>
      `Forecast daily peak heat index (WBGT) is expected to reach around ${v}°C — very high heatstroke risk. Avoid strenuous activity and drink water often.`,
    heatBodyDanger: (v) =>
      `Forecast daily peak heat index (WBGT) is expected to reach around ${v}°C — dangerous heat. Avoid going outside and stay hydrated.`,
    stormTitle: "Violent wind alert",
    stormBody: (v) =>
      `Winds around ${v} are expected within the next 24 hours. Stay indoors and away from windows.`,
    snowTitle: "Heavy snow alert",
    snowBody: (v) =>
      `Snowfall around ${v} cm per hour is expected within the next 24 hours. Expect travel disruption and avoid unnecessary trips.`,
    disclaimer:
      "Independent estimate by Mood-Ring Weather based on weather data — not an official government warning. Refer to official sources for final decisions.",
  },
  es: {
    heatTitle: "Alerta de golpe de calor",
    heatBodySevere: (v) =>
      `Se prevé que el índice de calor máximo diario (WBGT) alcance los ${v}°C: riesgo muy alto de golpe de calor. Evita el ejercicio intenso y bebe agua con frecuencia.`,
    heatBodyDanger: (v) =>
      `Se prevé que el índice de calor máximo diario (WBGT) alcance los ${v}°C: calor peligroso. Evita salir y mantente hidratado.`,
    stormTitle: "Alerta de viento violento",
    stormBody: (v) =>
      `Se prevén vientos de unos ${v} en las próximas 24 horas. Permanece en el interior y aléjate de las ventanas.`,
    snowTitle: "Alerta de nevada intensa",
    snowBody: (v) =>
      `Se prevé una nevada de unos ${v} cm por hora en las próximas 24 horas. Espera alteraciones en el transporte y evita desplazamientos innecesarios.`,
    disclaimer:
      "Estimación independiente de Mood-Ring Weather basada en datos meteorológicos; no es un aviso oficial de las autoridades. Consulta las fuentes oficiales para la decisión final.",
  },
  zh: {
    heatTitle: "中暑警示",
    heatBodySevere: (v) =>
      `预报的日最高暑热指数 (WBGT) 预计约为 ${v}°C，中暑风险非常高。请避免剧烈运动并及时补充水分。`,
    heatBodyDanger: (v) =>
      `预报的日最高暑热指数 (WBGT) 预计约为 ${v}°C，已达危险高温。请尽量避免外出并注意补水。`,
    stormTitle: "狂风警示",
    stormBody: (v) =>
      `未来 24 小时预计有风速约 ${v} 的大风。请留在室内并远离窗户。`,
    snowTitle: "暴雪警示",
    snowBody: (v) =>
      `未来 24 小时预计每小时降雪约 ${v} cm。请注意交通受阻，避免不必要的出行。`,
    disclaimer:
      "本提醒为 Mood-Ring Weather 基于气象数据的独立估算，并非政府部门发布的官方预警。最终判断请以官方信息为准。",
  },
};

/** BCP 47 → 対応 4 言語。未対応言語は英語にフォールバック。 */
export function fallbackLangOf(locale: string): FallbackLang {
  const lang = (locale || '').toLowerCase().split(/[-_]/)[0];
  return lang === 'ja' || lang === 'es' || lang === 'zh' ? lang : 'en';
}

/** 免責文(spec §12.10.4 / mri-spec §5.4)。本文末尾に必ず併記する。 */
export function disclaimerFor(locale: string): string {
  return FALLBACK[fallbackLangOf(locale)].disclaimer;
}

/** Judgement → FCM Notification。data payload(クライアント契約)+ dedup キーを同梱。 */
export function buildNotification(j: ForecastJudgement, locale: string = 'ja'): Notification {
  const s = FALLBACK[fallbackLangOf(locale)];
  // Dart 側 (metricValue.round()) と同じ整数丸め。data.metric は小数 1 桁のまま。
  const v = Math.round(j.metricValue).toString();
  let title: string;
  let body: string;
  switch (j.kind) {
    case 'heat_stroke':
      title = s.heatTitle;
      body = j.severity === 'danger' ? s.heatBodyDanger(v) : s.heatBodySevere(v);
      break;
    case 'strong_wind':
      title = s.stormTitle;
      // 単位込み。数値と単位は改行しない空白 (U+00A0) でつなぐ (アプリと同じ)。
      body = s.stormBody(`${v}\u00A0m/s`);
      break;
    case 'heavy_snow':
      title = s.snowTitle;
      body = s.snowBody(v);
      break;
  }
  return {
    title,
    body: `${body}\n${s.disclaimer}`,
    kind: j.kind,
    critical: j.severity === 'danger', // danger のみ Time-Sensitive(mri-spec §5.3)
    data: {
      ...buildEmergencyDataPayload(j),
      dedupe: dedupeKeyOf(j),
    },
  };
}

// ──────────────────────────────────────────────────────────────────
// 購読ユーザー取得(Firestore REST runQuery、サービスアカウント)
// ──────────────────────────────────────────────────────────────────

/**
 * `push_subscriptions` を 200 件ページ単位で列挙する (設計 §4.2 / 計画 S7)。
 * 名前の「OptedIn」は歴史的経緯: 緊急通知に opt-in/out は存在せず、
 * 「地点を登録している = 購読している」全員が対象 (spec §12.2.1)。
 */
async function* loadOptedInUsers(
  env: Env,
  firestoreToken: string,
  nowUtc: Date,
): AsyncGenerator<UserRecord[], void, void> {
  for await (const page of iterateActiveSubscriptions(env.FIRESTORE_PROJECT_ID, firestoreToken, nowUtc)) {
    yield page.map(toUserRecord);
  }
}

function toUserRecord(s: PushSubscription): UserRecord {
  return {
    uid: s.uid,
    lat: s.lat,
    lon: s.lon,
    fcmToken: s.fcmToken,
    platform: s.platform,
    locale: s.locale,
  };
}
