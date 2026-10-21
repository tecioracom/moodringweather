// test/golden/screens_golden_test.dart
//
// 主要 3 画面 (ホーム / 詳細 / 設定) × Dark/Light × en/ja の見た目の回帰検出。
// v1.3 デザイン反映 (docs/v1.3-design-implementation-plan.md) の各段階で、
// 意図した差分だけが出ていることを差分画像で確認してから基準を更新する。
//
// 実行:   flutter test test/golden
// 更新:   flutter test test/golden --update-goldens   (差分を目視した後だけ)
// 差分:   test/golden/failures/*_masterImage.png / *_testImage.png / *_isolatedDiff.png

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  const locales = [Locale('en'), Locale('ja')];
  const modes = [Brightness.dark, Brightness.light];

  for (final brightness in modes) {
    for (final locale in locales) {
      final tag = '${brightness.name}/${locale.languageCode}';

      testWidgets('MainShell 3 タブ ($tag)', (tester) async {
        useGoldenViewport(tester);
        final overrides = await goldenOverrides();
        await tester.pumpWidget(goldenApp(
          home: const MainShell(),
          brightness: brightness,
          locale: locale,
          overrides: overrides,
        ));
        await settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(goldenName('home', brightness, locale)),
        );

        // 下部ナビの 2 番目 (詳細) → 3 番目 (設定)。
        final destinations = find.byType(QuietNavBar);
        expect(destinations, findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
        await settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(goldenName('detail', brightness, locale)),
        );

        await tester.tap(find.byKey(const ValueKey('quiet-nav-2')));
        await settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(goldenName('settings', brightness, locale)),
        );
      });
    }
  }
}
