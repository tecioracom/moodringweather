// workers/src/lib/forecast-emergency.ts
//
// 緊急通知 v1.1「予報発火ルール」の純ロジック草案(正本: docs/mri-spec.md §5.3.2 / §5.3.3)。
// I/O(Open-Meteo fetch / Firestore / FCM)を一切含まないテスト可能な判定層。
//
// ⚠️ ステータス: スキャフォールド。Firebase プロジェクト / APNs 鍵 / Workers 配備 /
//    購読ストアが揃うまで本番配信には使われない(docs/notification-delivery-design.md §8)。
//
// しきい値(mri-spec §5.3 を正本とする。変更時は mri-spec を先に改訂すること):
//   熱中症: 予報日最高 WBGT ≥ 33 → メイン発火(severe)
//           予報日最高 WBGT ≥ 35 → Time-Sensitive + 最上級文言(danger / special)
//           判定タイミング: 当日 5:00 JST(heat_morning)/ 前日 17:00 JST(heat_evening)
//           ≥ 35 のみ 前日 14:00 JST(heat_special)を追加
//           (環境省 熱中症警戒アラート 33・特別警戒アラート 35 の発表基準・時刻に整合)
//   暴風  : 平均風速 ≥ 20 m/s(severe)/ ≥ 30 m/s(danger)。突風(gusts)は使わない
//   大雪  : 降雪 ≥ 3 cm/h(severe)/ ≥ 5 cm/h(danger)
//
// dedup 契約: 「種別 × 深刻度」キー(Dart 側 EmergencyAlert.dedupKey と同粒度)。
// 深刻度が上がった場合はキーが変わり即時再発火する(安全側)。

/** Cron トリガー種別。wrangler.toml の cron 文字列から index.ts が変換する。 */
export type EmergencyCronTrigger =
  | 'periodic'      // */10 * * * * — 暴風・大雪(+ 実況系)の汎用判定
  | 'heat_morning'  // JST 当日 05:00 — 熱中症 当日判定(警戒アラート発表時刻)
  | 'heat_evening'  // JST 前日 17:00 — 熱中症 前日判定(警戒アラート発表時刻)
  | 'heat_special'; // JST 前日 14:00 — 熱中症 特別警戒(≥ 35)のみ判定

/** Dart 側 EmergencySeverity と同一文字列(severe=通常 / danger=Time-Sensitive)。 */
export type ForecastSeverity = 'severe' | 'danger';

/** fcm.ts の EmergencyAlertKind と同一文字列。Dart 側パーサ
 *  (lib/domain/safety/emergency_push_payload.dart)との契約。 */
export type ForecastEmergencyKind = 'heat_stroke' | 'strong_wind' | 'heavy_snow';

export interface ForecastJudgement {
  kind: ForecastEmergencyKind;
  severity: ForecastSeverity;
  /** heat: 予報日最高 WBGT °C / wind: 平均風速 m/s / snow: 降雪 cm/h */
  metricValue: number;
  /** 予報 WBGT ≥ 35(熱中症特別警戒アラート相当)。最上級文言を要求する。 */
  special: boolean;
}

// ── しきい値定数(mri-spec §5.3.2 / §5.3.3)──────────────────────────
export const FORECAST_HEAT_MAIN_WBGT = 33;    // 熱中症警戒アラート発表基準
export const FORECAST_HEAT_SPECIAL_WBGT = 35; // 熱中症特別警戒アラート相当
export const WIND_SEVERE_MS = 20;             // JMA 暴風警報(陸上)目安の下限
export const WIND_DANGER_MS = 30;             // 「猛烈な風」区分
export const SNOW_SEVERE_CM_PER_HOUR = 3;     // 大雪注意報〜警報級の強い降り方
export const SNOW_DANGER_CM_PER_HOUR = 5;     // 顕著な大雪に関する気象情報級

/**
 * 熱中症(予報)判定。mri-spec §5.3.2。
 *
 * - periodic では予報発火しない。実況エスカレーション(現在値 WBGT 31/33)は
 *   クライアント側 EmergencyAdvisor(v1.0 ルール)が並走して担う。
 * - heat_special(前日 14:00)は ≥ 35 のみ発火(公式の特別警戒発表時刻に整合)。
 * - heat_morning / heat_evening は ≥ 33 で severe、≥ 35 で danger(special)。
 */
