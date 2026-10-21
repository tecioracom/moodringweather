// test/qa/weather_rail_probe_test.dart
//
// QA-10 (天気レールの項目が隣と接する) の修正の独立検証 (再サインオフ 2026-09-29)。
// **既定では実行しない**:
//
//   flutter test test/qa/weather_rail_probe_test.dart \
//     --dart-define=MRW_QA_RAIL=true
//
// ホーム・詳細の時間別 MRI を実際に描画し、天気レールの項目 (グリフ + 気温) の
// 字面の間隔を測る。気温の字面の右端は、同じ書体・大きさ・文字倍率で文字を画像に
// 描いて**画素で**測る (実装の「全角「°」の右 55% は空き」という見積もりを使わない)。
// グリフは 9.5px の枠を字面とみなす (実際の線は枠より内側なので、間隔は小さめに出る)。
//
// 条件: en / ja / es / zh × 文字倍率 1.0 / 1.3 / 1.6 / 2.0 × 幅 320 / 360 / 375 /
//       390 / 430 × ホーム / 詳細 × 気温 22°C / -12°C / 100°F (37.8°C)。
// 出力 (1 条件 1 行):
//   QA_RAIL|画面|言語|倍率|幅|気温|labels=修正後/修正前|placement|
//           gap=修正後の最小間隔|gapBefore=修正前の最小間隔 (同じ画素の測り方)|
//           drift=レール項目の中心とラベルの中心の最大のずれ|out=行からのはみ出し
// 失敗にする条件: レールとラベルの本数が違う / 修正後の字面の間隔が 1px 未満 /
// 行 (時刻ラベルの幅) からはみ出す。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_glyphs.dart';
import 'package:mood_ring_weather/presentation/shared/weather_rail.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

const bool _run = bool.fromEnvironment('MRW_QA_RAIL');

/// 描いた文字の字面の右端 (文字の原点から。px)。画素で測る。
final Map<String, double> _inkRightCache = {};

Future<double> _inkRight(
  WidgetTester tester,
  String text,
  TextStyle style,
  TextScaler scaler,
  Locale locale,
) async {
  final key = '$text|${style.fontFamily}|${style.fontSize}|'
      '${style.fontWeight}|${scaler.scale(10)}|$locale';
  final cached = _inkRightCache[key];
  if (cached != null) return cached;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(color: const Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    locale: locale,
    maxLines: 1,
  )..layout();
  const pad = 8;
  final w = painter.width.ceil() + pad * 2;
  final h = painter.height.ceil() + pad * 2;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Offset(pad * 1.0, pad * 1.0));
  final picture = recorder.endRecording();
  final data = await tester.runAsync(() async {
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!;
  });
  painter.dispose();
  var right = -1;
  for (var x = w - 1; x >= 0 && right < 0; x--) {
    for (var y = 0; y < h; y++) {
      if (data!.getUint8((y * w + x) * 4 + 3) > 24) {
        right = x;
        break;
      }
    }
  }
  final value = right < 0 ? 0.0 : right + 1 - pad * 1.0;
  _inkRightCache[key] = value;
  return value;
}

