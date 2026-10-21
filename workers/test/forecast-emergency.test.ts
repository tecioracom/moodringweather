// workers/test/forecast-emergency.test.ts
//
// 予報発火ルール(mri-spec §5.3.2 / §5.3.3)の純ロジック検証。
// しきい値境界・トリガーゲーティング・FCM data payload 契約・JST 対象日。

import { describe, expect, it } from 'vitest';
import {
  buildEmergencyDataPayload,
  dailyMax,
  dedupeKeyOf,
  judgeForecastHeat,
  judgeForecastSnow,
  judgeForecastWind,
  maxOverHours,
  targetJstDate,
} from '../src/lib/forecast-emergency';

describe('judgeForecastHeat (mri-spec §5.3.2)', () => {
  it('heat_morning: 32.9 は発火しない', () => {
    expect(judgeForecastHeat(32.9, 'heat_morning')).toBeNull();
  });

  it('heat_morning: 33.0 ちょうどで severe(メイン発火)', () => {
    const j = judgeForecastHeat(33.0, 'heat_morning');
    expect(j).toMatchObject({ kind: 'heat_stroke', severity: 'severe', special: false });
  });

  it('heat_evening: 35.0 ちょうどで danger + special(特別警戒相当)', () => {
    const j = judgeForecastHeat(35.0, 'heat_evening');
    expect(j).toMatchObject({ kind: 'heat_stroke', severity: 'danger', special: true });
  });

  it('heat_special(前日 14:00): 34.9 は発火しない(≥ 35 のみ)', () => {
    expect(judgeForecastHeat(34.9, 'heat_special')).toBeNull();
  });

  it('heat_special: 35.2 で danger + special', () => {
    const j = judgeForecastHeat(35.2, 'heat_special');
    expect(j).toMatchObject({ severity: 'danger', special: true, metricValue: 35.2 });
  });

  it('periodic では予報発火しない(実況系はクライアント v1.0 ルールが担当)', () => {
    expect(judgeForecastHeat(40, 'periodic')).toBeNull();
  });

  it('NaN / -Infinity(該当時刻なし)は発火しない', () => {
    expect(judgeForecastHeat(Number.NaN, 'heat_morning')).toBeNull();
    expect(judgeForecastHeat(-Infinity, 'heat_morning')).toBeNull();
  });
});

describe('judgeForecastWind (mri-spec §5.3.3: 平均風速 20/30 m/s)', () => {
  it('19.9 は発火しない / 20.0 で severe / 30.0 で danger', () => {
    expect(judgeForecastWind(19.9)).toBeNull();
    expect(judgeForecastWind(20.0)).toMatchObject({ kind: 'strong_wind', severity: 'severe' });
    expect(judgeForecastWind(30.0)).toMatchObject({ kind: 'strong_wind', severity: 'danger' });
  });
});

describe('judgeForecastSnow (mri-spec §5.3.3: 3/5 cm/h)', () => {
  it('2.9 は発火しない / 3.0 で severe / 5.0 で danger', () => {
    expect(judgeForecastSnow(2.9)).toBeNull();
    expect(judgeForecastSnow(3.0)).toMatchObject({ kind: 'heavy_snow', severity: 'severe' });
    expect(judgeForecastSnow(5.0)).toMatchObject({ kind: 'heavy_snow', severity: 'danger' });
  });
});

describe('targetJstDate', () => {
  // UTC 2026-07-14 20:00 = JST 2026-07-15 05:00(heat_morning 発火時刻)
  const morningUtc = new Date('2026-07-14T20:00:00Z');
  // UTC 2026-07-15 08:00 = JST 2026-07-15 17:00(heat_evening 発火時刻)
  const eveningUtc = new Date('2026-07-15T08:00:00Z');
  // UTC 2026-07-15 05:00 = JST 2026-07-15 14:00(heat_special 発火時刻)
  const specialUtc = new Date('2026-07-15T05:00:00Z');

  it('heat_morning は JST 当日を対象にする', () => {
    expect(targetJstDate('heat_morning', morningUtc)).toBe('2026-07-15');
  });

  it('heat_evening / heat_special は JST 翌日を対象にする(前日発表)', () => {
    expect(targetJstDate('heat_evening', eveningUtc)).toBe('2026-07-16');
    expect(targetJstDate('heat_special', specialUtc)).toBe('2026-07-16');
  });
});

describe('dailyMax / maxOverHours', () => {
  const times = [
    '2026-07-15T23:00',
    '2026-07-16T00:00',
    '2026-07-16T13:00',
    '2026-07-16T14:00',
    '2026-07-17T00:00',
  ];
  const values = [30, 28, 34.5, 33.9, 29];

  it('対象日の時刻のみから最大値を取る', () => {
    expect(dailyMax(times, values, '2026-07-16')).toBe(34.5);
    expect(dailyMax(times, values, '2026-07-15')).toBe(30);
  });

  it('該当時刻がない日は -Infinity(判定側で発火しない)', () => {
    expect(dailyMax(times, values, '2026-07-20')).toBe(-Infinity);
  });

  it('maxOverHours は先頭 n 時間のみ見る', () => {
    expect(maxOverHours(values, 2)).toBe(30);
    expect(maxOverHours(values, 5)).toBe(34.5);
    expect(maxOverHours([], 24)).toBe(-Infinity);
  });
});

describe('FCM data payload 契約 (lib/domain/safety/emergency_push_payload.dart と同期)', () => {
  it('種別・深刻度・数値・special を文字列で持つ', () => {
    const j = judgeForecastHeat(35.25, 'heat_evening')!;
    expect(buildEmergencyDataPayload(j)).toEqual({
      type: 'emergency',
      kind: 'heat_stroke',
      severity: 'danger',
      metric: '35.3',
      source: 'forecast',
      special: '1',
    });
  });

  it('special でない場合は special キーを含めない', () => {
    const j = judgeForecastWind(22)!;
    expect(buildEmergencyDataPayload(j)).toEqual({
      type: 'emergency',
      kind: 'strong_wind',
      severity: 'severe',
      metric: '22.0',
      source: 'forecast',
    });
  });

  it('dedup キーは「種別 × 深刻度」(Dart EmergencyAlert.dedupKey と同粒度)', () => {
    expect(dedupeKeyOf(judgeForecastSnow(6)!)).toBe('heavy_snow:danger');
    expect(dedupeKeyOf(judgeForecastSnow(3.5)!)).toBe('heavy_snow:severe');
  });
});
