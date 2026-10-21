// test/widget/main_shell_test.dart
//
// MainShell (ホーム / 詳細 / 設定 タブ) のテスト。
//   - 下部ナビの index 切替でタブ本体が即時に入れ替わる (push しない)
//   - タブ直下 (トップレベル) では戻る矢印を出さない
//   - 設定タブ配下のサブ画面は従来どおり push (戻る矢印あり・下部ナビ無し)
// 実ネットワークなしで検証するため weather 系 provider を override する。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

WeatherSnapshot _snapshot(DateTime timestamp) => WeatherSnapshot(
      timestamp: timestamp,
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

List<WeatherSnapshot> _hourlySnapshots() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day, now.hour).subtract(
    const Duration(hours: 6),
  );
  return [for (var h = 0; h < 24; h++) _snapshot(base.add(Duration(hours: h)))];
}

Widget _app({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('en')],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MainShell(),
    ),
  );
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    weatherSnapshotProvider.overrideWith((ref) async => _snapshot(
          DateTime.now(),
        )),
    cityNameProvider.overrideWith((ref) async => 'Tokyo'),
    hourlyWeatherProvider.overrideWith((ref) async => _hourlySnapshots()),
    // 単位の初期値は日本の端末 (°C・m/s) に固定する。
    unitRegionOverride(),
  ];
}

void main() {
  testWidgets('ホーム / 詳細 / 設定 はタブ切替で即時に入れ替わり、下部ナビが常に残る', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(overrides: await _overrides()));
    await tester.pumpAndSettle();

    // ホームタブ: 気温と下部ナビ 3 タブ。トップレベルなので戻る矢印なし。
    // ('22°' は天気レール各項目にも出るため、ヘッダの大気温
    //  (fontSize 64、Figma v1.3 3:52) を style で特定して 1 件に絞る。)
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == '22°' && w.style?.fontSize == 64,
      ),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(kQuietBackKey), findsNothing);

    // 詳細タブへ切替 (push ではなく index 切替。ナビは残り、戻る矢印なし)。
    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();
    expect(find.text('24 Hours'), findsOneWidget);
    expect(find.text('MRI TREND'), findsOneWidget); // v1.3: mono ラベルは大文字
    expect(find.byType(QuietNavBar), findsOneWidget);
    expect(find.byKey(kQuietBackKey), findsNothing);

    // 設定タブへ切替 (ナビは残り、戻る矢印なし)。
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byType(QuietNavBar), findsOneWidget);
    expect(find.byKey(kQuietBackKey), findsNothing);

    // ホームタブへ戻る (IndexedStack なので即時切替・状態保持)。
    // ('22°' は詳細タブのメトリクスにも存在しうるため、ホーム固有の
    //  体感温度表記で判定する。)
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('FEELS 22°'), findsOneWidget); // v1.3: mono ラベルは大文字
  });

  testWidgets('設定タブ配下のサブ画面は push 遷移 (戻る矢印あり・下部ナビ無し)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(overrides: await _overrides()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // 一般設定へ push: 戻る矢印が付き、下部ナビは画面外 (offstage)。
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('TEMPERATURE UNIT'), findsOneWidget);
    expect(find.byKey(kQuietBackKey), findsOneWidget);
    expect(find.byType(QuietNavBar), findsNothing);

    // 戻ると設定タブ (下部ナビあり) に復帰する。
    await tester.tap(find.byKey(kQuietBackKey));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byType(QuietNavBar), findsOneWidget);
    expect(find.byKey(kQuietBackKey), findsNothing);
  });
}
