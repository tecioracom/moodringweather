// test/widget/detail_page_test.dart
//
// Detail (24 時間) 画面のスモークテスト。
// hourlyWeatherProvider を override して実ネットワークなしで描画を検証する。
// 指標タイル (docs/design-metric-units-proposal.md §2.1・§2.7): 気温は「22°」、
// UV・空気質は段階語、花粉は風に差し替え、風は風速の単位の設定に従う。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_metric_tile.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';
import '../golden/golden_harness.dart' show loadAppFonts;

List<WeatherSnapshot> _hourlySnapshots() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day, now.hour).subtract(
    const Duration(hours: 6),
  );
  return [
    for (var h = 0; h < 24; h++)
      WeatherSnapshot(
        timestamp: base.add(Duration(hours: h)),
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
      ),
  ];
}

Widget _app({required List<Override> overrides}) {
  return ProviderScope(
    // 単位の初期値は日本の端末 (°C・m/s) に固定する。
    overrides: [...overrides, unitRegionOverride()],
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('en')],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: DetailPage(),
    ),
  );
}

/// 値 (fontSize 18) は時刻ラベル ("22" 時など) と衝突しうるため style で特定する。
Finder _value(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 18,
    );

Future<void> _pumpDetail(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 温度・風速の単位 (settings_provider) が SharedPreferences を参照するため注入する。
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();

  await tester.pumpWidget(_app(overrides: [
    sharedPreferencesProvider.overrideWithValue(shared),
    hourlyWeatherProvider.overrideWith((ref) async => _hourlySnapshots()),
  ]));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('DetailPage はチャートと 6 メトリクスカードを表示する', (tester) async {
    await _pumpDetail(tester);

    // loading → data
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    // Figma v1.3 (3:243): ラベルは mono 大文字、値と後ろの文字は別テキスト。
    expect(find.text('24 Hours'), findsOneWidget); // タイトル
    expect(find.text('MRI TREND'), findsOneWidget); // チャートセクション
    expect(find.text('CURRENT CONDITIONS'), findsOneWidget);

    // 6 タイル (参照快適日: 22° / 50% / UV 3 Moderate / AIR 42 Good /
    // 風 2.0 m/s (日本の端末の初期値) / 1013 hPa)。
    expect(find.text('TEMPERATURE'), findsOneWidget);
    // 気温は「22°」(単位は設定で決まるので付けない。ホーム・天気レールと同じ)。
    expect(_value('22°'), findsOneWidget);
    expect(find.text('°C'), findsNothing);
    expect(find.text('HUMIDITY'), findsOneWidget);
    expect(_value('50'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    // UV・空気質は単位ではなく段階語 (「index」「AQI」は出さない)。
    expect(find.text('UV'), findsOneWidget);
    expect(_value('3'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('index'), findsNothing);
    expect(find.text('AIR'), findsOneWidget);
    expect(_value('42'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('AQI'), findsNothing);
    // 花粉のタイルは出さない (データ未接続で常に「Low」を出していた)。風に差し替え。
    expect(find.text('POLLEN'), findsNothing);
    expect(find.text('Low'), findsNothing);
    expect(find.text('WIND'), findsOneWidget);
    expect(_value('2.0'), findsOneWidget);
    expect(find.text('m/s'), findsOneWidget);
    expect(find.text('PRESSURE'), findsOneWidget);
    expect(_value('1013'), findsOneWidget);
    expect(find.text('hPa'), findsOneWidget);
    // Figma のタイルは独自の状態語 (Steady 等) を持たない。
    expect(find.text('Steady'), findsNothing);

    // 現在値の表示 (参照快適日 → MRI 64。mri-spec.md §7)
    expect(find.text('NOW 64'), findsOneWidget);
  });

  testWidgets('6 タイルの並びは 気温・湿度 / UV・空気質 / 風・気圧 (2 列 × 3 行)', (tester) async {
    await _pumpDetail(tester);
    await tester.pumpAndSettle();

    const order = [
      'TEMPERATURE',
      'HUMIDITY',
      'UV',
      'AIR',
      'WIND',
      'PRESSURE',
    ];
    final rects = [for (final l in order) tester.getRect(find.text(l))];
    for (var i = 0; i < order.length; i += 2) {
      final left = rects[i];
      final right = rects[i + 1];
      // 同じ行 (上端が同じ)、左 → 右。
      expect(right.top, closeTo(left.top, 0.5), reason: order[i]);
      expect(right.left, greaterThan(left.right), reason: order[i]);
      if (i > 0) {
        // 前の行より下。
        expect(left.top, greaterThan(rects[i - 2].bottom), reason: order[i]);
      }
    }
    // 同じ行の 2 枚は高さが同じ。
    final tiles = find.byType(QuietMetricTile);
    expect(tiles, findsNWidgets(6));
    for (var i = 0; i < 6; i += 2) {
      expect(tester.getSize(tiles.at(i)).height,
          tester.getSize(tiles.at(i + 1)).height);
    }
  });

  for (final (tag, shown, symbol) in const [
    ('metersPerSecond', '2.0', 'm/s'),
    ('kilometersPerHour', '7', 'km/h'), // 2 m/s × 3.6 = 7.2
    ('milesPerHour', '4', 'mph'), // 2 m/s × 2.237 = 4.47
  ]) {
    testWidgets('風のタイルは風速の単位の設定に従う ($symbol)', (tester) async {
      await _pumpDetail(tester, prefs: {kPrefKeyWindSpeedUnit: tag});
      await tester.pumpAndSettle();
      expect(_value(shown), findsOneWidget);
      expect(find.text(symbol), findsOneWidget);
    });
  }

  testWidgets('°F の設定では気温タイルも「72°」(単位は付けない)', (tester) async {
    await _pumpDetail(tester, prefs: {kPrefKeyTemperatureUnit: 'fahrenheit'});
    await tester.pumpAndSettle();
    expect(_value('72°'), findsOneWidget);
    expect(find.text('°F'), findsNothing);
  });

  testWidgets('取得失敗時はエラーメッセージと再試行ボタンを表示する', (tester) async {
    // mriTimelineProvider がキャリブレーション (personalProfileProvider) を
    // 参照するため SharedPreferences の注入が必要。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_app(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      hourlyWeatherProvider.overrideWith(
        (ref) async => throw const AppException(
          '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
          'test failure',
          ErrorType.network,
        ),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Couldn’t load the weather. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
