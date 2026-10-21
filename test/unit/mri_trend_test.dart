// MriTrendClassifier (lib/domain/mri/mri_trend.dart) のユニット。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/domain/mri/mri_trend.dart';

void main() {
  test('先が今より 8 以上下がるなら riskRises', () {
    expect(MriTrendClassifier.classify(now: 74, future: [72, 70, 66, 65]),
        MriTrend.riskRises);
  });
  test('先が今より 8 以上上がるなら easing', () {
    expect(MriTrendClassifier.classify(now: 40, future: [42, 45, 48, 50]),
        MriTrend.easing);
  });
  test('±8 未満なら stable', () {
    expect(MriTrendClassifier.classify(now: 74, future: [73, 75, 70, 78]),
        MriTrend.stable);
  });
  test('境界: ちょうど 8 は該当、7 は非該当', () {
    expect(
        MriTrendClassifier.classify(now: 50, future: [42]), MriTrend.riskRises);
    expect(MriTrendClassifier.classify(now: 50, future: [43]), MriTrend.stable);
    expect(MriTrendClassifier.classify(now: 50, future: [58]), MriTrend.easing);
  });
  test('両方に該当するときは安全側 (riskRises)', () {
    expect(MriTrendClassifier.classify(now: 50, future: [60, 40]),
        MriTrend.riskRises);
  });
  test('先が空なら stable', () {
    expect(MriTrendClassifier.classify(now: 50, future: const []),
        MriTrend.stable);
  });
}
