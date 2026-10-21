// test/unit/settings_provider_test.dart
//
// 設定 provider (温度単位 / 風速の単位 / テーマ / 通知設定) の永続化テスト。
// SharedPreferences はモック初期値で注入し、「保存 → 別コンテナで復元」の
// 往復が成立することを locale_controller と同じ流儀で検証する。
// 単位の初期値は端末の地域 (unitRegionProvider) で決まる
// (docs/design-metric-units-proposal.md §2.6)。保存済みの値は地域より優先。

import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/regional_unit_defaults.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/data/models/notification_preferences.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

const UnitRegion _us = UnitRegion(countryCode: 'US', languageCode: 'en');
const UnitRegion _gb = UnitRegion(countryCode: 'GB', languageCode: 'en');
const UnitRegion _es = UnitRegion(countryCode: 'ES', languageCode: 'es');

Future<ProviderContainer> _container({
  Map<String, Object> initial = const {},
  UnitRegion region = kTestUnitRegionJp,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      unitRegionOverride(region),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<SharedPreferences> _prefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('temperatureUnitProvider', () {
    test('まだ選んでいなければ地域の初期値 (日本・スペイン・英国 °C / 米国 °F)', () async {
      expect((await _container()).read(temperatureUnitProvider),
          TemperatureUnit.celsius);
      expect((await _container(region: _es)).read(temperatureUnitProvider),
          TemperatureUnit.celsius);
      expect((await _container(region: _gb)).read(temperatureUnitProvider),
          TemperatureUnit.celsius);
      expect((await _container(region: _us)).read(temperatureUnitProvider),
          TemperatureUnit.fahrenheit);
      expect(
        (await _container(region: const UnitRegion(languageCode: 'en')))
            .read(temperatureUnitProvider),
        TemperatureUnit.celsius,
      );
    });

    test('保存済みの値は地域より優先 (米国の端末でも °C を選んだ人は °C)', () async {
      final c = await _container(
        initial: {kPrefKeyTemperatureUnit: 'celsius'},
        region: _us,
      );
      expect(c.read(temperatureUnitProvider), TemperatureUnit.celsius);
    });

    test('選択すると永続化され、再起動 (別コンテナ) 後も復元される', () async {
      final c1 = await _container();
      await c1
          .read(temperatureUnitProvider.notifier)
          .select(TemperatureUnit.fahrenheit);
      expect(c1.read(temperatureUnitProvider), TemperatureUnit.fahrenheit);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefKeyTemperatureUnit), 'fahrenheit');

      // 保存済み値からの復元 (アプリ再起動相当)。
      final c2 = await _container(
        initial: {kPrefKeyTemperatureUnit: 'fahrenheit'},
      );
      expect(c2.read(temperatureUnitProvider), TemperatureUnit.fahrenheit);
    });

    test('壊れた保存値は地域の初期値にフォールバックする', () async {
      final c = await _container(initial: {kPrefKeyTemperatureUnit: 'kelvin'});
      expect(c.read(temperatureUnitProvider), TemperatureUnit.celsius);
      final us = await _container(
        initial: {kPrefKeyTemperatureUnit: 'kelvin'},
        region: _us,
      );
      expect(us.read(temperatureUnitProvider), TemperatureUnit.fahrenheit);
    });
  });

  group('windSpeedUnitProvider', () {
    test('まだ選んでいなければ地域の初期値 (JP m/s / US・GB mph / ES km/h / 地域なし)', () async {
      expect((await _container()).read(windSpeedUnitProvider),
          WindSpeedUnit.metersPerSecond);
      expect((await _container(region: _us)).read(windSpeedUnitProvider),
          WindSpeedUnit.milesPerHour);
      expect((await _container(region: _gb)).read(windSpeedUnitProvider),
          WindSpeedUnit.milesPerHour);
      expect((await _container(region: _es)).read(windSpeedUnitProvider),
          WindSpeedUnit.kilometersPerHour);
      // 地域が取れないときはアプリの言語 (ja・zh は m/s、ほかは km/h)。
      expect(
        (await _container(region: const UnitRegion(languageCode: 'zh')))
            .read(windSpeedUnitProvider),
        WindSpeedUnit.metersPerSecond,
      );
      expect(
        (await _container(region: const UnitRegion(languageCode: 'en')))
            .read(windSpeedUnitProvider),
        WindSpeedUnit.kilometersPerHour,
      );
    });

    test('選択すると永続化され、地域が変わっても保存済みの値を保つ', () async {
      final c1 = await _container(region: _us);
      await c1
          .read(windSpeedUnitProvider.notifier)
          .select(WindSpeedUnit.kilometersPerHour);
      expect(c1.read(windSpeedUnitProvider), WindSpeedUnit.kilometersPerHour);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefKeyWindSpeedUnit), 'kilometersPerHour');

      // 再起動 (別コンテナ) で、端末の地域が日本になっていても保存済みの値。
      final c2 = await _container(
        initial: {kPrefKeyWindSpeedUnit: 'kilometersPerHour'},
      );
      expect(c2.read(windSpeedUnitProvider), WindSpeedUnit.kilometersPerHour);
    });

    test('壊れた保存値は地域の初期値にフォールバックする', () async {
      final c = await _container(
        initial: {kPrefKeyWindSpeedUnit: 'knots'},
        region: _gb,
      );
      expect(c.read(windSpeedUnitProvider), WindSpeedUnit.milesPerHour);
    });

    test('データを削除 (prefs を消して読み直し) すると地域の初期値に戻る', () async {
      final c = await _container(
        initial: {kPrefKeyWindSpeedUnit: 'kilometersPerHour'},
        region: _us,
      );
      expect(c.read(windSpeedUnitProvider), WindSpeedUnit.kilometersPerHour);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      c.invalidate(windSpeedUnitProvider);
      expect(c.read(windSpeedUnitProvider), WindSpeedUnit.milesPerHour);
    });
  });

  group('resolveUnitRegion / resolveWindSpeedUnitFromPrefs (Riverpod の外)', () {
    test('端末のロケールの国コードを使う (アプリの表示言語ではない)', () async {
      final prefs = await _prefs();
      final region = resolveUnitRegion(
        prefs,
        systemLocales: const [Locale('en', 'US'), Locale('ja', 'JP')],
        appLanguageCode: 'ja',
      );
      expect(region, const UnitRegion(countryCode: 'US', languageCode: 'ja'));
      expect(region.defaultWindSpeedUnit, WindSpeedUnit.milesPerHour);
    });

    test('国コードの無いロケールはアプリの言語で決める', () async {
      final prefs = await _prefs();
      final ja = resolveUnitRegion(
        prefs,
        systemLocales: const [Locale('en')],
        appLanguageCode: 'ja',
      );
      expect(ja.countryCode, isNull);
      expect(ja.defaultWindSpeedUnit, WindSpeedUnit.metersPerSecond);
    });

    test('OS のロケールが取れない isolate では、前景で記録した地域を使う', () async {
      final prefs = await _prefs();
      // 前景: 米国の端末を記録する。
      resolveUnitRegion(
        prefs,
        systemLocales: const [Locale('en', 'US')],
        appLanguageCode: 'en',
        remember: true,
      );
      expect(prefs.getString(kPrefKeyUnitRegionLastSeen), 'US');

      // background isolate (ロケールが空): 記録した地域 → mph。
      expect(
        resolveWindSpeedUnitFromPrefs(prefs, systemLocales: const []),
        WindSpeedUnit.milesPerHour,
      );
      // 選んだ値があれば、それが最優先。
      await prefs.setString(kPrefKeyWindSpeedUnit, 'metersPerSecond');
      expect(
        resolveWindSpeedUnitFromPrefs(prefs, systemLocales: const []),
        WindSpeedUnit.metersPerSecond,
      );
    });

    test('前景の記録も無い isolate は、最後に解決した言語で決める', () async {
      final prefs = await _prefs({'app_locale_last_resolved': 'ja'});
      expect(
        resolveWindSpeedUnitFromPrefs(prefs, systemLocales: const []),
        WindSpeedUnit.metersPerSecond,
      );
      final en = await _prefs({'app_locale_last_resolved': 'en'});
      expect(
        resolveWindSpeedUnitFromPrefs(en, systemLocales: const []),
        WindSpeedUnit.kilometersPerHour,
      );
    });

    test('地域の無いロケールを記録した端末は、isolate でも言語で決める', () async {
      final prefs = await _prefs({'app_locale_last_resolved': 'en'});
      resolveUnitRegion(
        prefs,
        systemLocales: const [Locale('en')],
        appLanguageCode: 'en',
        remember: true,
      );
      expect(prefs.getString(kPrefKeyUnitRegionLastSeen), '');
      expect(
        resolveWindSpeedUnitFromPrefs(prefs, systemLocales: const []),
        WindSpeedUnit.kilometersPerHour,
      );
    });
  });

  group('themeModeProvider', () {
    test('既定は system', () async {
      final c = await _container();
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('選択すると永続化され、復元される', () async {
      final c1 = await _container();
      await c1.read(themeModeProvider.notifier).select(ThemeMode.dark);
      expect(c1.read(themeModeProvider), ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefKeyThemeMode), 'dark');

      final c2 = await _container(initial: {kPrefKeyThemeMode: 'dark'});
      expect(c2.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('notificationPreferencesProvider', () {
    test('既定値は NotificationPreferences のデフォルトと一致する', () async {
      final c = await _container();
      final prefs = c.read(notificationPreferencesProvider);
      expect(prefs.weatherChangeEnabled, isTrue);
      expect(prefs.personalEnabled, isTrue);
      expect(prefs.personalToggles.hasAny, isFalse);
      expect(prefs.quietHours.start, '22:00');
      expect(prefs.quietHours.end, '07:00');
      expect(prefs.dailyLimit, 3);
    });

    test('更新すると JSON で永続化され、復元される', () async {
      final c1 = await _container();
      final notifier = c1.read(notificationPreferencesProvider.notifier);
      await notifier.update((p) => p.copyWith(
            weatherChangeEnabled: false,
            personalToggles: p.personalToggles.copyWith(pressure: true),
            quietHours: const QuietHours(start: '23:30', end: '06:00'),
            dailyLimit: 5,
          ));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPrefKeyNotificationPrefs);
      expect(raw, isNotNull);

      // アプリ再起動相当: 保存された JSON から状態を復元する。
      final c2 = await _container(initial: {kPrefKeyNotificationPrefs: raw!});
      final restored = c2.read(notificationPreferencesProvider);
      expect(restored.weatherChangeEnabled, isFalse);
      expect(restored.personalToggles.pressure, isTrue);
      expect(restored.personalToggles.humidity, isFalse);
      expect(restored.quietHours.start, '23:30');
      expect(restored.quietHours.end, '06:00');
      expect(restored.dailyLimit, 5);
    });

    test('壊れた JSON は既定値にフォールバックする', () async {
      final c = await _container(
        initial: {kPrefKeyNotificationPrefs: '{not json'},
      );
      final prefs = c.read(notificationPreferencesProvider);
      expect(prefs.weatherChangeEnabled, isTrue);
      expect(prefs.dailyLimit, 3);
    });
  });
}
