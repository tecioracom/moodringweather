// workers/test/wbgt.test.ts
// vitest で実行。spec.md §12.10.5 の SLO(RMSE ≤ 1.5°C)に向けた基本検証。

import { describe, it, expect } from 'vitest';
import { calcWbgt, classifyWbgt, shouldPushHeatAlert, wetBulbTemperature } from '../src/lib/wbgt';

describe('wetBulbTemperature (Stull 2011)', () => {
  it('Ta=30°C, RH=60% で Tw ≈ 24°C 前後', () => {
    const tw = wetBulbTemperature(30, 60);
    expect(tw).toBeGreaterThan(23);
    expect(tw).toBeLessThan(25);
  });
});

describe('calcWbgt', () => {
  it('夏の典型日(Ta=32, RH=70, SR=700)で danger 級 WBGT を返す', () => {
    const r = calcWbgt({
      temperatureC: 32,
      relativeHumidity: 70,
      shortwaveRadiation: 700,
      windSpeed: 2,
    });
    expect(r.wbgt).toBeGreaterThanOrEqual(31);
    expect(r.level).toBe('danger');
  });

  it('夜間(SR=0, Ta=20, RH=50)で safe', () => {
    const r = calcWbgt({
      temperatureC: 20,
      relativeHumidity: 50,
      shortwaveRadiation: 0,
    });
    expect(r.level).toBe('safe');
  });
});

describe('classifyWbgt', () => {
  it.each([
    [20, 'safe'],
    [22, 'caution'],
    [26, 'warning'],
    [29, 'severe'],
    [32, 'danger'],
  ] as const)('%i -> %s', (w, level) => {
    expect(classifyWbgt(w)).toBe(level);
  });
});

describe('shouldPushHeatAlert', () => {
  it('予報 WBGT >= 33 でプッシュ true', () => {
    expect(shouldPushHeatAlert(33)).toBe(true);
    expect(shouldPushHeatAlert(32.9)).toBe(false);
  });
});
