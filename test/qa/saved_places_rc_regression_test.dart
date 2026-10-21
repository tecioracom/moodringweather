// test/qa/saved_places_rc_regression_test.dart
//
// 保存地点リリース候補 (2026-09-29) の QA で追加した回帰テスト。既存テストが
// provider 単体で確かめている条件を、実際のアプリの組み立て (main.dart の
// MoodRingApp) と画面の操作で確かめる。実通信なし。
//
//   G3  main.dart のライフサイクル監視 → バックグラウンド 30 分以上で現在地
//   G1  main.dart の壁紙の配線: 保存地点を表示しても壁紙は現在地の MRI のまま
//   G1  キャリブレーションの記録は保存地点の表示中でも現在地の天気で学習する
//   #6  データ削除で保存地点・表示中の地点・地点ごとの天気キャッシュが消える
//   上限 Plus → 無料 (解約) で 5 件は消えず、新規追加は paywall (grandfathering)。
//        保存地点は Plus 限定 (無料 0 件、2026-09-30 ユーザー決裁)
//   元に戻す 削除 → 元に戻す (連打しても 1 回) で並び順も元どおり
//   連打 候補の同時タップで 2 件追加されない
//   時差 海外の保存地点 (UTC−10 / UTC+0) の時刻ラベル・「今」・天気レール
//
// 不具合の再現テスト (2026-09-29 に修正済み。skip を外して回帰テストとして常時実行。
// 詳細は docs/qa-report-saved-places-2026-09-29.md の不具合一覧):
//   QA-02 (Sev2) 削除アイコンの連打で次の行の地点まで消え、先の 1 件は戻せない
//   QA-03 (Sev2) 文字倍率 2.0 の JA / ZH で G4 バナーのアラート種別が省略で消える
//   QA-07 (Sev3) 削除の「元に戻す」が上限を再判定せず、上限を超えて保存できる
//   QA-08 (Sev3) 名前も地域行も同じ候補が 2 行並ぶ (横浜 / 天草市・熊本県・日本)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/datasources/weather_api_client.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/personal_profile.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/privacy/data_deletion.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/domain/calibration/calibration_engine.dart';
import 'package:mood_ring_weather/domain/calibration/calibration_feedback.dart';
import 'package:mood_ring_weather/domain/places/place_search_rules.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/main.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_feedback_page.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/current_location_cues.dart';
import 'package:mood_ring_weather/presentation/places/place_header.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/weather_rail.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/display_weather_provider.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/mri_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/privacy_provider.dart';
import 'package:mood_ring_weather/providers/saved_place_weather_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../fixtures/wallpaper_overlay_fixtures.dart';
import '../golden/golden_harness.dart';

const Locale _en = Locale('en');

// ─── フェイク ───────────────────────────────────────────────────────

class _FakeGateway implements NotificationGateway {
  final shown = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    shown.add(id);
  }
}

class _FakeWallpaper implements WallpaperBridge {
  final sent = <int>[];

  @override
  Future<bool> setMriState(WallpaperState state) async {
    sent.add(state.mri);
    return true;
  }

  @override
  Future<bool> clearMriState() async => true;
}

/// 進められる時計 (clockProvider に渡す)。
class _Clock {
  DateTime now = kPlacesNow;
  DateTime call() => now;
}

// ─── アプリ全体 (main.dart の MoodRingApp) ─────────────────────────

class _App {
  _App(this.container, this.clock, this.wallpaper, this.gateway, this.overlay);

  final ProviderContainer container;
  final _Clock clock;
  final _FakeWallpaper wallpaper;
  final _FakeGateway gateway;
  final RecordingWallpaperOverlay overlay;

  String? get selected => container.read(selectedPlaceIdProvider);

  void select(String id) =>
      container.read(selectedPlaceIdProvider.notifier).select(id);
}