export function judgeForecastHeat(
  maxForecastWbgt: number,
  trigger: EmergencyCronTrigger,
): ForecastJudgement | null {
  if (!Number.isFinite(maxForecastWbgt)) return null;
  if (trigger === 'periodic') return null;

  const special = maxForecastWbgt >= FORECAST_HEAT_SPECIAL_WBGT;
  if (trigger === 'heat_special') {
    if (!special) return null;
    return { kind: 'heat_stroke', severity: 'danger', metricValue: maxForecastWbgt, special: true };
  }
  if (special) {
    return { kind: 'heat_stroke', severity: 'danger', metricValue: maxForecastWbgt, special: true };
  }
  if (maxForecastWbgt >= FORECAST_HEAT_MAIN_WBGT) {
    return { kind: 'heat_stroke', severity: 'severe', metricValue: maxForecastWbgt, special: false };
  }
  return null;
}

/** 暴風判定。mri-spec §5.3.3(平均風速 20/30 m/s。gusts は判定に使わない)。 */
export function judgeForecastWind(maxMeanWindMs: number): ForecastJudgement | null {
  if (!Number.isFinite(maxMeanWindMs) || maxMeanWindMs < WIND_SEVERE_MS) return null;
  return {
    kind: 'strong_wind',
    severity: maxMeanWindMs >= WIND_DANGER_MS ? 'danger' : 'severe',
    metricValue: maxMeanWindMs,
    special: false,
  };
}

/** 大雪判定。mri-spec §5.3.3(1 時間降雪量 3/5 cm/h)。 */
export function judgeForecastSnow(maxHourlySnowfallCm: number): ForecastJudgement | null {
  if (!Number.isFinite(maxHourlySnowfallCm) || maxHourlySnowfallCm < SNOW_SEVERE_CM_PER_HOUR) {
    return null;
  }
  return {
    kind: 'heavy_snow',
    severity:
      maxHourlySnowfallCm >= SNOW_DANGER_CM_PER_HOUR ? 'danger' : 'severe',
    metricValue: maxHourlySnowfallCm,
    special: false,
  };
}

/**
 * トリガーが評価すべき対象日(JST、YYYY-MM-DD)。
 * heat_morning = 当日 / heat_evening・heat_special = 翌日(前日発表のため)。
 */
export function targetJstDate(
  trigger: 'heat_morning' | 'heat_evening' | 'heat_special',
  nowUtc: Date,
): string {
  const dayOffset = trigger === 'heat_morning' ? 0 : 1;
  const jst = new Date(nowUtc.getTime() + 9 * 3_600_000 + dayOffset * 86_400_000);
  return jst.toISOString().slice(0, 10);
}

/**
 * Open-Meteo hourly(timezone=Asia/Tokyo で取得済み前提)の time / 値列から
 * 対象日(YYYY-MM-DD)の最大値を返す。該当時刻がなければ -Infinity。
 */
export function dailyMax(times: string[], values: number[], targetDate: string): number {
  let max = -Infinity;
  const n = Math.min(times.length, values.length);
  for (let i = 0; i < n; i++) {
    const v = values[i];
    if (!Number.isFinite(v)) continue;
    if (!times[i].startsWith(targetDate)) continue;
    if (v > max) max = v;
  }
  return max;
}

/** 先頭から [hours] 時間ぶんの最大値(暴風・大雪の periodic 判定用)。 */
export function maxOverHours(values: number[], hours: number): number {
  let max = -Infinity;
  const n = Math.min(values.length, hours);
  for (let i = 0; i < n; i++) {
    const v = values[i];
    if (Number.isFinite(v) && v > max) max = v;
  }
  return max;
}

/**
 * FCM data メッセージ payload(クライアントとの契約の正本)。
 *
 * クライアント lib/domain/safety/emergency_push_payload.dart がこれをパースして
 * EmergencyAlert に復元し、l10n 文言 + 免責文を端末側で組み立てて表示する
 * (Android: data-only push。iOS の扱いは docs/notification-delivery-design.md §6)。
 * キー・値を変更する場合は Dart 側パーサと同時に改訂すること。
 */
export function buildEmergencyDataPayload(j: ForecastJudgement): Record<string, string> {
  return {
    type: 'emergency',
    kind: j.kind,
    severity: j.severity,
    metric: j.metricValue.toFixed(1),
    // 数値の実体は予報 (Dart 側は欠落時も forecast 扱い。文言の選択にのみ使う)
    source: 'forecast',
    ...(j.special ? { special: '1' } : {}),
  };
}

/**
 * KV dedup キー(種別 × 深刻度)。Dart 側 EmergencyAlert.dedupKey と同粒度で、
 * 深刻度エスカレーション時のみ即時再発火を許す(安全側)。
 */
export function dedupeKeyOf(j: ForecastJudgement): string {
  return `${j.kind}:${j.severity}`;
}
