// 緊急アラート判定器 (lib/domain/safety/emergency_advisor.dart) のユニット。
// test/_pending/emergency_advisor_test.dart.pending を実装に合わせて整理・拡張。
//   - 熱中症の発火しきい値 WBGT 31 (severe) / 33 (danger) — mri-spec.md §5.3.1。
//     表示用の WbgtLevel 区分からは発火を導出しない
//   - 風速 / 降雪のしきい値境界
//   - de-dup (クールダウン・深刻度エスカレーション・永続化 round-trip)

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/pollen_level.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/safety/emergency_advisor.dart';
import 'package:mood_ring_weather/domain/safety/wbgt_calculator.dart';

WeatherSnapshot makeSnapshot({
  double temp = 25,
  double? humidity = 50,
  double? wind = 3,
  double? solar,
  double? snowfallCm,
  int aqi = 40,
}) =>
    WeatherSnapshot(
      timestamp: DateTime(2026, 7, 15, 12),
      latitude: 35.66,
      longitude: 139.75,
      temperature: temp,
      apparentTemperature: temp,
      humidity: humidity,
      pressure: 1013,
      windSpeed: wind,
      uvIndex: 5,
      aqi: aqi,
      pollen: PollenLevel.low,
      solarRadiationWm2: solar,
      snowfallCm: snowfallCm,
      condition: 'sunny',
    );

