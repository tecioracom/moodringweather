// test/widget/calibration_page_test.dart
//
// Calibration 3 画面 (学習モード Home / フィードバック Tag / 体感プロファイル)
// のスモーク + フィードバック → θ 更新 → 永続化の検証。
// SharedPreferences と天気 provider はモックで注入する。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_feedback_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_profile_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

Widget _app({required List<Override> overrides, required Widget home}) {
  return ProviderScope(
    overrides: overrides,
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

Future<SharedPreferences> _mockPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

WeatherSnapshot _snapshot({DateTime? timestamp, double temperature = 30}) =>
    WeatherSnapshot(
      timestamp: timestamp ?? DateTime.now(),
      latitude: 35.66,
      longitude: 139.70,
      temperature: temperature,
      apparentTemperature: temperature,
      humidity: 70,
      pressure: 1010,
      pressureChange6h: 0,
      windSpeed: 1,
      uvIndex: 6,
      aqi: 50,
      pollen: null,
      condition: 'sunny',
    );

List<WeatherSnapshot> _hourly() {
  final base = DateTime.now();
  return [
    for (var i = 0; i < 24; i++)
      _snapshot(timestamp: base.add(Duration(hours: i - 6))),
  ];
}

List<Override> _overrides(SharedPreferences prefs) => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      weatherSnapshotProvider.overrideWith((ref) async => _snapshot()),
      hourlyWeatherProvider.overrideWith((ref) async => _hourly()),
      // 温度の単位の初期値は日本の端末 (°C) に固定する。
      unitRegionOverride(),
    ];

void main() {
  testWidgets('設定 > キャリブレーション で学習モード Home へ遷移する', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: _overrides(prefs),
      home: const SettingsPage(),
    ));

    await tester.tap(find.text('Calibration'));
    await tester.pumpAndSettle();

    // プレースホルダではなく実画面 (学習進度 + 件数 + 導線)
    expect(find.text('Coming soon'), findsNothing);
    // v1.3: mono の区画ラベルは大文字化される。
    expect(find.text('LEARNING PROGRESS'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 feedback entries'), findsOneWidget);
    expect(find.text('Record how it feels'), findsOneWidget);
    expect(find.text('Sensitivity profile'), findsOneWidget);
    expect(find.text('What we’ve learned'), findsOneWidget);
  });

  testWidgets('フィードバック記録 → θ 更新 + 永続化、同日 2 回目はガード', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: _overrides(prefs),
      home: const CalibrationFeedbackPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('How does the weather feel right now?'), findsOneWidget);
    expect(find.textContaining('Current MRI:'), findsOneWidget);

    await tester.tap(find.text('Too hot'));
    await tester.pumpAndSettle();
    expect(find.text('Thanks! Your profile has been updated.'), findsOneWidget);
    expect(prefs.getString(kPrefKeyPersonalProfile), isNotNull);
    expect(prefs.getString(kPrefKeyPersonalProfile), contains('"deltaT":-0.6'));

    // 同日・同方向の 2 件目は無効 (mri-spec §6.3-5)
    await tester.tap(find.text('A bit hot'));
    await tester.pumpAndSettle();
    expect(
      find.text('Already recorded for today. Please try again tomorrow.'),
      findsOneWidget,
    );
  });

  testWidgets('体感プロファイル: スライダー手動調整とリセット', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: _overrides(prefs),
      home: const CalibrationProfilePage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Manual adjustment'), findsOneWidget);
    expect(find.text('Preferred temperature shift'), findsOneWidget);
    expect(find.text('Heat sensitivity'), findsOneWidget);
    expect(find.text('Cold sensitivity'), findsOneWidget);
    expect(find.textContaining('comfort sweet spot'), findsOneWidget);

    // δT スライダーを右端 (+3.0) までドラッグ → 手動調整として永続化
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();
    // 差の表記はアプリの気温と同じ「+3.0°」(単位は設定で決まる)。
    expect(find.text('+3.0°'), findsOneWidget);
    expect(find.text('+3.0°C'), findsNothing);
    expect(prefs.getString(kPrefKeyPersonalProfile), contains('"deltaT":3.0'));
    expect(
      prefs.getString(kPrefKeyPersonalProfile),
      contains('"manualOverride":true'),
    );

    // リセット → 確認ダイアログ → 既定値へ戻りストレージからも消える
    await tester.tap(find.text('Reset learning data'));
    await tester.pumpAndSettle();
    expect(find.text('Reset learning data?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Learning data has been reset.'), findsOneWidget);
    expect(find.text('+0.0°'), findsOneWidget);
    expect(prefs.getString(kPrefKeyPersonalProfile), isNull);
  });

  testWidgets('体感プロファイル: °F では好みの温度の差を ×1.8 で出す (+1.5 → +2.7°)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs({
      kPrefKeyTemperatureUnit: 'fahrenheit',
      kPrefKeyPersonalProfile: '{"deltaT":1.5,"manualOverride":true}',
    });
    await tester.pumpWidget(_app(
      overrides: _overrides(prefs),
      home: const CalibrationProfilePage(),
    ));
    await tester.pumpAndSettle();
    // 差なので 32 は足さない (1.5 × 1.8 = 2.7)。
    expect(find.text('+2.7°'), findsOneWidget);
    expect(find.text('+1.5°'), findsNothing);

    // 右端 (+3.0 °C) までドラッグ → +5.4°。保存する値は °C のまま。
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('+5.4°'), findsOneWidget);
    expect(prefs.getString(kPrefKeyPersonalProfile), contains('"deltaT":3.0'));
  });

  testWidgets('体感プロファイル: 花粉のスライダーは出さない (β_pollen は保存のまま)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs({
      kPrefKeyPersonalProfile:
          '{"betaPollen":0.3,"manualOverride":true,"feedbackCount":0}',
    });
    final container = ProviderContainer(overrides: _overrides(prefs));
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: _app(overrides: const [], home: const CalibrationProfilePage()),
    ));
    await tester.pumpAndSettle();

    // δT・暑さ・寒さ・湿度・UV・空気質の 6 本。花粉は無い (compliance §8 A5)。
    expect(find.byType(Slider), findsNWidgets(6));
    expect(find.text('Pollen'), findsNothing);
    // 学習データ (β_pollen) は変えない。
    expect(container.read(personalProfileProvider).betaPollen, 0.3);
  });

  testWidgets('学習モード Home: 花粉の気づきは出さない (β_pollen が高くても)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pump(String profile) async {
      final prefs = await _mockPrefs({kPrefKeyPersonalProfile: profile});
      await tester.pumpWidget(_app(
        overrides: _overrides(prefs),
        home: const CalibrationHomePage(),
      ));
      await tester.pumpAndSettle();
    }

    // 花粉だけ高い → 気づきは無し (「まだデータが足りません」)。
    await pump('{"betaPollen":0.3,"manualOverride":true}');
    expect(find.text('Pollen affects your comfort.'), findsNothing);
    expect(find.textContaining('Not enough data yet'), findsOneWidget);

    // ほかの気づきはこれまでどおり出る。
    await tester.pumpWidget(const SizedBox());
    await pump('{"betaPollen":0.3,"betaUv":0.3,"manualOverride":true}');
    expect(find.text('Strong sunlight (UV) affects your comfort.'),
        findsOneWidget);
    expect(find.text('Pollen affects your comfort.'), findsNothing);
  });

  testWidgets('学習モード Home: 24h チャートが描画される', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: _overrides(prefs),
      home: const CalibrationHomePage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('24-hour MRI (personalized)'), findsOneWidget);
    // 未学習 (n=0) はランプイン案内
    expect(
      find.text('Personalization kicks in after 5 feedback entries.'),
      findsOneWidget,
    );
    expect(
      find.text('All learning data stays on this device.'),
      findsOneWidget,
    );
  });
}
