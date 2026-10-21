// 同梱フォントが読めない環境でもテーマが落ちないこと (段階 S2 の完了条件 5)。
//
// flutter_test は既定でフォントアセットを読み込まない (= 同梱フォントが
// 存在しない状態と同じ)。この状態で buildAppTheme を適用した画面が例外なく
// 描画され、テキストがエンジンの既定フォントへフォールバックすることを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ja')]) {
    testWidgets('フォント未読込でも buildAppTheme の画面が描画される ($locale)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light, locale: locale),
        darkTheme: buildAppTheme(Brightness.dark, locale: locale),
        locale: locale,
        home: Scaffold(
          body: Builder(builder: (context) {
            final t = Theme.of(context).textTheme;
            return Column(children: [
              Text('Heading 見出し', style: t.headlineMedium),
              Text('Title タイトル', style: t.titleMedium),
              Text('Body 本文 22°', style: t.bodyMedium),
              Text('LABEL ラベル', style: t.labelMedium),
              Text('74',
                  style: MrwFonts.numeral(context,
                      size: 40, weight: FontWeight.w600)),
            ]);
          }),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('74'), findsOneWidget);
      expect(find.text('Body 本文 22°'), findsOneWidget);
    });
  }

  test('TextTheme の書体は v1.3 の同梱ファミリを指す', () {
    final en = buildAppTheme(Brightness.dark, locale: const Locale('en'));
    expect(en.textTheme.headlineMedium!.fontFamily, MrwFonts.fraunces);
    expect(en.textTheme.bodyMedium!.fontFamily, MrwFonts.inter);
    expect(en.textTheme.labelMedium!.fontFamily, MrwFonts.plexMono);
    expect(en.textTheme.headlineMedium!.fontVariations,
        contains(const FontVariation('WONK', 1)));
    final ja = buildAppTheme(Brightness.dark, locale: const Locale('ja'));
    expect(ja.textTheme.headlineMedium!.fontFamily, MrwFonts.plexSansJp);
    expect(ja.textTheme.bodyMedium!.fontFamily, MrwFonts.plexSansJp);
    expect(ja.textTheme.labelMedium!.fontFamily, MrwFonts.plexSansJp);
    expect(ja.textTheme.titleMedium!.fontWeight, FontWeight.w700);
  });
}
