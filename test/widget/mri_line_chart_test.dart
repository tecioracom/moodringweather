// test/widget/mri_line_chart_test.dart
//
// 折れ線 (mri_line_chart.dart) の幾何と描画。docs/home-sparkline-line-consult.md。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/shared/mri_bar_scale.dart';
import 'package:mood_ring_weather/presentation/shared/mri_line_chart.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';

const _size = Size(282, 36);
const _scale = MriBarScale(lo: 50, hi: 80);

MriLineGeometry _geo({double stroke = 1.75}) => MriLineGeometry(
      size: _size,
      scale: _scale,
      slotCount: 9,
      verticesPerSlot: 1.5,
      gap: 8,
      strokeWidth: stroke,
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.dark}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(brightness),
    home: Scaffold(body: Center(child: SizedBox(width: 282, child: child))),
  ));
  await tester.pump();
}

void main() {
  group('MriLineGeometry', () {
    test('頂点は時刻ラベルと同じスロット中心に載る (頂点 3 = スロット 2)', () {
      final g = _geo();
      const slotW = (282 - 8 * 8) / 9;
      expect(g.slotWidth, closeTo(slotW, 1e-9));
      expect(g.xAt(0), closeTo(slotW / 2, 1e-9));
      expect(g.xAt(3), closeTo(slotW / 2 + 2 * (slotW + 8), 1e-9));
      expect(g.xAt(12), closeTo(slotW / 2 + 8 * (slotW + 8), 1e-9));
    });

    test('y は表示範囲を高さ全体に写像する (下駄なし、線幅の半分だけ内側)', () {
      final g = _geo();
      expect(g.yAt(80), closeTo(0.875, 1e-9)); // 上限 = 上端 + 線幅/2
      expect(g.yAt(50), closeTo(36 - 0.875, 1e-9)); // 下限 = 下端 − 線幅/2
      expect(g.yAt(65), closeTo(18, 1e-9)); // 中央
      // 範囲外はクランプ。
      expect(g.yAt(100), g.yAt(80));
      expect(g.yAt(0), g.yAt(50));
    });

    test('MRI 1 点あたりの高さは capsule bar (下駄 0.5) の約 2 倍', () {
      final g = _geo();
      final perPoint = (g.yAt(50) - g.yAt(80)) / 30;
      const barPerPoint = 36 * 0.5 / 30; // 旧: 18px を幅 30 で割る
      expect(perPoint, greaterThan(barPerPoint * 1.9));
    });

    test('快適帯は線と同じ写像。上限が範囲の上端なら 0 から、下端は 60 の高さまで', () {
      final g = _geo();
      final r = g.bandRect(kComfortBandMin, kComfortBandMax)!;
      expect(r.top, 0); // 80 = 上限 → 上端まで
      expect(r.bottom, closeTo(g.yAt(60), 1e-9));
      expect(r.width, 282);
      expect(g.bandEdgeVisible(kComfortBandMin), isTrue);
    });

    test('表示範囲に掛からなければ帯は null、下限が範囲外なら基準線を引かない', () {
      const hot = MriLineGeometry(
        size: _size,
        scale: MriBarScale(lo: 20, hi: 50),
        slotCount: 9,
        verticesPerSlot: 1.5,
        gap: 8,
        strokeWidth: 1.75,
      );
      expect(hot.bandRect(kComfortBandMin, kComfortBandMax), isNull);
      const high = MriLineGeometry(
        size: _size,
        scale: MriBarScale(lo: 65, hi: 90),
        slotCount: 9,
        verticesPerSlot: 1.5,
        gap: 8,
        strokeWidth: 1.75,
      );
      final r = high.bandRect(kComfortBandMin, kComfortBandMax)!;
      expect(r.bottom, 36); // 下限 60 は範囲外 → 底まで
      expect(high.bandEdgeVisible(kComfortBandMin), isFalse);
    });
  });

  group('MriLineChart', () {
    const values = <double?>[
      58,
      61,
      66,
      74,
      73,
      70,
      66,
      62,
      60,
      63,
      68,
      72,
      75
    ];

    Widget chart(
            {PastLineStyle past = PastLineStyle.dashed,
            List<double?> v = values}) =>
        MriLineChart(
          values: v,
          nowIndex: 3,
          slotCount: 9,
          verticesPerSlot: 1.5,
          scale: _scale,
          pastStyle: past,
          bandMin: kComfortBandMin,
          bandMax: kComfortBandMax,
        );

    testWidgets('描画できる (Dark / Light、実線 / 破線)', (tester) async {
      await _pump(tester, chart(past: PastLineStyle.dim));
      expect(find.byType(CustomPaint), findsWidgets);
      await _pump(tester, chart(), brightness: Brightness.light);
      expect(tester.getSize(find.byType(MriLineChart)).height, 36);
    });

    testWidgets('欠測 (null) があっても落ちない', (tester) async {
      await _pump(
          tester,
          chart(v: const [
            58,
            null,
            66,
            74,
            null,
            null,
            66,
            62,
            60,
            null,
            68,
            72,
            null
          ]));
      expect(find.byType(MriLineChart), findsOneWidget);
    });

    testWidgets('全部 null でも落ちない', (tester) async {
      await _pump(tester, chart(v: List<double?>.filled(13, null)));
      expect(find.byType(MriLineChart), findsOneWidget);
    });

    testWidgets('既定は採用案 C: 破線 3/3 + 過去 wash 4% + 現在線 40%、面塗り・ラベル・微光なし',
        (tester) async {
      await _pump(tester, chart());
      final w = tester.widget<MriLineChart>(find.byType(MriLineChart));
      expect(w.futureAlpha, isNull); // テーマ既定 (Dark 0.60 / Light 0.68)
      expect(w.pastAlpha, isNull); // 破線なので未来と同じ α
      expect(w.strokeWidth, 1.75);
      expect(w.pastStyle, PastLineStyle.dashed);
      expect(w.dashOn, 3);
      expect(w.dashOff, 3);
      expect(w.pastWashAlpha, 0.04);
      expect(w.nowLineAlpha, 0.40);
      expect(w.bandTopEdgeAlpha, 0);
      expect(w.nowGlowRadius, 0);
      expect(w.bandLabel, isNull);
    });
  });
}
