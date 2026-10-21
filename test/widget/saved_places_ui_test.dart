// test/widget/saved_places_ui_test.dart
//
// 保存地点 (Plus 多地点) の画面の振る舞い。実通信なし (fixtures で override)。
//   - ホームの地点タブ (切替・「+」の分岐・自動スクロール・タブは無彩色)。
//     保存地点は Plus 限定 (無料 0 件、2026-09-30 ユーザー決裁): 無料の「+」/
//     「+ Add a place …」は見た目そのままで paywall
//   - 取得中 E6a / 取得失敗 E6b (再試行・現在地に戻る)
//   - G4: 保存地点を表示中の現在地行と、現在地の緊急アラートのバナー
//   - 詳細タブの追随 (見出し・現地時刻のラベル)
//   - 地点を追加 (状態 B0〜B4、候補タップで即追加 → タブ選択 + 元に戻す、保存済み、
//     タップ時の上限の再判定、閉じ方 4 種、IME 変換中、Android の戻る 2 回)
//   - 地点管理 A1〜A5 (件数・追加ボタン・Plus 導線。A1 = 無料 0 件は件数を出さず
//     Plus カードだけ、無料で地点が残っていれば 1 件でも A5)
//   - 文字倍率 2.0 で溢れない

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/current_location_cues.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';
import 'package:mood_ring_weather/providers/display_weather_provider.dart';
import 'package:mood_ring_weather/providers/mri_provider.dart';
import 'package:mood_ring_weather/providers/place_search_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/saved_place_weather_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

const _en = Locale('en');

Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  int saved = 0,
  bool plus = false,
  Locale locale = _en,
  WeatherSnapshot Function(DateTime)? current,
  Map<String, PlaceWeatherMode> modes = const {},
  List<Override> extra = const [],
  double textScale = 1.0,
  List<Override>? entitlement,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: const MainShell(),
      ),
    ),
    brightness: Brightness.dark,
    locale: locale,
    overrides: [
      ...await placesBaseOverrides(
        savedCount: saved,
        locale: locale,
        current: current,
        city: locale.languageCode == 'ja' ? '東京' : 'Tokyo',
      ),
      ...entitlement ?? entitlementOverrides(plus: plus),
      ...savedPlaceWeatherOverrides(modes: modes),
      ...extra,
    ],
  ));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MainShell)));
}

PlaceCandidate _kyoto() =>
    fixtureCandidate(kFixturePlaces[1], _en, admin1: 'Kyoto');

PlaceCandidate _naha() =>
    fixtureCandidate(kFixturePlaces[0], _en, admin1: 'Okinawa');

/// ホームの大きな気温 (64px)。レールの小さな気温とは区別する。
Finder _bigTemp(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 64,
    );

Finder _inTabs(Finder finder) =>
    find.descendant(of: find.byType(PlaceTabBar), matching: finder);

