// workers/src/cron/personal-notifier.ts
//
// パーソナル通知 5 種(気圧 / 湿度 / AQI / UV / 花粉)の Workers Cron 配信。
// spec.md §12.2.3 / §12.3 / §12.4 / §12.6 / §12.8 / §12.9 / §12.11.3 準拠。
//
// 設計方針:
//   - 緊急通知(emergency-notifier.ts)とは別 Cron で発火する。チャネル ID も `mrw_personal`。
//   - 1 回 5〜10 分間隔(spec.md §12.4)で巡回。UV だけは「当日朝 1 回」運用とし、
//     KV の cooldown(uv_high = 12h)で多重送信を抑える。
//   - Plus(Advanced Safety, §12.11.3)は本ファイルでは未使用。Plus 専用のリードタイム延長は
//     別 Worker で扱う(spec.md の責務分離)。
//   - 静音時間(§12.3 デフォルト 22:00-7:00)はパーソナル通知では強制適用(緊急のみ例外)。
//   - 1 日上限はユーザー設定で 1-10。本 Worker では 1 ループ内の累計のみ判断し、日跨ぎは
//     Firestore 側の `users/{uid}/notificationCounter` で別途管理する想定。

import { fetchForecast, fetchAirQuality } from '../lib/open-meteo';
import { isCoolingDown, markSent } from '../lib/dedupe';
import { sendFcm, type Notification } from '../lib/fcm';
import {
  evaluatePersonalAlerts,
  type PersonalNotification,
  type PersonalOptIn,
  type PersonalSensitivity,
} from '../lib/personal-alerts';

export interface Env {
  OPEN_METEO_BASE: string;             // /v1/forecast
  OPEN_METEO_AIRQ_BASE: string;        // /v1/air-quality
  FIRESTORE_PROJECT_ID: string;
  FCM_ACCESS_TOKEN: string;
  ALERT_DEDUPE: KVNamespace;
}

export interface PersonalUserRecord {
  uid: string;
  lat: number;
  lon: number;
  fcmToken: string;
  platform: 'ios' | 'android';
  /** spec.md §12.3 静音時間。JST 24h "HH:MM" 表現 */
  quietHours: { start: string; end: string };
  /** 1 日あたりの送信上限(spec.md §12.3) */
  dailyLimit: number;
  /** 直近 24h で送信済み件数(Firestore から読む) */
  sentToday: number;
  /** spec.md §12.5 個別 ON/OFF(パーソナル 5 種) */
  optIn: PersonalOptIn;
  /** spec.md §12.6 感受性ベクトル */
  sensitivity: PersonalSensitivity;
}

/** 現在時刻 (UTC) を JST に変換し past_hours=6 を考慮した nowIdx を返す */
export function resolveNowIdx(
  hourlyTime: string[],
  nowUtc: Date,
): number {
  const isoHour = nowUtc.toISOString().slice(0, 13) + ':00'; // "YYYY-MM-DDTHH:00"
  // Open-Meteo は JST 表記 ("Asia/Tokyo") + past_hours 同居 = 配列の先頭が 6h 前
  // 安全策: 完全一致 → なければ 6 を返す(past_hours=6 既定)
  const exact = hourlyTime.findIndex((t) => t === isoHour);
  if (exact >= 0) return exact;
  // 直近の未来時刻の 1 つ手前を選ぶ
  for (let i = 0; i < hourlyTime.length; i++) {
    if (hourlyTime[i] > isoHour) return Math.max(0, i - 1);
  }
  return 6;
}

/** spec.md §12.3 静音時間判定。22:00-07:00 のような跨ぎを許す。 */
export function isQuietHour(
  nowJst: Date,
  q: { start: string; end: string },
): boolean {
  const minNow = nowJst.getHours() * 60 + nowJst.getMinutes();
  const [sh, sm] = q.start.split(':').map(Number);
  const [eh, em] = q.end.split(':').map(Number);
  const minStart = sh * 60 + sm;
  const minEnd = eh * 60 + em;
  if (minStart <= minEnd) {
    return minNow >= minStart && minNow < minEnd;
  }
  // 日跨ぎ(22:00-07:00 等)
  return minNow >= minStart || minNow < minEnd;
}

/** UTC Date を JST(UTC+9)の Date 風オブジェクトに変換 */
function toJstDate(utc: Date): Date {
  return new Date(utc.getTime() + 9 * 60 * 60 * 1000);
}

export async function runPersonalCheck(
  env: Env,
  now: Date = new Date(),
): Promise<{ scanned: number; pushed: number; suppressedQuiet: number; suppressedLimit: number }> {
  const users = await loadOptedInPersonalUsers(env);
  let pushed = 0;
  let suppressedQuiet = 0;
  let suppressedLimit = 0;

  for (const user of users) {
    try {
      const nowJst = toJstDate(now);

      if (isQuietHour(nowJst, user.quietHours)) {
        suppressedQuiet += 1;
        continue;
      }
      if (user.sentToday >= user.dailyLimit) {
        suppressedLimit += 1;
        continue;
      }

      const [forecast, airQuality] = await Promise.all([
        fetchForecast(user.lat, user.lon, env.OPEN_METEO_BASE),
        fetchAirQuality(user.lat, user.lon, env.OPEN_METEO_AIRQ_BASE),
      ]);

      const nowIdx = resolveNowIdx(forecast.hourly.time, now);
      const alerts: PersonalNotification[] = evaluatePersonalAlerts({
        forecast,
        airQuality,
        nowIdx,
        sensitivity: user.sensitivity,
        optIn: user.optIn,
      });

      // spec.md §12.3 dailyLimit / 重複抑制
      let remaining = user.dailyLimit - user.sentToday;
      for (const a of alerts) {
        if (remaining <= 0) {
          suppressedLimit += 1;
          break;
        }
        if (await isCoolingDown(env.ALERT_DEDUPE, user.uid, a.kind)) continue;

        const notif: Notification = {
          title: a.title,
          body: a.body,
          kind: a.kind,
          critical: false, // パーソナルは Time-Sensitive ではない(spec.md §12.8 Active)
          data: a.data,
        };

        const res = await sendFcm(
          env.FCM_ACCESS_TOKEN,
          env.FIRESTORE_PROJECT_ID,
          { fcmToken: user.fcmToken, platform: user.platform },
          notif,
        );
        if (res.ok) {
          await markSent(env.ALERT_DEDUPE, user.uid, a.kind);
          pushed += 1;
          remaining -= 1;
        } else {
          console.error('[personal-fcm-fail]', user.uid, a.kind, res.status, res.body);
        }
      }
    } catch (e) {
      console.error('[personal-user-eval-fail]', user.uid, (e as Error).message);
    }
  }

  return { scanned: users.length, pushed, suppressedQuiet, suppressedLimit };
}

// ──────────────────────────────────────────────────────────────────
// Firestore: パーソナル通知 opt-in ユーザー取得(REST、サービスアカウント)
// ──────────────────────────────────────────────────────────────────

async function loadOptedInPersonalUsers(env: Env): Promise<PersonalUserRecord[]> {
  // TODO: Firestore REST `runQuery` で
  //       users where notificationPreferences.personalEnabled == true
  //       かつ individualToggles に少なくとも 1 つ true が含まれる
  //       を実装。ページネーション + 200 件バッチ。
  return [];
}
