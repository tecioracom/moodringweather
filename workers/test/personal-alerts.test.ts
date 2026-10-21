// workers/test/personal-alerts.test.ts
// パーソナル通知 5 種の純関数判定の最低ユニットテスト。spec.md §12.2.3 / §12.6 / §12.7 / §12.9 準拠。

import { describe, it, expect } from 'vitest';
import {
  evaluatePressureDrop,
  evaluateHumiditySurge,
  evaluateAqiSpike,
  evaluateUvHigh,
  evaluatePollenBurst,
  evaluatePersonalAlerts,
  sensitivityPercentile,
  PRESSURE_DROP_HPA,
  HUMIDITY_SURGE_PCT,
  AQI_SPIKE_THRESHOLD,
  UV_HIGH_THRESHOLD,
  POLLEN_BURST_GRAINS,
} from '../src/lib/personal-alerts';
import type { OpenMeteoForecast, OpenMeteoAirQuality } from '../src/lib/open-meteo';
import { resolveNowIdx, isQuietHour } from '../src/cron/personal-notifier';

// ──────────────────────────────────────────────────────────────────
// fixtures
// ──────────────────────────────────────────────────────────────────

function makeHourly(over: Partial<OpenMeteoForecast['hourly']> = {}): OpenMeteoForecast['hourly'] {
  const len = 12;
  const arr = (v: number) => Array.from({ length: len }, () => v);
  return {
    time: Array.from({ length: len }, (_, i) => `2026-05-26T${String(i).padStart(2, '0')}:00`),
    temperature_2m: arr(25),
    relative_humidity_2m: arr(50),
    shortwave_radiation: arr(0),
    wind_speed_10m: arr(2),
    wind_gusts_10m: arr(3),
    snowfall: arr(0),
    snow_depth: arr(0),
    pressure_msl: arr(1013),
    uv_index: arr(3),
    ...over,
  };
}

function makeDaily(over: Partial<OpenMeteoForecast['daily']> = {}): OpenMeteoForecast['daily'] {
  return {
    time: ['2026-05-26', '2026-05-27'],
    snowfall_sum: [0, 0],
    wind_speed_10m_max: [5, 5],
    wind_gusts_10m_max: [7, 7],
    temperature_2m_max: [25, 25],
    uv_index_max: [4, 4],
    ...over,
  };
}

function makeAq(over: Partial<OpenMeteoAirQuality['hourly']> = {}): OpenMeteoAirQuality['hourly'] {
  const len = 12;
  const arr = (v: number) => Array.from({ length: len }, () => v);
  return {
    time: Array.from({ length: len }, (_, i) => `2026-05-26T${String(i).padStart(2, '0')}:00`),
    us_aqi: arr(50),
    pm2_5: arr(10),
    alder_pollen: arr(0),
    birch_pollen: arr(0),
    grass_pollen: arr(0),
    mugwort_pollen: arr(0),
    olive_pollen: arr(0),
    ragweed_pollen: arr(0),
    ...over,
  };
}

// ──────────────────────────────────────────────────────────────────
// 気圧急変
// ──────────────────────────────────────────────────────────────────

