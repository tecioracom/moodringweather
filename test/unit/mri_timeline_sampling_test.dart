// MriTimeline.valueAt / sample (直線補間) のユニット。Home の Sparkline (1.5 時間刻み) 用。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/domain/mri/mri_timeline.dart';

MriTimelinePoint _p(DateTime t, int mri) => MriTimelinePoint(
      snapshot: WeatherSnapshot(
        timestamp: t,
        latitude: 0,
        longitude: 0,
        temperature: 20,
      ),
      mri: MoodRingIndex(
        value: mri,
        band: MriBand.comfortable,
        calculatedAt: t,
        factorContributions: const {},
      ),
    );

void main() {
  final t0 = DateTime(2026, 7, 15, 12);
  final points = [
    _p(t0, 60),
    _p(t0.add(const Duration(hours: 1)), 70),
    _p(t0.add(const Duration(hours: 2)), 50),
  ];

  test('点の上ではその値、点の間は直線補間', () {
    expect(MriTimeline.valueAt(points, t0), 60);
    expect(
        MriTimeline.valueAt(points, t0.add(const Duration(minutes: 30))), 65);
    expect(
        MriTimeline.valueAt(points, t0.add(const Duration(minutes: 90))), 60);
    expect(MriTimeline.valueAt(points, t0.add(const Duration(hours: 2))), 50);
  });

  test('範囲外・空は null', () {
    expect(MriTimeline.valueAt(points, t0.subtract(const Duration(minutes: 1))),
        isNull);
    expect(
        MriTimeline.valueAt(points, t0.add(const Duration(hours: 3))), isNull);
    expect(MriTimeline.valueAt(const [], t0), isNull);
  });

  test('sample: 1.5 時間刻みで 3 点', () {
    final s = MriTimeline.sample(points,
        start: t0, step: const Duration(minutes: 90), count: 3);
    expect(s, [60, 60, null]);
  });

  test('未ソートの入力でも補間できる', () {
    final shuffled = [points[2], points[0], points[1]];
    expect(
        MriTimeline.valueAt(shuffled, t0.add(const Duration(minutes: 30))), 65);
  });
}
