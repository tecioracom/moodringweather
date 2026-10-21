// 寒さの区分名を体感温度で決める (domain/mri/cold_label.dart・band_label.dart)。
//
// 回帰: MRI は寒さで 100 付近に張り付くため、南極点 (体感 −62°) でも「涼しい」と
// 出ていた (2026-10-01、Galaxy Z Fold 6 の実機。mri-spec.md §4 / §10)。
// MRI の値・帯・色は変えず、区分名だけを変える:
//   体感 −10° 以下 → 帯を問わず「とても寒い — 防寒を」(OPTIMAL より優先)
//   cool 帯で体感 6° 未満 → 「寒い」/ それ以外の cool 帯 → 「涼しい」

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/domain/mri/cold_label.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/shared/band_label.dart';

MoodRingIndex _mri(int value) => MoodRingIndex(
      value: value,
      band: MriBand.fromValue(value),
      factorContributions: const {},
      calculatedAt: DateTime(2026, 10, 1, 14),
    );

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));

  String label(int value, double? tApp,
          {AppLocalizations? t, int optimalMri = 64}) =>
      mriBandLabel(t ?? ja, _mri(value),
          optimalMri: optimalMri, apparentTemperature: tApp);

  group('coldLabelFor (境界は丸める前の体感温度)', () {
    test('cool 帯: 6.0 は涼しい、5.99 から寒い', () {
      expect(coldLabelFor(MriBand.cool, 6.0), ColdLabel.none);
      expect(coldLabelFor(MriBand.cool, 5.99), ColdLabel.cold);
      expect(coldLabelFor(MriBand.cool, -9.99), ColdLabel.cold);
    });

    test('−10.0 ちょうどから、とても寒い (帯を問わない)', () {
      for (final band in MriBand.values) {
        expect(coldLabelFor(band, -10.0), ColdLabel.veryCold, reason: '$band');
        expect(coldLabelFor(band, -62), ColdLabel.veryCold, reason: '$band');
      }
    });

    test('「寒い」は cool 帯の中だけ', () {
      expect(coldLabelFor(MriBand.comfortable, 0), ColdLabel.none);
      expect(coldLabelFor(MriBand.warm, 5), ColdLabel.none);
    });

    test('体感温度が分からなければ何も変えない', () {
      expect(coldLabelFor(MriBand.cool, null), ColdLabel.none);
      expect(coldLabelFor(MriBand.cool, double.nan), ColdLabel.none);
    });
  });

  group('mriBandLabel', () {
    test('cool 帯: 体感 6° 以上は「涼しい」', () {
      expect(label(85, 10), '涼しい');
      expect(label(80, 6.0), '涼しい');
    });

    test('cool 帯: 体感 −10° より上 6° 未満は「寒い」', () {
      expect(label(85, 5.99), '寒い');
      expect(label(95, 0), '寒い');
      expect(label(100, -9.99), '寒い');
    });

    test('体感 −10° 以下は「とても寒い — 防寒を」', () {
      expect(label(100, -10.0), 'とても寒い — 防寒を');
      // 実機で見つけた南極点 (−56°・体感 −62°)。寒さへの感受性 ×0.70 で MRI 81。
      expect(label(81, -62), 'とても寒い — 防寒を');
    });

    test('寒さに強いキャリブレーションで緑 (快適・最適) のままでも、とても寒いを優先', () {
      // λ_cool 0.7・δT −3 の人は厳寒でも comfortable になり得る (weather-science)。
      expect(label(70, -15), 'とても寒い — 防寒を');
      // 推定最適 64 との差が 4 以内 (= 最適に昇格する条件) でも優先する。
      expect(label(64, -10.0), 'とても寒い — 防寒を');
      // −10° より上なら従来どおり (寒いは cool 帯の中だけ)。
      expect(label(64, -9.99), '最適');
      expect(label(70, 0), '快適');
    });

    test('体感温度が分からなければ従来どおり「涼しい」', () {
      expect(label(100, null), '涼しい');
    });

    test('暑い側は体感温度で変わらない', () {
      expect(label(50, 30), 'やや暑い');
      expect(label(30, 40), '暑い');
      expect(label(10, 40), 'とても暑い — 水分補給を');
    });
  });

  test('4 言語に寒い・とても寒いの文言がある (とても寒いは「—」で 2 行に分けられる)', () {
    for (final code in ['ja', 'en', 'es', 'zh']) {
      final t = lookupAppLocalizations(Locale(code));
      final cold = label(95, 0, t: t);
      final veryCold = label(100, -20, t: t);
      expect(cold, isNot(t.bandCool), reason: code);
      expect(veryCold, isNot(cold), reason: code);
      expect(veryCold, contains(' — '), reason: code);
    }
    final en = lookupAppLocalizations(const Locale('en'));
    expect(label(95, 0, t: en), 'COLD');
    expect(label(100, -20, t: en), 'VERY COLD — BUNDLE UP');
  });
}
