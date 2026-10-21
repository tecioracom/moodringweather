// test/widget/quiet_metric_tile_test.dart
//
// 指標タイル (docs/design-metric-units-proposal.md §3・§4)。
//   - 倍率 1.0 では Figma の高さ 72 / 84 のまま (値の欄の固定幅 74 はやめた)
//   - 値の後ろの文字 (単位 / 段階語) は値の直後: 間隔 `%` 1px (es 4px)、ほか 4px。
//     ベースラインは値に揃え、色は textMono
//   - 単位は値から離さず、入らなければ値といっしょに縮小する
//   - 段階語は入らなければ値の下の行へ。1 語でも入らなければ縮小する
//   - 省略記号・語の途中の改行なし。同じ行の 2 枚は高さを揃える
//   - 読み上げはタイル 1 枚で 1 つ

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_glyphs.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_metric_tile.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';

import '../golden/golden_harness.dart';

Widget _harness({
  required Widget child,
  double textScale = 1.0,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ja'), Locale('es')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildAppTheme(brightness, locale: locale),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

Future<void> _pumpTile(
  WidgetTester tester, {
  double textScale = 1.0,
  double height = 72,
  double width = 169,
  String value = '1013',
  String unit = 'hPa',
  String level = '',
  String label = 'PRESSURE',
  String? semanticsLabel,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_harness(
    textScale: textScale,
    locale: locale,
    brightness: brightness,
    child: SizedBox(
      width: width,
      child: QuietMetricTile(
        icon: QuietIcon.humidity,
        label: label,
        value: value,
        unit: unit,
        level: level,
        semanticsLabel: semanticsLabel,
        height: height,
      ),
    ),
  ));
  await tester.pump();
}

/// 段落のアルファベットのベースライン (画面座標。FittedBox の縮小も込み)。
double _baseline(WidgetTester tester, Finder text) {
  final p = tester.renderObject<RenderParagraph>(text);
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textHeightBehavior: p.textHeightBehavior,
    maxLines: p.maxLines,
  )..layout();
  final distance = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.dispose();
  return p.localToGlobal(Offset(0, distance)).dy;
}

/// 段落の行数 (語の途中の改行・折り返しの検出)。
int _lines(WidgetTester tester, Finder text) {
  final p = tester.renderObject<RenderParagraph>(text);
  final length = p.text.toPlainText().length;
  return p
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
      .map((b) => b.top.round())
      .toSet()
      .length;
}

/// 値の行に使える幅の右端 (タイルの右端 − 右余白 13)。
double _contentRight(WidgetTester tester, [Finder? tile]) =>
    tester.getRect(tile ?? find.byType(QuietMetricTile)).right - 13;

void main() {
  setUpAll(loadAppFonts);

  group('倍率 1.0 (Figma の寸法)', () {
    for (final (height, unit, level) in const [
      (72.0, 'hPa', ''),
      (84.0, 'hPa', ''),
      (72.0, '', 'Moderate'),
      (84.0, '', 'Moderate'),
    ]) {
      testWidgets('高さ $height のまま (${unit.isEmpty ? '段階語' : '単位'})',
          (tester) async {
        await _pumpTile(tester, height: height, unit: unit, level: level);
        expect(tester.getSize(find.byType(QuietMetricTile)).height, height);
      });
    }

    testWidgets('値は下端に置かれる (下余白 10)', (tester) async {
      await _pumpTile(tester);
      final tile = tester.getRect(find.byType(QuietMetricTile));
      final value = tester.getRect(find.text('1013'));
      expect(tile.bottom - value.bottom, closeTo(10, 0.5));
    });

    testWidgets('値の欄の固定幅はやめた: 値の送り幅の直後に単位 (間隔 4px)', (tester) async {
      await _pumpTile(tester, value: '3.2', unit: 'm/s');
      final value = tester.getRect(find.text('3.2'));
      final unit = tester.getRect(find.text('m/s'));
      expect(unit.left - value.right, closeTo(4, 0.01));
      // 値の送り幅は自然な幅 (74 に広げない)。
      expect(value.width, lessThan(40));
    });

    testWidgets('「%」は 1px で値に付ける (en)', (tester) async {
      await _pumpTile(tester, value: '58', unit: '%');
      final gap = tester.getRect(find.text('%')).left -
          tester.getRect(find.text('58')).right;
      expect(gap, closeTo(1, 0.01));
    });

    testWidgets('「%」は 1px (ja)', (tester) async {
      await _pumpTile(tester,
          value: '58', unit: '%', locale: const Locale('ja'), label: '湿度');
      final gap = tester.getRect(find.text('%')).left -
          tester.getRect(find.text('58')).right;
      expect(gap, closeTo(1, 0.01));
    });

    testWidgets('es の「%」だけ 4px (「58 %」)', (tester) async {
      await _pumpTile(tester,
          value: '58', unit: '%', locale: const Locale('es'), label: 'HUMEDAD');
      final gap = tester.getRect(find.text('%')).left -
          tester.getRect(find.text('58')).right;
      expect(gap, closeTo(4, 0.01));
    });

    testWidgets('段階語も値の直後 4px、同じ行', (tester) async {
      await _pumpTile(tester, value: '42', unit: '', level: 'Good');
      final value = tester.getRect(find.text('42'));
      final level = tester.getRect(find.text('Good'));
      expect(level.left - value.right, closeTo(4, 0.01));
      expect(_baseline(tester, find.text('Good')),
          closeTo(_baseline(tester, find.text('42')), 0.5));
    });

    for (final (locale, value, trailing, isLevel) in const [
      (Locale('en'), '1013', 'hPa', false),
      (Locale('ja'), '1013', 'hPa', false),
      (Locale('en'), '3', 'Moderate', true),
      (Locale('ja'), '3', '中程度', true),
      (Locale('ja'), '58', '%', false),
    ]) {
      testWidgets('ベースラインを値に揃える (${locale.languageCode}「$value $trailing」)',
          (tester) async {
        await _pumpTile(
          tester,
          value: value,
          unit: isLevel ? '' : trailing,
          level: isLevel ? trailing : '',
          locale: locale,
        );
        expect(_baseline(tester, find.text(trailing)),
            closeTo(_baseline(tester, find.text(value)), 0.5));
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('後ろの文字の色は textMono (${brightness.name})', (tester) async {
        await _pumpTile(tester, brightness: brightness);
        final tokens =
            brightness == Brightness.dark ? MrwTokens.dark : MrwTokens.light;
        final unit = tester.widget<Text>(find.text('hPa'));
        expect(unit.style?.color, tokens.textMono);
        expect(unit.style?.letterSpacing, 0);
        // 値は textHi のまま。
        expect(
            tester.widget<Text>(find.text('1013')).style?.color, tokens.textHi);
      });
    }

    testWidgets('「—」(muted) は textLo で、後ろの文字なし', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(
        child: const SizedBox(
          width: 169,
          child: QuietMetricTile(
            icon: QuietIcon.uv,
            label: 'UV',
            value: '—',
            muted: true,
          ),
        ),
      ));
      expect(tester.widget<Text>(find.text('—')).style?.color,
          MrwTokens.dark.textLo);
      expect(tester.getSize(find.byType(QuietMetricTile)).height, 72);
    });
  });

  group('文字倍率・狭い幅 (§4.1)', () {
    // 溢れれば flutter_test が例外で落とす。
    for (final scale in [1.3, 1.6, 2.0, 2.5]) {
      testWidgets('倍率 $scale: 単位は値と同じ行で、はみ出さず縮小される', (tester) async {
        await _pumpTile(tester, textScale: scale, width: 154);
        final h = tester.getSize(find.byType(QuietMetricTile)).height;
        expect(h, greaterThanOrEqualTo(72));
        final value = tester.getRect(find.text('1013'));
        final unit = tester.getRect(find.text('hPa'));
        // 単位は値の右 (同じ行)、ベースラインも同じ。
        expect(unit.left, greaterThan(value.right));
        expect(_baseline(tester, find.text('hPa')),
            closeTo(_baseline(tester, find.text('1013')), 0.5));
        // 値の行に使える幅に収まる (必要なら 2 つとも縮小)。
        expect(unit.right, lessThanOrEqualTo(_contentRight(tester) + 0.5));
        expect(_lines(tester, find.text('1013')), 1);
        expect(_lines(tester, find.text('hPa')), 1);
      });
    }

    testWidgets('単位が入らない幅では、値と単位をいっしょに縮小する (間隔の比も保つ)', (tester) async {
      await _pumpTile(
        tester,
        textScale: 2.0,
        width: 130,
        value: '108',
        unit: 'km/h',
      );
      final value = tester.getRect(find.text('108'));
      final unit = tester.getRect(find.text('km/h'));
      final natural = tester.renderObject<RenderParagraph>(find.text('108'));
      // 縮小されている (描画の幅 < 段落の幅)。
      expect(value.width, lessThan(natural.size.width - 0.5));
      expect(unit.right, lessThanOrEqualTo(_contentRight(tester) + 0.5));
      final scale = value.width / natural.size.width;
      expect(unit.left - value.right, closeTo(4 * scale, 0.05));
    });

    testWidgets('段階語が入らないときは値の下の行へ (左端は値と同じ)', (tester) async {
      // ×1.3・360dp (タイル 154) の en「200 Unhealthy」(§4.2 の表で「次行」)。
      await _pumpTile(
        tester,
        textScale: 1.3,
        width: 154,
        value: '200',
        unit: '',
        level: 'Unhealthy',
        label: 'AIR',
      );
      final value = tester.getRect(find.text('200'));
      final level = tester.getRect(find.text('Unhealthy'));
      expect(level.top, greaterThanOrEqualTo(value.bottom - 0.5));
      expect(level.left, closeTo(value.left, 0.5));
      expect(_lines(tester, find.text('Unhealthy')), 1);
      // タイルは伸びる (最小高さ 72 を超える)。段階語の行は下余白 10 の上。
      final tile = tester.getRect(find.byType(QuietMetricTile));
      expect(tile.height, greaterThan(72));
      expect(tile.bottom - level.bottom, closeTo(10, 0.5));
    });

    testWidgets('次の行に回した段階語も入らなければ、その語を縮小する (省略しない)', (tester) async {
      await _pumpTile(
        tester,
        textScale: 2.0,
        width: 154,
        value: '10',
        unit: '',
        level: 'Very high',
        label: 'UV',
      );
      final value = tester.getRect(find.text('10'));
      final level = tester.getRect(find.text('Very high'));
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text('Very high'));
      expect(level.top, greaterThanOrEqualTo(value.bottom - 0.5));
      expect(level.width, lessThan(paragraph.size.width - 0.5));
      expect(level.right, lessThanOrEqualTo(_contentRight(tester) + 0.5));
      expect(_lines(tester, find.text('Very high')), 1);
      expect(paragraph.didExceedMaxLines, isFalse);
    });

    testWidgets('値だけが入らないとき (×2.5 の長い値) も省略せず縮小する', (tester) async {
      await _pumpTile(
        tester,
        textScale: 2.5,
        width: 110,
        value: '1013.25',
        unit: '',
      );
      final value = tester.getRect(find.text('1013.25'));
      expect(value.right, lessThanOrEqualTo(_contentRight(tester) + 0.5));
      expect(_lines(tester, find.text('1013.25')), 1);
    });

    testWidgets('省略記号はどのテキストにも使わない', (tester) async {
      await _pumpTile(
        tester,
        textScale: 2.0,
        width: 130,
        value: '350',
        unit: '',
        level: 'Hazardous',
        label: 'AIR',
      );
      for (final e in find
          .descendant(
            of: find.byType(QuietMetricTile),
            matching: find.byType(Text),
          )
          .evaluate()) {
        expect((e.widget as Text).overflow, isNot(TextOverflow.ellipsis));
      }
    });
  });

  group('見出し', () {
    testWidgets('1 行。収まらないときは語中で折らず縮小する (TEMPERATUR / A の是正)', (tester) async {
      await _pumpTile(tester, textScale: 1.3, label: 'TEMPERATURA');
      final label = find.text('TEMPERATURA');
      final paragraph = tester.renderObject<RenderParagraph>(label);
      // 1 行 (折り返し・省略なし)。
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.height,
        lessThan(paragraph.getMaxIntrinsicHeight(double.infinity) * 1.5),
      );
      // 縮小されて見出しの枠 (タイル右端の内側 13) に収まる。
      final shown = tester.getRect(label);
      expect(shown.width, lessThan(paragraph.size.width));
      expect(shown.right, lessThanOrEqualTo(_contentRight(tester) + 0.5));
    });

    testWidgets('収まる見出しは縮小しない (倍率 1.0)', (tester) async {
      await _pumpTile(tester);
      final label = find.text('PRESSURE');
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(tester.getRect(label).width, closeTo(paragraph.size.width, 0.01));
    });
  });

  group('QuietMetricTileRow (同じ行の 2 枚)', () {
    Future<void> pumpRow(WidgetTester tester, {double textScale = 1.0}) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(
        textScale: textScale,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: QuietMetricTileRow(
            gap: 12,
            left: const QuietMetricTile(
              icon: QuietIcon.uv,
              label: 'UV',
              value: '10',
              level: 'Very high',
            ),
            right: const QuietMetricTile(
              icon: QuietIcon.air,
              label: 'AIR',
              value: '42',
              level: 'Good',
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('幅は (全幅 − 12) ÷ 2 で、倍率 1.0 では 72 のまま', (tester) async {
      await pumpRow(tester);
      final tiles = find.byType(QuietMetricTile);
      final left = tester.getRect(tiles.at(0));
      final right = tester.getRect(tiles.at(1));
      expect(left.width, closeTo(154, 0.01)); // 360dp
      expect(right.width, closeTo(154, 0.01));
      expect(right.left - left.right, closeTo(12, 0.01));
      expect(left.height, 72);
      expect(right.height, 72);
    });

    testWidgets('片方だけ段階語が次の行へ回っても、高さを揃え、値は下揃えのまま', (tester) async {
      await pumpRow(tester, textScale: 1.3);
      final tiles = find.byType(QuietMetricTile);
      final left = tester.getRect(tiles.at(0));
      final right = tester.getRect(tiles.at(1));
      // 左 (UV 10 Very high) は次の行へ回って伸びる。
      expect(tester.getRect(find.text('Very high')).top,
          greaterThanOrEqualTo(tester.getRect(find.text('10')).bottom - 0.5));
      expect(left.height, greaterThan(72));
      // 右 (AIR 42 Good) も同じ高さ。値の行は下端 (下余白 10)。
      expect(right.height, closeTo(left.height, 0.01));
      expect(right.bottom - tester.getRect(find.text('42')).bottom,
          closeTo(10, 0.5));
    });
  });

  testWidgets('読み上げはタイル 1 枚で 1 つ (見出し + 値 + 後ろの文字)', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpTile(
      tester,
      semanticsLabel: 'Pressure 1013 hectopascals',
    );
    expect(find.bySemanticsLabel('Pressure 1013 hectopascals'), findsOneWidget);
    // 子の文字は個別に読ませない。
    expect(find.bySemanticsLabel('hPa'), findsNothing);
    expect(find.bySemanticsLabel('1013'), findsNothing);
    semantics.dispose();
  });

  testWidgets('読み上げを渡さないときは「見出し 値 後ろの文字」', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpTile(tester);
    expect(find.bySemanticsLabel('PRESSURE 1013 hPa'), findsOneWidget);
    semantics.dispose();
  });
}
