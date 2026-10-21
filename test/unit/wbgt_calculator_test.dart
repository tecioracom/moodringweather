import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/domain/safety/wbgt_calculator.dart';

void main() {
  group('WbgtCalculator', () {
    test('快適域 (25°C / 40% RH) は 18〜23°C', () {
      final v = WbgtCalculator.compute(tempC: 25, humidityPercent: 40);
      expect(v, inInclusiveRange(18, 23));
    });

    test('猛暑日 (35°C / 70% RH + 強日射) は 31°C 超え', () {
      final v = WbgtCalculator.compute(
        tempC: 35,
        humidityPercent: 70,
        solarRadiationWm2: 800,
      );
      expect(v, greaterThan(31));
    });

    test('湿度が上がると WBGT も上がる', () {
      final dry = WbgtCalculator.compute(tempC: 30, humidityPercent: 30);
      final humid = WbgtCalculator.compute(tempC: 30, humidityPercent: 90);
      expect(humid, greaterThan(dry));
    });

    test('level マッピングが環境省指針に一致 (表示用区分 21/25/28/31)', () {
      expect(WbgtCalculator.level(20), WbgtLevel.safe);
      expect(WbgtCalculator.level(22), WbgtLevel.caution);
      expect(WbgtCalculator.level(26), WbgtLevel.warning);
      expect(WbgtCalculator.level(29), WbgtLevel.severe);
      expect(WbgtCalculator.level(32), WbgtLevel.danger);
    });

    // docs/mri-spec.md §8.3 期待値テーブル (Stull Tw + Tg = Ta + 0.038×SR)。
    // 許容誤差 ±0.05°C。
    test('mri-spec.md §8.3 の期待値テーブルに一致', () {
      const cases = [
        // (Ta, RH, SR, Tw, WBGT)
        (22.0, 50.0, 500.0, 15.42, 21.19),
        (25.0, 50.0, 600.0, 18.00, 24.66),
        (30.0, 80.0, 0.0, 27.13, 27.99),
        (30.0, 70.0, 800.0, 25.60, 33.00),
        (33.0, 65.0, 850.0, 27.55, 35.65),
        (35.0, 55.0, 950.0, 27.56, 37.01),
        (36.0, 60.0, 900.0, 29.39, 38.21),
      ];
      for (final (ta, rh, sr, tw, wbgt) in cases) {
        expect(WbgtCalculator.wetBulbStull(ta, rh), closeTo(tw, 0.05),
            reason: 'Tw(Ta=$ta, RH=$rh)');
        expect(
          WbgtCalculator.compute(
            tempC: ta,
            humidityPercent: rh,
            solarRadiationWm2: sr,
          ),
          closeTo(wbgt, 0.05),
          reason: 'WBGT(Ta=$ta, RH=$rh, SR=$sr)',
        );
      }
    });
  });
}
