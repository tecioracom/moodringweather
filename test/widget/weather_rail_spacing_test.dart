// test/widget/weather_rail_spacing_test.dart
//
// 天気レール (時間別 MRI の時刻ラベルの下のグリフ + 気温) の項目どうしが接しない
// (QA-10、docs/qa-report-saved-places-2026-09-29.md)。
//   - 詳細 zh ×2.0 / 360dp: 時刻ラベル (「6时」) は収まるがレールの「22°」が接触
//     していた → 1 段多く間引く (ラベルとレールは同じ本数のまま)
//   - ホーム・詳細 en ×1.3 / 360dp: 両端の項目が枠ごと内側へ寄って隣と接していた
//     → ラベルの本数は保ち、項目を中身の幅で置く (項目の中心 = 時刻ラベルの中心)
//   - JA は全角「°」の右半分が空き。見た目で接していた条件だけ置き方を変え、
//     倍率 1.0 / 390dp (golden・Figma の幅) は従来の置き方のまま
// 部品 (TimeAxisLabels.companion / BarSlotRow) の単体は chart_axes_test.dart。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/weather_rail.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

/// [scope] の天気レールの項目の字面 (グリフの左端 〜 気温の右端) を左から順に。
/// グリフ・間隔・気温は行の中で詰めて並ぶので、グリフの左端 = 気温の左端 − 12.5。
/// JA の全角「°」は右 55% を空きとして除く (weather_rail.dart と同じ)。
List<Rect> _railInk(WidgetTester tester, Finder scope) {
  final rects = <Rect>[];
  for (final e in find
      .descendant(of: scope, matching: find.byType(WeatherRailItem))
      .evaluate()) {
    final item = find.byWidget(e.widget);
    final p = tester.renderObject<RenderParagraph>(
        find.descendant(of: item, matching: find.byType(RichText)));
    final text = p.text.toPlainText();
    final toGlobal = p.getTransformTo(null);
    final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length));
    final first = MatrixUtils.transformRect(toGlobal, boxes.first.toRect());
    var right = MatrixUtils.transformRect(toGlobal, boxes.last.toRect()).right;
    final degree = p
        .getBoxesForSelection(TextSelection(
            baseOffset: text.length - 1, extentOffset: text.length))
        .single;
    final degreeWidth = degree.right - degree.left;
    final em = MediaQuery.textScalerOf(e).scale(p.text.style!.fontSize!);
    if (degreeWidth >= em * kFullWidthDegreeMinAdvance) {
      right -= degreeWidth * kFullWidthDegreeBlank;
    }
    final left = first.left - kWeatherRailGlyphSize - kWeatherRailGlyphGap;
    rects.add(Rect.fromLTRB(left, first.top, right, first.bottom));
  }
  rects.sort((a, b) => a.left.compareTo(b.left));
  return rects;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Locale locale,
  required double textScale,
  required double width,
  bool detail = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(goldenApp(
    home: const MainShell(),
    brightness: Brightness.dark,
    locale: locale,
    textScale: textScale,
    overrides: [
      ...await placesBaseOverrides(
          savedCount: 1, locale: locale, city: 'Tokyo'),
      ...entitlementOverrides(plus: true),
      ...savedPlaceWeatherOverrides(),
    ],
  ));
  await settle(tester);
  if (detail) {
    await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
    await settle(tester);
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final (lang, scale, width, detail, labels) in const [
    // QA の報告: 詳細 zh ×2.0 / 360dp (「22°22°」が接触) → 1 段多く間引く
    ('zh', 2.0, 360.0, true, 2),
    // QA の報告: ホーム en ×1.3 / 360dp (2 組が接触) → ラベル 5 本のまま置き方を変える
    ('en', 1.3, 360.0, false, 5),
    ('en', 1.3, 360.0, true, 4),
    // JA は全角「°」の右半分が空き。見た目で接していた条件だけ置き方を変える
    ('ja', 1.3, 360.0, true, 4),
    ('ja', 1.3, 390.0, true, 4),
    ('ja', 1.0, 360.0, false, 5),
  ]) {
    testWidgets(
        '${detail ? '詳細' : 'ホーム'} $lang ×$scale / ${width.toInt()}dp: '
        'ラベル $labels 本、レールも同じ数で 3px 以上空く', (tester) async {
      await _pumpScreen(tester,
          locale: Locale(lang), textScale: scale, width: width, detail: detail);
      final scope = detail ? find.byType(DetailPage) : find.byType(HomePage);
      final axis =
          find.descendant(of: scope, matching: find.byType(TimeAxisLabels));
      expect(find.descendant(of: axis, matching: find.byType(RichText)),
          findsNWidgets(labels));
      final rails = _railInk(tester, scope);
      expect(rails, hasLength(labels));
      for (var i = 1; i < rails.length; i++) {
        expect(rails[i].left - rails[i - 1].right,
            greaterThanOrEqualTo(kAxisCompanionMinSpacing - 0.01),
            reason: 'レール ${i - 1} と $i が接している');
      }
      final chart = tester.getRect(axis);
      expect(rails.first.left, greaterThanOrEqualTo(chart.left - 0.5));
      expect(rails.last.right, lessThanOrEqualTo(chart.right + 0.5));
    });
  }

  testWidgets('倍率 1.0 / 390dp (golden・Figma の幅) は枠 (slot) の置き方のまま',
      (tester) async {
    await _pumpScreen(tester,
        locale: const Locale('en'), textScale: 1.0, width: 390);
    final axisFinder = find.descendant(
        of: find.byType(HomePage), matching: find.byType(TimeAxisLabels));
    final axis = tester.widget<TimeAxisLabels>(axisFinder);
    final context = tester.element(axisFinder);
    final width = tester.getSize(axisFinder).width;
    expect(axis.companionPlacement(context, width), BarSlotPlacement.slot);
    expect(axis.visibleIndices(context, width), [0, 2, 4, 6, 8]);
  });
}
