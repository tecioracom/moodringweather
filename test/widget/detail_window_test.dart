// test/widget/detail_window_test.dart
//
// Detail の 24 時間チャートの窓 (docs/home-sparkline-decisions.md F8 の是正)。
// 現在だけを起点にすると +22h までサンプリングする一方でデータは +17h までしか
// 無く、右端 3 本 (25%) が恒久的に空だった。窓を「現在の 6 時間前」から取り、
// データ範囲から食み出すときは寄せることで、どの時刻でも空バーを出さない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/shared/mri_line_chart.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/weather_rail.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

import '../golden/golden_harness.dart';

WeatherSnapshot _snap(DateTime at) => WeatherSnapshot(
      timestamp: at,
      latitude: 35.66,
      longitude: 139.70,
      temperature: 22 + (at.hour % 6) * 0.8,
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

Future<void> _pumpDetail(
  WidgetTester tester, {
  required DateTime now,
  required List<WeatherSnapshot> hourly,
  double textScale = 1.0,
}) async {
  useGoldenViewport(tester);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(goldenApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: const DetailPage(),
      ),
    ),
    brightness: Brightness.dark,
    locale: const Locale('ja'),
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => now),
      weatherSnapshotProvider.overrideWith((ref) async => _snap(now)),
      cityNameProvider.overrideWith((ref) async => 'Tokyo'),
      hourlyWeatherProvider.overrideWith((ref) async => hourly),
      unitRegionOverride(),
    ],
  ));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('通常時: 過去 6h 〜 未来 16h。空のバーが 1 本も無い', (tester) async {
    // weather_api_client と同じ窓 (過去 6h 〜 未来 17h の 24 点)。
    final now = DateTime(2026, 7, 15, 12);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = -6; h < 18; h++) _snap(now.add(Duration(hours: h))),
      ],
    );

    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    // 12 スロット × 2h に毎時 23 点。
    expect(chart.values.length, 23);
    expect(chart.values.where((v) => v == null), isEmpty);
    // 現在はスロット 3 = 頂点 6。
    expect(chart.nowIndex, 6);
  });

  testWidgets('早朝: 過去が足りない時間帯は窓ごと前に寄せる (空バーを出さない)', (tester) async {
    // forecast_days=2 のため当日 00:00 始まり。02:00 では過去 6h が無い。
    final now = DateTime(2026, 7, 15, 2);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = 0; h < 24; h++)
          _snap(DateTime(2026, 7, 15).add(Duration(hours: h))),
      ],
    );

    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    expect(chart.values.where((v) => v == null), isEmpty);
    // 起点が 00:00 に寄るので現在はスロット 1 = 頂点 2。
    expect(chart.nowIndex, 2);
  });

  testWidgets('文字スケール 2.0 でも画面全体が溢れない', (tester) async {
    final now = DateTime(2026, 7, 15, 12);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = -6; h < 18; h++) _snap(now.add(Duration(hours: h))),
      ],
      textScale: 2.0,
    );
    expect(find.byType(MriLineChart), findsOneWidget);
  });

  testWidgets('時刻ラベルは現在を基準に 3 本おき (現在に必ず乗る)', (tester) async {
    final now = DateTime(2026, 7, 15, 12);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = -6; h < 18; h++) _snap(now.add(Duration(hours: h))),
      ],
    );

    final labels = find.byType(TimeAxisLabels);
    for (final h in ['6:00', '12:00', '18:00', '0:00']) {
      expect(
          find.descendant(of: labels, matching: find.text(h)), findsOneWidget,
          reason: h);
    }
  });

  testWidgets('時刻ラベルの下に天気レール (グリフ + 気温) が同じ数だけ出る。天気名の文字は出さない', (tester) async {
    final now = DateTime(2026, 7, 15, 12);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = -6; h < 18; h++) _snap(now.add(Duration(hours: h))),
      ],
    );

    // 時刻ラベル 6:00 / 12:00 / 18:00 / 0:00 と同じ 4 か所。
    final items = find.byType(WeatherRailItem);
    expect(items, findsNWidgets(4));
    expect(
      find.descendant(of: items, matching: find.text('22°')),
      findsNWidgets(4),
    );
    // 天気名 (晴れ) はレールに出さない (2026-09-29 ユーザー指示)。
    expect(find.descendant(of: items, matching: find.text('晴れ')), findsNothing);
  });

  testWidgets('文字スケール 2.0 では時刻ラベルと同じ間引きにレールも従う', (tester) async {
    final now = DateTime(2026, 7, 15, 12);
    await _pumpDetail(
      tester,
      now: now,
      hourly: [
        for (var h = -6; h < 18; h++) _snap(now.add(Duration(hours: h))),
      ],
      textScale: 2.0,
    );
    final labelTexts = find.descendant(
      of: find.byType(TimeAxisLabels),
      matching: find.byType(Text),
    );
    expect(
      find.byType(WeatherRailItem).evaluate().length,
      labelTexts.evaluate().length,
    );
  });
}
