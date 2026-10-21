// workers/src/lib/wbgt.ts
//
// 自前 WBGT(湿球黒球温度)算出ロジック。spec.md §12.10.1 に準拠。
// Dart 側 WbgtCalculator と同一式・誤差 ±0.5°C 以内であることをユニットテストで担保する(§12.10.3)。

/** WBGT 警戒レベル(spec.md §12.10.2)。 */
export type WbgtLevel = 'safe' | 'caution' | 'warning' | 'severe' | 'danger';

export interface WbgtResult {
  /** WBGT °C(小数 1 桁) */
  wbgt: number;
  /** 段階レベル */
  level: WbgtLevel;
  /** 算出に使った入力値(デバッグ・ログ用) */
  inputs: { ta: number; rh: number; sr: number; ws: number };
}

/**
 * Stull 2011 近似式による湿球温度 Tw(°C)。
 * spec.md §12.10.1 の式そのまま。
 */
export function wetBulbTemperature(ta: number, rh: number): number {
  const r = Math.max(0, Math.min(100, rh));
  return (
    ta * Math.atan(0.151977 * Math.sqrt(r + 8.313659)) +
    Math.atan(ta + r) -
    Math.atan(r - 1.676331) +
    0.00391838 * Math.pow(r, 1.5) * Math.atan(0.023101 * r) -
    4.686035
  );
}

/**
 * 黒球温度 Tg の近似。spec.md §12.10.1 の暫定式。
 * - 日射量 SR (W/m²) を受け取って晴天時近似を返す
 * - 夜間(SR <= 0)は Ta に等しい
 */
export function globeTemperature(ta: number, sr: number): number {
  if (sr <= 0) return ta;
  return ta + 0.038 * sr;
}

/**
 * WBGT 算出本体。spec.md §12.10.1 の重み(0.7 Tw + 0.2 Tg + 0.1 Ta)。
 */
export function calcWbgt(input: {
  temperatureC: number;       // Ta
  relativeHumidity: number;   // RH (%)
  shortwaveRadiation: number; // SR (W/m²)
  windSpeed?: number;         // WS (m/s) — 参考値、現状は未使用
}): WbgtResult {
  const ta = input.temperatureC;
  const rh = input.relativeHumidity;
  const sr = Math.max(0, input.shortwaveRadiation);
  const ws = input.windSpeed ?? 0;

  const tw = wetBulbTemperature(ta, rh);
  const tg = globeTemperature(ta, sr);
  const wbgt = 0.7 * tw + 0.2 * tg + 0.1 * ta;

  return {
    wbgt: Math.round(wbgt * 10) / 10,
    level: classifyWbgt(wbgt),
    inputs: { ta, rh, sr, ws },
  };
}

/** spec.md §12.10.2 の閾値マッピング。 */
export function classifyWbgt(wbgt: number): WbgtLevel {
  if (wbgt >= 31) return 'danger';     // ※ JMA 公式アラート閾値は予報 33。実況 31 から「危険」段階
  if (wbgt >= 28) return 'severe';     // 厳重警戒
  if (wbgt >= 25) return 'warning';    // 警戒
  if (wbgt >= 21) return 'caution';    // 注意
  return 'safe';
}

/**
 * プッシュ通知を発火すべきかの判定(spec.md §12.2.1 + §12.10.2)。
 * - 「予報 WBGT >= 33」をメイン閾値として true
 * - 「実況 WBGT >= 31 (= 'danger')」も true(Critical Alert 対象)
 */
export function shouldPushHeatAlert(forecastMaxWbgt: number): boolean {
  return forecastMaxWbgt >= 33;
}
