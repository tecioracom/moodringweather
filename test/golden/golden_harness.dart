// test/golden/golden_harness.dart
//
// ゴールデンテストの共通ハーネス (docs/v1.3-design-implementation-plan.md §4)。
//   - 本番と同じ ThemeData (buildAppTheme) と同梱フォントで描画する
//   - 時刻 (clockProvider) と天気データを固定し、実行時刻・ネットワークに依存しない
//   - 端末サイズは Figma のフレームと同じ 390×844 / DPR 1.0
//
// 基準画像は test/golden/goldens/ にコミットする。更新は段階ごとに
//   flutter test test/golden --update-goldens
// を実行し、差分 (test/golden/failures/) を目視してからコミットする。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

/// Figma フレームと同じ論理サイズ。
const Size kGoldenSize = Size(390, 844);

/// 固定の「現在時刻」(2026-07-15 12:00 ローカル)。
final DateTime kGoldenNow = DateTime(2026, 7, 15, 12);

/// FontManifest.json に載る全フォント (同梱 .ttf + MaterialIcons) を読み込む。
/// flutter_test の既定 (Ahem) では文字とアイコンが四角になり回帰検出にならない。
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family);
    for (final font
        in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

WeatherSnapshot goldenSnapshot(DateTime timestamp) => WeatherSnapshot(
      timestamp: timestamp,
      latitude: 35.66,
      longitude: 139.70,
      temperature: 22,
      apparentTemperature: 24,
      humidity: 58,
      pressure: 1013,
      pressureChange6h: 0,
      windSpeed: 3.2,
      uvIndex: 3,
      aqi: 42,
      pollen: null,
      condition: 'sunny',
    );

/// 固定時刻の 6 時間前から 24 時間ぶん (weather_api_client の past_hours=6 と同じ形)。
List<WeatherSnapshot> goldenHourly() => [
      for (var h = -6; h < 18; h++)
        goldenSnapshot(kGoldenNow.add(Duration(hours: h))),
    ];

/// 画面を固定データで描画するための override 一式。
/// 先頭は sharedPreferencesProvider (settingsOverrides が skip(1) で差し替える)。
/// 単位の初期値は日本の端末 (°C・m/s) に固定する (unit_region_fixtures.dart)。
Future<List<Override>> goldenOverrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kGoldenNow),
    weatherSnapshotProvider
        .overrideWith((ref) async => goldenSnapshot(kGoldenNow)),
    cityNameProvider.overrideWith((ref) async => 'Tokyo'),
    hourlyWeatherProvider.overrideWith((ref) async => goldenHourly()),
    unitRegionOverride(),
  ];
}

/// 本番と同じテーマ・ロケール設定で [home] を包む。
///
/// [typeScale] は文字サイズのプリセット (省略時は `--dart-define=MRW_TYPE_SCALE`、
/// 未指定なら既定の案2 = plus2)。[textScale] は端末の文字倍率 (1.0 以外のときだけ
/// 固定する)。
Widget goldenApp({
  required Widget home,
  required Brightness brightness,
  required Locale locale,
  required List<Override> overrides,
  MrwTypeScale? typeScale,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: supportedFlutterLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(
        Brightness.light,
        locale: locale,
        typeScale: typeScale,
      ),
      darkTheme: buildAppTheme(
        Brightness.dark,
        locale: locale,
        typeScale: typeScale,
      ),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: textScale == 1.0
          ? null
          : (context, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: textScale,
                maxScaleFactor: textScale,
                child: child!,
              ),
      home: home,
    ),
  );
}

/// 端末サイズを Figma フレームに合わせる (テスト終了時に元へ戻す)。
void useGoldenViewport(WidgetTester tester) {
  tester.view.physicalSize = kGoldenSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 非同期 provider の解決とアニメーションを待つ (無限アニメーションがあっても
/// 一定時間で打ち切る)。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String goldenName(String screen, Brightness brightness, Locale locale) =>
    'goldens/${screen}_${brightness == Brightness.dark ? 'dark' : 'light'}_${locale.languageCode}.png';
