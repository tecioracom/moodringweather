// lib/providers/mri_provider.dart
//
// WeatherSnapshot → MriCalculator の配線 (Riverpod)。
// 学習済みの感受性ベクトル θ (personalProfileProvider) を MriCalculator に
// 渡して MRI を個人補正する (mri-spec.md §6)。未学習時 (ランプイン前) は
// デフォルト計算と一致する。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/mood_ring_index.dart';
import '../domain/mri/mri_calculator.dart';
import '../domain/mri/mri_timeline.dart';
import 'calibration_provider.dart';
import 'weather_provider.dart';

final mriProvider = Provider<AsyncValue<MoodRingIndex>>((ref) {
  final profile = ref.watch(personalProfileProvider);
  final snapshot = ref.watch(weatherSnapshotProvider);
  return snapshot.whenData(
    (s) => MriCalculator.calculate(s, profile: profile),
  );
});

/// 24 時間の MRI 時系列 (Detail / Calibration 画面のバーチャート用)。
/// hourlyWeatherProvider の各時刻に MriCalculator (θ 適用) を適用する。
final mriTimelineProvider = Provider<AsyncValue<List<MriTimelinePoint>>>((ref) {
  final profile = ref.watch(personalProfileProvider);
  final hourly = ref.watch(hourlyWeatherProvider);
  return hourly.whenData(
    (list) => MriTimeline.fromSnapshots(list, profile: profile),
  );
});
