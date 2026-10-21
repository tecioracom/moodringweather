// test/widget/home_sparkline_test.dart
//
// Home の「時間別MRI」カード (docs/home-sparkline-decisions.md の決定 ①〜④)。
//   - 窓は 9 スロット × 1.5h = 過去 3h + 現在 + 未来 9h。頂点は毎時 13 点、現在は頂点 3
//   - 傾向語は現在より後ろだけで決める (過去を混ぜると事実と逆になる)
//   - 縦は自動スケール + 上限 / 下限の軸ラベル
//   - 背面に快適帯の参照バンド
//   - 時刻ラベルはロケール準拠 ("12:00")

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/shared/mri_line_chart.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_harness.dart';

WeatherSnapshot _snap(DateTime at, double temperature, double humidity) =>
    WeatherSnapshot(
      timestamp: at,
      latitude: 35.66,
      longitude: 139.70,
      temperature: temperature,
      apparentTemperature: temperature + 2,
      humidity: humidity,
      pressure: 1013,
      pressureChange6h: 0,
      windSpeed: 3.2,
      uvIndex: 3,
      aqi: 42,
      pollen: null,
      condition: 'sunny',
    );

/// 過去は酷暑 (40 °C / 85 %)、現在以降は快適 (22 °C / 55 %)。
/// 過去を傾向語に混ぜてしまうと「リスク上昇」になる系列。
List<WeatherSnapshot> _pastHotSeries() => [
      for (var h = -6; h < 18; h++)
        h < 0
            ? _snap(kGoldenNow.add(Duration(hours: h)), 40, 85)
            : _snap(kGoldenNow.add(Duration(hours: h)), 22, 55),
    ];

Future<List<Override>> _overrides(List<WeatherSnapshot> hourly) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kGoldenNow),
    weatherSnapshotProvider.overrideWith(
      (ref) async => hourly.firstWhere((s) => s.timestamp == kGoldenNow),
    ),
    cityNameProvider.overrideWith((ref) async => 'Tokyo'),
    hourlyWeatherProvider.overrideWith((ref) async => hourly),
  ];
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required List<WeatherSnapshot> hourly,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: const HomePage(),
      ),
    ),
    brightness: Brightness.dark,
    locale: locale,
    overrides: await _overrides(hourly),
  ));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('窓は毎時 13 点、現在は頂点 3 (過去 3h + 現在 + 未来 9h)', (tester) async {
    await _pumpHome(tester, hourly: _pastHotSeries());

    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    expect(chart.values.length, 13);
    expect(chart.nowIndex, 3);
    expect(chart.slotCount, 9);

    // 頂点 0〜2 は過去の酷暑 = 現在よりはっきり低い。
    expect(chart.values[0], isNotNull);
    expect(chart.values[3], isNotNull);
    expect(chart.values[0]!, lessThan(chart.values[3]! - 8));
    // 頂点 4 以降は現在と同条件。
    expect(chart.values[12], closeTo(chart.values[3]!, 0.5));
  });

  testWidgets('傾向語は現在より後ろだけで決める (過去の酷暑を混ぜない)', (tester) async {
    await _pumpHome(tester, hourly: _pastHotSeries());

    expect(find.text('STABLE'), findsOneWidget);
    expect(find.text('RISK RISES'), findsNothing);
  });

  testWidgets('未来が悪化する系列ならリスク上昇を出す', (tester) async {
    final series = [
      for (var h = -6; h < 18; h++)
        h <= 0
            ? _snap(kGoldenNow.add(Duration(hours: h)), 22, 55)
            : _snap(kGoldenNow.add(Duration(hours: h)), 40, 85),
    ];
    await _pumpHome(tester, hourly: series);

    expect(find.text('RISK RISES'), findsOneWidget);
    expect(find.text('STABLE'), findsNothing);
  });

  testWidgets('自動スケール + 上限 / 下限の軸ラベルを出す (決定 ①)', (tester) async {
    await _pumpHome(tester, hourly: _pastHotSeries());

    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    // 固定 0–100 ではなく実データに詰めている。
    expect(chart.scale.span, lessThan(100));

    final axis = find.byType(MriValueAxis);
    expect(axis, findsOneWidget);
    expect(
      find.descendant(
        of: axis,
        matching: find.text('${chart.scale.hi.round()}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: axis,
        matching: find.text('${chart.scale.lo.round()}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('快適帯の参照バンドを背面に敷く (決定 ④ 代替A)', (tester) async {
    await _pumpHome(tester, hourly: _pastHotSeries());

    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    expect(chart.bandMin, 60);
    expect(chart.bandMax, 80);
    // 快適帯が表示範囲に掛かっているので描かれる (線と同じ写像)。
    final g = chart.geometryFor(const Size(282, 36));
    expect(g.bandRect(chart.bandMin, chart.bandMax), isNotNull);
  });

  testWidgets('文字スケール 2.0 でも画面全体が溢れない', (tester) async {
    // レイアウト溢れが 1 つでもあれば flutter_test が例外で落とす。
    await _pumpHome(
      tester,
      hourly: _pastHotSeries(),
      locale: const Locale('ja'),
      textScale: 2.0,
    );

    expect(
        find.descendant(
          of: find.byType(TimeAxisLabels),
          matching: find.text('12:00'),
        ),
        findsOneWidget);
    // 軸が入る高さまでバー列が伸びている。
    final chart = tester.widget<MriLineChart>(find.byType(MriLineChart));
    expect(chart.height, greaterThan(36));
  });

  testWidgets('時刻ラベルは "12:00" 形式 (裸の数字を使わない。決定 ②)', (tester) async {
    await _pumpHome(
      tester,
      hourly: _pastHotSeries(),
      locale: const Locale('ja'),
    );

    final labels = find.byType(TimeAxisLabels);
    expect(labels, findsOneWidget);
    expect(find.descendant(of: labels, matching: find.text('12:00')),
        findsOneWidget);
    expect(
        find.descendant(of: labels, matching: find.text('12')), findsNothing);
    // 起点は現在の 3 時間前 = 9:00。
    expect(find.descendant(of: labels, matching: find.text('9:00')),
        findsOneWidget);

    // 軸の数字は JA でも Plex Mono (Figma JP の実測に合わせる)。
    final now = tester.widget<Text>(
      find.descendant(of: labels, matching: find.text('12:00')),
    );
    expect(now.style?.fontFamily, MrwFonts.plexMono);
    expect(now.style?.fontWeight, FontWeight.w600);
    // 上限 / 下限の値は系列で変わるので、軸列の先頭の Text を見る。
    final axis = tester.widget<Text>(
      find
          .descendant(
              of: find.byType(MriValueAxis), matching: find.byType(Text))
          .first,
    );
    expect(axis.style?.fontFamily, MrwFonts.plexMono);
  });
}
