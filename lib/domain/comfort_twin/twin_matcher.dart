// lib/domain/comfort_twin/twin_matcher.dart
//
// Comfort-Twin マッチング (純 Dart / Flutter 非依存)。
// 目標 MRI (ターゲット体感) に対して候補都市の MRI 類似度を算出し、
// 類似順にランキングする。ユニットテスト: test/unit/twin_matcher_test.dart
//
// 類似度の定義:
//   similarity = 100 − |MRI_city − MRI_target|  (MRI は 0–100 の int なので
//   |差| ∈ [0,100] がそのまま 100%–0% へ線形に写像される)

import '../../data/models/city.dart';
import '../../data/models/mood_ring_index.dart';
import '../../data/models/weather_snapshot.dart';

/// 候補都市 1 件の「現在の体感」(都市 + 気象スナップショット + MRI)。
class CityComfort {
  const CityComfort({
    required this.city,
    required this.snapshot,
    required this.mri,
  });

  final City city;
  final WeatherSnapshot snapshot;
  final MoodRingIndex mri;
}

/// ランキング結果 1 件 (rank は 1 始まり)。
class TwinMatch {
  const TwinMatch({
    required this.rank,
    required this.candidate,
    required this.similarity,
  });

  final int rank;
  final CityComfort candidate;

  /// 類似度 (0–100。100 = MRI 完全一致)。
  final double similarity;

  City get city => candidate.city;
  WeatherSnapshot get snapshot => candidate.snapshot;
  MoodRingIndex get mri => candidate.mri;
}

class TwinMatcher {
  TwinMatcher._();

  /// |MRI_city − MRI_target| を 0–100% の類似度へ線形に写像する。
  static double similarity(int targetMri, int cityMri) {
    final t = targetMri.clamp(0, 100);
    final c = cityMri.clamp(0, 100);
    return (100.0 - (c - t).abs()).clamp(0.0, 100.0);
  }

  /// 候補都市を類似度の高い順にランキングする。
  ///
  /// 同点 (類似度が等しい) の場合は都市名の辞書順 → ID の辞書順で
  /// 決定的に並べる (テスト・UI の安定性のため)。
  /// [limit] を与えると上位 N 件に絞る。
  static List<TwinMatch> rank(
    int targetMri,
    List<CityComfort> candidates, {
    int? limit,
  }) {
    final scored = [
      for (final c in candidates)
        (candidate: c, similarity: similarity(targetMri, c.mri.value)),
    ]..sort((a, b) {
        final bySim = b.similarity.compareTo(a.similarity);
        if (bySim != 0) return bySim;
        final byName = a.candidate.city.name.compareTo(b.candidate.city.name);
        if (byName != 0) return byName;
        return a.candidate.city.id.compareTo(b.candidate.city.id);
      });

    final n = limit == null || limit > scored.length ? scored.length : limit;
    return [
      for (var i = 0; i < n; i++)
        TwinMatch(
          rank: i + 1,
          candidate: scored[i].candidate,
          similarity: scored[i].similarity,
        ),
    ];
  }
}
