// test/widget/live_wallpaper_setup_row_test.dart
//
// 設定 › 一般 › ライブ壁紙「ライブ壁紙を設定」の行 (1.3.0 (14))。
// 2026-10-01 実機 (Galaxy Z Fold 6) で発見: One UI の「壁紙とスタイル」は他社アプリの
// ライブ壁紙を一覧に出さず、Dart から openLiveWallpaperPicker が一度も呼ばれていな
// かったため、ライブ壁紙を設定する手段が無かった。
//   - Android だけ。区画の先頭 (「壁紙に天気と気温を表示」の上)。シェブロン付き
//   - 押すとプレビュー画面を開く (openPicker)。開けなければ手順のスナックバー
//   - 今の壁紙がこのライブ壁紙なら「設定中」と、説明を「ロック画面への設定もここから」に。
//     設定中でも押せば開く
//   - 「設定中」は画面を開いたときと、アプリが前面に戻ったときに読み直す
//   - 読み上げは行を 1 つにまとめる (見出し・説明・設定中、ボタン)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/shared/glass_card.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_row_icons.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

/// 壁紙の設定の偽物。[active] は isActive の返事、[opens] は openPicker の返事。
class _FakeSetup implements LiveWallpaperSetupBridge {
  _FakeSetup({this.active = false, this.opens = true});

  bool active;
  bool opens;
  int openCalls = 0;
  int activeCalls = 0;

  /// 次の openPicker の返事を待たせる (開いている途中の連打の再現)。
  Completer<bool>? holdOpen;

  /// true なら isActive が例外を投げる。
  bool throwOnActive = false;

  @override
  Future<bool> openPicker() async {
    openCalls++;
    final hold = holdOpen;
    if (hold != null) return hold.future;
    return opens;
  }

  @override
  Future<bool> isActive() async {
    activeCalls++;
    if (throwOnActive) throw StateError('boom');
    return active;
  }
}

const _title = 'Set live wallpaper';
const _hint = 'Use it as your home screen wallpaper';
const _activeHint = 'Also set it on your lock screen from here';
const _badge = 'In use';
const _failed =
    'Choose “Mood-Ring Weather” in your device\'s wallpaper settings';