/// 画面を組み立てる (保存 1 件・Plus。気温は [celsius]、単位は [unit])。
Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required double scale,
  required double width,
  required bool detail,
  required double celsius,
  required TemperatureUnit unit,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  WeatherSnapshot at(DateTime t) =>
      comfortableSnapshot(t).copyWith(temperature: celsius);
  final overrides = await placesBaseOverrides(
    savedCount: 1,
    locale: locale,
    current: at,
    city: 'Tokyo',
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPrefKeyTemperatureUnit, unit.toTag());
  await tester.pumpWidget(goldenApp(
    home: const MainShell(),
    brightness: Brightness.dark,
    locale: locale,
    textScale: scale,
    overrides: [
      ...overrides,
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

  const skip = _run ? null : '--dart-define=MRW_QA_RAIL=true のときだけ実行する';

  const temps = [
    (22.0, TemperatureUnit.celsius, '22C'),
    (-12.0, TemperatureUnit.celsius, '-12C'),
    (37.8, TemperatureUnit.fahrenheit, '100F'),
  ];

  for (final lang in const ['en', 'ja', 'es', 'zh']) {
    for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
      for (final width in const [320.0, 360.0, 375.0, 390.0, 430.0]) {
        for (final detail in const [false, true]) {
          for (final (celsius, unit, tempTag) in temps) {
            final screen = detail ? 'detail' : 'home';
            final tag = '$screen|$lang|$scale|${width.toInt()}|$tempTag';
            testWidgets('rail $tag', skip: skip != null, (tester) async {
              final locale = Locale(lang);
              await _pump(
                tester,
                locale: locale,
                scale: scale,
                width: width,
                detail: detail,
                celsius: celsius,
                unit: unit,
              );
              expect(tester.takeException(), isNull);
              final page = find.byType(detail ? DetailPage : HomePage);
              final axisFinder = find.descendant(
                of: page,
                matching: find.byType(TimeAxisLabels),
              );
              final axis = tester.widget<TimeAxisLabels>(axisFinder);
              final axisContext = tester.element(axisFinder);
              final axisBox = tester.renderObject<RenderBox>(axisFinder);
              final rowWidth = axisBox.size.width;
              final rowLeft = axisBox.localToGlobal(Offset.zero).dx;
              final scaler = MediaQuery.textScalerOf(axisContext);

              // 修正後: 描画された時刻ラベルとレール。
              final labelTexts = find
                  .descendant(of: axisFinder, matching: find.byType(Text))
                  .evaluate()
                  .map((e) => e.widget as Text)
                  .toList();
              final labelCenters = <double>[
                for (final t in labelTexts)
                  tester.getCenter(find.byWidget(t)).dx,
              ]..sort();
              final items = find
                  .descendant(of: page, matching: find.byType(WeatherRailItem))
                  .evaluate()
                  .toList();
              expect(items.length, labelTexts.length,
                  reason: 'レールとラベルの本数が違う ($tag)');

              final ink = <(double, double)>[];
              for (final e in items) {
                final item = find.byWidget(e.widget);
                final glyph = tester.getRect(find.descendant(
                    of: item, matching: find.byType(QuietGlyphIcon)));
                final p = tester.renderObject<RenderParagraph>(
                    find.descendant(of: item, matching: find.byType(RichText)));
                final text = p.text.toPlainText();
                final boxes = p.getBoxesForSelection(
                    TextSelection(baseOffset: 0, extentOffset: text.length));
                final origin =
                    p.localToGlobal(Offset.zero).dx + boxes.first.left;
                final right = origin +
                    await _inkRight(
                        tester, text, p.text.style!, scaler, locale);
                ink.add((glyph.left, right));
              }
              ink.sort((a, b) => a.$1.compareTo(b.$1));
              var gap = double.infinity;
              for (var i = 1; i < ink.length; i++) {
                final g = ink[i].$1 - ink[i - 1].$2;
                if (g < gap) gap = g;
              }
              var out = 0.0;
              for (final (l, r) in ink) {
                final over = [rowLeft - l, r - (rowLeft + rowWidth)]
                    .reduce((a, b) => a > b ? a : b);
                if (over > out) out = over;
              }
              // レール項目の中心と、同じスロットの時刻ラベルの中心のずれ。
              var drift = 0.0;
              for (var i = 0; i < ink.length && i < labelCenters.length; i++) {
                final center = (ink[i].$1 + ink[i].$2) / 2;
                final d = (center - labelCenters[i]).abs();
                if (d > drift) drift = d;
              }

              // 修正前: companion なしの間引き + 枠 (slot) の置き方を、同じ
              // 画素の測り方で計算する (BarSlotRow の幾何 = barSlotItemExtent)。
              final companion = axis.companion!;
              final before = TimeAxisLabels(
                labels: axis.labels,
                gap: axis.gap,
                style: axis.style,
                anchorIndex: axis.anchorIndex,
                anchorStyle: axis.anchorStyle,
                minSpacing: axis.minSpacing,
              ).visibleIndices(axisContext, rowWidth);
              final count = axis.labels.length;
              final barWidth = (rowWidth - axis.gap * (count - 1)) / count;
              // 気温の文字は全スロット同じ (固定データ)。字面の右端 = 項目の
              // 左端 + グリフ 9.5 + 間隔 3 + 気温の字面。
              final sample = tester.renderObject<RenderParagraph>(
                  find.descendant(
                      of: find.byWidget(items.first.widget),
                      matching: find.byType(RichText)));
              final textInk = await _inkRight(tester, sample.text.toPlainText(),
                  sample.text.style!, scaler, locale);
              var gapBefore = double.infinity;
              double? prevRight;
              for (final i in before) {
                final width = companion.widths[i];
                if (width == null) continue;
                final extent = barSlotItemExtent(
                  index: i,
                  contentWidth: width,
                  barWidth: barWidth,
                  gap: axis.gap,
                  span: companion.span,
                  maxWidth: rowWidth,
                  placement: BarSlotPlacement.slot,
                );
                final left = extent.left;
                final right = left +
                    kWeatherRailGlyphSize +
                    kWeatherRailGlyphGap +
                    textInk;
                if (prevRight != null && left - prevRight < gapBefore) {
                  gapBefore = left - prevRight;
                }
                prevRight = right;
              }
              final placement =
                  axis.companionPlacement(axisContext, rowWidth).name;
              String f(double v) => v.isInfinite ? '-' : v.toStringAsFixed(1);
              // ignore: avoid_print
              print('QA_RAIL|$tag|labels=${labelTexts.length}/${before.length}|'
                  '$placement|gap=${f(gap)}|gapBefore=${f(gapBefore)}|'
                  'drift=${f(drift)}|out=${f(out)}');
              expect(gap, greaterThanOrEqualTo(1.0),
                  reason: 'レールの項目が接する ($tag)');
              expect(out, lessThanOrEqualTo(0.5), reason: 'レールが行からはみ出す ($tag)');
            });
          }
        }
      }
    }
  }
}
