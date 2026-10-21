// test/type_scale/type_scale_layout_test.dart
//
// 案2 を既定にしたときの個別の修正 (designer / compliance 2026-09-29) の回帰テスト。
// golden と同じ固定データ・同梱フォントで、既定のプリセット (案2) を描画して見る。
//   - FEELS 行: EN は「FEELS nn°」。省略記号なし・折り返しは値の直前だけ
//   - About App のアプリ名: 「Mood-Ring」/「Weather」の 2 行 + バージョン行まで 8px
//   - Calibration の 24 時間ミニチャート: 時刻は Plex Mono・1 行 (1 文字ずつ折れない)
//   - ホーム ×1.3: 天気レールは時刻ラベルと同じ本数 (間引きに従う)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/constants/app_links.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_app_page.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_glyphs.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_page.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

import '../golden/golden_harness.dart';
import 'type_scale_scenarios.dart';

TypeScaleCase _case(Locale locale, {double textScale = 1.0}) => TypeScaleCase(
      brightness: Brightness.dark,
      locale: locale,
      typeScale: MrwTypeScale.fromEnvironment,
      textScale: textScale,
    );

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page,
  TypeScaleCase c, {
  Size size = kGoldenSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(goldenApp(
    home: page,
    brightness: c.brightness,
    locale: c.locale,
    overrides: await settingsOverrides(),
    typeScale: c.typeScale,
    textScale: c.textScale,
  ));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('feelsLine: 折り返しは値の直前だけ', () {
    test('ラベルの語間は NBSP、値の前は通常の空白', () {
      expect(feelsLine('FEELS LIKE 24°', '24'), 'FEELS\u00A0LIKE 24°');
      expect(feelsLine('FEELS 24°', '24'), 'FEELS 24°');
      expect(feelsLine('SENSACIÓN —', '—'), 'SENSACIÓN —');
      expect(feelsLine('体感 −3°', '−3'), '体感 −3°');
    });

    test('値が先頭 (ラベルが後ろ) の並びはそのまま', () {
      expect(feelsLine('24° RESSENTI', '24'), '24° RESSENTI');
    });
  });

  group('ホームの FEELS 行', () {
    testWidgets('EN は「FEELS 24°」(Figma 24:6)。省略記号を使わない', (tester) async {
      await kTypeScaleScenarios['ホーム現在地']!(tester, _case(const Locale('en')));
      final feels = find.text('FEELS 24°');
      expect(feels, findsOneWidget);
      final text = tester.widget<Text>(feels);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, 2);
      expect(
        tester.renderObject<RenderParagraph>(feels).didExceedMaxLines,
        isFalse,
      );
    });

    testWidgets('ホーム ×1.3 (ja): 天気レールは時刻ラベルと同じ本数', (tester) async {
      await kTypeScaleScenarios['ホーム現在地']!(
        tester,
        _case(const Locale('ja'), textScale: 1.3),
      );
      final labels = find.descendant(
        of: find.byType(TimeAxisLabels),
        matching: find.byType(RichText),
      );
      final rails = find.descendant(
        of: find.byType(BarSlotRow),
        matching: find.byType(QuietGlyphIcon),
      );
      expect(labels, findsWidgets);
      expect(rails.evaluate().length, labels.evaluate().length);
    });
  });

  group('About App のアプリ名は語間で 2 行 (縮小しない)', () {
    for (final locale in const [Locale('en'), Locale('ja'), Locale('es')]) {
      testWidgets(locale.languageCode, (tester) async {
        final c = _case(locale);
        await _pumpPage(tester, const AboutAppPage(), c);
        final t = AppLocalizations.of(tester.element(find.byType(QuietPage)));
        final name = find.text(t.appTitle).first;
        final p = tester.renderObject<RenderParagraph>(name);
        // 「Mood-Ring」は 1 行目、「Weather」は 2 行目 (ハイフンでは折らない)。
        final first = p.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 9));
        final second = p.getBoxesForSelection(
            const TextSelection(baseOffset: 10, extentOffset: 17));
        expect(first.map((b) => b.top).toSet(), hasLength(1));
        expect(second.first.top, greaterThan(first.first.top));
        expect(second.map((b) => b.top).toSet(), hasLength(1));
        // 24 / 1.1 のまま (縮小しない)。
        final style = tester.widget<Text>(name).style!;
        expect(style.fontSize, 24);
        // 行高 26.4 は画素に丸められる (2 行で 52〜53)。
        expect(tester.getRect(name).height, closeTo(24 * 1.1 * 2, 1.0));
        // 2 行目とバージョン行の間 8px (QuietLabel は大文字化する)。
        final version =
            find.text(t.aboutVersion(AppLinks.appVersion).toUpperCase());
        expect(
          tester.getRect(version).top - tester.getRect(name).bottom,
          closeTo(8, 0.5),
        );
      });
    }
  });

  group('Calibration の 24 時間ミニチャートの時刻', () {
    for (final textScale in const [1.0, 1.3, 2.0]) {
      testWidgets('Plex Mono・1 行 (×$textScale)', (tester) async {
        // 縦に伸ばして、倍率 2.0 でもチャートまで組み立てる (ListView は画面外を
        // 作らない)。
        await _pumpPage(
          tester,
          const CalibrationHomePage(),
          _case(const Locale('ja'), textScale: textScale),
          size: const Size(390, 2400),
        );
        final hours = find.byWidgetPredicate((w) =>
            w is Text &&
            const {'0', '6', '12', '18'}.contains(w.data) &&
            w.style?.fontFamily == MrwFonts.plexMono);
        expect(hours, findsWidgets);
        final axis = MrwType.of(tester.element(hours.first)).axis;
        for (final e in hours.evaluate()) {
          final text = e.widget as Text;
          expect(text.softWrap, isFalse);
          expect(text.style?.fontSize, axis.fontSize(10));
          final p = e.renderObject! as RenderParagraph;
          // 1 行 (「1 / 2」と縦に折れない)。
          expect(
            p
                .getBoxesForSelection(TextSelection(
                    baseOffset: 0, extentOffset: text.data!.length))
                .map((b) => b.top)
                .toSet(),
            hasLength(1),
          );
        }
        expect(midWordBreaks(), isEmpty);
      });
    }
  });
}
