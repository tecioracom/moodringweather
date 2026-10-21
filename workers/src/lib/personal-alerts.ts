// workers/src/lib/personal-alerts.ts
//
// パーソナル通知 5 種(気圧 / 湿度 / AQI / UV / 花粉)の純関数判定群。
// spec.md §12.2.3(トリガー条件)/ §12.6(自動有効化提案)/ §12.7(本文パーソナル化)/
// §12.8(優先度マッピング)/ §12.9(データモデル)準拠。
//
// 設計方針:
//   - 各 evaluator は副作用なしの純関数。Workers Cron からも、ユニットテストからも同一 IF で呼べる。
//   - 通知本文は spec.md §12.7 のパーソナル版コピーに準じる。MRI 換算や感受性順位は呼び出し側で注入する。
//   - 「キャリブレーション連携」は emergency と異なり opt-in と感受性閾値の AND を取る。
//     感受性閾値は spec.md §12.6 に従い、本ファイルでは外部から渡される `sensitivity` で評価する。

import type { OpenMeteoForecast, OpenMeteoAirQuality } from './open-meteo';

// ──────────────────────────────────────────────────────────────────
// 型定義
// ──────────────────────────────────────────────────────────────────

/** spec.md §12.9 に対応する通知種別 ID(緊急 3 種 + パーソナル 5 種)。 */
export type PersonalAlertKind =
  | 'pressure_drop'
  | 'humidity_surge'
  | 'aqi_spike'
  | 'uv_high'
  | 'pollen_burst';

export interface PersonalNotification {
  title: string;
  body: string;
  kind: PersonalAlertKind;
  /** 詳細画面ディープリンク用 */
  data?: Record<string, string>;
}

/** ユーザーごとの感受性ベクトル(オンデバイスから Workers へ送る最小集合)。spec.md §12.6 / §4.2 */
export interface PersonalSensitivity {
  pressure: number;   // 0.0 - 1.0(0.75 以上で気圧通知の提案 / 配信対象)
  humidity: number;   // 0.0 - 1.0(0.80 以上)
  uv: number;         // 0.0 - 1.0(0.70 以上)
  airQuality: number; // 0.0 - 1.0(0.70 以上)
  /** 花粉アレルギーは Yes/No のセルフ申告(spec.md §12.2.3「既知の花粉アレルギーユーザーのみ」) */
  pollenAllergy: boolean;
}

/** ユーザーごとの個別 ON/OFF(spec.md §12.5 設定画面)。 */
export interface PersonalOptIn {
  pressure: boolean;
  humidity: boolean;
  aqi: boolean;
  uv: boolean;
  pollen: boolean;
}

// ──────────────────────────────────────────────────────────────────
// 閾値定数(spec.md §12.2.3 を単一情報源として参照)
// ──────────────────────────────────────────────────────────────────

export const PRESSURE_DROP_HPA = 8;        // 6h で 8 hPa 以上の下降
export const PRESSURE_WINDOW_H = 6;
export const HUMIDITY_SURGE_PCT = 30;      // 1h で +30% 以上
export const HUMIDITY_WINDOW_H = 1;
export const AQI_SPIKE_THRESHOLD = 100;    // AQI > 100
export const UV_HIGH_THRESHOLD = 8;        // UV >= 8
export const POLLEN_BURST_GRAINS = 50;     // 「非常に多い」相当(grains/m³)
                                            // ※ 環境省花粉飛散観測の「非常に多い」目安 50 個/cm² ≒ 同 grains/m³ クラス。
                                            //   spec.md §12.2.3 の閾値が「非常に多い」と表記されているため定数化。

// 感受性閾値(spec.md §12.6)
export const SENS_PRESSURE = 0.75;
export const SENS_HUMIDITY = 0.80;
export const SENS_UV = 0.70;
export const SENS_AIR_QUALITY = 0.70;

// ──────────────────────────────────────────────────────────────────
// 気圧急変(spec.md §12.2.3)
// ──────────────────────────────────────────────────────────────────

/**
 * 直近 [PRESSURE_WINDOW_H] 時間で [PRESSURE_DROP_HPA] hPa 以上の下降があれば発火。
 * past_hours=6 を Open-Meteo に要求している前提(open-meteo.ts 参照)。
 *
 * @param hourly forecast.hourly。past + future の連続配列で nowIdx=現在時刻位置を渡す
 * @param nowIdx 現在時刻に対応する index(past_hours=6 なら通常 6)
 */
