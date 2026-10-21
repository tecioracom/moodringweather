// test/widget/quiet_list_row_test.dart
//
// 行カード (QuietListRow) の右要素の置き方 (designer 2026-09-29 の指摘)。
// 題 (Expanded) と右要素 (Flexible) が 1:1 で幅を分けていたため、右要素が行の
// 中ほどに浮いていた。右要素は内容の幅 (上限 = 行の内側の幅の 50%) で右端に寄せ、
// 題が残りの幅を取る。右端はシェブロンの左 8px (シェブロンが無ければ内側 10px)。
// 見出しのバッジ (titleBadge。1.3.0 (14) の「設定中」): 見出しと 1 行に収まれば文字の
// 列の右端、収まらなければ見出しの下。説明の幅は食わない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_row_icons.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';

import '../golden/golden_harness.dart';

const _trailingKey = ValueKey('trailing');

Future<void> _pumpRow(
  WidgetTester tester,
  QuietListRow row, {
  double width = 334,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: width, child: row)),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('右要素は内容の幅で、シェブロンの左 8px に寄る', (tester) async {
    await _pumpRow(
      tester,
      QuietListRow(
        title: 'Heat alerts',
        trailing: const SizedBox(key: _trailingKey, width: 40, height: 20),
        chevron: true,
        onTap: () {},
      ),
    );
    final trailing = tester.getRect(find.byKey(_trailingKey));
    final chevron = tester.getRect(find.byWidgetPredicate(
        (w) => w is QuietRowIconMark && w.icon == QuietRowIcon.chevron));
    expect(trailing.width, 40);
    expect(chevron.left - trailing.right, closeTo(8, 0.01));
  });

  testWidgets('シェブロンが無ければ行の右端 (内側 10px) に寄る', (tester) async {
    await _pumpRow(
      tester,
      const QuietListRow(
        title: 'Heat alerts',
        trailing: SizedBox(key: _trailingKey, width: 52, height: 30),
      ),
    );
    final row = tester.getRect(find.byType(QuietListRow));
    final trailing = tester.getRect(find.byKey(_trailingKey));
    expect(row.right - trailing.right, closeTo(10, 0.01));
    // 題は残りの幅を取る (右要素の左 10px まで)。
    final title = tester.getRect(find.ancestor(
      of: find.text('Heat alerts'),
      matching: find.byType(Expanded),
    ));
    expect(trailing.left - title.right, closeTo(10, 0.01));
  });

  testWidgets('右要素の幅は行の内側の幅の 50% まで (長い値は折り返す)', (tester) async {
    await _pumpRow(
      tester,
      QuietListRow(
        title: 'Paris',
        trailing: const Text(
          'A very long trailing value that would take the whole row',
          key: _trailingKey,
        ),
        chevron: true,
        onTap: () {},
      ),
    );
    // 内側の幅 = 334 − 左 16 − 右 10 = 308。
    final trailing = tester.getRect(find.byKey(_trailingKey));
    expect(trailing.width, lessThanOrEqualTo(308 * 0.5 + 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('倍率 2.0 のスイッチ行でも溢れない', (tester) async {
    await _pumpRow(
      tester,
      QuietListRow(
        title: 'Notificaciones personales',
        emphasizeTitle: true,
        trailing: QuietSwitch(value: true, onChanged: (_) {}),
        onTap: () {},
      ),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(QuietListRow));
    final toggle = tester.getRect(find.byType(Switch));
    expect(row.right - toggle.right, closeTo(10, 0.01));
  });

  group('見出しのバッジ (titleBadge)', () {
    const badgeKey = ValueKey('badge');
    QuietListRow row({String title = 'Set live wallpaper'}) => QuietListRow(
          title: title,
          subtitle: 'Also set it on your lock screen from here',
          emphasizeTitle: true,
          titleBadge: const QuietBadge('In use', key: badgeKey),
          chevron: true,
          onTap: () {},
        );
    Rect chevron(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
        (w) => w is QuietRowIconMark && w.icon == QuietRowIcon.chevron));

    testWidgets('1 行に収まれば見出しの行の右端 (シェブロンの左 8px)', (tester) async {
      await _pumpRow(tester, row());
      final badge = tester.getRect(find.byKey(badgeKey));
      final title = tester.getRect(find.text('Set live wallpaper'));
      expect(badge.left, greaterThan(title.right));
      expect(badge.center.dy, closeTo(title.center.dy, 2));
      expect(chevron(tester).left - badge.right, closeTo(8, 0.01));
    });

    testWidgets('収まらなければ見出しの下 (左寄せ)。説明の幅は狭くならない', (tester) async {
      await _pumpRow(tester, row(), width: 304, textScale: 2.0);
      expect(tester.takeException(), isNull);
      final badge = tester.getRect(find.byKey(badgeKey));
      final title = tester.getRect(find.text('Set live wallpaper'));
      final hint = tester
          .getRect(find.text('Also set it on your lock screen from here'));
      expect(badge.top, greaterThanOrEqualTo(title.bottom));
      expect(badge.bottom, lessThanOrEqualTo(hint.top));
      expect(badge.left, closeTo(title.left, 0.01));
      // 説明は文字の列の幅いっぱい (= 右要素があるときより広い)。
      expect(hint.width, greaterThan(304 - 16 - 10 - 28 - 90));
    });

    testWidgets('バッジなしは従来どおり (見出しは Text 1 つ)', (tester) async {
      await _pumpRow(
        tester,
        QuietListRow(title: 'General', chevron: true, onTap: () {}),
      );
      expect(find.byType(Wrap), findsNothing);
    });
  });
}