describe('evaluatePressureDrop', () => {
  it('6h で 8hPa 以上下降かつ感受性 0.75 以上 → 発火', () => {
    const hourly = makeHourly();
    // index 6 が「現在」、index 0 が 6h 前
    hourly.pressure_msl[0] = 1020;
    hourly.pressure_msl[6] = 1011; // -9hPa
    const r = evaluatePressureDrop(hourly, 6, 0.8);
    expect(r).not.toBeNull();
    expect(r!.kind).toBe('pressure_drop');
    expect(r!.body).toContain('-9.0 hPa');
  });

  it('感受性 0.75 未満は発火しない(spec.md §12.6)', () => {
    const hourly = makeHourly();
    hourly.pressure_msl[0] = 1020;
    hourly.pressure_msl[6] = 1010;
    expect(evaluatePressureDrop(hourly, 6, 0.74)).toBeNull();
  });

  it('下降幅 < 8hPa は発火しない', () => {
    const hourly = makeHourly();
    hourly.pressure_msl[0] = 1015;
    hourly.pressure_msl[6] = 1008; // -7hPa < 8
    expect(evaluatePressureDrop(hourly, 6, 0.9)).toBeNull();
  });

  it('閾値ジャスト -8hPa で発火', () => {
    const hourly = makeHourly();
    hourly.pressure_msl[0] = 1020;
    hourly.pressure_msl[6] = 1020 - PRESSURE_DROP_HPA;
    expect(evaluatePressureDrop(hourly, 6, 0.75)).not.toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────
// 湿度急上昇
// ──────────────────────────────────────────────────────────────────

describe('evaluateHumiditySurge', () => {
  it('1h で +30% 以上かつ感受性 0.8 以上 → 発火', () => {
    const hourly = makeHourly();
    hourly.relative_humidity_2m[5] = 40;
    hourly.relative_humidity_2m[6] = 75; // +35
    const r = evaluateHumiditySurge(hourly, 6, 0.85);
    expect(r).not.toBeNull();
    expect(r!.body).toContain('+35%');
  });

  it('感受性 0.79 では発火しない', () => {
    const hourly = makeHourly();
    hourly.relative_humidity_2m[5] = 40;
    hourly.relative_humidity_2m[6] = 80;
    expect(evaluateHumiditySurge(hourly, 6, 0.79)).toBeNull();
  });

  it('+29% は発火しない', () => {
    const hourly = makeHourly();
    hourly.relative_humidity_2m[5] = 40;
    hourly.relative_humidity_2m[6] = 40 + (HUMIDITY_SURGE_PCT - 1);
    expect(evaluateHumiditySurge(hourly, 6, 0.9)).toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────
// AQI
// ──────────────────────────────────────────────────────────────────

describe('evaluateAqiSpike', () => {
  it('AQI > 100 かつ感受性 0.7 以上 → 発火', () => {
    const aq = makeAq({ us_aqi: Array.from({ length: 12 }, (_, i) => (i === 6 ? 130 : 50)) });
    const r = evaluateAqiSpike(aq, 6, 0.72);
    expect(r).not.toBeNull();
    expect(r!.body).toContain('AQI=130');
  });

  it('AQI = 100 では発火しない(> 100)', () => {
    const aq = makeAq({ us_aqi: Array.from({ length: 12 }, () => AQI_SPIKE_THRESHOLD) });
    expect(evaluateAqiSpike(aq, 6, 0.9)).toBeNull();
  });

  it('感受性不足では発火しない', () => {
    const aq = makeAq({ us_aqi: Array.from({ length: 12 }, () => 150) });
    expect(evaluateAqiSpike(aq, 6, 0.5)).toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────
// UV
// ──────────────────────────────────────────────────────────────────

describe('evaluateUvHigh', () => {
  it('当日 UV 最大 >= 8 かつ感受性 0.7 以上 → 発火', () => {
    const daily = makeDaily({ uv_index_max: [9, 5] });
    const r = evaluateUvHigh(daily, 0.75);
    expect(r).not.toBeNull();
    expect(r!.kind).toBe('uv_high');
  });

  it('UV 7 は発火しない(spec.md §12.2.3 は UV 8+)', () => {
    const daily = makeDaily({ uv_index_max: [UV_HIGH_THRESHOLD - 1, 4] });
    expect(evaluateUvHigh(daily, 0.9)).toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────
// 花粉
// ──────────────────────────────────────────────────────────────────

describe('evaluatePollenBurst', () => {
  it('合計が閾値超過 かつ花粉アレルギーあり → 発火', () => {
    const aq = makeAq();
    aq.birch_pollen[6] = POLLEN_BURST_GRAINS + 5;
    const r = evaluatePollenBurst(aq, 6, true);
    expect(r).not.toBeNull();
    expect(r!.body).toContain('カバノキ');
  });

  it('花粉アレルギーフラグ false なら発火しない(spec.md §12.2.3)', () => {
    const aq = makeAq();
    aq.birch_pollen[6] = 200;
    expect(evaluatePollenBurst(aq, 6, false)).toBeNull();
  });

  it('合計が閾値未満なら発火しない', () => {
    const aq = makeAq();
    aq.birch_pollen[6] = POLLEN_BURST_GRAINS - 1;
    expect(evaluatePollenBurst(aq, 6, true)).toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────
// evaluatePersonalAlerts 集約
// ──────────────────────────────────────────────────────────────────

describe('evaluatePersonalAlerts', () => {
  it('OptIn = 全 ON / 全閾値超過 → 5 種すべて返る', () => {
    const hourly = makeHourly();
    hourly.pressure_msl[0] = 1020;
    hourly.pressure_msl[6] = 1010; // -10hPa
    hourly.relative_humidity_2m[5] = 40;
    hourly.relative_humidity_2m[6] = 80; // +40%
    const daily = makeDaily({ uv_index_max: [10, 4] });
    const aq = makeAq();
    aq.us_aqi[6] = 150;
    aq.ragweed_pollen[6] = 80;

    const alerts = evaluatePersonalAlerts({
      forecast: { hourly, daily },
      airQuality: { hourly: aq },
      nowIdx: 6,
      sensitivity: { pressure: 0.9, humidity: 0.9, uv: 0.9, airQuality: 0.9, pollenAllergy: true },
      optIn: { pressure: true, humidity: true, aqi: true, uv: true, pollen: true },
    });

    expect(alerts.map((a) => a.kind).sort()).toEqual(
      ['aqi_spike', 'humidity_surge', 'pollen_burst', 'pressure_drop', 'uv_high'].sort(),
    );
  });

  it('OptIn=false の項目は閾値を超えても返らない', () => {
    const hourly = makeHourly();
    hourly.pressure_msl[0] = 1020;
    hourly.pressure_msl[6] = 1010;
    const alerts = evaluatePersonalAlerts({
      forecast: { hourly, daily: makeDaily() },
      airQuality: { hourly: makeAq() },
      nowIdx: 6,
      sensitivity: { pressure: 0.9, humidity: 0.9, uv: 0.9, airQuality: 0.9, pollenAllergy: true },
      optIn: { pressure: false, humidity: true, aqi: true, uv: true, pollen: true },
    });
    expect(alerts.find((a) => a.kind === 'pressure_drop')).toBeUndefined();
  });
});

describe('sensitivityPercentile', () => {
  it('0.8 → 上位 20%', () => {
    expect(sensitivityPercentile(0.8)).toBe(20);
  });
  it('1.0 → 上位 1%(最低保証)', () => {
    expect(sensitivityPercentile(1.0)).toBe(1);
  });
});

// ──────────────────────────────────────────────────────────────────
// personal-notifier の小ユーティリティ
// ──────────────────────────────────────────────────────────────────

describe('isQuietHour', () => {
  it('22:00-07:00 跨ぎ。23:30 は静音', () => {
    const d = new Date('2026-05-26T23:30:00+09:00');
    // JST に既に変換された Date を直接渡す前提のテスト(personal-notifier 内では toJstDate で変換済み)
    const local = new Date(2026, 4, 26, 23, 30);
    expect(isQuietHour(local, { start: '22:00', end: '07:00' })).toBe(true);
    expect(d).toBeInstanceOf(Date); // dummy
  });

  it('22:00-07:00 跨ぎ。10:00 は非静音', () => {
    const local = new Date(2026, 4, 26, 10, 0);
    expect(isQuietHour(local, { start: '22:00', end: '07:00' })).toBe(false);
  });

  it('非跨ぎ 13:00-15:00。14:00 は静音', () => {
    const local = new Date(2026, 4, 26, 14, 0);
    expect(isQuietHour(local, { start: '13:00', end: '15:00' })).toBe(true);
  });
});

describe('resolveNowIdx', () => {
  it('past_hours=6 で hourly 先頭が 6h 前のとき、現在時刻に対応する index を返す', () => {
    const hourly = makeHourly();
    // index 6 が 06:00、現在時刻 = 06:30 UTC → 06:00 と一致
    const idx = resolveNowIdx(hourly.time, new Date('2026-05-26T06:30:00Z'));
    expect(idx).toBe(6);
  });

  it('一致がない場合は 6 を返す(past_hours=6 既定)', () => {
    const idx = resolveNowIdx([], new Date('2026-05-26T06:30:00Z'));
    expect(idx).toBe(6);
  });
});
