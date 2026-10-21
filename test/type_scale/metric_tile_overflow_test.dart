// test/type_scale/metric_tile_overflow_test.dart
//
// 指標タイル (単位・段階語) の文字倍率 × 画面幅の溢れ検査
// (docs/design-metric-units-proposal.md §4.3、compliance-review-v1.3.0 §9-2)。
// 型スケールの画面の組み立て (type_scale_scenarios.dart) でホーム・詳細を出し、
// 4 言語 × 倍率 1.0 / 1.3 / 2.0 × 幅 360 / 375 / 390 で、各言語の最長の組み合わせ
// (UV・空気質の段階語、風の 3 単位、湿度 100%、気圧 1013 hPa) を見る。
//
// 判定:
//   - 溢れ例外なし・省略記号なし・どのテキストも 1 行 (語の途中の改行なし)
//   - 文字はタイルの内側に収まる (必要なら縮小)
//   - 単位は値と同じ行 (ベースラインが同じ、値の右)
//   - 同じ行の 2 枚は同じ高さ
//   - 倍率 1.0 ではタイルの高さ 72 (ホーム) / 84 (詳細) のまま。例外は en の空気質の
//     区分 5「Very unhealthy」だけ (3 桁の値のあとには入らず、値の下の行へ回る。
//     compliance §9-2 で許容)
// プリセットは --dart-define=MRW_TYPE_SCALE (未指定は既定の案2 = plus2)。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_metric_tile.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

import '../golden/golden_harness.dart';
import 'type_scale_scenarios.dart';

/// 最長の組み合わせ (名前, UV, US AQI, 風 m/s, 風速の単位)。湿度は 100%。
const _sets = <(String, double, int, double, WindSpeedUnit)>[
  // ja「10 非常に強い」「350 極めて悪い」/ en「10 Very high」「350 Hazardous」/
  // es「10 Muy alto」「350 Pésimo」/ zh「10 很高」「350 有害」、「30.0 m/s」
  ('UV10・AQI350・30.0m/s', 10, 350, 30, WindSpeedUnit.metersPerSecond),
  // 「11 極端に強い / Extreme / Extremo / 极高」「200 悪い / Unhealthy / Malo /
  // 不健康」、「108 km/h」
  ('UV11・AQI200・108km/h', 11, 200, 30, WindSpeedUnit.kilometersPerHour),
  // 「5 中程度 / Moderate / Moderado / 中等」「250 非常に悪い / Very unhealthy /
  // Muy malo / 很不健康」、「67 mph」
  ('UV5・AQI250・67mph', 5, 250, 30, WindSpeedUnit.milesPerHour),
];

const _units = ['%', 'm/s', 'km/h', 'mph', 'hPa'];

/// 段落のアルファベットのベースライン (画面座標。FittedBox の縮小も込み)。
double _baseline(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textHeightBehavior: p.textHeightBehavior,
    maxLines: p.maxLines,
  )..layout();
  final distance =
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.dispose();
  return p.localToGlobal(Offset(0, distance)).dy;
}

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

/// 段落の描画上の矩形 (FittedBox の縮小込み)。
Rect _paintedRect(RenderParagraph p) {
  final topLeft = p.localToGlobal(Offset.zero);
  final bottomRight = p.localToGlobal(p.size.bottomRight(Offset.zero));
  return Rect.fromPoints(topLeft, bottomRight);
}

int _lineCount(RenderParagraph p) {
  final length = p.text.toPlainText().length;
  if (length == 0) return 1;
  return p
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
      .map((b) => b.top.round())
      .toSet()
      .length;
}