/// 本番と同じ MoodRingApp を、固定の天気・保存地点で組み立てる。
Future<_App> _pumpMoodRingApp(WidgetTester tester, {int saved = 2}) async {
  useGoldenViewport(tester);
  SharedPreferences.setMockInitialValues({
    kPrefKeyComfortRecords: savedPlacesJson(count: saved, locale: _en),
  });
  final prefs = await SharedPreferences.getInstance();
  final clock = _Clock();
  final wallpaper = _FakeWallpaper();
  final gateway = _FakeGateway();
  final overlay = RecordingWallpaperOverlay();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(clock.call),
      cityCatalogProvider.overrideWith((ref) async => const <City>[]),
      // main.dart は起動時に現在地の取得を待ってから通知を初期化する。本物の
      // Geolocator を呼ばないよう差し替える (QA-19)。
      currentLocationProvider
          .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
      weatherSnapshotProvider
          .overrideWith((ref) async => comfortableSnapshot(kPlacesNow)),
      hourlyWeatherProvider
          .overrideWith((ref) async => hourlyAround(comfortableSnapshot)),
      cityNameProvider.overrideWith((ref) async => 'Tokyo'),
      ...entitlementOverrides(plus: true),
      ...savedPlaceWeatherOverrides(),
      notificationGatewayProvider.overrideWithValue(gateway),
      wallpaperBridgeProvider.overrideWithValue(wallpaper),
      overlay.providerOverride,
    ],
    child: const MoodRingApp(),
  ));
  await settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MainShell)));
  return _App(container, clock, wallpaper, gateway, overlay);
}

/// ホーム (MainShell) を固定データで組み立てる。
Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  int saved = 1,
  bool plus = true,
  List<Override> extra = const [],
  List<Override>? entitlement,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: const MainShell(),
    brightness: Brightness.dark,
    locale: _en,
    overrides: [
      ...await placesBaseOverrides(
        savedCount: saved,
        locale: _en,
        city: 'Tokyo',
      ),
      ...entitlement ?? entitlementOverrides(plus: plus),
      ...savedPlaceWeatherOverrides(),
      ...extra,
    ],
  ));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MainShell)));
}

Future<ProviderContainer> _pumpLocations(
  WidgetTester tester, {
  required int saved,
  bool plus = true,
  List<Override>? entitlement,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: const LocationsPage(),
    brightness: Brightness.dark,
    locale: _en,
    overrides: [
      ...await placesBaseOverrides(savedCount: saved, locale: _en),
      ...entitlement ?? entitlementOverrides(plus: plus),
      currentLocationProvider
          .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
      savedPlaceMriOverride(),
    ],
  ));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(LocationsPage)));
}

Finder _inTabs(Finder finder) =>
    find.descendant(of: find.byType(PlaceTabBar), matching: finder);

