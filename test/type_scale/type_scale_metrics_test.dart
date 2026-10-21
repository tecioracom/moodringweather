// test/type_scale/type_scale_metrics_test.dart
//
// 型スケール (現状 / 案1 / 案2) の寸法の検査と計測。
//   - 常時: 下部ナビのラベルがピル (幅 86) に 1 行で収まる (4 言語 × 3 プリセット)
//   - 常時: ホームの右列 (FEELS + 概況) が気温の行 (70 × 倍率) を超えない
//     (en / ja / es × 倍率 1.0 / 1.3、既定のプリセット)
//   - --dart-define=MRW_TYPE_METRICS=true のときだけ計測値を出力する
//       ホームのスクロール可能量 (= コンテンツ全体の高さ − ビューポート 844)。
//         safe area (上 47 / 下 34) 付きでも測る (scrollSafe)
//       Paywall の CTA と表示域の下端 (safe area 付き。paywallSafe)
//       ホームの気温行: 気温 / 右列の高さ・FEELS と概況の行数・右列を下に回したか
//         (tempRow。概況 6 種 × en/ja/es × 倍率 1.0 / 1.3 / 2.0)
//       地点タブの 1 行に見える件数 (画面内 / 右端のフェード 24px にかからない)
//       保存 0 件のタブ列「＋ 地点を追加…」の右端
//       省略 (maxLines で切れる文字) と語中改行の洗い出し
//         (主要画面 × en/ja/es × 倍率 1.0/1.3/2.0。2.0 は報告だけ)
//     出力: TYPE_SCALE_METRIC|... の 1 行ずつ
//   flutter test test/type_scale/type_scale_metrics_test.dart \
//     --dart-define=MRW_TYPE_METRICS=true

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/shared/data_attribution_line.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';
import 'type_scale_scenarios.dart';

const bool _printMetrics = bool.fromEnvironment('MRW_TYPE_METRICS');

/// Figma 3:116: 選択ピルの幅。
const double _kPillWidth = 86;

void _metric(String line) {
  // ignore: avoid_print
  if (_printMetrics) print('TYPE_SCALE_METRIC|$line');
}

/// 行数の上限で切れている (省略記号・クリップ) 文字と、語の途中で折れている
/// 段落を出力する。
void _reportEllipsis(
  String screen,
  MrwTypeScale scale,
  Locale locale,
  double textScale,
) {
  for (final element in find.byType(RichText).evaluate()) {
    final p = element.renderObject! as RenderParagraph;
    if (!p.attached || !p.didExceedMaxLines) continue;
    final text = p.text.toPlainText().replaceAll('\n', ' ');
    final natural = p.getMaxIntrinsicWidth(double.infinity);
    _metric('ellipsis|$screen|${scale.name}|${locale.languageCode}|'
        '$textScale|$text|${natural.toStringAsFixed(0)}>'
        '${p.size.width.toStringAsFixed(0)}');
  }
  for (final b in midWordBreaks()) {
    _metric('midword|$screen|${scale.name}|${locale.languageCode}|'
        '$textScale|$b');
  }
}

/// 段落の行数 (キャレットの y の種類)。
int _lineCount(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final ys = <int>{};
  for (var i = 0; i <= text.length; i++) {
    ys.add(p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy.round());
  }
  return ys.length;
}

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

/// ホームの気温行 (気温 | FEELS + 概況) の寸法。段落は上から気温・FEELS・概況。
({
  Rect row,
  Rect temperature,
  Rect feels,
  Rect condition,
  int feelsLines,
  int conditionLines,
  bool stacked,
  bool temperatureClipped,
}) _temperatureRow(WidgetTester tester) {
  final row = find
      .byWidgetPredicate((w) => w.runtimeType.toString() == '_TemperatureRow')
      .first;
  final paragraphs = find
      .descendant(of: row, matching: find.byType(RichText))
      .evaluate()
      .map((e) => e.renderObject! as RenderParagraph)
      .toList();
  expect(paragraphs.length, greaterThanOrEqualTo(3));
  final temperature = _rectOf(paragraphs[0]);
  final feels = _rectOf(paragraphs[1]);
  return (
    row: tester.getRect(row),
    temperature: temperature,
    feels: feels,
    condition: _rectOf(paragraphs[2]),
    feelsLines: _lineCount(paragraphs[1]),
    conditionLines: _lineCount(paragraphs[2]),
    stacked: feels.top >= temperature.bottom - 0.5,
    temperatureClipped: paragraphs[0].size.width + 0.5 <
        paragraphs[0].getMaxIntrinsicWidth(double.infinity),
  );
}