void main() {
  setUpAll(loadAppFonts);

  final preset = MrwTypeScale.fromEnvironment;
  const locales = [Locale('ja'), Locale('en'), Locale('es'), Locale('zh')];

  for (final screen in const ['ホーム現在地', '詳細']) {
    final base = screen == '詳細' ? 84.0 : 72.0;
    for (final width in const [360.0, 375.0, 390.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final locale in locales) {
          for (final (name, uv, aqi, wind, windUnit) in _sets) {
            testWidgets(
                '$screen ${width.toInt()}dp ×$scale '
                '${locale.languageCode} $name', (tester) async {
              await kTypeScaleScenarios[screen]!(
                tester,
                TypeScaleCase(
                  brightness: Brightness.dark,
                  locale: locale,
                  typeScale: preset,
                  textScale: scale,
                  // 縦は伸ばして、タイルを全部組み立てる (横の溢れを見る)。
                  viewport: Size(width, 4000),
                  uvIndex: uv,
                  aqi: aqi,
                  windSpeed: wind,
                  humidity: 100,
                  windUnit: windUnit,
                ),
              );
              expect(tester.takeException(), isNull);

              final tiles = find.byType(QuietMetricTile);
              expect(tiles, findsNWidgets(screen == '詳細' ? 6 : 4));
              // 最長の組み合わせが実際に出ている (値と単位)。
              Finder inTiles(String text) => find.descendant(
                    of: tiles,
                    matching: find.text(text),
                  );
              expect(inTiles('${uv.round()}'), findsOneWidget);
              expect(inTiles('$aqi'), findsOneWidget);
              expect(inTiles(windUnit.formatValue(wind)), findsOneWidget);
              expect(inTiles(windUnit.symbol), findsOneWidget);
              expect(inTiles('100'), findsOneWidget); // 湿度 100%
              if (locale.languageCode == 'en' && aqi == 250) {
                expect(inTiles('Very unhealthy'), findsOneWidget);
              }
              for (final tileElement in tiles.evaluate()) {
                final tileRect =
                    _rectOf(tileElement.renderObject! as RenderBox);
                final texts = find.descendant(
                  of: find.byWidget(tileElement.widget),
                  matching: find.byType(Text),
                );
                final paragraphs = <String, RenderParagraph>{};
                for (final e in texts.evaluate()) {
                  final text = e.widget as Text;
                  // 省略記号は使わない。
                  expect(text.overflow, isNot(TextOverflow.ellipsis),
                      reason: text.data);
                  final p = tester.renderObject<RenderParagraph>(
                    find.descendant(
                      of: find.byWidget(text),
                      matching: find.byType(RichText),
                    ),
                  );
                  paragraphs[text.data!] = p;
                  // 1 行 (語の途中の改行・折り返しなし)。
                  expect(_lineCount(p), 1, reason: '「${text.data}」が 2 行');
                  expect(p.didExceedMaxLines, isFalse, reason: text.data);
                  // タイルの内側に収まる (縮小込み)。
                  final r = _paintedRect(p);
                  expect(r.left, greaterThanOrEqualTo(tileRect.left - 0.5),
                      reason: text.data);
                  expect(r.right, lessThanOrEqualTo(tileRect.right + 0.5),
                      reason: '「${text.data}」がタイルの右にはみ出す');
                  expect(r.bottom, lessThanOrEqualTo(tileRect.bottom + 0.5),
                      reason: text.data);
                }
                // 単位は値と同じ行 (ベースラインが同じ・値の右)。
                for (final unit in _units) {
                  final u = paragraphs[unit];
                  if (u == null) continue;
                  final value = paragraphs.entries
                      .firstWhere((e) =>
                          e.value != u && RegExp(r'^[0-9.]+$').hasMatch(e.key))
                      .value;
                  expect(_baseline(u), closeTo(_baseline(value), 0.5),
                      reason: '$unit が値と別の行');
                  expect(_paintedRect(u).left,
                      greaterThan(_paintedRect(value).right - 0.5),
                      reason: unit);
                }
              }

              // 同じ行の 2 枚は同じ高さ。倍率 1.0 は 72 / 84 のまま
              // (en の「Very unhealthy」の行だけ例外)。
              final rows = find.byType(QuietMetricTileRow);
              expect(rows, findsNWidgets(screen == '詳細' ? 3 : 2));
              for (final row in rows.evaluate()) {
                final pair = find.descendant(
                  of: find.byWidget(row.widget),
                  matching: tiles,
                );
                final left = tester.getSize(pair.at(0)).height;
                final right = tester.getSize(pair.at(1)).height;
                expect(right, closeTo(left, 0.01));
                if (scale == 1.0) {
                  final exception = find
                      .descendant(
                        of: find.byWidget(row.widget),
                        matching: find.text('Very unhealthy'),
                      )
                      .evaluate()
                      .isNotEmpty;
                  if (!exception) expect(left, base);
                }
              }
            });
          }
        }
      }
    }
  }
}
