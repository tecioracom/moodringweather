// lib/domain/mri/mri_timeline.dart
//
// 毎時 WeatherSnapshot の列 → MRI 時系列への変換 (Detail 画面の
// 24 時間バーチャート用)。docs/mri-spec.md の MriCalculator を
// 各時刻へそのまま適用する。純 Dart (Flutter 非依存)。
// ユニットテスト: test/unit/mri_timeline_test.dart

import '../../data/models/mood_ring_index.dart';
import '../../data/models/personal_profile.dart';
import '../../data/models/weather_snapshot.dart';
import 'mri_calculator.dart';

/// 1 時刻分の (気象スナップショット, MRI) ペア。
class MriTimelinePoint {
  const MriTimelinePoint({required this.snapshot, required this.mri});

  final WeatherSnapshot snapshot;
  final MoodRingIndex mri;

  DateTime get timestamp => snapshot.timestamp;
}

class MriTimeline {
  MriTimeline._();

  /// スナップショット列を時刻昇順に整列し、各時刻に MriCalculator を
  /// 適用した時系列を返す。[weights] はカスタム重み (未学習時は null →
  /// デフォルト重み)、[profile] は学習済みの感受性ベクトル θ
  /// (mri-spec.md §6。null なら補正なし)。
  static List<MriTimelinePoint> fromSnapshots(
    List<WeatherSnapshot> snapshots, {
    Map<String, double>? weights,
    PersonalProfile? profile,
  }) {
    final sorted = [...snapshots]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return [
      for (final s in sorted)
        MriTimelinePoint(
          snapshot: s,
          mri: MriCalculator.calculate(s, weights: weights, profile: profile),
        ),
    ];
  }

  /// [at] 時点の MRI 値を直線補間で返す。点が 1 つも無い、または [at] が
  /// 系列の範囲外なら null。Home の Sparkline (1.5 時間刻み) など、毎時の
  /// 系列を別の刻みで標本化するために使う。
  static double? valueAt(List<MriTimelinePoint> points, DateTime at) {
    if (points.isEmpty) return null;
    final sorted = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (at.isBefore(sorted.first.timestamp) ||
        at.isAfter(sorted.last.timestamp)) {
      return null;
    }
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (!at.isBefore(a.timestamp) && !at.isAfter(b.timestamp)) {
        final span = b.timestamp.difference(a.timestamp).inSeconds;
        if (span == 0) return a.mri.value.toDouble();
        final t = at.difference(a.timestamp).inSeconds / span;
        return a.mri.value + (b.mri.value - a.mri.value) * t;
      }
    }
    return sorted.last.mri.value.toDouble();
  }

  /// [start] から [step] 刻みで [count] 個を標本化する (範囲外は null)。
  static List<double?> sample(
    List<MriTimelinePoint> points, {
    required DateTime start,
    required Duration step,
    required int count,
  }) {
    return [
      for (var i = 0; i < count; i++) valueAt(points, start.add(step * i)),
    ];
  }

  /// [at] に最も近い点 (空なら null)。
  static MriTimelinePoint? nearest(List<MriTimelinePoint> points, DateTime at) {
    final i = indexNearest(points, reference: at);
    return i < 0 ? null : points[i];
  }

  /// [reference] (既定: 現在時刻) に最も近い時刻の点のインデックス。
  /// 空リストは -1。
  static int indexNearest(
    List<MriTimelinePoint> points, {
    DateTime? reference,
  }) {
    if (points.isEmpty) return -1;
    final ref = reference ?? DateTime.now();
    var best = 0;
    var bestDiff = points[0].timestamp.difference(ref).abs();
    for (var i = 1; i < points.length; i++) {
      final diff = points[i].timestamp.difference(ref).abs();
      if (diff < bestDiff) {
        best = i;
        bestDiff = diff;
      }
    }
    return best;
  }
}
