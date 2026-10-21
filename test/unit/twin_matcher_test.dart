// test/unit/twin_matcher_test.dart
//
// Comfort-Twin マッチング (domain/comfort_twin/twin_matcher.dart) の
// ユニットテスト: 類似度写像 / ランキング / 同点処理 / limit / 空入力。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';

City _city(String id, String name) => City(
      id: id,
      name: name,
      country: 'Testland',
      latitude: 0,
      longitude: 0,
      emoji: '🌍',
    );

WeatherSnapshot _snapshot() => WeatherSnapshot(
      timestamp: DateTime(2026, 6, 11, 12),
      latitude: 0,
      longitude: 0,
      temperature: 22,
    );

CityComfort _candidate(String id, String name, int mri) => CityComfort(
      city: _city(id, name),
      snapshot: _snapshot(),
      mri: MoodRingIndex(
        value: mri,
        band: MriBand.fromValue(mri),
        factorContributions: const {},
        calculatedAt: DateTime(2026, 6, 11, 12),
      ),
    );

void main() {
  group('TwinMatcher.similarity', () {
    test('MRI 完全一致 → 100%', () {
      expect(TwinMatcher.similarity(64, 64), 100.0);
    });

    test('|差| が 1 につき 1% 減衰する線形写像', () {
      expect(TwinMatcher.similarity(64, 54), 90.0);
      expect(TwinMatcher.similarity(64, 74), 90.0);
      expect(TwinMatcher.similarity(50, 25), 75.0);
    });

    test('最大差 (0 ⇄ 100) → 0%', () {
      expect(TwinMatcher.similarity(0, 100), 0.0);
      expect(TwinMatcher.similarity(100, 0), 0.0);
    });

    test('範囲外入力は 0–100 にクランプして評価する', () {
      expect(TwinMatcher.similarity(120, 100), 100.0);
      expect(TwinMatcher.similarity(-10, 0), 100.0);
    });
  });

  group('TwinMatcher.rank', () {
    test('類似度の高い順に並び、rank は 1 始まりで連番', () {
      final matches = TwinMatcher.rank(64, [
        _candidate('a', 'Anchorage', 20), // 56%
        _candidate('b', 'Barcelona', 64), // 100%
        _candidate('c', 'Cairo', 50), // 86%
      ]);

      expect(matches.map((m) => m.city.id).toList(), ['b', 'c', 'a']);
      expect(matches.map((m) => m.rank).toList(), [1, 2, 3]);
      expect(matches[0].similarity, 100.0);
      expect(matches[1].similarity, 86.0);
      expect(matches[2].similarity, 56.0);
    });

    test('同点 (ターゲットを挟んで等距離) は都市名の辞書順で決定的', () {
      final matches = TwinMatcher.rank(50, [
        _candidate('z', 'Zurich', 60), // 90%
        _candidate('a', 'Athens', 40), // 90%
      ]);

      expect(matches[0].city.name, 'Athens');
      expect(matches[1].city.name, 'Zurich');
      expect(matches[0].similarity, matches[1].similarity);
    });

    test('都市名まで同じ場合は ID の辞書順', () {
      final matches = TwinMatcher.rank(50, [
        _candidate('b2', 'Springfield', 45),
        _candidate('a1', 'Springfield', 55),
      ]);

      expect(matches[0].city.id, 'a1');
      expect(matches[1].city.id, 'b2');
    });

    test('limit で上位 N 件に絞れる (N > 件数なら全件)', () {
      final candidates = [
        _candidate('a', 'A', 64),
        _candidate('b', 'B', 54),
        _candidate('c', 'C', 44),
      ];
      expect(TwinMatcher.rank(64, candidates, limit: 2).length, 2);
      expect(TwinMatcher.rank(64, candidates, limit: 10).length, 3);
    });

    test('空の候補リスト → 空のランキング', () {
      expect(TwinMatcher.rank(64, const []), isEmpty);
    });

    test('入力リストは破壊しない', () {
      final candidates = [
        _candidate('a', 'A', 10),
        _candidate('b', 'B', 90),
      ];
      TwinMatcher.rank(64, candidates);
      expect(candidates[0].city.id, 'a');
      expect(candidates[1].city.id, 'b');
    });
  });
}
