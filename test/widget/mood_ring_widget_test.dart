import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/shared/mood_ring_widget.dart';

void main() {
  testWidgets('MoodRingWidget はスコアとラベルを表示する', (tester) async {
    final mri = MoodRingIndex(
      value: 72,
      band: MriBand.comfortable,
      factorContributions: const {'temp': 22, 'humid': 15},
      calculatedAt: DateTime(2026, 5, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: MoodRingWidget(mri: mri)),
        ),
      ),
    );

    expect(find.text('72'), findsOneWidget);
    expect(find.text('COMFORTABLE'), findsOneWidget);
  });

  testWidgets('ホット警告ラベルは「—」の直後で 2 行になり、数値の中心は動かない', (tester) async {
    Future<double> numberCenterY(MriBand band, int value, String label) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MoodRingWidget(
                mri: MoodRingIndex(
                  value: value,
                  band: band,
                  factorContributions: const {},
                  calculatedAt: DateTime(2026, 5, 22),
                ),
                label: label,
              ),
            ),
          ),
        ),
      );
      return tester.getCenter(find.text('$value')).dy;
    }

    final oneLine = await numberCenterY(MriBand.comfortable, 72, 'COMFORTABLE');
    final twoLines =
        await numberCenterY(MriBand.hotAlert, 12, 'VERY HOT — HYDRATE');

    final label = find.text('VERY HOT —\nHYDRATE');
    expect(label, findsOneWidget);
    // 数値の中心は 1 行の帯名のときと同じ (2 行目は下へ伸びる)。
    expect(twoLines, closeTo(oneLine, 0.01));
    // 2 行にした帯名は幅 124 以内 (176px のリングの内側)。
    expect(tester.getSize(label).width, lessThanOrEqualTo(124));
    expect(tester.getTopLeft(label).dy, greaterThan(twoLines));
  });

  testWidgets('とても寒いの帯名も 2 行でリングの内側 (幅 124) に収まる', (tester) async {
    for (final label in const [
      'VERY COLD — BUNDLE UP',
      'MUCHO FRÍO — ABRÍGATE',
      'とても寒い — 防寒を',
      '严寒 — 请保暖',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MoodRingWidget(
                mri: MoodRingIndex(
                  value: 100,
                  band: MriBand.cool,
                  factorContributions: const {},
                  calculatedAt: DateTime(2026, 10, 1),
                ),
                label: label,
              ),
            ),
          ),
        ),
      );
      final (first, second) = MoodRingWidget.splitLabel(label)!;
      final text = find.text('$first\n$second');
      expect(text, findsOneWidget, reason: label);
      // 幅 124 を超える分は FittedBox で縮める。描かれた幅 (縮めた後) で見る。
      expect(tester.getRect(text).width, lessThanOrEqualTo(124.01),
          reason: label);
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  test('帯名の分割は「—」の直後だけ', () {
    expect(MoodRingWidget.splitLabel('VERY HOT — HYDRATE'),
        ('VERY HOT —', 'HYDRATE'));
    expect(MoodRingWidget.splitLabel('とても暑い — 水分補給を'), ('とても暑い —', '水分補給を'));
    expect(MoodRingWidget.splitLabel('MUCHO CALOR — HIDRÁTATE'),
        ('MUCHO CALOR —', 'HIDRÁTATE'));
    // 寒い側の「とても寒い — 防寒を」も同じく 2 行 (band_label.dart、2026-10-01)
    expect(MoodRingWidget.splitLabel('VERY COLD — BUNDLE UP'),
        ('VERY COLD —', 'BUNDLE UP'));
    expect(MoodRingWidget.splitLabel('とても寒い — 防寒を'), ('とても寒い —', '防寒を'));
    expect(MoodRingWidget.splitLabel('MUCHO FRÍO — ABRÍGATE'),
        ('MUCHO FRÍO —', 'ABRÍGATE'));
    expect(MoodRingWidget.splitLabel('严寒 — 请保暖'), ('严寒 —', '请保暖'));
    expect(MoodRingWidget.splitLabel('COMFORTABLE'), isNull);
    expect(MoodRingWidget.splitLabel('SLIGHTLY HOT'), isNull);
  });

  testWidgets('既定の英語ラベル (⚠ VERY HOT — HYDRATE) も 2 行', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MoodRingWidget(
              mri: MoodRingIndex(
                value: 12,
                band: MriBand.hotAlert,
                factorContributions: const {},
                calculatedAt: DateTime(2026, 5, 22),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('⚠ VERY HOT —\nHYDRATE'), findsOneWidget);
  });
}