/// ホームの縦スクロールの量 (中身の実高さ・ビューポート)。
({double maxScroll, double content, double viewport}) _homeScroll(
  WidgetTester tester,
) {
  final scrollables = find.descendant(
    of: find.byType(HomePage),
    matching: find.byType(Scrollable),
  );
  final vertical = scrollables.evaluate().where(
      (e) => (e.widget as Scrollable).axisDirection == AxisDirection.down);
  expect(vertical, hasLength(1));
  final p =
      ((vertical.single as StatefulElement).state as ScrollableState).position;
  // 中身の実高さ (1 画面に収まるときは maxScrollExtent が 0 なので、
  // 末尾の帰属表示の下端 + リストの下余白で測る)。
  final list = tester.widget<ListView>(find
      .descendant(of: find.byType(HomePage), matching: find.byType(ListView))
      .first);
  final bottomPad = (list.padding! as EdgeInsets).bottom;
  final attribution = tester.getRect(find.descendant(
    of: find.byType(HomePage),
    matching: find.byType(WeatherDataAttribution),
  ));
  // ビューポートの上端 (safe area の分だけ下がる) を差し引いた中身の高さ。
  final top = tester.getRect(find.byType(HomePage)).top +
      MediaQuery.of(tester.element(find.byType(HomePage))).padding.top;
  final content = attribution.bottom - top + p.pixels + bottomPad;
  return (
    maxScroll: p.maxScrollExtent,
    content: content,
    viewport: p.viewportDimension,
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('下部ナビのラベルはピル幅 86 に収まる', () {
    for (final scale in MrwTypeScale.values) {
      for (final locale in const [
        Locale('en'),
        Locale('ja'),
        Locale('es'),
        Locale('zh'),
      ]) {
        testWidgets('${scale.name} ${locale.languageCode}', (tester) async {
          await kTypeScaleScenarios['ホーム保存なし']!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: scale,
            ),
          );
          final texts = find.descendant(
            of: find.byType(QuietNavBar),
            matching: find.byType(RichText),
          );
          expect(texts, findsNWidgets(3));
          for (final element in texts.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
            final label = paragraph.text.toPlainText();
            _metric('nav|${scale.name}|${locale.languageCode}|$label|'
                '${natural.toStringAsFixed(1)}|$_kPillWidth|'
                '${paragraph.size.height.toStringAsFixed(1)}');
            expect(paragraph.didExceedMaxLines, isFalse, reason: label);
            expect(natural, lessThanOrEqualTo(_kPillWidth), reason: label);
          }
        });
      }
    }
  });

  group('ホームの右列 (FEELS + 概況) は気温の行を超えない', () {
    // designer 2026-09-29: FEELS・概況は省略せず 2 行まで。ただし既定の固定データ
    // (晴れ・体感 24°) では右列が気温の行 (70 × 倍率) より高くならないこと。
    for (final locale in const [Locale('en'), Locale('ja'), Locale('es')]) {
      for (final textScale in const [1.0, 1.3]) {
        testWidgets('${locale.languageCode} ×$textScale', (tester) async {
          await kTypeScaleScenarios['ホーム現在地']!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: MrwTypeScale.fromEnvironment,
              textScale: textScale,
            ),
          );
          final m = _temperatureRow(tester);
          expect(m.stacked, isFalse);
          expect(m.condition.bottom, lessThanOrEqualTo(m.temperature.bottom));
          expect(m.row.height, closeTo(m.temperature.height, 0.5));
          expect(m.temperature.height, closeTo(70 * textScale, 0.5));
        });
      }
      // ×2.0 は気温が右列と並ばない (「°」が落ちる) ので右列を下へ回す。
      testWidgets('${locale.languageCode} ×2.0: 右列を下へ回し「°」が切れない',
          (tester) async {
        await kTypeScaleScenarios['ホーム現在地']!(
          tester,
          TypeScaleCase(
            brightness: Brightness.dark,
            locale: locale,
            typeScale: MrwTypeScale.fromEnvironment,
            textScale: 2.0,
          ),
        );
        final m = _temperatureRow(tester);
        expect(m.stacked, isTrue);
        expect(m.temperatureClipped, isFalse);
      });
    }
  });

  group('省略で切れる文字 (MRW_TYPE_METRICS)', skip: !_printMetrics, () {
    const screens = [
      'ホーム現在地',
      'ホーム保存地点',
      '詳細',
      '設定トップ',
      '設定地点',
      '設定通知',
      '一般設定',
      '地点追加シート',
    ];
    for (final scale in MrwTypeScale.values) {
      for (final locale in const [Locale('en'), Locale('ja'), Locale('es')]) {
        // 2.0 は集計して報告するだけ (合否なし)。
        for (final textScale in const [1.0, 1.3, 2.0]) {
          for (final screen in screens) {
            testWidgets(
                '$screen ${scale.name} ${locale.languageCode} ×$textScale',
                (tester) async {
              await kTypeScaleScenarios[screen]!(
                tester,
                TypeScaleCase(
                  brightness: Brightness.dark,
                  locale: locale,
                  typeScale: scale,
                  textScale: textScale,
                ),
              );
              _reportEllipsis(screen, scale, locale, textScale);
            });
          }
          for (final entry in kOverflowSettingsScreens.entries) {
            if (const ['設定 Top', '一般', '通知', '地点'].contains(entry.key)) {
              continue; // 上で見ている
            }
            testWidgets(
                '${entry.key} ${scale.name} ${locale.languageCode} ×$textScale',
                (tester) async {
              tester.view.physicalSize = kGoldenSize;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(goldenApp(
                home: entry.value(),
                brightness: Brightness.dark,
                locale: locale,
                overrides: await settingsOverrides(),
                typeScale: scale,
                textScale: textScale,
              ));
              await settle(tester);
              _reportEllipsis(entry.key, scale, locale, textScale);
            });
          }
        }
      }
    }
  });

  group('計測 (MRW_TYPE_METRICS)', skip: !_printMetrics, () {
    const systems = [
      (Brightness.dark, Locale('ja')),
      (Brightness.light, Locale('en')),
    ];
    for (final scale in MrwTypeScale.values) {
      for (final (brightness, locale) in systems) {
        final system = '${brightness == Brightness.dark ? 'Dark' : 'Light'}_'
            '${locale.languageCode.toUpperCase()}';
        final c = TypeScaleCase(
          brightness: brightness,
          locale: locale,
          typeScale: scale,
        );

        for (final screen in const ['ホーム保存なし', 'ホーム現在地', 'ホーム保存地点']) {
          // safe area なし (golden と同じ 844) と、iPhone 相当 (上 47 / 下 34)。
          for (final safe in const [false, true]) {
            testWidgets(
                'ホームのスクロール量 $screen ${scale.name} $system'
                '${safe ? ' safe area' : ''}', (tester) async {
              await kTypeScaleScenarios[screen]!(
                tester,
                TypeScaleCase(
                  brightness: brightness,
                  locale: locale,
                  typeScale: scale,
                  safeArea: safe ? kPhoneSafeArea : null,
                ),
              );
              final s = _homeScroll(tester);
              _metric('${safe ? 'scrollSafe' : 'scroll'}|$screen|${scale.name}|'
                  '$system|${s.maxScroll.toStringAsFixed(1)}|'
                  '${s.content.toStringAsFixed(1)}|'
                  '${s.viewport.toStringAsFixed(1)}|'
                  '${(s.viewport - s.content).toStringAsFixed(1)}');
            });
          }
        }

        testWidgets('保存 0 件のタブ列 ${scale.name} $system', (tester) async {
          await kTypeScaleScenarios['ホーム保存なし']!(tester, c);
          final add = find.descendant(
            of: find.byType(PlaceTabBar),
            matching: find.textContaining(
              locale.languageCode == 'ja' ? '地点を追加' : 'Add a place',
            ),
          );
          expect(add, findsOneWidget);
          final rect = tester.getRect(add);
          _metric('addFirst|${scale.name}|$system|'
              '${rect.left.toStringAsFixed(0)}-${rect.right.toStringAsFixed(0)}|'
              '${rect.right <= kGoldenSize.width ? 'in' : 'out'}');
        });

        for (final screen in const ['ホーム現在地', 'ホーム保存地点']) {
          testWidgets('地点タブの見える件数 $screen ${scale.name} $system',
              (tester) async {
            await kTypeScaleScenarios[screen]!(tester, c);
            final labels = [
              locale.languageCode == 'ja' ? '現在地' : 'My location',
              for (final p in kFixturePlaces) p.name(locale),
            ];
            final width = kGoldenSize.width;
            var inScreen = 0;
            var clearOfFade = 0;
            final truncated = <String>[];
            final rights = <String>[];
            for (final label in labels) {
              final finder = find.descendant(
                of: find.byType(PlaceTabBar),
                matching: find.text(label),
              );
              expect(finder, findsOneWidget, reason: label);
              final rect = tester.getRect(finder);
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              if (paragraph.didExceedMaxLines) truncated.add(label);
              rights.add('$label:${rect.left.toStringAsFixed(0)}'
                  '-${rect.right.toStringAsFixed(0)}');
              if (rect.left >= 0 && rect.right <= width) inScreen++;
              // 右端 24px は続きがあるときにフェードする。
              if (rect.left >= 0 && rect.right <= width - 24) clearOfFade++;
            }
            final tabBar = tester.getRect(find.byType(PlaceTabBar));
            _metric('tabs|$screen|${scale.name}|$system|$inScreen|'
                '$clearOfFade|${labels.length}|'
                '${tabBar.height.toStringAsFixed(0)}|'
                '${truncated.join(',')}|${rights.join(' ')}');
          });
        }
      }

      // Paywall: safe area 付きで CTA が初期表示に入るか (合否は paywall_page_test)。
      for (final locale in const [Locale('en'), Locale('ja'), Locale('es')]) {
        testWidgets(
            'Paywall の CTA ${scale.name} ${locale.languageCode} safe area',
            (tester) async {
          await kTypeScaleScenarios['Paywall']!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: scale,
              safeArea: kPhoneSafeArea,
            ),
          );
          final t =
              AppLocalizations.of(tester.element(find.byType(PaywallPage)));
          final cta = tester.getRect(find
              .ancestor(
                of: find.text(t.paywallStartCta),
                matching: find.byType(Material),
              )
              .first);
          final scrollable = find
              .descendant(
                of: find.byType(PaywallPage),
                matching: find.byType(Scrollable),
              )
              .first;
          final viewport = tester.getRect(scrollable);
          final position = tester.state<ScrollableState>(scrollable).position;
          _metric('paywallSafe|${scale.name}|${locale.languageCode}|'
              'cta=${cta.top.toStringAsFixed(1)}-${cta.bottom.toStringAsFixed(1)}|'
              'viewport=${viewport.top.toStringAsFixed(1)}-'
              '${viewport.bottom.toStringAsFixed(1)}|'
              'margin=${(viewport.bottom - cta.bottom).toStringAsFixed(1)}|'
              'maxScroll=${position.maxScrollExtent.toStringAsFixed(1)}');
        });
      }
    }
  });

  group('ホームの気温行 (MRW_TYPE_METRICS)', skip: !_printMetrics, () {
    // 右列 (FEELS 2 行 + 概況 2 行まで) が気温の行より高くなるとき、ホームが
    // 縦にどれだけ伸びるか (growth = 行の高さ − 気温の行)。倍率 2.0 は右列を
    // 気温の下へ回す (stacked)。
    const conditions = ['sunny', 'cloudy', 'foggy', 'rainy', 'snowy', 'stormy'];
    for (final locale in const [Locale('en'), Locale('ja'), Locale('es')]) {
      for (final textScale in const [1.0, 1.3, 2.0]) {
        for (final condition in conditions) {
          testWidgets('気温行 ${locale.languageCode} ×$textScale $condition',
              (tester) async {
            await kTypeScaleScenarios['ホーム現在地']!(
              tester,
              TypeScaleCase(
                brightness: Brightness.dark,
                locale: locale,
                typeScale: MrwTypeScale.fromEnvironment,
                textScale: textScale,
                condition: condition,
              ),
            );
            final m = _temperatureRow(tester);
            final side =
                m.condition.bottom - (m.stacked ? m.feels.top : m.row.top);
            _metric('tempRow|${locale.languageCode}|$textScale|$condition|'
                'temp=${m.temperature.height.toStringAsFixed(1)}|'
                'side=${side.toStringAsFixed(1)}|'
                'row=${m.row.height.toStringAsFixed(1)}|'
                'feelsLines=${m.feelsLines}|condLines=${m.conditionLines}|'
                'stacked=${m.stacked}|clipped=${m.temperatureClipped}|'
                'growth=${(m.row.height - m.temperature.height).toStringAsFixed(1)}');
          });
        }
      }
    }
  });
}