export function evaluatePressureDrop(
  hourly: OpenMeteoForecast['hourly'],
  nowIdx: number,
  sensitivity: number,
): PersonalNotification | null {
  if (sensitivity < SENS_PRESSURE) return null;
  const startIdx = nowIdx - PRESSURE_WINDOW_H;
  if (startIdx < 0 || nowIdx >= hourly.pressure_msl.length) return null;

  const pStart = hourly.pressure_msl[startIdx];
  const pNow = hourly.pressure_msl[nowIdx];
  const delta = pNow - pStart; // 負なら下降
  if (delta > -PRESSURE_DROP_HPA) return null;

  const percentile = sensitivityPercentile(sensitivity);
  return {
    title: '気圧が急降下しています',
    body:
      `気圧が ${PRESSURE_WINDOW_H} 時間で ${delta.toFixed(1)} hPa 下降中。` +
      `あなたの気圧感受性は上位 ${percentile}% です。早めの休息を。`,
    kind: 'pressure_drop',
    data: { deltaHpa: delta.toFixed(1) },
  };
}

// ──────────────────────────────────────────────────────────────────
// 湿度急上昇(spec.md §12.2.3)
// ──────────────────────────────────────────────────────────────────

export function evaluateHumiditySurge(
  hourly: OpenMeteoForecast['hourly'],
  nowIdx: number,
  sensitivity: number,
): PersonalNotification | null {
  if (sensitivity < SENS_HUMIDITY) return null;
  const startIdx = nowIdx - HUMIDITY_WINDOW_H;
  if (startIdx < 0 || nowIdx >= hourly.relative_humidity_2m.length) return null;

  const rhStart = hourly.relative_humidity_2m[startIdx];
  const rhNow = hourly.relative_humidity_2m[nowIdx];
  const delta = rhNow - rhStart;
  if (delta < HUMIDITY_SURGE_PCT) return null;

  return {
    title: '湿度が急上昇',
    body:
      `1 時間で湿度が +${delta.toFixed(0)}% 上昇(現在 ${rhNow.toFixed(0)}%)。` +
      `あなたには MRI への影響が大きい値です。エアコン除湿モードがおすすめです。`,
    kind: 'humidity_surge',
    data: { rhNow: rhNow.toFixed(0), delta: delta.toFixed(0) },
  };
}

// ──────────────────────────────────────────────────────────────────
// AQI 急悪化(spec.md §12.2.3)
// ──────────────────────────────────────────────────────────────────

export function evaluateAqiSpike(
  aq: OpenMeteoAirQuality['hourly'],
  nowIdx: number,
  sensitivity: number,
): PersonalNotification | null {
  if (sensitivity < SENS_AIR_QUALITY) return null;
  if (nowIdx < 0 || nowIdx >= aq.us_aqi.length) return null;

  const aqi = aq.us_aqi[nowIdx];
  if (aqi <= AQI_SPIKE_THRESHOLD) return null;

  const pm = aq.pm2_5[nowIdx];
  return {
    title: '空気質が悪化しています',
    body:
      `現在 AQI=${aqi.toFixed(0)}(PM2.5 ${pm.toFixed(0)} µg/m³)。` +
      `感受性の高いあなたは外出時のマスク着用や換気の見送りを検討してください。`,
    kind: 'aqi_spike',
    data: { aqi: aqi.toFixed(0), pm25: pm.toFixed(0) },
  };
}

// ──────────────────────────────────────────────────────────────────
// 強紫外線(spec.md §12.2.3)
// ──────────────────────────────────────────────────────────────────

/**
 * 当日の UV index 最大が UV_HIGH_THRESHOLD 以上なら発火。
 * `daily.uv_index_max[0]`(今日)を使い、当日朝(JST 07:00)前後に 1 回送る運用を想定。
 */
export function evaluateUvHigh(
  daily: OpenMeteoForecast['daily'],
  sensitivity: number,
): PersonalNotification | null {
  if (sensitivity < SENS_UV) return null;
  if (!daily.uv_index_max?.[0]) return null;

  const uvMax = daily.uv_index_max[0];
  if (uvMax < UV_HIGH_THRESHOLD) return null;

  return {
    title: '強い紫外線に注意',
    body:
      `本日の UV 最大は ${uvMax.toFixed(0)}(Very High)。` +
      `日射感受性の高いあなたは日傘・サングラス・SPF50+ を推奨します。`,
    kind: 'uv_high',
    data: { uvMax: uvMax.toFixed(0) },
  };
}

