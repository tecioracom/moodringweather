// test/unit/mri_timeline_test.dart
//
// hourly スナップショット列 → MRI 時系列 (MriTimeline) の変換テスト。
// 期待 MRI は docs/mri-spec.md §8.1 の qa テーブルと 1:1 対応。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/pollen_level.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/domain/mri/mri_calculator.dart';
import 'package:mood_ring_weather/domain/mri/mri_timeline.dart';

WeatherSnapshot _snapshot(
  DateTime time, {
  required double temp,
  required double humidity,
  required double uv,
  required int aqi,
  PollenLevel pollen = PollenLevel.low,
  required double wind,
  double pressureChange6h = 0,
  required double tApp,
}) {
  return WeatherSnapshot(
    timestamp: time,
    latitude: 35.66,
    longitude: 139.70,
    temperature: temp,
    apparentTemperature: tApp,
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

void main() {
  final base = DateTime(2026, 6, 11, 0);

  group('MriTimeline.fromSnapshots', () {
    test('mri-spec §8.1 の各ケースが期待 MRI / バンドに変換される', () {
      final snapshots = [
        // ケース 1: 参照快適日 → 64 comfortable
        _snapshot(base,
            temp: 22, humidity: 50, uv: 3, aqi: 42, wind: 2, tApp: 22),
        // ケース 3: 猛暑 (アラート域) → 24 hot
        _snapshot(base.add(const Duration(hours: 1)),
            temp: 36, humidity: 60, uv: 9, aqi: 55, wind: 2, tApp: 44),
        // ケース 6: 冬晴れ → 87 cool
        _snapshot(base.add(const Duration(hours: 2)),
            temp: 5,
            humidity: 35,
            uv: 2,
            aqi: 40,
            pollen: PollenLevel.none,
            wind: 4,
            tApp: 2),
        // ケース 7: 低気圧の雨 → 57 warm
        _snapshot(base.add(const Duration(hours: 3)),
            temp: 20,
            humidity: 85,
            uv: 1,
            aqi: 25,
            wind: 5,
            pressureChange6h: -7,
            tApp: 19),
      ];

      final timeline = MriTimeline.fromSnapshots(snapshots);

      expect(timeline, hasLength(4));
      expect(timeline.map((p) => p.mri.value), [64, 24, 87, 57]);
      expect(timeline.map((p) => p.mri.band), [
        MriBand.comfortable,
        MriBand.hot,
        MriBand.cool,
        MriBand.warm,
      ]);
    });

    test('入力順序によらず時刻昇順に整列される', () {
      final s0 = _snapshot(base,
          temp: 22, humidity: 50, uv: 3, aqi: 42, wind: 2, tApp: 22);
      final s1 = _snapshot(base.add(const Duration(hours: 5)),
          temp: 30, humidity: 70, uv: 6, aqi: 80, wind: 1, tApp: 34);
      final s2 = _snapshot(base.add(const Duration(hours: 10)),
          temp: 15, humidity: 45, uv: 2, aqi: 30, wind: 2, tApp: 14);

      final timeline = MriTimeline.fromSnapshots([s2, s0, s1]);

      expect(
        timeline.map((p) => p.timestamp),
        [s0.timestamp, s1.timestamp, s2.timestamp],
      );
    });

    test('各点の MRI は MriCalculator.calculate と一致する', () {
      final snapshots = [
        for (var h = 0; h < 24; h++)
          _snapshot(base.add(Duration(hours: h)),
              temp: 18 + h * 0.5,
              humidity: 40.0 + h,
              uv: (h - 6).clamp(0, 10).toDouble(),
              aqi: 30 + h,
              wind: 1 + h * 0.2,
              tApp: 18 + h * 0.6),
      ];

      final timeline = MriTimeline.fromSnapshots(snapshots);

      expect(timeline, hasLength(24));
      for (final point in timeline) {
        final expected = MriCalculator.calculate(point.snapshot);
        expect(point.mri.value, expected.value,
            reason: '時刻 ${point.timestamp} の MRI が単発計算と不一致');
        expect(point.mri.band, expected.band);
      }
    });

    test('空リストは空の時系列を返す', () {
      expect(MriTimeline.fromSnapshots(const []), isEmpty);
    });
  });

  group('MriTimeline.indexNearest', () {
    test('基準時刻に最も近い点のインデックスを返す', () {
      final points = MriTimeline.fromSnapshots([
        for (var h = 0; h < 24; h++)
          _snapshot(base.add(Duration(hours: h)),
              temp: 22, humidity: 50, uv: 3, aqi: 42, wind: 2, tApp: 22),
      ]);

      expect(
        MriTimeline.indexNearest(points,
            reference: base.add(const Duration(hours: 7, minutes: 10))),
        7,
      );
      expect(
        MriTimeline.indexNearest(points,
            reference: base.subtract(const Duration(hours: 3))),
        0,
      );
      expect(
        MriTimeline.indexNearest(points,
            reference: base.add(const Duration(days: 2))),
        23,
      );
    });

    test('空リストは -1', () {
      expect(MriTimeline.indexNearest(const []), -1);
    });
  });
}
