// test/widget/chart_axes_test.dart
//
// 軸の部品 (chart_axes.dart) の検証。折れ線本体は mri_line_chart_test.dart。
// docs/home-sparkline-decisions.md 決定 ② / ④ と申し送り 2・3。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/mri_bar_scale.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';

const _style = TextStyle(fontSize: 10, height: 1.2);

/// CLDR は AM/PM の前に狭い無改行スペース (U+202F) を使う。比較用に通常の空白へ。
String _normalizeSpaces(String? s) =>
    (s ?? '').replaceAll(RegExp(r'[\u00A0\u202F\u2009]'), ' ');

/// 9 本・2 本おき (Home と同じ) のラベル列。
List<String?> _labels(List<String> hours) => [
      for (var i = 0; i < 9; i++) i.isEven ? hours[i ~/ 2] : null,
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool alwaysUse24HourFormat = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ja')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        alwaysUse24HourFormat: alwaysUse24HourFormat,
      ),
      child: inner!,
    ),
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump();
}

void main() {
  group('formatAxisHour', () {
    testWidgets('24 時間制のロケールは "15:00" (ユーザー要望の :00 表記)', (tester) async {
      String? out;
      await _pump(
        tester,
        Builder(builder: (context) {
          out = formatAxisHour(context, DateTime(2026, 7, 15, 15));
          return const SizedBox.shrink();
        }),
        locale: const Locale('ja'),
      );
      expect(out, '15:00');
    });

    testWidgets('12 時間制のロケールは "3 PM" (":00 PM" は軸に収まらない)', (tester) async {
      String? out;
      await _pump(
        tester,
        Builder(builder: (context) {
          out = formatAxisHour(context, DateTime(2026, 7, 15, 15));
          return const SizedBox.shrink();
        }),
      );
      expect(_normalizeSpaces(out), '3 PM');
    });

    testWidgets('端末が 24 時間表示なら en でも "15:00"', (tester) async {
      String? out;
      await _pump(
        tester,
        Builder(builder: (context) {
          out = formatAxisHour(context, DateTime(2026, 7, 15, 15));
          return const SizedBox.shrink();
        }),
        alwaysUse24HourFormat: true,
      );
      expect(out, '15:00');
    });
  });

  group('TimeAxisLabels', () {
    final hours = ['9:00', '12:00', '15:00', '18:00', '21:00'];

    testWidgets('余裕があれば全部出す', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 600,
          child: TimeAxisLabels(
            labels: _labels(hours),
            gap: 8,
            style: _style,
            anchorIndex: 2,
          ),
        ),
      );
      for (final h in hours) {
        expect(find.text(h), findsOneWidget);
      }
    });

    testWidgets('狭いと間引くが「現在」のラベルは必ず残る', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 120,
          child: TimeAxisLabels(
            labels: _labels(hours),
            gap: 8,
            style: _style,
            anchorIndex: 2,
          ),
        ),
      );
      final shown = hours.where((h) => find.text(h).evaluate().isNotEmpty);
      expect(shown.length, lessThan(hours.length));
      // index 2 = 3 番目のスロット = hours[1]。
      expect(find.text(hours[1]), findsOneWidget);
    });

    testWidgets('文字スケール 2.0 でも「現在」は残る (決定 ② の条件)', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 266, // Home の実寸 (390 − 余白 − 軸列)
          child: TimeAxisLabels(
            labels: _labels(hours),
            gap: 8,
            style: _style,
            anchorIndex: 2,
          ),
        ),
        textScale: 2.0,
      );
      expect(find.text(hours[1]), findsOneWidget);
    });

    testWidgets('BarSlotRow(follow:) は時刻ラベルと同じ間引きに従う (天気レール)', (tester) async {
      // 狭い幅でラベルが間引かれても、レールがラベルの無いスロットに残らない
      // (×1.3 でラベル 2 本に対しレール 5 個が残り、右端が詰まっていた件)。
      final labels = TimeAxisLabels(
        labels: _labels(hours),
        gap: 8,
        style: _style,
        anchorIndex: 2,
      );
      await _pump(
        tester,
        SizedBox(
          width: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              labels,
              BarSlotRow(
                gap: 8,
                height: 12,
                follow: labels,
                children: [
                  for (var i = 0; i < 9; i++)
                    i.isEven
                        ? SizedBox(key: ValueKey('rail-$i'), height: 12)
                        : null,
                ],
              ),
            ],
          ),
        ),
      );
      final shownLabels = [
        for (var i = 0; i < 9; i += 2)
          if (find.text(hours[i ~/ 2]).evaluate().isNotEmpty) i,
      ];
      final shownRails = [
        for (var i = 0; i < 9; i += 2)
          if (find.byKey(ValueKey('rail-$i')).evaluate().isNotEmpty) i,
      ];
      expect(shownLabels.length, lessThan(hours.length));
      expect(shownRails, shownLabels);
    });

    testWidgets('BarSlotRow は follow が無ければ全部置く', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 120,
          child: BarSlotRow(
            gap: 8,
            height: 12,
            children: [
              for (var i = 0; i < 9; i++)
                i.isEven
                    ? SizedBox(key: ValueKey('rail-$i'), height: 12)
                    : null,
            ],
          ),
        ),
      );
      for (var i = 0; i < 9; i += 2) {
        expect(find.byKey(ValueKey('rail-$i')), findsOneWidget);
      }
    });

    testWidgets('両端のラベルが枠からはみ出さない (Figma 3:90 の 14px 逸脱の是正)', (tester) async {
      const width = 266.0;
      await _pump(
        tester,
        SizedBox(
          width: width,
          child: TimeAxisLabels(
            labels: _labels(hours),
            gap: 8,
            style: _style,
            anchorIndex: 2,
          ),
        ),
      );
      final box = tester.getRect(find.byType(TimeAxisLabels));
      for (final h in hours) {
        final finder = find.text(h);
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(box.left - 0.5), reason: h);
        expect(rect.right, lessThanOrEqualTo(box.right + 0.5), reason: h);
      }
    });

    testWidgets('「現在」のラベルだけ別のスタイルを当てられる (申し送り 2)', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 600,
          child: TimeAxisLabels(
            labels: _labels(hours),
            gap: 8,
            style: _style,
            anchorIndex: 2,
            anchorStyle: _style.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      );
      final now = tester.widget<Text>(find.text(hours[1]));
      final other = tester.widget<Text>(find.text(hours[2]));
      expect(now.style?.fontWeight, FontWeight.w600);
      expect(other.style?.fontWeight, isNot(FontWeight.w600));
    });
  });

  // QA-10: 時刻ラベルは収まっていても、下の天気レール (グリフ + 気温) の方が幅が
  // 広く隣と接していた。レールの項目幅 (companion) も見て置き方と間引きを選ぶ。
  // 幅 266 / 9 本 / 間隔 8 → バー 22.4、2 スロットの枠 52.9、中心 11.2, 72.1, …
  group('TimeAxisLabels.companion (天気レールの項目幅)', () {
    const width = 266.0;
    // ラベル自体は間引かれない短さ (テスト書体は 1 字 1em = 10px)。
    final hours = ['9', '12', '15', '18', '21'];

    /// ラベル行と、その下のレール (幅 [railWidth] の箱) を並べる。
    Future<TimeAxisLabels> pumpRows(
      WidgetTester tester, {
      required double railWidth,
      Map<int, double> blanks = const {},
    }) async {
      final labels = TimeAxisLabels(
        labels: _labels(hours),
        gap: 8,
        style: _style,
        anchorIndex: 2,
        companion: AxisCompanionRow(
          span: 2,
          widths: {for (var i = 0; i < 9; i += 2) i: railWidth},
          trailingBlanks: blanks,
        ),
      );
      await _pump(
        tester,
        SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              labels,
              BarSlotRow(
                gap: 8,
                height: 12,
                span: 2,
                follow: labels,
                children: [
                  for (var i = 0; i < 9; i++)
                    i.isEven
                        ? SizedBox(
                            key: ValueKey('rail-$i'),
                            height: 12,
                            width: railWidth,
                          )
                        : null,
                ],
              ),
            ],
          ),
        ),
      );
      return labels;
    }

    List<int> shownRails() => [
          for (var i = 0; i < 9; i += 2)
            if (find.byKey(ValueKey('rail-$i')).evaluate().isNotEmpty) i,
        ];

    BuildContext rowContext(WidgetTester tester) =>
        tester.element(find.byType(TimeAxisLabels));

    testWidgets('接しなければ枠 (slot) の置き方のまま (倍率 1.0 の見た目を変えない)', (tester) async {
      final labels = await pumpRows(tester, railWidth: 30);
      final context = rowContext(tester);
      expect(labels.companionPlacement(context, width), BarSlotPlacement.slot);
      expect(labels.visibleIndices(context, width), [0, 2, 4, 6, 8]);
      // 枠は 2 スロットぶん (52.9) で、両端は行の内側へ寄る。
      final slot = barSlotWidth(
          barWidth: (width - 8 * 8) / 9, gap: 8, span: 2, maxWidth: width);
      final left = tester.getTopLeft(find.byType(BarSlotRow)).dx;
      final rail0 = tester.getRect(find.byKey(const ValueKey('rail-0')));
      expect(rail0.center.dx - left, closeTo(slot / 2, 0.5));
    });

    testWidgets('枠の置き方で接するなら、ラベルを減らさずに中身の幅で置く (centered)', (tester) async {
      // slot: 0 と 2 の間 1.7px (< 3)。centered: 5.6px。
      final labels = await pumpRows(tester, railWidth: 44);
      final context = rowContext(tester);
      expect(
          labels.companionPlacement(context, width), BarSlotPlacement.centered);
      expect(labels.visibleIndices(context, width), [0, 2, 4, 6, 8]);
      expect(shownRails(), [0, 2, 4, 6, 8]);

      final left = tester.getTopLeft(find.byType(BarSlotRow)).dx;
      const barWidth = (width - 8 * 8) / 9;
      final rails = [
        for (var i = 0; i < 9; i += 2)
          tester.getRect(find.byKey(ValueKey('rail-$i'))),
      ];
      // 中の項目は担当スロットの中心、両端は行の内側に寄せる (はみ出さない)。
      expect(rails[2].center.dx - left,
          closeTo(4 * (barWidth + 8) + barWidth / 2, 0.5));
      expect(rails.first.left, greaterThanOrEqualTo(left - 0.5));
      expect(rails.last.right, lessThanOrEqualTo(left + width + 0.5));
      for (var i = 1; i < rails.length; i++) {
        expect(rails[i].left - rails[i - 1].right,
            greaterThanOrEqualTo(kAxisCompanionMinSpacing));
      }
    });

    testWidgets('centered でも接するなら 1 段多く間引き、ラベルとレールは同じスロット', (tester) async {
      final labels = await pumpRows(tester, railWidth: 56);
      final context = rowContext(tester);
      expect(labels.visibleIndices(context, width), [2, 6]);
      expect(shownRails(), [2, 6]);
      final shownLabels = [
        for (var i = 0; i < 9; i += 2)
          if (find.text(hours[i ~/ 2]).evaluate().isNotEmpty) i,
      ];
      expect(shownLabels, [2, 6]);
    });

    testWidgets('右端の空き (JA の全角「°」) は間隔の判定から除く', (tester) async {
      // 空きが無いと centered でも接する (0 と 2 の間 −3.4px) → 間引かれる。
      final plain = await pumpRows(tester, railWidth: 50);
      expect(plain.visibleIndices(rowContext(tester), width), [2, 6]);
      // 右端 8px が空きなら、枠の置き方のままでも字面の間は 3.65px → 間引かず、
      // 置き方も変えない。
      final withBlank = await pumpRows(
        tester,
        railWidth: 50,
        blanks: {for (var i = 0; i < 9; i += 2) i: 8},
      );
      final context = rowContext(tester);
      expect(withBlank.visibleIndices(context, width), [0, 2, 4, 6, 8]);
      expect(
          withBlank.companionPlacement(context, width), BarSlotPlacement.slot);
    });
  });

  group('axisLabelStyle', () {
    testWidgets('JA でも軸ラベルは IBM Plex Mono (Figma JP 77:64 の実測に合わせる)',
        (tester) async {
      TextStyle? style;
      await _pump(
        tester,
        Builder(builder: (context) {
          style = axisLabelStyle(context, color: Colors.white);
          return const SizedBox.shrink();
        }),
        locale: const Locale('ja'),
      );
      expect(style?.fontFamily, MrwFonts.plexMono);
      // 型スケールの axis (既定の案2 は 12。--dart-define=MRW_TYPE_SCALE で
      // current = v1.3 の 10 / 案1 = 11)。
      expect(
        style?.fontSize,
        MrwType.forScale(MrwTypeScale.fromEnvironment).axis.fontSize(10),
      );
    });

    testWidgets('現在のラベルは weight 600 (同梱の SemiBold)', (tester) async {
      TextStyle? style;
      await _pump(
        tester,
        Builder(builder: (context) {
          style = axisLabelStyle(
            context,
            color: Colors.white,
            weight: FontWeight.w600,
          );
          return const SizedBox.shrink();
        }),
      );
      expect(style?.fontFamily, MrwFonts.plexMono);
      expect(style?.fontWeight, FontWeight.w600);
    });
  });

  group('MriValueAxis', () {
    testWidgets('上限 / 下限を出す', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 18,
          height: 36,
          child: MriValueAxis(
            scale: MriBarScale(lo: 50, hi: 80),
            style: _style,
          ),
        ),
      );
      expect(find.text('80'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('文字スケール 2.0 でも minChartHeight の高さなら溢れない', (tester) async {
      // 溢れれば flutter_test が例外で落とす。
      await _pump(
        tester,
        Builder(builder: (context) {
          final h = MriValueAxis.minChartHeight(context, _style);
          expect(h, greaterThan(36));
          return SizedBox(
            width: MriValueAxis.widthFor(context),
            height: h,
            child: const MriValueAxis(
              scale: MriBarScale(lo: 50, hi: 80),
              style: _style,
            ),
          );
        }),
        textScale: 2.0,
      );
      expect(find.text('80'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });
  });
}