/// 地点管理の行の地名 (画面の上から順)。
List<String> _rowOrder(WidgetTester tester) {
  final names = [for (final p in kFixturePlaces) p.en];
  final shown = [
    for (final name in names)
      if (find.text(name).evaluate().isNotEmpty)
        (name, tester.getTopLeft(find.text(name)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final s in shown) s.$1];
}

void main() {
  setUpAll(loadAppFonts);

  group('G3 / G1: main.dart の配線 (MoodRingApp)', () {
    testWidgets('バックグラウンド 30 分以上で戻ると現在地、30 分未満は保存地点のまま', (tester) async {
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final app = await _pumpMoodRingApp(tester);
      app.select(kNahaId);
      await settle(tester);
      expect(app.selected, kNahaId);
      expect(find.byType(SavedPlaceTag), findsOneWidget);

      // 29 分 59 秒: 保存地点のまま
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      app.clock.now =
          app.clock.now.add(const Duration(minutes: 29, seconds: 59));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(app.selected, kNahaId);

      // 30 分: 現在地へ (見出しも現在地に戻り、「保存地点」タグが消える)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      app.clock.now = app.clock.now.add(const Duration(minutes: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(app.selected, isNull);
      expect(find.byType(SavedPlaceTag), findsNothing);
      expect(
        find.descendant(
            of: find.byType(PlaceHeaderRow), matching: find.text('Tokyo')),
        findsOneWidget,
      );
    });

    testWidgets('通知センターを開いた程度 (inactive) では時間を数えない', (tester) async {
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final app = await _pumpMoodRingApp(tester);
      app.select(kNahaId);
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      app.clock.now = app.clock.now.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(app.selected, kNahaId);
    });

    testWidgets('壁紙は起動時に現在地の MRI を受け、保存地点を表示しても変わらない', (tester) async {
      final app = await _pumpMoodRingApp(tester);
      final current = app.container.read(mriProvider).requireValue.value;
      expect(app.wallpaper.sent, [current]);

      app.select(kNahaId); // 那覇 = 暑い (現在地と MRI が違う)
      await settle(tester);
      final naha = app.container.read(displayMriProvider).requireValue.value;
      expect(naha, isNot(current));
      expect(app.wallpaper.sent, [current]);
      // 重ね描き (天気・気温・区分名 · 時刻) も現在地のまま (1.3.0 (13))
      final snapshot = app.container.read(weatherSnapshotProvider).requireValue;
      expect(app.overlay.calls, ['set']);
      expect(app.overlay.contents.single.asOf, snapshot.timestamp);
      expect(
        app.overlay.contents.single.temperature,
        app.container
            .read(temperatureUnitProvider)
            .formatDegrees(snapshot.temperature),
      );
      // 保存地点の天気では緊急通知を出さない
      expect(app.gateway.shown, isEmpty);
    });
  });

  group('G1: 保存地点の表示中もキャリブレーションは現在地で学習する', () {
    testWidgets('記録画面は現在地の MRI を出し、学習は現在地の天気で行う', (tester) async {
      final c = await _pumpShell(tester);
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      await settle(tester);
      final current = c.read(mriProvider).requireValue.value;
      final naha = c.read(displayMriProvider).requireValue.value;
      expect(naha, isNot(current));

      unawaited(Navigator.of(tester.element(find.byType(MainShell))).push(
        MaterialPageRoute<void>(
            builder: (_) => const CalibrationFeedbackPage()),
      ));
      await settle(tester);
      final t = AppLocalizations.of(
          tester.element(find.byType(CalibrationFeedbackPage)));
      expect(find.text(t.calibrationCurrentMri(current)), findsOneWidget);
      expect(find.text(t.calibrationCurrentMri(naha)), findsNothing);

      await tester.ensureVisible(find.text(t.feedbackTooHot));
      await settle(tester);
      await tester.tap(find.text(t.feedbackTooHot));
      await settle(tester);

      Map<String, dynamic> learned(WeatherSnapshot snapshot, int mri) {
        final json = CalibrationEngine.applyFeedback(
          profile: PersonalProfile.initial(),
          feedback: CalibrationFeedback.tooHot,
          snapshot: snapshot,
          currentMri: mri,
          now: kPlacesNow,
        ).profile.toJson()
          ..remove('lastFeedbackDayByDirection');
        return json;
      }

      final actual = c.read(personalProfileProvider).toJson()
        ..remove('lastFeedbackDayByDirection');
      expect(actual['feedbackCount'], 1);
      expect(actual, learned(comfortableSnapshot(kPlacesNow), current));
      expect(actual, isNot(learned(nahaSnapshot(kPlacesNow), naha)));
    });
  });

  group('#6 データ削除', () {
    testWidgets('保存地点・表示中の地点・地点ごとの天気キャッシュが消える', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        kPrefKeyComfortRecords: savedPlacesJson(count: 3, locale: _en),
      });
      final prefs = await SharedPreferences.getInstance();
      final api = MockClient((request) async {
        if (request.url.host.startsWith('air-quality')) {
          return http.Response(
              jsonEncode({
                'current': {'us_aqi': 30},
              }),
              200);
        }
        return http.Response(
          jsonEncode({
            'utc_offset_seconds': 32400,
            'current': {
              'time': '2026-07-15T12:00',
              'temperature_2m': 30.0,
              'relative_humidity_2m': 70,
            },
          }),
          200,
        );
      });
      await tester.pumpWidget(goldenApp(
        home: const PrivacyPage(),
        brightness: Brightness.dark,
        locale: _en,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => kPlacesNow),
          cityCatalogProvider.overrideWith((ref) async => const <City>[]),
          weatherApiClientProvider
              .overrideWithValue(WeatherApiClient(httpClient: api)),
          dataDeletionServiceProvider
              .overrideWithValue(DataDeletionService(prefs: prefs)),
          ...entitlementOverrides(plus: true),
        ],
      ));
      await settle(tester);
      final c =
          ProviderScope.containerOf(tester.element(find.byType(PrivacyPage)));

      // 那覇を表示し、那覇の天気を取得してキャッシュに載せる。
      c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
      final sub = c.listen(savedPlaceSnapshotProvider(kNahaId), (_, __) {});
      await settle(tester);
      expect(
          c.read(savedPlaceSnapshotProvider(kNahaId)).requireValue.temperature,
          30);
      final before = c.read(savedPlaceWeatherRepositoryProvider);
      expect(before.cachedPlaceIds, contains(kNahaId));
      expect(c.read(selectedPlaceIdProvider), kNahaId);
      expect(c.read(savedPlacesProvider), hasLength(3));

      await tester.tap(find.widgetWithText(TextButton, 'Delete my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(prefs.getString(kPrefKeyComfortRecords), isNull);
      expect(c.read(savedPlacesProvider), isEmpty);
      expect(c.read(selectedPlaceIdProvider), isNull);
      expect(c.read(displayedPlaceIdProvider), isNull);
      final after = c.read(savedPlaceWeatherRepositoryProvider);
      expect(identical(after, before), isFalse);
      expect(after.cachedPlaceIds, isEmpty);
      // 消した地点の天気は取り直せない (現在地で代用もしない)
      expect(c.read(savedPlaceSnapshotProvider(kNahaId)).hasError, isTrue);
      sub.close();
    });
  });

  group('上限: 解約後の grandfathering', () {
    testWidgets('Plus → 無料で 5 件は消えず、「+」は paywall、新規の保存は Plus 導線',
        (tester) async {
      final plus = StateProvider<bool>((ref) => true);
      final c = await _pumpShell(
        tester,
        saved: 5,
        entitlement: switchableEntitlementOverrides(plus),
      );
      expect(c.read(savedPlaceQuotaProvider).canAddNew, isFalse);

      // 解約 (Plus → 無料)
      c.read(plus.notifier).state = false;
      await settle(tester);
      final quota = c.read(savedPlaceQuotaProvider);
      expect(quota.isOverLimit, isTrue);
      expect(c.read(savedPlacesProvider), hasLength(5));
      final prefs = c.read(sharedPreferencesProvider);
      expect(
        (jsonDecode(prefs.getString(kPrefKeyComfortRecords)!) as List).length,
        5,
      );
      for (final p in kFixturePlaces) {
        expect(_inTabs(find.text(p.en)), findsOneWidget);
      }

      // 新規追加は paywall (シートは開かない)
      await tester.drag(find.byType(PlaceTabBar), const Offset(-900, 0));
      await settle(tester);
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.byType(AddPlaceSheet), findsNothing);

      // Comfort-Twin の「この場所を保存」も新規は Plus 導線、何も書かない
      final check = await c.read(savedPlacesControllerProvider).saveCatalogCity(
            const City(
              id: 'vancouver',
              name: 'Vancouver',
              country: 'Canada',
              latitude: 49.28,
              longitude: -123.12,
              emoji: 'CA',
            ),
            65,
          );
      expect(check.name, 'needsPlus');
      expect(c.read(savedPlacesProvider), hasLength(5));
    });
  });

  group('元に戻す・連打', () {
    testWidgets('削除 → 「Undo」を連打しても 1 回だけ戻り、並び順も元どおり', (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      expect(_rowOrder(tester), ['Naha', 'Kyoto', 'Sapporo']);

      // 真ん中 (Kyoto) を削除
      final deletes = find.byIcon(Icons.delete_outline);
      await tester.tap(deletes.at(1));
      await settle(tester);
      expect(find.text('Removed Kyoto.'), findsOneWidget);
      expect(_rowOrder(tester), ['Naha', 'Sapporo']);

      // Undo を連打
      final undo = tester.getCenter(find.text('Undo'));
      await tester.tapAt(undo);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(undo);
      await settle(tester);

      expect(c.read(savedPlacesProvider).map((p) => p.id),
          [kNahaId, kKyotoId, kSapporoId]);
      expect(_rowOrder(tester), ['Naha', 'Kyoto', 'Sapporo']);
      expect(find.text('3 / 5'), findsOneWidget);
    });

    testWidgets('候補の同時タップで 2 件追加されない (スナックバーも 1 つ)', (tester) async {
      final kyoto = fixtureCandidate(kFixturePlaces[1], _en, admin1: 'Kyoto');
      final c = await _pumpShell(
        tester,
        extra: [
          placeSearchOverride({
            'Kyoto': [kyoto],
          }),
        ],
      );
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      await tester.enterText(find.byKey(kAddPlaceFieldKey), 'Kyoto');
      await settle(tester);

      final row = tester.getCenter(find.text('Kyoto, Japan'));
      await tester.tapAt(row);
      await tester.tapAt(row);
      await settle(tester);

      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId, kKyotoId]);
      expect(find.text('Added Kyoto.'), findsOneWidget);
      expect(find.byType(AddPlaceSheet), findsNothing);
    });
  });

  group('時差: 海外の保存地点の時刻ラベルと「今」', () {
    // (名前, UTC オフセット秒)。夏時間の無い地点。
    const places = [('Honolulu', -36000), ('Reykjavik', 0)];

    /// 地点の天気 (毎時で気温を変え、レールの対応を確かめられるようにする)。
    WeatherSnapshot at(DateTime t, int offset) => nahaSnapshot(t).copyWith(
          temperature: 20 + t.difference(kPlacesNow).inHours.toDouble(),
          utcOffsetSeconds: offset,
        );

    List<Override> weather(int offset) => [
          savedPlaceSnapshotProvider
              .overrideWith((ref, id) async => at(kPlacesNow, offset)),
          savedPlaceHourlyProvider.overrideWith(
            (ref, id) async => hourlyAround((t) => at(t, offset)),
          ),
        ];

    /// 現地の壁時計 (端末のタイムゾーンに依らない期待値)。
    String localLabel(DateTime instant, int offset) => DateFormat.j('en')
        .format(instant.toUtc().add(Duration(seconds: offset)))
        .replaceAll(' ', ' ');

    /// [scope] の時刻軸で「今」のラベル (太字) と、その真下の天気レール。
    (String, WeatherRailItem) nowLabelAndRail(
        WidgetTester tester, Finder scope) {
      final axis =
          find.descendant(of: scope, matching: find.byType(TimeAxisLabels));
      final bold = find
          .descendant(of: axis, matching: find.byType(Text))
          .evaluate()
          .where((e) => (e.widget as Text).style?.fontWeight == FontWeight.w600)
          .single;
      final label = (bold.widget as Text).data!.replaceAll(' ', ' ');
      final x = tester.getCenter(find.byWidget(bold.widget)).dx;
      final rails = find
          .descendant(of: scope, matching: find.byType(WeatherRailItem))
          .evaluate()
          .toList()
        ..sort((a, b) => (tester.getCenter(find.byWidget(a.widget)).dx - x)
            .abs()
            .compareTo(
                (tester.getCenter(find.byWidget(b.widget)).dx - x).abs()));
      return (label, rails.first.widget as WeatherRailItem);
    }

    for (final (name, offset) in places) {
      testWidgets('$name (UTC${offset ~/ 3600}): ホームと詳細の「今」は現地時刻、レールも同じ時刻',
          (tester) async {
        final c = await _pumpShell(tester, extra: weather(offset));
        c.read(selectedPlaceIdProvider.notifier).select(kNahaId);
        await settle(tester);

        final expected = localLabel(kPlacesNow, offset);
        final (home, homeRail) = nowLabelAndRail(tester, find.byType(HomePage));
        expect(home, expected);
        expect(homeRail.point.timestamp, kPlacesNow); // 絶対時刻の「今」
        expect(homeRail.point.snapshot.temperature, 20);

        await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
        await settle(tester);
        final (detail, detailRail) =
            nowLabelAndRail(tester, find.byType(DetailPage));
        expect(detail, expected);
        expect(detailRail.point.timestamp, kPlacesNow);

        // 現在地に戻すと端末の時刻 (現在地の時刻ラベルは変換しない)
        c.read(selectedPlaceIdProvider.notifier).showCurrentLocation();
        await settle(tester);
        final (current, _) = nowLabelAndRail(tester, find.byType(DetailPage));
        expect(current,
            DateFormat.j('en').format(kPlacesNow).replaceAll(' ', ' '));
      });
    }
  });

  // ── 不具合の再現テスト (修正済み。回帰テストとして常時実行) ──────────

  group('再現: QA-02 (Sev2) 削除アイコンの連打', () {
    testWidgets('削除アイコンを 150ms 以内に 2 回押しても消えるのは 1 件', (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      final first = tester.getCenter(find.byIcon(Icons.delete_outline).first);
      await tester.tapAt(first);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(first); // 行が繰り上がり、次の地点の削除アイコンに当たる
      await settle(tester);
      expect(c.read(savedPlacesProvider), hasLength(2));
    });
  });

  group('再現: QA-03 (Sev2) G4 バナーの省略', () {
    for (final (locale, city, kind) in const [
      (Locale('ja'), '東京', '熱中症アラート'),
      (Locale('zh'), '东京', '中暑警示'),
    ]) {
      testWidgets('${locale.languageCode} 倍率 2.0 / 360dp でもアラート種別が読める',
          (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(goldenApp(
          home: const MainShell(),
          brightness: Brightness.dark,
          locale: locale,
          textScale: 2.0,
          overrides: [
            ...await placesBaseOverrides(
              savedCount: 1,
              locale: locale,
              current: dangerousHeatSnapshot,
              city: city,
            ),
            ...entitlementOverrides(plus: true),
            ...savedPlaceWeatherOverrides(),
          ],
        ));
        await settle(tester);
        ProviderScope.containerOf(tester.element(find.byType(MainShell)))
            .read(selectedPlaceIdProvider.notifier)
            .select(kNahaId);
        await settle(tester);

        final banner = find.byKey(CurrentAlertBanner.bannerKey);
        final message = find
            .descendant(of: banner, matching: find.byType(RichText))
            .evaluate()
            .map((e) => e.renderObject! as RenderParagraph)
            .firstWhere((p) => p.text.toPlainText().contains(kind));
        expect(message.didExceedMaxLines, isFalse, reason: '「$kind」が省略で見えない');
      });
    }
  });

  group('再現: QA-07 (Sev3) 元に戻すで上限を超える', () {
    // 保存地点が Plus 限定 (無料 0 件) になったので、元の再現 (無料 1 / 1 → 削除 →
    // Comfort-Twin で保存 → 元に戻す) は起きない (無料は保存できない)。同じ穴を
    // 「Plus で保存 → 解約 → 元に戻す」で確かめる: 削除前の件数を超えない。
    testWidgets('Plus 1 件: 削除 → Comfort-Twin で保存 → 解約 → 元に戻す でも削除前の 1 件まで',
        (tester) async {
      final plus = StateProvider<bool>((ref) => true);
      final c = await _pumpLocations(
        tester,
        saved: 1,
        entitlement: switchableEntitlementOverrides(plus),
      );
      final places = c.read(savedPlacesControllerProvider);
      final removed = await places.remove(kNahaId);
      await places.saveCatalogCity(
        const City(
          id: 'lisbon',
          name: 'Lisbon',
          country: 'Portugal',
          latitude: 38.72,
          longitude: -9.14,
          emoji: 'PT',
        ),
        70,
      );
      c.read(plus.notifier).state = false; // 解約
      await places.restore(removed!);
      await settle(tester);
      final quota = c.read(savedPlaceQuotaProvider);
      expect(quota.count, lessThanOrEqualTo(removed.countBefore));
      expect(c.read(savedPlacesProvider).map((p) => p.id), ['place-lisbon']);
    });

    testWidgets('無料で 1 件残っている: 削除 → Comfort-Twin の保存は Plus 導線 → 元に戻す で 1 件に戻る',
        (tester) async {
      final c = await _pumpLocations(tester, saved: 1, plus: false);
      final places = c.read(savedPlacesControllerProvider);
      final removed = await places.remove(kNahaId);
      final check = await places.saveCatalogCity(
        const City(
          id: 'lisbon',
          name: 'Lisbon',
          country: 'Portugal',
          latitude: 38.72,
          longitude: -9.14,
          emoji: 'PT',
        ),
        70,
      );
      expect(check.name, 'needsPlus');
      await places.restore(removed!);
      await settle(tester);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [kNahaId]);
    });
  });

  group('再現: QA-08 (Sev3) 同じ表示の候補が 2 行', () {
    test('名前と地域行が同じ候補は 1 行にまとめる (横浜 / 天草市・熊本県・日本)', () {
      GeocodingHit hit(int id) => GeocodingHit(
            id: id,
            name: '横浜',
            latitude: 32.4,
            longitude: 130.2,
            featureCode: 'PPLL',
            countryCode: 'JP',
            country: '日本',
            admin1: '熊本県',
            admin2: '天草市',
          );
      final plan = PlaceQueryPlan.forInput('横浜');
      final results = rankPlaceCandidates(
        plan: plan,
        batches: [
          [hit(11247763), hit(11265390)],
          for (var i = 1; i < plan.queries.length; i++) const <GeocodingHit>[],
        ],
        language: 'ja',
      );
      final rows = {
        for (final r in results) '${r.name}|${r.regionParts.join('・')}',
      };
      expect(rows.length, results.length, reason: '見分けのつかない候補が並ぶ');
    });
  });
}