Future<void> _openSheet(WidgetTester tester) async {
  // 地点が多いと「+」は右にはみ出すので、タブ列を終端までスクロールしてから押す。
  await tester.drag(find.byType(PlaceTabBar), const Offset(-600, 0));
  await settle(tester);
  await tester.tap(find.byKey(kPlaceTabAddKey));
  await settle(tester);
  expect(find.byType(AddPlaceSheet), findsOneWidget);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(kAddPlaceFieldKey), text);
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('ホームの地点タブ', () {
    testWidgets('Plus・保存 0 件: 「+ Add a place (family, travel)」から追加シートを開く',
        (tester) async {
      await _pumpShell(tester, plus: true);

      expect(_inTabs(find.text('My location')), findsOneWidget);
      expect(
          _inTabs(find.text('+ Add a place (family, travel)')), findsOneWidget);
      expect(_inTabs(find.text('+')), findsNothing);

      await _openSheet(tester);
      expect(find.text('Add a place'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets(
        '無料・保存 0 件: 「+ Add a place (family, travel)」は見た目そのままで paywall '
        '(シートは開かない。保存地点は Plus 限定)', (tester) async {
      final c = await _pumpShell(tester);
      expect(c.read(savedPlaceQuotaProvider).limit, kFreeSavedLocationLimit);

      // 見た目は Plus・0 件と同じ (tertiary の「+ Add a place …」)。
      final label = _inTabs(find.text('+ Add a place (family, travel)'));
      expect(label, findsOneWidget);
      final context = tester.element(label);
      expect(
        tester.widget<Text>(label).style?.color,
        MrwTokens.of(context).actionTertiaryLabel,
      );

      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(c.read(savedPlacesProvider), isEmpty);
    });

    testWidgets('タブのタップで表示を切り替え、見出しは栞 + 地名 + 保存地点タグ', (tester) async {
      final c = await _pumpShell(tester, saved: 5, plus: true);

      expect(find.byIcon(Icons.bookmark_border), findsNothing);
      await tester.tap(_inTabs(find.text('Naha')));
      await settle(tester);

      expect(c.read(selectedPlaceIdProvider), kNahaId);
      expect(find.text('Saved place'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(_bigTemp('34°'), findsOneWidget); // 那覇の気温
      expect(find.byKey(CurrentLocationRow.tapTargetKey), findsOneWidget);

      await tester.tap(_inTabs(find.text('My location')));
      await settle(tester);
      expect(c.read(selectedPlaceIdProvider), isNull);
      expect(find.text('Saved place'), findsNothing);
      expect(_bigTemp('22°'), findsOneWidget);
      expect(find.byKey(CurrentLocationRow.tapTargetKey), findsNothing);
    });

    testWidgets('タブに MRI の数値や帯ドット (状態色) を置かない', (tester) async {
      await _pumpShell(tester, saved: 5, plus: true);
      final texts = tester
          .widgetList<Text>(_inTabs(find.byType(Text)))
          .map((t) => t.data ?? '')
          .where((s) => RegExp(r'\d').hasMatch(s));
      expect(texts, isEmpty);
    });

    testWidgets('選んだタブが見える位置へ自動でスクロールする', (tester) async {
      final c = await _pumpShell(tester, saved: 5, plus: true);
      final scroll = tester.widget<SingleChildScrollView>(
        _inTabs(find.byType(SingleChildScrollView)),
      );
      expect(scroll.controller!.offset, 0);

      c.read(selectedPlaceIdProvider.notifier).select(kReykjavikId);
      await settle(tester);

      expect(scroll.controller!.offset, greaterThan(0));
      final tab = tester.getRect(_inTabs(find.text('Reykjavik')));
      final bar = tester.getRect(find.byType(PlaceTabBar));
      expect(tab.left, greaterThanOrEqualTo(bar.left));
      expect(tab.right, lessThanOrEqualTo(bar.right));
    });

    testWidgets('無料で地点が残っている (1 件。無料 1 件の時期に保存) の「+」も paywall', (tester) async {
      final c = await _pumpShell(tester, saved: 1);
      // 残っている地点は消えず、タブにも出る (grandfathering)。
      expect(_inTabs(find.text('Naha')), findsOneWidget);
      expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(c.read(savedPlacesProvider), hasLength(1));
    });

    testWidgets('Plus で上限 (5 件) の「+」は理由のスナックバー。「Manage」で地点管理へ', (tester) async {
      await _pumpShell(tester, saved: 5, plus: true);
      await tester.drag(find.byType(PlaceTabBar), const Offset(-600, 0));
      await settle(tester);
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);

      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(find.text('5 of 5 places saved.'), findsOneWidget);
      await tester.tap(find.text('Manage'));
      await settle(tester);
      expect(find.byType(LocationsPage), findsOneWidget);
    });
  });

  group('取得中 / 取得失敗', () {
    testWidgets('取得中 (E6a): 数値は「—」、体感は「Feels —」、取得中の文言', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 5,
        plus: true,
        modes: {kSapporoId: PlaceWeatherMode.loading},
      );
      c.read(selectedPlaceIdProvider.notifier).select(kSapporoId);
      await settle(tester);

      expect(find.text('Loading weather for Sapporo…'), findsOneWidget);
      expect(find.text('FEELS —'), findsOneWidget);
      // 見出し・タブ・現在地行は残る。他地点 (現在地) の値で代用しない。
      expect(find.text('Sapporo'), findsWidgets);
      expect(find.byKey(CurrentLocationRow.tapTargetKey), findsOneWidget);
      expect(_bigTemp('22°'), findsNothing);
    });

    testWidgets('取得失敗 (E6b): 文言と「Retry」で取り直す', (tester) async {
      var calls = 0;
      final c = await _pumpShell(
        tester,
        saved: 5,
        plus: true,
        extra: [
          savedPlaceSnapshotProvider.overrideWith((ref, id) async {
            calls++;
            if (calls == 1) throw kPlaceNetworkError;
            return mildSnapshot(kPlacesNow, 64.15, -21.94);
          }),
        ],
      );
      c.read(selectedPlaceIdProvider.notifier).select(kReykjavikId);
      await settle(tester);

      expect(
        find.text(
          'Couldn’t load weather for Reykjavik. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Back to my location'), findsOneWidget);
      expect(_bigTemp('22°'), findsNothing); // 現在地の値で代用しない

      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(calls, 2);
      expect(_bigTemp('21°'), findsOneWidget);
    });

    testWidgets('取得失敗 (E6b): 「Back to my location」で現在地へ', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 5,
        plus: true,
        modes: {kReykjavikId: PlaceWeatherMode.error},
      );
      c.read(selectedPlaceIdProvider.notifier).select(kReykjavikId);
      await settle(tester);

      await tester.tap(find.text('Back to my location'));
      await settle(tester);
      expect(c.read(selectedPlaceIdProvider), isNull);
      expect(_bigTemp('22°'), findsOneWidget);
    });
  });

  group('G4 現在地の手がかり', () {
    testWidgets('保存地点を表示中: リング直下に「My location ● 64 ›」。タップで現在地へ',
        (tester) async {
      final c = await _pumpShell(tester, saved: 1);
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);

      final current = c.read(mriProvider).requireValue.value;
      final row = find.byKey(CurrentLocationRow.tapTargetKey);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('$current')),
        findsOneWidget,
      );
      expect(
          find.byKey(const ValueKey('current-location-dot')), findsOneWidget);

      await tester.tap(row);
      await settle(tester);
      expect(c.read(selectedPlaceIdProvider), isNull);
    });

    testWidgets('現在地が危険: 保存地点を表示中は最上段にバナー。タップで現在地へ', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 1,
        current: dangerousHeatSnapshot,
      );
      // 現在地を表示中はバナーを出さない (画面そのものが現在地)。
      expect(find.byKey(CurrentAlertBanner.bannerKey), findsNothing);

      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);
      final banner = find.byKey(CurrentAlertBanner.bannerKey);
      expect(banner, findsOneWidget);
      expect(find.text('Heat alert at your location (Tokyo)'), findsOneWidget);
      expect(find.text('View ›'), findsOneWidget);
      // 閉じるボタンは無い。
      expect(
        find.descendant(of: banner, matching: find.byIcon(Icons.close)),
        findsNothing,
      );
      // 最上段 (見出しより上)。
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(find.text('Saved place')).dy),
      );

      await tester.tap(banner);
      await settle(tester);
      expect(c.read(selectedPlaceIdProvider), isNull);
    });

    testWidgets('現在地が快適ならバナーは出ない', (tester) async {
      final c = await _pumpShell(tester, saved: 1);
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);
      expect(find.byKey(CurrentAlertBanner.bannerKey), findsNothing);
    });

    testWidgets('保存地点を表示しても現在地の MRI (壁紙・通知の経路) は現在地のまま', (tester) async {
      final c = await _pumpShell(tester, saved: 1);
      final before = c.read(mriProvider).requireValue.value;
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);
      expect(c.read(displayMriProvider).requireValue.value, isNot(before));
      expect(c.read(mriProvider).requireValue.value, before);
    });
  });

  group('詳細タブ', () {
    testWidgets('ホームの選択に追随し、見出しに地名と保存地点タグを出す', (tester) async {
      final c = await _pumpShell(tester, saved: 1);
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
      await settle(tester);

      final detail = find.byType(DetailPage);
      expect(
        find.descendant(of: detail, matching: find.text('Naha')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('Saved place')),
        findsOneWidget,
      );
      // 気温タイルは「34°」(天気レールにも「34°」が出るため、タイルの値の
      // 大きさ 18 で特定する)。
      expect(
        find.descendant(
          of: detail,
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data == '34°' && w.style?.fontSize == 18,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('保存地点の時刻ラベルは現地時刻 (端末 +1 時間の地点)', (tester) async {
      final shifted = kPlacesOffsetSeconds + 3600;
      final c = await _pumpShell(
        tester,
        saved: 1,
        extra: [
          savedPlaceHourlyProvider.overrideWith(
            (ref, id) async => hourlyAround(
              (at) => nahaSnapshot(at).copyWith(utcOffsetSeconds: shifted),
            ),
          ),
        ],
      );
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
      await settle(tester);

      final detail = find.byType(DetailPage);
      // 端末では 12 PM だが、現地では 1 PM (intl は時刻と PM の間に U+202F を使う)。
      Finder hour(String label) => find.descendant(
            of: detail,
            matching: find.byWidgetPredicate(
              (w) => w is Text && w.data?.replaceAll('\u202f', ' ') == label,
            ),
          );
      expect(hour('1 PM'), findsOneWidget);
      expect(hour('12 PM'), findsNothing);
    });
  });

  group('地点を追加 (ボトムシート)', () {
    List<Override> search(Map<String, Object> results, [List<String>? calls]) =>
        [placeSearchOverride(results, calls: calls)];

    testWidgets('B0: フィールドに自動でフォーカス。案内と出典を出す', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true);
      await _openSheet(tester);

      final field = tester.widget<TextField>(find.byKey(kAddPlaceFieldKey));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        find.text(
            'Type a city or town.\nResults show places, not weather yet.'),
        findsOneWidget,
      );
      expect(
          find.text('Search: Open-Meteo · Places: GeoNames'), findsOneWidget);
    });

    testWidgets('候補のタップで即追加 → シートを閉じ、そのタブを選び、元に戻せる', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({
          'Kyoto': [_kyoto()],
        }),
      );
      await _openSheet(tester);
      await _type(tester, 'Kyoto');
      expect(find.text('Kyoto, Japan'), findsOneWidget);

      await tester.tap(find.text('Kyoto, Japan'));
      await settle(tester);

      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(c.read(selectedPlaceIdProvider), kKyotoId);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId, kKyotoId]);
      expect(find.text('Added Kyoto.'), findsOneWidget);
      expect(_inTabs(find.text('Kyoto')), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId]);
      expect(c.read(selectedPlaceIdProvider), isNull);
    });

    // Flutter 3.44 の SnackBar は action があると既定で閉じない。操作付きでも
    // 時間で閉じること (追加はそのまま残る)。
    testWidgets('「元に戻す」付きのスナックバーは 4 秒で閉じ、追加は残る', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({
          'Kyoto': [_kyoto()],
        }),
      );
      await _openSheet(tester);
      await _type(tester, 'Kyoto');
      await tester.tap(find.text('Kyoto, Japan'));
      await settle(tester);
      expect(find.text('Added Kyoto.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      expect(find.text('Added Kyoto.'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId, kKyotoId]);
    });

    testWidgets('スクリーンリーダー使用中は「元に戻す」を押せるまで残す', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({
          'Kyoto': [_kyoto()],
        }),
      );
      await _openSheet(tester);
      await _type(tester, 'Kyoto');
      await tester.tap(find.text('Kyoto, Japan'));
      await settle(tester);

      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.text('Added Kyoto.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('Added Kyoto.'), findsNothing);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId]);
    });

    testWidgets('保存済みの候補は「Saved」。タップでその地点のタブへ (重複追加しない)', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({
          'Naha': [_naha()],
        }),
      );
      await _openSheet(tester);
      await _type(tester, 'Naha');
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.text('Saved'));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(c.read(selectedPlaceIdProvider), kNahaId);
      expect(c.read(savedPlacesProvider), hasLength(1));
    });

    testWidgets('B3: 0 件は「No places found.」(通信エラーとは別)', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true, extra: search({}));
      await _openSheet(tester);
      await _type(tester, 'kyouto');
      expect(
        find.text('No places found.\nTry another spelling, e.g. Kyoto.'),
        findsOneWidget,
      );
      expect(find.byKey(kAddPlaceRetryKey), findsNothing);
    });

    testWidgets('B4: 通信エラーは再試行で検索し直す', (tester) async {
      final calls = <String>[];
      await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({'Kyoto': kPlaceNetworkError}, calls),
      );
      await _openSheet(tester);
      await _type(tester, 'Kyoto');
      expect(
        find.text('Couldn’t search right now.\nCheck your connection.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(kAddPlaceRetryKey));
      await settle(tester);
      expect(calls, ['Kyoto', 'Kyoto']);
    });

    testWidgets('IME の変換中は検索しない。確定したら検索する', (tester) async {
      final calls = <String>[];
      await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: search({}, calls),
      );
      await _openSheet(tester);
      await tester.showKeyboard(find.byKey(kAddPlaceFieldKey));

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'きょうと',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ));
      await settle(tester);
      expect(calls, isEmpty);

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '京都',
        selection: TextSelection.collapsed(offset: 2),
      ));
      await settle(tester);
      expect(calls, ['京都']);
    });

    testWidgets('入力の間引き 300ms (最後の入力から待ってから検索)', (tester) async {
      final calls = <String>[];
      await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        extra: [
          placeSearchControllerProvider.overrideWith(
            (ref) => PlaceSearchController(
              search: (q, {abortTrigger}) async {
                calls.add(q);
                return const [];
              },
            ),
          ),
        ],
      );
      await _openSheet(tester);
      await tester.enterText(find.byKey(kAddPlaceFieldKey), 'Kyo');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(kAddPlaceFieldKey), 'Kyoto');
      await tester.pump(const Duration(milliseconds: 299));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, ['Kyoto']);
    });

    testWidgets('上限は候補タップ時に再判定: シートを開いている間に解約して無料なら paywall (追加しない)',
        (tester) async {
      final plus = StateProvider<bool>((ref) => true);
      final c = await _pumpShell(
        tester,
        entitlement: switchableEntitlementOverrides(plus),
        extra: search({
          'Kyoto': [_kyoto()],
        }),
      );
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsOneWidget);
      await _type(tester, 'Kyoto');
      // シートを開いている間に Plus が切れた (無料 = 保存地点は Plus 限定)。
      c.read(plus.notifier).state = false;
      await settle(tester);

      await tester.tap(find.text('Kyoto, Japan'));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(c.read(savedPlacesProvider), isEmpty);
    });

    testWidgets('上限は候補タップ時に再判定: Plus で上限に達していたら理由のスナックバー', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 4,
        plus: true,
        extra: search({
          'Kyoto': [
            fixtureCandidate(
              const FixturePlace('place-geo-1', 'X', 'Testville', 1, 1),
              _en,
            ),
          ],
        }),
      );
      await _openSheet(tester);
      await _type(tester, 'Kyoto');
      await c.read(savedPlacesControllerProvider).add(
            fixtureCandidate(kFixturePlaces[4], _en),
          );
      await settle(tester);

      await tester.tap(find.text('Testville'));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(find.text('5 of 5 places saved.'), findsOneWidget);
      expect(c.read(savedPlacesProvider), hasLength(5));
    });

    testWidgets('閉じる: 「Cancel」', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true);
      await _openSheet(tester);
      await tester.tap(find.byKey(kAddPlaceCloseKey));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
    });

    testWidgets('閉じる: 背後 (暗くしたホーム) のタップ', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true);
      await _openSheet(tester);
      await tester.tap(find.byKey(kAddPlaceScrimKey));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
    });

    testWidgets('閉じる: 題のあたりを下へスワイプ', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true);
      await _openSheet(tester);
      await tester.drag(find.text('Add a place'), const Offset(0, 600));
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
    });

    testWidgets('Android の戻る: 1 回目はキーボードだけ閉じ、2 回目でシートを閉じる', (tester) async {
      await _pumpShell(tester, saved: 1, plus: true);
      await _openSheet(tester);
      // キーボードが出ている状態 (viewInsets) を再現する。
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final field = tester.widget<TextField>(find.byKey(kAddPlaceFieldKey));
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsOneWidget);
      expect(field.focusNode!.hasFocus, isFalse);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsNothing);
    });
  });

  group('地点管理 A1〜A5', () {
    Future<ProviderContainer> pumpLocations(
      WidgetTester tester, {
      required int saved,
      required bool plus,
      List<Override> extra = const [],
      double textScale = 1.0,
    }) async {
      useGoldenViewport(tester);
      await tester.pumpWidget(goldenApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const LocationsPage(),
          ),
        ),
        brightness: Brightness.dark,
        locale: _en,
        overrides: [
          ...await placesBaseOverrides(
            savedCount: saved,
            locale: _en,
            city: 'Tokyo',
          ),
          ...entitlementOverrides(plus: plus),
          currentLocationProvider
              .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
          savedPlaceMriOverride(),
          ...extra,
        ],
      ));
      await settle(tester);
      return ProviderScope.containerOf(
          tester.element(find.byType(LocationsPage)));
    }

    Finder addButton() => find.byKey(kLocationsAddKey);

    /// 見出しの右の件数 (「n / m」「n saved」)。
    Finder countLabel() => find.byWidgetPredicate(
          (w) =>
              w is Text &&
              RegExp(r'^\d+ (/ \d+|saved)$').hasMatch(w.data ?? ''),
        );

    const a1Body = 'Free includes your current location only. '
        'Add up to 5 places with Plus. Emergency alerts stay free.';

    testWidgets(
        'A1 無料 0 件: 件数・空状態・追加ボタンを出さず、Plus カード '
        '(保存地点は Plus の機能) から paywall', (tester) async {
      await pumpLocations(tester, saved: 0, plus: false);
      expect(countLabel(), findsNothing); // 「0 / 0」「0 / 1」を出さない
      expect(find.textContaining('No saved places yet'), findsNothing);
      expect(addButton(), findsNothing);
      expect(find.text('Multi-location'), findsOneWidget);
      expect(find.text(a1Body), findsOneWidget);
      // Plus カードは見出しの直下 (空状態のカードの位置)。
      final title = tester.getRect(find.text('Saved places'));
      final card = tester.getRect(find.byType(QuietPlusCard));
      expect(card.top - title.bottom, inInclusiveRange(8, 14));

      await tester.tap(find.text('See Plus'));
      await settle(tester);
      expect(find.byType(PaywallPage), findsOneWidget);
    });

    testWidgets(
        'A5 (1 件) 無料で 1 件残っている: 「1 saved」、地点は表示され、追加ボタンなし、'
        'Plus カードから paywall', (tester) async {
      await pumpLocations(tester, saved: 1, plus: false);
      expect(find.text('1 saved'), findsOneWidget);
      expect(find.text('1 / 0'), findsNothing);
      expect(find.text('Naha'), findsOneWidget);
      expect(find.text('MRI 65'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(addButton(), findsNothing);
      expect(
        find.text('Your saved place stays. Adding new ones needs Plus.'),
        findsOneWidget,
      );
      await tester.tap(find.text('See Plus'));
      await settle(tester);
      expect(find.byType(PaywallPage), findsOneWidget);
    });

    testWidgets('無料で 1 件残っている → 削除すると A1 (件数なし・Plus カード)、元に戻すと 1 件',
        (tester) async {
      final c = await pumpLocations(tester, saved: 1, plus: false);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await settle(tester);
      expect(find.text('Removed Naha.'), findsOneWidget);
      expect(c.read(savedPlacesProvider), isEmpty);
      expect(countLabel(), findsNothing);
      expect(find.text(a1Body), findsOneWidget);
      expect(addButton(), findsNothing);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId]);
      expect(find.text('1 saved'), findsOneWidget);
    });

    testWidgets('Plus 0 件: 0 / 5、空状態と追加ボタン。Plus カードは出さない', (tester) async {
      await pumpLocations(tester, saved: 0, plus: true);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.textContaining('No saved places yet'), findsOneWidget);
      expect(addButton(), findsOneWidget);
      expect(find.byType(QuietPlusCard), findsNothing);
    });

    testWidgets('A3 Plus 4 / 5: 追加ボタンからシートを開き、追加後はスナックバー', (tester) async {
      final c = await pumpLocations(
        tester,
        saved: 4,
        plus: true,
        extra: [
          placeSearchOverride({
            'Reykjavik': [fixtureCandidate(kFixturePlaces[4], _en)],
          }),
        ],
      );
      expect(find.text('4 / 5'), findsOneWidget);
      expect(find.text('MRI 65'), findsOneWidget);
      await tester.tap(addButton());
      await settle(tester);
      expect(find.byType(AddPlaceSheet), findsOneWidget);
      await _type(tester, 'Reykjavik');
      await tester.tap(find.text('Reykjavik').last);
      await settle(tester);

      expect(find.byType(AddPlaceSheet), findsNothing);
      expect(find.text('Added Reykjavik.'), findsOneWidget);
      expect(find.text('5 / 5'), findsOneWidget);
      // 地点管理から追加しても表示中の地点は変えない。
      expect(c.read(selectedPlaceIdProvider), isNull);
    });

    testWidgets('A4 Plus 5 / 5: 追加ボタンは無効 + 理由', (tester) async {
      await pumpLocations(tester, saved: 5, plus: true);
      expect(find.text('5 / 5'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.descendant(of: addButton(), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('5 of 5 places saved. Remove one to add another.'),
        findsOneWidget,
      );
    });

    testWidgets('A5 無料で 5 件残存: 「5 saved」、消さない、Plus カード', (tester) async {
      await pumpLocations(tester, saved: 5, plus: false);
      expect(find.text('5 saved'), findsOneWidget);
      for (final p in kFixturePlaces) {
        expect(find.text(p.en), findsOneWidget);
      }
      expect(addButton(), findsNothing);
      expect(
        find.text('Your 5 saved places stay. Adding new ones needs Plus.'),
        findsOneWidget,
      );
    });

    testWidgets('行の MRI は現在値。取得中は無彩色の「MRI —」', (tester) async {
      await pumpLocations(
        tester,
        saved: 2,
        plus: true,
        extra: [
          savedPlaceMriOverride(values: const {kNahaId: 38}),
        ],
      );
      expect(find.text('MRI 38'), findsOneWidget);
      expect(find.text('MRI —'), findsOneWidget);
    });

    testWidgets('文字倍率 2.0 でも溢れない (A4)', (tester) async {
      await pumpLocations(tester, saved: 5, plus: true, textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    for (final saved in const [0, 1]) {
      testWidgets('文字倍率 2.0 でも溢れない (無料 $saved 件)', (tester) async {
        await pumpLocations(tester, saved: saved, plus: false, textScale: 2.0);
        expect(tester.takeException(), isNull);
        expect(find.byType(QuietPlusCard), findsOneWidget);
      });
    }
  });

  group('文字倍率 2.0', () {
    testWidgets('ホーム: 保存地点を表示中 + 現在地のバナーでも溢れない', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 5,
        plus: true,
        current: dangerousHeatSnapshot,
        textScale: 2.0,
      );
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(CurrentAlertBanner.bannerKey), findsOneWidget);
    });

    testWidgets('ホーム: 取得失敗 (E6b) でも溢れない', (tester) async {
      final c = await _pumpShell(
        tester,
        saved: 5,
        plus: true,
        modes: {kReykjavikId: PlaceWeatherMode.error},
        textScale: 2.0,
      );
      c.read(selectedPlaceIdProvider.notifier).select(kReykjavikId);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('地点を追加: 候補の表示でも溢れない', (tester) async {
      await _pumpShell(
        tester,
        saved: 1,
        plus: true,
        textScale: 2.0,
        extra: [
          placeSearchOverride({
            'Kyoto': [_kyoto(), _naha()],
          }),
        ],
      );
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      await _type(tester, 'Kyoto');
      expect(tester.takeException(), isNull);
      expect(find.text('Kyoto, Japan'), findsOneWidget);
    });
  });

  test('シートの scrim は onyx-900 α.60', () {
    expect(kAddPlaceScrim, const Color(0x990D0E11));
    expect(kAddPlaceScrim.a, closeTo(0.6, 0.002));
  });
}
