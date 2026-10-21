// test/unit/mri_calculator_test.dart
//
// docs/mri-spec.md §8 の qa 期待値テーブルと 1:1 対応するユニットテスト。
// 許容誤差: サブスコア・MRI_base・raw は ±0.01、最終 MRI は完全一致 (int)。
// 式・係数を変えた場合は mri-spec.md を先に改訂し、本テーブルを再計算すること。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/pollen_level.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/domain/mri/mri_calculator.dart';

WeatherSnapshot _snapshot({
  double temp = 22,
  double? apparent = 22,
  double? humidity = 50,
  double? pressureChange6h = 0,
  double? wind = 2,
  double? uv = 3,
  int? aqi = 42,
  PollenLevel? pollen = PollenLevel.low,
}) {
  return WeatherSnapshot(
    timestamp: DateTime(2026, 6, 11, 12),
    latitude: 35.66,
    longitude: 139.70,
    temperature: temp,
    apparentTemperature: apparent,
    humidity: humidity,
    pressure: 1013,
    pressureChange6h: pressureChange6h,
    windSpeed: wind,
    uvIndex: uv,
    aqi: aqi,
    pollen: pollen,
    condition: 'sunny',
  );
}

/// mri-spec.md §8.1 の 1 行を検証する。
void _expectCase({
  required String name,
  required WeatherSnapshot snapshot,
  required double mriBase,
  required double thermalAdjustment, // Δcool − Δheat
  required int mri,
  required MriBand band,
}) {
  final result = MriCalculator.calculate(snapshot);
  final base =
      result.factorContributions.values.fold<double>(0, (a, b) => a + b);
  expect(base, closeTo(mriBase, 0.01), reason: '$name: MRI_base');
  expect(result.thermalAdjustment, closeTo(thermalAdjustment, 0.01),
      reason: '$name: Δcool−Δheat');
  expect(result.value, mri, reason: '$name: MRI');
  expect(result.band, band, reason: '$name: band');
}