Future<void> _pump(
  WidgetTester tester,
  _FakeSetup setup, {
  Locale locale = const Locale('en'),
  Widget home = const GeneralSettingsPage(),
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      unitRegionOverride(),
      liveWallpaperSetupBridgeProvider.overrideWithValue(setup),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// アプリをバックグラウンドへ送り、前面に戻す (壁紙のプレビュー画面へ行って戻る)。
Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

Finder _row() => find
    .ancestor(of: find.text(_title), matching: find.byType(QuietListRow))
    .first;

void main() {
  testWidgets('区画の先頭 (トグル行の上) に出る。未設定の説明・シェブロン・設定中なし', (tester) async {
    final setup = _FakeSetup();
    await _pump(tester, setup);

    final section = tester.getRect(find.text('LIVE WALLPAPER'));
    final title = tester.getRect(find.text(_title));
    final toggle = tester.getRect(find.text('Show weather on wallpaper'));
    expect(title.top, greaterThan(section.bottom));
    expect(toggle.top, greaterThan(title.bottom));
    // 別のカード (行) で、トグル行の上。
    final rowCard = tester.getRect(find
        .ancestor(of: find.text(_title), matching: find.byType(QuietCard))
        .first);
    final toggleCard = tester.getRect(find
        .ancestor(
          of: find.text('Show weather on wallpaper'),
          matching: find.byType(QuietCard),
        )
        .first);
    expect(toggleCard.top, greaterThanOrEqualTo(rowCard.bottom));

    expect(find.text(_hint), findsOneWidget);
    expect(find.text(_activeHint), findsNothing);
    expect(find.text(_badge), findsNothing);
    final row = tester.widget<QuietListRow>(_row());
    expect(row.chevron, isTrue);
    expect(row.trailing, isNull);
    expect(row.titleBadge, isNull);
    expect(row.icon, isNull); // 区画のトグル行と同じくアイコンなし
    expect(
      find.descendant(
        of: _row(),
        matching: find.byWidgetPredicate(
            (w) => w is QuietRowIconMark && w.icon == QuietRowIcon.chevron),
      ),
      findsOneWidget,
    );
    expect(setup.activeCalls, 1); // 画面を開いたときに読む
  });

  testWidgets('iOS (ライブ壁紙なし) では出さず、ネイティブにも問い合わせない', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final setup = _FakeSetup(active: true);
      await _pump(tester, setup);
      expect(find.text(_title), findsNothing);
      expect(find.text(_badge), findsNothing);
      expect(find.text('LIVE WALLPAPER'), findsNothing);
      expect(setup.activeCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('押すとプレビュー画面を開く (openPicker)。開けたらスナックバーは出さない', (tester) async {
    final setup = _FakeSetup();
    await _pump(tester, setup);
    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(setup.openCalls, 1);
    expect(find.byType(SnackBar), findsNothing);

    // 説明を押しても同じ (行のどこでも)。
    await tester.tap(find.text(_hint));
    await tester.pumpAndSettle();
    expect(setup.openCalls, 2);
  });

  testWidgets('開けなければ (false) 手順をスナックバーで案内する', (tester) async {
    final setup = _FakeSetup(opens: false);
    await _pump(tester, setup);
    await tester.tap(find.text(_title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(setup.openCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_failed), findsOneWidget);
  });

  testWidgets('開いている途中の連打では 2 回開かない', (tester) async {
    final setup = _FakeSetup()..holdOpen = Completer<bool>();
    await _pump(tester, setup);
    await tester.tap(find.text(_title));
    await tester.pump();
    await tester.tap(find.text(_title));
    await tester.pump();
    expect(setup.openCalls, 1);
    setup.holdOpen!.complete(true);
    setup.holdOpen = null;
    await tester.pumpAndSettle();
    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(setup.openCalls, 2);
  });

  testWidgets('設定中: 右に「設定中」、説明はロック画面の案内。押せばまた開く', (tester) async {
    final setup = _FakeSetup(active: true);
    await _pump(tester, setup);
    expect(find.text(_badge), findsOneWidget);
    expect(find.text(_activeHint), findsOneWidget);
    expect(find.text(_hint), findsNothing);
    final row = tester.widget<QuietListRow>(_row());
    expect(row.titleBadge, isA<QuietBadge>());
    expect(row.chevron, isTrue);
    // 「設定中」は見出しの右 (同じ行)・シェブロンの左。
    final badge = tester.getRect(find.byType(QuietBadge));
    final title = tester.getRect(find.text(_title));
    final chevron = tester.getRect(find.descendant(
      of: _row(),
      matching: find.byWidgetPredicate(
          (w) => w is QuietRowIconMark && w.icon == QuietRowIcon.chevron),
    ));
    expect(badge.left, greaterThan(title.right));
    expect(badge.center.dy, closeTo(title.center.dy, 2));
    expect(badge.right, lessThanOrEqualTo(chevron.left));

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(setup.openCalls, 1);
  });

  testWidgets('前面に戻ったら読み直す (プレビュー画面で設定 → 戻ると「設定中」)', (tester) async {
    final setup = _FakeSetup();
    await _pump(tester, setup);
    expect(find.text(_badge), findsNothing);
    expect(setup.activeCalls, 1);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    setup.active = true; // プレビュー画面で「壁紙を設定」
    await _backgroundAndResume(tester);
    expect(setup.activeCalls, 2);
    expect(find.text(_badge), findsOneWidget);
    expect(find.text(_activeHint), findsOneWidget);

    // 端末の設定でほかの壁紙に変えて戻ると、「設定中」が消える。
    setup.active = false;
    await _backgroundAndResume(tester);
    expect(setup.activeCalls, 3);
    expect(find.text(_badge), findsNothing);
    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('画面を開くたびに読み直す (閉じている間は問い合わせない)', (tester) async {
    final setup = _FakeSetup();
    await _pump(
      tester,
      setup,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const GeneralSettingsPage()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    expect(setup.activeCalls, 0);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(setup.activeCalls, 1);
    expect(find.text(_badge), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    setup.active = true;
    // 閉じている間に前面復帰しても問い合わせない (行が無い)。
    await _backgroundAndResume(tester);
    expect(setup.activeCalls, 1);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(setup.activeCalls, 2);
    expect(find.text(_badge), findsOneWidget);
  });

  testWidgets('読めない (例外) ときは未設定の表示', (tester) async {
    final setup = _FakeSetup(active: true)..throwOnActive = true;
    await _pump(tester, setup);
    expect(tester.takeException(), isNull);
    expect(find.text(_badge), findsNothing);
    expect(find.text(_hint), findsOneWidget);
  });

  testWidgets('ja: 文言と、行を 1 つにまとめた読み上げ (ボタン)', (tester) async {
    final semantics = tester.ensureSemantics();
    final setup = _FakeSetup(active: true);
    await _pump(tester, setup, locale: const Locale('ja'));
    expect(find.text('ライブ壁紙を設定'), findsOneWidget);
    expect(find.text('ロック画面への設定もここから'), findsOneWidget);
    expect(find.text('設定中'), findsOneWidget);

    final node = tester.getSemantics(find.text('ライブ壁紙を設定'));
    expect(node.label, contains('ライブ壁紙を設定'));
    expect(node.label, contains('ロック画面への設定もここから'));
    expect(node.label, contains('設定中'));
    expect(node, isSemantics(isButton: true, hasTapAction: true));

    setup.active = false;
    await _backgroundAndResume(tester);
    expect(find.text('ホーム画面の壁紙に設定します'), findsOneWidget);
    expect(find.text('設定中'), findsNothing);

    setup.opens = false;
    await tester.tap(find.text('ライブ壁紙を設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('端末の壁紙設定から「Mood-Ring Weather」を選んでください'), findsOneWidget);
    semantics.dispose();
  });
}