// ──────────────────────────────────────────────────────────────────
// 花粉激増(spec.md §12.2.3)
// ──────────────────────────────────────────────────────────────────

/**
 * CAMS の花粉系列の合計が POLLEN_BURST_GRAINS を超えたら発火。
 * spec.md §12.2.3 は「スギ・ヒノキ・ブタクサ」だが Open-Meteo は欧州モデルのみ提供のため、
 * 近縁種を合算した近似指標を使用する(花粉症のあるユーザーへの安全側通知)。
 */
export function evaluatePollenBurst(
  aq: OpenMeteoAirQuality['hourly'],
  nowIdx: number,
  hasPollenAllergy: boolean,
): PersonalNotification | null {
  if (!hasPollenAllergy) return null;
  if (nowIdx < 0 || nowIdx >= aq.time.length) return null;

  const series = [
    aq.alder_pollen[nowIdx],
    aq.birch_pollen[nowIdx],
    aq.grass_pollen[nowIdx],
    aq.mugwort_pollen[nowIdx],
    aq.olive_pollen[nowIdx],
    aq.ragweed_pollen[nowIdx],
  ].map((v) => (Number.isFinite(v) ? v : 0));

  const total = series.reduce((a, b) => a + b, 0);
  if (total < POLLEN_BURST_GRAINS) return null;

  // ピーク種を本文に出す(汎用版より具体的にする §12.7)
  const labels = ['ハンノキ', 'カバノキ', 'イネ科', 'ヨモギ', 'オリーブ', 'ブタクサ'];
  let peakIdx = 0;
  for (let i = 1; i < series.length; i++) if (series[i] > series[peakIdx]) peakIdx = i;

  return {
    title: '花粉が激増しています',
    body:
      `現在 ${labels[peakIdx]} 花粉が多く飛散中(総量 ${total.toFixed(0)} grains/m³)。` +
      `外出時はマスク・帰宅後の洗顔と着替えで持ち込みを抑えましょう。`,
    kind: 'pollen_burst',
    data: { total: total.toFixed(0), peak: labels[peakIdx] },
  };
}

// ──────────────────────────────────────────────────────────────────
// 集約: 1 ユーザー分のパーソナル通知を一括判定する
// ──────────────────────────────────────────────────────────────────

export interface EvaluatePersonalInput {
  forecast: OpenMeteoForecast;
  airQuality: OpenMeteoAirQuality;
  /** 現在時刻に対応する hourly インデックス(past_hours=6 なら通常 6) */
  nowIdx: number;
  sensitivity: PersonalSensitivity;
  optIn: PersonalOptIn;
}

export function evaluatePersonalAlerts(
  input: EvaluatePersonalInput,
): PersonalNotification[] {
  const out: PersonalNotification[] = [];
  const { forecast, airQuality, nowIdx, sensitivity, optIn } = input;

  if (optIn.pressure) {
    const a = evaluatePressureDrop(forecast.hourly, nowIdx, sensitivity.pressure);
    if (a) out.push(a);
  }
  if (optIn.humidity) {
    const a = evaluateHumiditySurge(forecast.hourly, nowIdx, sensitivity.humidity);
    if (a) out.push(a);
  }
  if (optIn.aqi) {
    const a = evaluateAqiSpike(airQuality.hourly, nowIdx, sensitivity.airQuality);
    if (a) out.push(a);
  }
  if (optIn.uv) {
    const a = evaluateUvHigh(forecast.daily, sensitivity.uv);
    if (a) out.push(a);
  }
  if (optIn.pollen) {
    const a = evaluatePollenBurst(airQuality.hourly, nowIdx, sensitivity.pollenAllergy);
    if (a) out.push(a);
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────
// 補助: 感受性スコアを「上位 X%」に変換(spec.md §12.7 本文)
// ──────────────────────────────────────────────────────────────────

/**
 * 感受性 0.0-1.0 を「母集団内のおおよその上位パーセンタイル」に変換。
 * 暫定式: 上位 = round((1 - sensitivity) * 100)。後でテレメトリと突合し再調整。
 */
export function sensitivityPercentile(sensitivity: number): number {
  const clamped = Math.max(0, Math.min(1, sensitivity));
  return Math.max(1, Math.round((1 - clamped) * 100));
}