void main() {
  const advisor = EmergencyAdvisor();

  group('EmergencyAdvisor: 基本', () {
    test('快適時は何も通知しない', () {
      expect(advisor.evaluate(makeSnapshot()), isEmpty);
    });

    test('猛暑 (WBGT 危険級) で熱中症通知', () {
      final alerts = advisor.evaluate(
        makeSnapshot(temp: 36, humidity: 70),
        solarRadiationWm2: 800,
      );
      final heat =
          alerts.where((a) => a.kind == EmergencyKind.heatStroke).toList();
      expect(heat, hasLength(1));
      expect(heat.single.severity, EmergencySeverity.danger);
    });

    test('スナップショット側の solarRadiationWm2 / snowfallCm も使われる', () {
      final alerts = advisor.evaluate(
        makeSnapshot(temp: 36, humidity: 70, solar: 800, snowfallCm: 4),
      );
      expect(alerts.map((a) => a.kind),
          containsAll([EmergencyKind.heatStroke, EmergencyKind.heavySnow]));
    });

    test('湿度欠測時は熱中症判定をスキップする (誤発火させない)', () {
      final alerts = advisor.evaluate(
        makeSnapshot(temp: 40, humidity: null),
        solarRadiationWm2: 800,
      );
      expect(alerts.where((a) => a.kind == EmergencyKind.heatStroke), isEmpty);
    });

    test('通知 ID は kind ごとに固定 (1001-1003)', () {
      final alerts = advisor.evaluate(
        makeSnapshot(temp: 36, humidity: 70, wind: 30),
        solarRadiationWm2: 800,
        snowfallCm: 25,
      );
      expect(alerts.length, 3);
      expect(
        alerts.map((a) => a.notificationId).toSet(),
        equals({1001, 1002, 1003}),
      );
    });
  });

  group('EmergencyAdvisor: 熱中症の発火しきい値 (mri-spec §5.3.1)', () {
    // 発火条件が「WBGT ≥ 31 で severe / ≥ 33 で danger」(表示用の
    // WbgtLevel 区分とは独立) であることを温度 × 湿度のグリッドで確認する。
    test(
        '発火条件 = WBGT ≥ heatSevereWbgtC / danger = ≥ heatDangerWbgtC '
        '(グリッド検証)', () {
      var seenBelow = 0;
      var seenSevere = 0;
      var seenDanger = 0;
      for (var temp = 15.0; temp <= 42.0; temp += 1.5) {
        for (var rh = 20.0; rh <= 95.0; rh += 7.5) {
          final wbgt = WbgtCalculator.compute(
            tempC: temp,
            humidityPercent: rh,
            solarRadiationWm2: 300,
          );
          final alerts = advisor.evaluate(
            makeSnapshot(temp: temp, humidity: rh),
            solarRadiationWm2: 300,
          );
          final heat =
              alerts.where((a) => a.kind == EmergencyKind.heatStroke).toList();
          if (wbgt >= EmergencyAdvisor.heatSevereWbgtC) {
            expect(heat, hasLength(1),
                reason: 'WBGT=$wbgt は発火すべき (T=$temp RH=$rh)');
            final expected = wbgt >= EmergencyAdvisor.heatDangerWbgtC
                ? EmergencySeverity.danger
                : EmergencySeverity.severe;
            expect(heat.single.severity, expected,
                reason: 'WBGT=$wbgt の severity 対応 (T=$temp RH=$rh)');
            expect(heat.single.metricValue, closeTo(wbgt, 1e-9));
            expected == EmergencySeverity.danger ? seenDanger++ : seenSevere++;
          } else {
            expect(heat, isEmpty,
                reason: 'WBGT=$wbgt (< 31) は発火しない (T=$temp RH=$rh)');
            seenBelow++;
          }
        }
      }
      // グリッドが 非発火 / severe / danger をすべて実際に踏んだことを保証。
      expect(seenBelow, greaterThan(0));
      expect(seenSevere, greaterThan(0));
      expect(seenDanger, greaterThan(0));
    });

    // mri-spec §8.3 の期待値 (Ta=30 RH=70 SR=800 → WBGT 33.00) に整合する
    // danger 境界。実計算値 32.997 は 33 直下のため severe 側に落ちる。
    test('31 ≤ WBGT < 33 は severe (Ta=30 RH=70 SR=800 ≈ 33.00 直下)', () {
      final wbgt = WbgtCalculator.compute(
        tempC: 30,
        humidityPercent: 70,
        solarRadiationWm2: 800,
      );
      expect(wbgt, closeTo(33.00, 0.05)); // §8.3 期待値テーブル
      expect(wbgt, lessThan(EmergencyAdvisor.heatDangerWbgtC));
      expect(wbgt, greaterThanOrEqualTo(EmergencyAdvisor.heatSevereWbgtC));
      final alert = advisor
          .evaluate(makeSnapshot(temp: 30, humidity: 70),
              solarRadiationWm2: 800)
          .singleWhere((a) => a.kind == EmergencyKind.heatStroke);
      expect(alert.severity, EmergencySeverity.severe);
    });

    test(
        'WBGT ≥ 33.00 (danger 境界・警戒アラート発表基準値) で danger '
        '(Ta=30 RH=70 SR=810 ≈ 33.07)', () {
      final wbgt = WbgtCalculator.compute(
        tempC: 30,
        humidityPercent: 70,
        solarRadiationWm2: 810,
      );
      expect(wbgt, greaterThanOrEqualTo(EmergencyAdvisor.heatDangerWbgtC));
      final alert = advisor
          .evaluate(makeSnapshot(temp: 30, humidity: 70),
              solarRadiationWm2: 810)
          .singleWhere((a) => a.kind == EmergencyKind.heatStroke);
      expect(alert.severity, EmergencySeverity.danger);
    });

    test(
        '28 ≤ WBGT < 31 (厳重警戒・表示のみ) ではプッシュしない '
        '(Ta=32 RH=60 SR=300 ≈ 29.93)', () {
      final wbgt = WbgtCalculator.compute(
        tempC: 32,
        humidityPercent: 60,
        solarRadiationWm2: 300,
      );
      // 表示分類では severe (厳重警戒) 域であることを前提確認。
      expect(WbgtCalculator.level(wbgt), WbgtLevel.severe);
      expect(wbgt, lessThan(EmergencyAdvisor.heatSevereWbgtC));
      final alerts = advisor.evaluate(
        makeSnapshot(temp: 32, humidity: 60),
        solarRadiationWm2: 300,
      );
      expect(alerts.where((a) => a.kind == EmergencyKind.heatStroke), isEmpty);
    });
  });

  group('EmergencyAdvisor: 暴風しきい値境界', () {
    test('19.9 m/s では発火しない', () {
      expect(
        advisor
            .evaluate(makeSnapshot(wind: 19.9))
            .where((a) => a.kind == EmergencyKind.storm),
        isEmpty,
      );
    });

    test('20 m/s (下端含む) で severe', () {
      final alert = advisor
          .evaluate(makeSnapshot(wind: 20))
          .singleWhere((a) => a.kind == EmergencyKind.storm);
      expect(alert.severity, EmergencySeverity.severe);
      expect(alert.metricValue, 20);
    });

    test('30 m/s (下端含む) で danger', () {
      final alert = advisor
          .evaluate(makeSnapshot(wind: 30))
          .singleWhere((a) => a.kind == EmergencyKind.storm);
      expect(alert.severity, EmergencySeverity.danger);
    });

    test('風速欠測ではスキップ', () {
      expect(advisor.evaluate(makeSnapshot(wind: null)), isEmpty);
    });
  });

  group('EmergencyAdvisor: 大雪しきい値境界', () {
    test('2.9 cm/h では発火しない', () {
      expect(advisor.evaluate(makeSnapshot(), snowfallCm: 2.9), isEmpty);
    });

    test('3 cm/h (下端含む) で severe', () {
      final alert = advisor
          .evaluate(makeSnapshot(), snowfallCm: 3)
          .singleWhere((a) => a.kind == EmergencyKind.heavySnow);
      expect(alert.severity, EmergencySeverity.severe);
    });

    test('5 cm/h (下端含む) で danger', () {
      final alert = advisor
          .evaluate(makeSnapshot(), snowfallCm: 5)
          .singleWhere((a) => a.kind == EmergencyKind.heavySnow);
      expect(alert.severity, EmergencySeverity.danger);
    });

    test('降雪データ欠測ではスキップ', () {
      expect(advisor.evaluate(makeSnapshot()), isEmpty);
    });
  });

  group('EmergencyAlertDeduper: 再発火防止', () {
    final base = DateTime(2026, 7, 15, 12);

    test('初回は発火できる', () {
      final deduper = EmergencyAlertDeduper();
      expect(deduper.shouldFire('heatStroke:severe', base), isTrue);
    });

    test('クールダウン内の同一キーは抑止される', () {
      final deduper = EmergencyAlertDeduper(cooldown: const Duration(hours: 6));
      deduper.recordFired('heatStroke:severe', base);
      expect(
        deduper.shouldFire(
            'heatStroke:severe', base.add(const Duration(hours: 5))),
        isFalse,
      );
      expect(
        deduper.shouldFire(
            'heatStroke:severe', base.add(const Duration(hours: 6))),
        isTrue,
      );
    });

    test('深刻度が上がるとキーが変わり即時発火できる (安全側)', () {
      final deduper = EmergencyAlertDeduper();
      deduper.recordFired('heatStroke:severe', base);
      expect(
        deduper.shouldFire(
            'heatStroke:danger', base.add(const Duration(minutes: 1))),
        isTrue,
      );
    });

    test('toJson / fromJson round-trip で記録が保持される', () {
      final deduper = EmergencyAlertDeduper();
      deduper.recordFired('storm:severe', base);
      final restored = EmergencyAlertDeduper.fromJson(deduper.toJson());
      expect(
        restored.shouldFire('storm:severe', base.add(const Duration(hours: 1))),
        isFalse,
      );
      expect(restored.shouldFire('heavySnow:severe', base), isTrue);
    });

    test('壊れた値は無視して発火側に倒す', () {
      final restored = EmergencyAlertDeduper.fromJson(
        {'storm:severe': 'not-a-date', 'snow': 12},
      );
      expect(restored.shouldFire('storm:severe', base), isTrue);
    });
  });
}
