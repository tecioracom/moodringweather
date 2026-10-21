// MriBarScale (capsule bar の自動スケール) と参照バンドの値域のユニット。
// docs/home-sparkline-decisions.md 決定 ① / ④

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/shared/mri_bar_scale.dart';

void main() {
  test('下端は切り捨て・上端は切り上げの 10 刻み', () {
    final s = MriBarScale.forSamples(const [42.0, 58.0, 71.0]);
    expect(s.lo, 40);
    expect(s.hi, 80);
  });

  test('幅が 20 未満なら上下へ 10 ずつ広げる', () {
    // 64 だけ → 60/70 (幅 10) では狭いので 50/80 まで広げる。
    final s = MriBarScale.forSamples(const [64.0]);
    expect(s.hi - s.lo, greaterThanOrEqualTo(MriBarScale.minSpan));
    expect(s.lo, 50);
    expect(s.hi, 80);
  });

  test('0–100 の外へは出ない', () {
    expect(MriBarScale.forSamples(const [0.0]).lo, 0);
    expect(MriBarScale.forSamples(const [100.0]).hi, 100);
    expect(MriBarScale.forSamples(const [0.0]).span,
        greaterThanOrEqualTo(MriBarScale.minSpan));
    expect(MriBarScale.forSamples(const [100.0]).span,
        greaterThanOrEqualTo(MriBarScale.minSpan));
  });

  test('null は無視し、全部 null / 空なら既定', () {
    final s = MriBarScale.forSamples(const [null, 64.0, null]);
    expect(s.lo, 50);
    expect(s.hi, 80);
    expect(
        MriBarScale.forSamples(const [null, null]).lo, MriBarScale.fallback.lo);
    expect(MriBarScale.forSamples(const []).hi, MriBarScale.fallback.hi);
  });

  test('固定レンジ 0–100 より必ず拡大される (F1 の解像度不足の是正)', () {
    // 実データが快適帯付近に固まっている典型例。
    final s = MriBarScale.forSamples(const [61.0, 64.0, 68.0]);
    expect(s.span, lessThan(100));
    // Home のバー高さ 36・下駄 0.5 で MRI 1 点あたりの px。
    final pxPerPoint = 36 * 0.5 / s.span;
    expect(pxPerPoint, greaterThan(0.241 * 2));
  });

  test('参照バンドの値域が MriBand.comfortable と一致している', () {
    // 帯の下端は comfortable の下端、上端は cool の下端 (= comfortable の外)。
    expect(MriBand.fromValue(kComfortBandMin.round()), MriBand.comfortable);
    expect(MriBand.fromValue(kComfortBandMin.round() - 1),
        isNot(MriBand.comfortable));
    expect(MriBand.fromValue(kComfortBandMax.round() - 1), MriBand.comfortable);
    expect(MriBand.fromValue(kComfortBandMax.round()), MriBand.cool);
  });
}