void main() {
  group('MRI 統合ケース (mri-spec.md §8.1。未学習・欠測なし)', () {
    test('#1 参照快適日 22°C/50%/UV3/AQI42 → MRI 64 (comfortable)', () {
      _expectCase(
        name: '#1',
        snapshot: _snapshot(),
        mriBase: 94.61,
        thermalAdjustment: 0,
        mri: 64,
        band: MriBand.comfortable,
      );
    });

    test('#2 真夏多湿 33°C/65%/UV8 (T_app 40) → MRI 29 (hot)', () {
      _expectCase(
        name: '#2',
        snapshot: _snapshot(
            temp: 33, apparent: 40, humidity: 65, uv: 8, aqi: 60, wind: 1),
        mriBase: 69.75,
        thermalAdjustment: -18.0,
        mri: 29,
        band: MriBand.hot,
      );
    });

    test('#3 猛暑アラート域 36°C/60%/UV9 (T_app 44) → MRI 24 (< 25 で通知条件成立)', () {
      _expectCase(
        name: '#3',
        snapshot: _snapshot(
            temp: 36, apparent: 44, humidity: 60, uv: 9, aqi: 55, wind: 2),
        mriBase: 68.38,
        thermalAdjustment: -22.5,
        mri: 24,
        band: MriBand.hot,
      );
      final alertCase = MriCalculator.calculate(_snapshot(
          temp: 36, apparent: 44, humidity: 60, uv: 9, aqi: 55, wind: 2));
      expect(alertCase.value, lessThan(25));
    });

    test('#4 熱帯夜 30°C/80%/UV0 (T_app 38) → MRI 38 (hot)', () {
      _expectCase(
        name: '#4',
        snapshot: _snapshot(
            temp: 30, apparent: 38, humidity: 80, uv: 0, aqi: 50, wind: 0.5),
        mriBase: 77.35,
        thermalAdjustment: -15.0,
        mri: 38,
        band: MriBand.hot,
      );
    });

    test('#5 秋晴れ 15°C/45%/UV2 (T_app 14) → MRI 69 (comfortable)', () {
      _expectCase(
        name: '#5',
        snapshot: _snapshot(
            temp: 15, apparent: 14, humidity: 45, uv: 2, aqi: 30, wind: 2),
        mriBase: 88.10,
        thermalAdjustment: 8.8,
        mri: 69,
        band: MriBand.comfortable,
      );
    });

    test('#6 冬晴れ 5°C/35%/UV2 (T_app 2) → MRI 87 (cool)', () {
      _expectCase(
        name: '#6',
        snapshot: _snapshot(
            temp: 5,
            apparent: 2,
            humidity: 35,
            uv: 2,
            aqi: 40,
            wind: 4,
            pollen: PollenLevel.none),
        mriBase: 76.22,
        thermalAdjustment: 35.2,
        mri: 87,
        band: MriBand.cool,
      );
    });

    test('#7 低気圧の雨 20°C/85%/Δp−7 (T_app 19) → MRI 57 (warm)', () {
      _expectCase(
        name: '#7',
        snapshot: _snapshot(
            temp: 20,
            apparent: 19,
            humidity: 85,
            uv: 1,
            aqi: 25,
            wind: 5,
            pressureChange6h: -7),
        mriBase: 83.42,
        thermalAdjustment: 0,
        mri: 57,
        band: MriBand.warm,
      );
    });

    test('#8 春の花粉嵐 18°C/40%/UV5/veryHigh (T_app 17) → MRI 53 (warm)', () {
      _expectCase(
        name: '#8',
        snapshot: _snapshot(
            temp: 18,
            apparent: 17,
            humidity: 40,
            uv: 5,
            aqi: 95,
            wind: 6,
            pollen: PollenLevel.veryHigh),
        mriBase: 74.60,
        thermalAdjustment: 2.2,
        mri: 53,
        band: MriBand.warm,
      );
    });

    test('#9 極端高温 41°C/55%/UV10/AQI120 (T_app 48) → MRI 16 (hotAlert)', () {
      _expectCase(
        name: '#9',
        snapshot: _snapshot(
            temp: 41,
            apparent: 48,
            humidity: 55,
            uv: 10,
            aqi: 120,
            wind: 1,
            pollen: PollenLevel.moderate),
        mriBase: 56.95,
        thermalAdjustment: -22.5,
        mri: 16,
        band: MriBand.hotAlert,
      );
    });
  });

  group('サブスコア境界ケース (mri-spec.md §8.2)', () {
    test('score_temp', () {
      expect(MriCalculator.scoreTemperature(22), closeTo(100, 0.01));
      expect(MriCalculator.scoreTemperature(12), closeTo(65, 0.01));
      expect(MriCalculator.scoreTemperature(32), closeTo(65, 0.01));
      expect(MriCalculator.scoreTemperature(50.6), closeTo(0, 0.01));
      expect(MriCalculator.scoreTemperature(-6.6), closeTo(0, 0.01));
    });

    test('score_humid', () {
      expect(MriCalculator.scoreHumidity(50, 22), closeTo(100, 0.01));
      expect(MriCalculator.scoreHumidity(65, 33), closeTo(64, 0.01));
      expect(MriCalculator.scoreHumidity(80, 30), closeTo(46, 0.01));
      expect(MriCalculator.scoreHumidity(20, 22), closeTo(79, 0.01));
      expect(MriCalculator.scoreHumidity(100, 35), closeTo(0, 0.01));
    });

    test('score_uv', () {
      expect(MriCalculator.scoreUv(0), closeTo(100, 0.01));
      expect(MriCalculator.scoreUv(0.5), closeTo(100, 0.01));
      expect(MriCalculator.scoreUv(3), closeTo(75, 0.01));
      expect(MriCalculator.scoreUv(6), closeTo(45, 0.01));
      expect(MriCalculator.scoreUv(8), closeTo(25, 0.01));
      expect(MriCalculator.scoreUv(11), closeTo(0, 0.01));
    });

    test('score_aqi (区分境界で連続)', () {
      expect(MriCalculator.scoreAqi(0), closeTo(100, 0.01));
      expect(MriCalculator.scoreAqi(42), closeTo(87.4, 0.01));
      expect(MriCalculator.scoreAqi(50), closeTo(85, 0.01));
      expect(MriCalculator.scoreAqi(100), closeTo(60, 0.01));
      expect(MriCalculator.scoreAqi(150), closeTo(40, 0.01));
      expect(MriCalculator.scoreAqi(200), closeTo(20, 0.01));
      expect(MriCalculator.scoreAqi(300), closeTo(0, 0.01));
      expect(MriCalculator.scoreAqi(400), closeTo(0, 0.01));
    });

    test('score_pollen', () {
      expect(MriCalculator.scorePollen(PollenLevel.none), 100);
      expect(MriCalculator.scorePollen(PollenLevel.low), 90);
      expect(MriCalculator.scorePollen(PollenLevel.moderate), 60);
      expect(MriCalculator.scorePollen(PollenLevel.high), 30);
      expect(MriCalculator.scorePollen(PollenLevel.veryHigh), 10);
    });

    test('score_wind', () {
      expect(MriCalculator.scoreWind(2, 22), closeTo(100, 0.01));
      expect(MriCalculator.scoreWind(10, 22), closeTo(68.5, 0.01));
      expect(MriCalculator.scoreWind(0.5, 30), closeTo(96, 0.01));
      expect(MriCalculator.scoreWind(4, 5), closeTo(89.5, 0.01));
      expect(MriCalculator.scoreWind(0, 22), closeTo(100, 0.01));
    });

    test('score_pressure', () {
      expect(MriCalculator.scorePressure(0), closeTo(100, 0.01));
      expect(MriCalculator.scorePressure(-1), closeTo(100, 0.01));
      expect(MriCalculator.scorePressure(-4), closeTo(64, 0.01));
      expect(MriCalculator.scorePressure(-7), closeTo(28, 0.01));
      expect(MriCalculator.scorePressure(5), closeTo(76, 0.01));
      expect(MriCalculator.scorePressure(-10), closeTo(0, 0.01));
    });
  });

  group('MriBand.fromValue (mri-spec.md §4。閉区間下端)', () {
    test('境界値', () {
      expect(MriBand.fromValue(0), MriBand.hotAlert);
      expect(MriBand.fromValue(19), MriBand.hotAlert);
      expect(MriBand.fromValue(20), MriBand.hot);
      expect(MriBand.fromValue(39), MriBand.hot);
      expect(MriBand.fromValue(40), MriBand.warm);
      expect(MriBand.fromValue(59), MriBand.warm);
      expect(MriBand.fromValue(60), MriBand.comfortable);
      expect(MriBand.fromValue(79), MriBand.comfortable);
      expect(MriBand.fromValue(80), MriBand.cool);
      expect(MriBand.fromValue(100), MriBand.cool);
    });
  });

  group('欠測フォールバック (mri-spec.md §2.8)', () {
    test('temp 以外が全欠測でも MRI を計算できる (フォールバック score)', () {
      final result = MriCalculator.calculate(WeatherSnapshot(
        timestamp: DateTime(2026, 6, 11, 12),
        latitude: 35.66,
        longitude: 139.70,
        temperature: 22,
      ));
      final scores = MriCalculator.computeFactorScores(WeatherSnapshot(
        timestamp: DateTime(2026, 6, 11, 12),
        latitude: 35.66,
        longitude: 139.70,
        temperature: 22,
      ));
      expect(scores['humid'], 80);
      expect(scores['uv'], 100);
      expect(scores['aqi'], 75);
      expect(scores['pollen'], 90);
      expect(scores['wind'], 95);
      expect(scores['pressure'], 70);
      // base = 0.3×100 + 0.2×80 + 0.1×100 + 0.15×75 + 0.1×90 + 0.05×95 + 0.1×70
      //      = 88.0 → raw = 0.68×88.0 = 59.84 → 60
      expect(result.value, 60);
    });

    test('体感温度欠測時は気温で代用 (Δcool/Δheat)', () {
      final result = MriCalculator.calculate(
        _snapshot(
            temp: 5,
            apparent: null,
            humidity: 35,
            uv: 2,
            aqi: 40,
            wind: 4,
            pollen: PollenLevel.none),
      );
      // T_app := 5 → Δcool = 2.2 × 13 = 28.6
      expect(result.thermalAdjustment, closeTo(28.6, 0.01));
    });
  });

  group('重みの取り扱い (mri-spec.md §3.1 / §6.1 正規化)', () {
    test('カスタム重み (湿度感受性高) は多湿高温条件で MRI を下げる', () {
      final base = _snapshot(temp: 28, apparent: 30, humidity: 85);
      final defaultMri = MriCalculator.calculate(base);
      final sensitive = MriCalculator.calculate(base, weights: const {
        'temp': 0.20,
        'humid': 0.40,
        'uv': 0.10,
        'aqi': 0.10,
        'pollen': 0.10,
        'wind': 0.05,
        'pressure': 0.05,
      });
      expect(sensitive.value, lessThan(defaultMri.value));
    });

    test('合計が 1.0 でない重みは正規化される', () {
      final doubled =
          MriCalculator.defaultWeights.map((k, v) => MapEntry(k, v * 2));
      final a = MriCalculator.calculate(_snapshot());
      final b = MriCalculator.calculate(_snapshot(), weights: doubled);
      expect(b.value, a.value);
    });

    test('全要素 0 の重みは defaultWeights へフォールバック', () {
      final result = MriCalculator.calculate(
        _snapshot(),
        weights: const {
          'temp': 0,
          'humid': 0,
          'uv': 0,
          'aqi': 0,
          'pollen': 0,
          'wind': 0,
          'pressure': 0,
        },
      );
      expect(result.value, 64);
    });
  });

  group('クランプと不変条件', () {
    test('極端入力でも 0..100 に収まる', () {
      final worst = MriCalculator.calculate(_snapshot(
        temp: 48,
        apparent: 55,
        humidity: 100,
        uv: 12,
        aqi: 500,
        pollen: PollenLevel.veryHigh,
        wind: 25,
        pressureChange6h: -20,
      ));
      expect(worst.value, inInclusiveRange(0, 100));
      expect(worst.band, MriBand.hotAlert);

      final freezing = MriCalculator.calculate(_snapshot(
        temp: -20,
        apparent: -30,
        humidity: 30,
        uv: 0,
        aqi: 10,
        pollen: PollenLevel.none,
        wind: 0,
      ));
      expect(freezing.value, inInclusiveRange(0, 100));
    });

    test('factorContributions の合計 = MRI_base (Δ補正は thermalAdjustment 側)', () {
      final result = MriCalculator.calculate(_snapshot());
      final base =
          result.factorContributions.values.fold<double>(0, (a, b) => a + b);
      expect(base, closeTo(94.61, 0.01));
      expect(result.thermalAdjustment, 0);
    });
  });
}
