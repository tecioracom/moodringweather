// test/widget/comfort_twin_test.dart
//
// Comfort-Twin 3 画面 (検索 / マップ / 比較) のスモークテスト。
// 候補都市の天気は twinCandidatesProvider を override して実通信しない。
// 「この場所を保存」は保存地点 (Plus 限定。無料 0 件、2026-09-30 ユーザー決裁):
// Plus は保存、無料は Paywall、Plus の 5 件で理由のスナックバー。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_compare_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_map_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_search_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_world_map.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart'
    show entitlementOverrides, savedPlacesJson;
import '../fixtures/unit_region_fixtures.dart';

Widget _app({required List<Override> overrides, required Widget home}) {
  return ProviderScope(
    // 単位の初期値は日本の端末 (°C・m/s) に固定する。
    overrides: [...overrides, unitRegionOverride()],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

const Locale _enLocale = Locale('en');

Future<SharedPreferences> _mockPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

/// 自分の街: 22°C / 50% / UV3 (MRI ≈ 64 帯)。
WeatherSnapshot _mySnapshot() => WeatherSnapshot(
      timestamp: DateTime.now(),
      latitude: 35.66,
      longitude: 139.70,
      temperature: 22,
      apparentTemperature: 22,
      humidity: 50,
      pressure: 1013,
      pressureChange6h: 0,
      windSpeed: 2,
      uvIndex: 3,
      aqi: 42,
      pollen: null,
      condition: 'sunny',
    );

CityComfort _candidate({
  required String id,
  required String name,
  required int mri,
  double temperature = 25,
  double? humidity = 60,
  double? uvIndex = 5,
  double latitude = 48.86,
  double longitude = 2.35,
}) {
  return CityComfort(
    city: City(
      id: id,
      name: name,
      country: 'Testland',
      latitude: latitude,
      longitude: longitude,
      emoji: '🌍',
    ),
    snapshot: WeatherSnapshot(
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      temperature: temperature,
      humidity: humidity,
      uvIndex: uvIndex,
      condition: 'cloudy',
    ),
    mri: MoodRingIndex(
      value: mri,
      band: MriBand.fromValue(mri),
      factorContributions: const {},
      calculatedAt: DateTime.now(),
    ),
  );
}

List<CityComfort> _candidates() => [
      _candidate(id: 'paris', name: 'Paris', mri: 64),
      _candidate(id: 'tokyo', name: 'Tokyo', mri: 54, temperature: 28),
      _candidate(id: 'sydney', name: 'Sydney', mri: 84, temperature: 15),
    ];

void main() {
  testWidgets('検索: ターゲットスライダー・記録セクション・検索ボタンを表示する', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
      ],
      home: const TwinSearchPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Comfort-Twin'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('TARGET FEEL (MRI)'), findsOneWidget);
    expect(find.text('Search worldwide'), findsOneWidget);
    // 記録なしの空表示
    expect(
      find.text(
          'No saved records yet. Save today\'s feel or a favorite place.'),
      findsOneWidget,
    );
  });

  testWidgets('検索: 「今日の体感を記録」でオンデバイス保存され、チップとして再選択できる', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
      ],
      home: const TwinSearchPage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save today\'s feel'));
    await tester.pumpAndSettle();

    expect(find.text('Saved today\'s feel.'), findsOneWidget); // snackbar
    expect(prefs.getString(kPrefKeyComfortRecords), contains('"type":"day"'));
  });

  testWidgets('マップ: 類似順リスト (類似% + ミニリング) とドット世界地図を表示する', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        twinCandidatesProvider.overrideWith((ref) async => _candidates()),
      ],
      home: const TwinMapPage(targetMri: 64),
    ));
    await tester.pumpAndSettle();

    // v1.3: 見出しが結果の説明文になり、ヘッダの小見出しは親画面名になった。
    expect(find.text('Comfort-Twin'), findsOneWidget);
    expect(find.text('Closest matches to MRI 64'), findsOneWidget);
    expect(find.byType(TwinWorldMap), findsOneWidget);

    // 類似順: Paris 100% > Tokyo 90% > Sydney 80%
    // v1.3: 一致率と MRI 値を 1 つの行 (帯色つき) にまとめた。表示は語なしの
    // 「nn% · MRI nn」(MRI と数値の間は NBSP)、読み上げは語つき。
    expect(find.text('🌍 Paris'), findsOneWidget);
    expect(find.text('100% · MRI\u00A064'), findsOneWidget);
    expect(find.text('90% · MRI\u00A054'), findsOneWidget);
    expect(find.text('80% · MRI\u00A084'), findsOneWidget);
    // 行はタップ可能な 1 ノードに統合されるので、ラベルに含まれることを見る。
    // 表示用の「100% · MRI 64」は読み上げに出さない (excludeSemantics)。
    Finder spoken(String s) => find.bySemanticsLabel(RegExp(RegExp.escape(s)));
    expect(spoken('100% match · MRI 64'), findsOneWidget);
    expect(spoken('80% match · MRI 84'), findsOneWidget);
    expect(spoken('100% · MRI'), findsNothing);
    semantics.dispose();

    final parisY = tester.getTopLeft(find.text('🌍 Paris')).dy;
    final tokyoY = tester.getTopLeft(find.text('🌍 Tokyo')).dy;
    final sydneyY = tester.getTopLeft(find.text('🌍 Sydney')).dy;
    expect(parisY, lessThan(tokyoY));
    expect(tokyoY, lessThan(sydneyY));
  });

  testWidgets('マップ→比較: 都市タップで 2 リング比較 + 差分 + 保存ができる (Plus)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        twinCandidatesProvider.overrideWith((ref) async => _candidates()),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
        cityNameProvider.overrideWith((ref) async => 'Shibuya'),
        ...entitlementOverrides(plus: true),
      ],
      home: const TwinMapPage(targetMri: 64),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('🌍 Paris'));
    await tester.pumpAndSettle();

    // 比較画面: 自分の街と選択都市
    // v1.3: 比較画面は幅が狭いので都市名から絵文字を外している。
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Shibuya'), findsOneWidget);
    expect(find.text('Paris'), findsWidgets);
    expect(find.text('Difference'), findsOneWidget);
    // 気温はリングカードの下 (自分 22° / Paris 25°)。
    expect(find.text('22°'), findsOneWidget);
    expect(find.text('25°'), findsOneWidget);
    // v1.3 (Figma 5:240): 差は「どちらがどれだけ多いか」で出す。
    // 湿度 50% / 60% → Paris +10
    expect(find.text('Humidity (%)'), findsOneWidget);
    expect(find.text('Paris +10'), findsOneWidget);
    // UV 3 / 5 → Paris +2、一致度も出る
    expect(find.text('Paris +2'), findsOneWidget);
    expect(find.text('MATCH QUALITY'), findsOneWidget);

    // この場所を保存 (オンデバイス)
    await tester.tap(find.text('Save this place'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to your records.'), findsOneWidget); // snackbar
    final raw = prefs.getString(kPrefKeyComfortRecords);
    expect(raw, contains('"id":"place-paris"'));
    expect(raw, contains('"label":"Paris"'));
  });

  // 見出しの記号の「/」の前後には U+2060 (幅 0。記号の途中で折らない。QA-20)。
  for (final (tag, label, diff) in const [
    (null, 'Wind (m\u2060/\u2060s)', 'Lima +2.5'), // 日本の端末の初期値 = m/s
    ('kilometersPerHour', 'Wind (km\u2060/\u2060h)', 'Lima +9'), // 2.5 × 3.6
    ('milesPerHour', 'Wind (mph)', 'Lima +6'), // 2.5 × 2.237 = 5.6
  ]) {
    testWidgets('比較: 風の見出しと差は風速の単位の設定に従う ($label)', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await _mockPrefs(
        tag == null ? const {} : {kPrefKeyWindSpeedUnit: tag},
      );
      final other = _candidate(id: 'lima', name: 'Lima', mri: 70);
      final windy = CityComfort(
        city: other.city,
        mri: other.mri,
        snapshot: other.snapshot.copyWith(windSpeed: 4.5), // 自分は 2.0
      );
      await tester.pumpWidget(_app(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
          cityNameProvider.overrideWith((ref) async => 'Shibuya'),
        ],
        home: TwinComparePage(other: windy),
      ));
      await tester.pumpAndSettle();

      expect(find.text(label), findsOneWidget);
      expect(find.text(diff), findsOneWidget);
    });
  }

  // 保存地点は Plus 限定 (無料 0 件)。無料は 0 件でも、無料 1 件の時期に保存した
  // 地点が残っていても、新規の保存は Paywall (「上限 N 件」は出さない)。
  for (final kept in const [0, 1]) {
    testWidgets('比較: 無料 (保存 $kept 件) の「この場所を保存」は Paywall、保存しない',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final stored =
          kept == 0 ? null : savedPlacesJson(count: kept, locale: _enLocale);
      final prefs = await _mockPrefs({
        if (stored != null) kPrefKeyComfortRecords: stored,
      });
      await tester.pumpWidget(_app(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
          cityNameProvider.overrideWith((ref) async => 'Shibuya'),
        ],
        home: TwinComparePage(other: _candidates().first),
      ));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
          tester.element(find.byType(TwinComparePage)));
      expect(c.read(isPlusProvider), isFalse);
      expect(c.read(savedLocationLimitProvider), kFreeSavedLocationLimit);

      await tester.tap(find.text('Save this place'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.text('Saved to your records.'), findsNothing);
      expect(find.textContaining('place limit'), findsNothing);
      expect(prefs.getString(kPrefKeyComfortRecords), stored);
    });
  }

  testWidgets('比較: Plus で 5 件保存済みなら「5 件まで」のスナックバー (Paywall は開かない)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stored = savedPlacesJson(count: 5, locale: _enLocale);
    final prefs = await _mockPrefs({kPrefKeyComfortRecords: stored});
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
        cityNameProvider.overrideWith((ref) async => 'Shibuya'),
        ...entitlementOverrides(plus: true),
      ],
      home: TwinComparePage(other: _candidates().first),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save this place'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallPage), findsNothing);
    expect(find.text('You have reached the 5-place limit.'), findsOneWidget);
    expect(prefs.getString(kPrefKeyComfortRecords), stored);
  });

  testWidgets('比較ページ単体: 欠測 (湿度/UV null) は — 表示で落ちない', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    final other = _candidate(
      id: 'lima',
      name: 'Lima',
      mri: 70,
      humidity: null,
      uvIndex: null,
    );
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
        cityNameProvider.overrideWith((ref) async => null),
      ],
      home: TwinComparePage(other: other),
    ));
    await tester.pumpAndSettle();

    expect(find.text('My location'), findsOneWidget); // 都市名フォールバック
    expect(find.text('Lima'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // 欠測値とその差分
  });

  testWidgets('設定: メニューから Comfort-Twin 検索画面へ遷移できる', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
      ],
      home: const SettingsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Comfort-Twin'), findsOneWidget);
    await tester.tap(find.text('Comfort-Twin'));
    await tester.pumpAndSettle();
    expect(find.text('Search worldwide'), findsOneWidget);
  });
}
