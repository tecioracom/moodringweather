// test/unit/metric_levels_test.dart
//
// UV (WHO・気象庁 5 区分) と空気質 (US EPA 6 区分) の段階の判定
// (docs/design-metric-units-proposal.md §2.2・§2.3)。境界の両側
// (2/3, 5/6, 7/8, 10/11, 50/51, 100/101, 150/151, 200/201, 300/301) を検査する。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/domain/metrics/metric_levels.dart';

void main() {
  group('UvLevel.of (表示している整数で判定)', () {
    const boundaries = <(int, UvLevel)>[
      (0, UvLevel.low), // 夜間の 0 も「弱い / Low」(WHO どおり)
      (2, UvLevel.low),
      (3, UvLevel.moderate),
      (5, UvLevel.moderate),
      (6, UvLevel.high),
      (7, UvLevel.high),
      (8, UvLevel.veryHigh),
      (10, UvLevel.veryHigh),
      (11, UvLevel.extreme),
      (16, UvLevel.extreme),
    ];
    for (final (uv, level) in boundaries) {
      test('UV $uv → ${level.name}', () {
        expect(UvLevel.of(uv), level);
      });
    }

    test('負の値 (データの誤り) は low', () {
      expect(UvLevel.of(-1), UvLevel.low);
    });

    test('段階は四捨五入した表示値で決まる (2.5 → 「3」→ 中程度)', () {
      // 「3」と表示して「弱い」にならないこと。
      expect(shownUvIndex(2.5), 3);
      expect(UvLevel.of(shownUvIndex(2.5)), UvLevel.moderate);
      expect(shownUvIndex(2.49), 2);
      expect(UvLevel.of(shownUvIndex(2.49)), UvLevel.low);
      expect(UvLevel.of(shownUvIndex(10.5)), UvLevel.extreme); // 「11」
      expect(UvLevel.of(shownUvIndex(10.4)), UvLevel.veryHigh); // 「10」
    });
  });

  group('AqiLevel.of (整数の US AQI)', () {
    const boundaries = <(int, AqiLevel)>[
      (0, AqiLevel.good),
      (50, AqiLevel.good),
      (51, AqiLevel.moderate),
      (100, AqiLevel.moderate),
      (101, AqiLevel.unhealthyForSensitiveGroups),
      (150, AqiLevel.unhealthyForSensitiveGroups),
      (151, AqiLevel.unhealthy),
      (200, AqiLevel.unhealthy),
      (201, AqiLevel.veryUnhealthy),
      (300, AqiLevel.veryUnhealthy),
      (301, AqiLevel.hazardous),
      (500, AqiLevel.hazardous),
    ];
    for (final (aqi, level) in boundaries) {
      test('AQI $aqi → ${level.name}', () {
        expect(AqiLevel.of(aqi), level);
      });
    }

    test('負の値 (データの誤り) は good', () {
      expect(AqiLevel.of(-5), AqiLevel.good);
    });
  });
}
