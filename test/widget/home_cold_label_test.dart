// test/widget/home_cold_label_test.dart
//
// ホームのリングの下の区分名に、現在の体感温度が渡っていること
// (domain/mri/cold_label.dart・band_label.dart)。
//
// 回帰: 南極点 (体感 −62°) でもリングの下が「涼しい」だった (2026-10-01、実機)。
// 体感 −10° 以下は「とても寒い — 防寒を」(リングの下では「—」の直後で 2 行)。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_harness.dart';

WeatherSnapshot _snap(DateTime at, {required double t, double? tApp}) =>
    WeatherSnapshot(
      timestamp: at,
      latitude: -89.99,
      longitude: 0,
      temperature: t,
      apparentTemperature: tApp,
      humidity: 70,
      pressure: 1013,
      pressureChange6h: 0,
      windSpeed: 3,
      uvIndex: 0,
      aqi: null,
      pollen: null,
      condition: 'cloudy',
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  required double t,
  double? tApp,
  Locale locale = const Locale('en'),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final hourly = [
    for (var h = -6; h < 18; h++)
      _snap(kGoldenNow.add(Duration(hours: h)), t: t, tApp: tApp),
  ];
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: const HomePage(),
    brightness: Brightness.dark,
    locale: locale,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => kGoldenNow),
      weatherSnapshotProvider.overrideWith(
        (ref) async => hourly.firstWhere((s) => s.timestamp == kGoldenNow),
      ),
      cityNameProvider.overrideWith((ref) async => 'South Pole'),
      hourlyWeatherProvider.overrideWith((ref) async => hourly),
    ],
  ));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('体感 −62° ならリングの下は「VERY COLD — BUNDLE UP」(涼しいではない)',
      (tester) async {
    await _pumpHome(tester, t: -56, tApp: -62);
    expect(find.text('VERY COLD —\nBUNDLE UP'), findsOneWidget);
    expect(find.text('COOL'), findsNothing);
  });

  testWidgets('日本語は「とても寒い — 防寒を」', (tester) async {
    await _pumpHome(tester, t: -56, tApp: -62, locale: const Locale('ja'));
    expect(find.text('とても寒い —\n防寒を'), findsOneWidget);
    expect(find.text('涼しい'), findsNothing);
  });

  testWidgets('体感温度が無ければ気温で決める', (tester) async {
    await _pumpHome(tester, t: -20);
    expect(find.text('VERY COLD —\nBUNDLE UP'), findsOneWidget);
  });
}
