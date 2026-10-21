// test/golden/settings_golden_test.dart
//
// 設定サブ画面 (S5) と Calibration / Comfort-Twin (S6) の見た目の回帰検出。
// 主要 3 画面 (ホーム / 詳細 / 設定 Top) は screens_golden_test.dart が見る。
//
// 実行:   flutter test test/golden
// 更新:   flutter test test/golden --update-goldens   (差分を目視した後だけ)
// 差分:   test/golden/failures/*_masterImage.png / *_testImage.png
//
// 端末は Figma と同じ 390×844 / DPR 1。画面が縦に長いものは最初の 1 画面ぶんだけ
// が写る (スクロールの下は widget テスト側で担保する)。

@Tags(['golden'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_feedback_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_profile_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_compare_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_map_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_search_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_app_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_mri_page.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/notification_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/plus_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import 'golden_harness.dart';

/// 保存済みの地点 1 件 (地点管理 / Comfort-Twin の記録セクション用)。
final String _savedRecords = jsonEncode([
  {
    'id': 'place-lisbon',
    'type': 'place',
    'mri': 72,
    'savedAt': '2026-06-01T10:00:00.000',
    'label': 'Lisbon',
    'emoji': '🇵🇹',
  },
]);

CityComfort _candidate({
  required String id,
  required String name,
  required int mri,
  required double temperature,
  required double latitude,
  required double longitude,
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
      timestamp: kGoldenNow,
      latitude: latitude,
      longitude: longitude,
      temperature: temperature,
      humidity: 62,
      pressure: 1009,
      windSpeed: 4.6,
      uvIndex: 5,
      condition: 'cloudy',
    ),
    mri: MoodRingIndex(
      value: mri,
      band: MriBand.fromValue(mri),
      factorContributions: const {},
      calculatedAt: kGoldenNow,
    ),
  );
}

List<CityComfort> _candidates() => [
      _candidate(
          id: 'vancouver',
          name: 'Vancouver',
          mri: 65,
          temperature: 22.2,
          latitude: 49.28,
          longitude: -123.12),
      _candidate(
          id: 'sanfrancisco',
          name: 'San Francisco',
          mri: 62,
          temperature: 19.4,
          latitude: 37.77,
          longitude: -122.42),
      _candidate(
          id: 'lisbon',
          name: 'Lisbon',
          mri: 60,
          temperature: 24.1,
          latitude: 38.72,
          longitude: -9.14),
    ];

Future<List<Override>> _overrides() async {
  // goldenOverrides() は中で setMockInitialValues({}) を呼ぶので、
  // **その後に** 記録入りの prefs を差し込む (順序を逆にすると空になる)。
  final base = await goldenOverrides();
  SharedPreferences.setMockInitialValues({
    kPrefKeyComfortRecords: _savedRecords,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    ...base.skip(1),
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentLocationProvider
        .overrideWith((ref) async => const GeoPoint(35.681, 139.767)),
    twinCandidatesProvider.overrideWith((ref) async => _candidates()),
    // 地点管理の MRI は保存地点の現在値 (実通信しないよう固定する)。
    savedPlaceMriOverride(values: const {'place-lisbon': 72}),
  ];
}

void main() {
  setUpAll(loadAppFonts);

  const locales = [Locale('en'), Locale('ja')];
  const modes = [Brightness.dark, Brightness.light];

  final screens = <String, Widget Function()>{
    'general': () => const GeneralSettingsPage(),
    'notifications': () => const NotificationSettingsPage(),
    'locations': () => const LocationsPage(),
    'privacy': () => const PrivacyPage(),
    'about_mri': () => const AboutMriPage(),
    'about_app': () => const AboutAppPage(),
    'plus': () => const PlusSettingsPage(),
    'calibration_home': () => const CalibrationHomePage(),
    'calibration_feedback': () => const CalibrationFeedbackPage(),
    'calibration_profile': () => const CalibrationProfilePage(),
    'twin_search': () => const TwinSearchPage(),
    'twin_map': () => const TwinMapPage(targetMri: 64),
    'twin_compare': () => TwinComparePage(other: _candidates().first),
  };

  for (final brightness in modes) {
    for (final locale in locales) {
      for (final entry in screens.entries) {
        final tag = '${brightness.name}/${locale.languageCode}';
        testWidgets('${entry.key} ($tag)', (tester) async {
          useGoldenViewport(tester);
          await tester.pumpWidget(goldenApp(
            home: entry.value(),
            brightness: brightness,
            locale: locale,
            overrides: await _overrides(),
          ));
          await settle(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(goldenName(entry.key, brightness, locale)),
          );
        });
      }
    }
  }

  // 設定 › 一般の「ライブ壁紙」の区画 (1.3.0 (13)。テーマの下で、1 画面目の下端に
  // かかるので、下までスクロールして撮る。docs/design-wallpaper-weather-overlay.md §6)。
  // 1.3.0 (14) から区画の先頭に「ライブ壁紙を設定」の行。general_live_wallpaper は
  // 未設定 (説明「ホーム画面の壁紙に設定します」)、general_live_wallpaper_active は
  // 設定中 (見出しの右に「設定中」、説明「ロック画面への設定もここから」)。
  for (final active in const [false, true]) {
    final screen =
        active ? 'general_live_wallpaper_active' : 'general_live_wallpaper';
    for (final brightness in modes) {
      for (final locale in locales) {
        final tag = '${brightness.name}/${locale.languageCode}';
        testWidgets('$screen ($tag)', (tester) async {
          useGoldenViewport(tester);
          await tester.pumpWidget(goldenApp(
            home: const GeneralSettingsPage(),
            brightness: brightness,
            locale: locale,
            overrides: [
              ...await _overrides(),
              liveWallpaperSetupBridgeProvider
                  .overrideWithValue(_GoldenSetup(active: active)),
            ],
          ));
          await settle(tester);
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -800));
          await settle(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(goldenName(screen, brightness, locale)),
          );
        });
      }
    }
  }
}

/// 「設定中」を固定で返す壁紙の設定 (ネイティブを呼ばない)。
class _GoldenSetup implements LiveWallpaperSetupBridge {
  const _GoldenSetup({required this.active});
  final bool active;

  @override
  Future<bool> openPicker() async => true;

  @override
  Future<bool> isActive() async => active;
}
