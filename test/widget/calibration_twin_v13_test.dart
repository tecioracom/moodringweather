// test/widget/calibration_twin_v13_test.dart
//
// v1.3「Quiet Instrument」で作り直した Calibration / Comfort-Twin (S6) の回帰テスト。
//
// 中心は **状態色 (state/*) の個数**。`codex-fixes_v1.3_unified.md` §4.1 は
//   規則 1: 状態色が付くのは ①ゲージの弧 ②行頭の帯ドット ③MRI 数値テキスト だけ
//   規則 2: 1 画面あたり最大 6 個 (§4.4 の天気グリフは算定対象外)
// と定めている。ここではその 3 種を機械的に数えて上限内であることを固定する。
//   - 弧と head dot は CustomPaint なので MoodRingWidget 1 個 = 2 個として数える
//   - 帯ドットは BoxDecoration の色、MRI 数値は TextStyle の色で数える
//
// 文字倍率 2.0 の溢れ検出も併せて行う。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_feedback_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_profile_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_compare_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_map_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_search_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_world_map.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/shared/mood_ring_widget.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MrwTokens _tokens = MrwTokens.dark;

WeatherSnapshot _mySnapshot() => WeatherSnapshot(
      timestamp: DateTime(2026, 7, 15, 12),
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

CityComfort _candidate(String id, String name, int mri) => CityComfort(
      city: City(
        id: id,
        name: name,
        country: 'Testland',
        latitude: 48.86,
        longitude: 2.35,
        emoji: '🌍',
      ),
      snapshot: WeatherSnapshot(
        timestamp: DateTime(2026, 7, 15, 12),
        latitude: 48.86,
        longitude: 2.35,
        temperature: 25,
        humidity: 60,
        pressure: 1009,
        windSpeed: 5,
        uvIndex: 5,
        condition: 'cloudy',
      ),
      mri: MoodRingIndex(
        value: mri,
        band: MriBand.fromValue(mri),
        factorContributions: const {},
        calculatedAt: DateTime(2026, 7, 15, 12),
      ),
    );

List<CityComfort> _candidates() => [
      _candidate('paris', 'Paris', 64),
      _candidate('tokyo', 'Tokyo', 54),
      _candidate('sydney', 'Sydney', 84),
    ];

Widget _app({
  required List<Override> overrides,
  required Widget home,
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      supportedLocales: supportedFlutterLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.dark, locale: locale),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<SharedPreferences> _mockPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

List<Override> _overrides(SharedPreferences prefs) => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      weatherSnapshotProvider.overrideWith((ref) async => _mySnapshot()),
      cityNameProvider.overrideWith((ref) async => 'Tokyo'),
      hourlyWeatherProvider.overrideWith((ref) async => [
            for (var h = -6; h < 18; h++)
              WeatherSnapshot(
                timestamp: DateTime(2026, 7, 15, 12).add(Duration(hours: h)),
                latitude: 35.66,
                longitude: 139.70,
                temperature: 22,
                humidity: 50,
                pressure: 1013,
                windSpeed: 2,
                uvIndex: 3,
                condition: 'sunny',
              ),
          ]),
      twinCandidatesProvider.overrideWith((ref) async => _candidates()),
    ];

/// §4.1 規則 1 の 3 種を数える。
/// 弧 + head dot は CustomPaint なので MoodRingWidget 1 個につき 2 とみなす。
int countStateColored(WidgetTester tester) {
  final stateColors = <Color>{
    _tokens.stateCold,
    _tokens.stateCool,
    _tokens.stateFresh,
    _tokens.stateComfortable,
    _tokens.stateWarm,
    _tokens.stateHot,
    _tokens.stateDanger,
  };
  var count =
      tester.widgetList<MoodRingWidget>(find.byType(MoodRingWidget)).length * 2;
  for (final w in tester.widgetList<Container>(find.byType(Container))) {
    final d = w.decoration;
    if (d is BoxDecoration &&
        d.color != null &&
        stateColors.contains(d.color)) {
      count++;
    }
  }
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final c = w.style?.color;
    if (c != null && stateColors.contains(c)) count++;
  }
  return count;
}

void _useTallViewport(WidgetTester tester, {double height = 3600}) {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('状態色の個数 (§4.1 規則 2: 1 画面 6 個まで)', () {
    testWidgets('Calibration 学習 Home: リングだけ (2 個)', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(
        _app(overrides: _overrides(prefs), home: const CalibrationHomePage()),
      );
      await tester.pumpAndSettle();
      expect(countStateColored(tester), 2);
      // 24 時間のバーは無彩色 (帯色で塗らない)。
      final ring = tester.widget<MoodRingWidget>(find.byType(MoodRingWidget));
      expect(ring.colorValue, isFalse); // 中央の数値は主文字色
    });

    testWidgets('Calibration フィードバック: リングだけ (2 個)', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: _overrides(prefs),
        home: const CalibrationFeedbackPage(),
      ));
      await tester.pumpAndSettle();
      expect(countStateColored(tester), 2);
    });

    testWidgets('Calibration プロファイル: 最適 MRI の数値だけ (1 個)', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: _overrides(prefs),
        home: const CalibrationProfilePage(),
      ));
      await tester.pumpAndSettle();
      expect(countStateColored(tester), 1);
    });

    testWidgets('Twin 検索: 記録が無ければ 0 個 (ターゲット値は無彩色)', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(
        _app(overrides: _overrides(prefs), home: const TwinSearchPage()),
      );
      await tester.pumpAndSettle();
      expect(countStateColored(tester), 0);
    });

    testWidgets('Twin マップ: 行の値だけ (3 件 = 3 個)。地図はニュートラル', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: _overrides(prefs),
        home: const TwinMapPage(targetMri: 64),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(TwinWorldMap), findsOneWidget);
      expect(countStateColored(tester), 3);
    });

    testWidgets('Twin 比較: 弧 2 + head dot 2 + 数値 2 = 6 個 (上限ちょうど)',
        (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: _overrides(prefs),
        home: TwinComparePage(other: _candidates().first),
      ));
      await tester.pumpAndSettle();
      expect(countStateColored(tester), 6);
      for (final ring
          in tester.widgetList<MoodRingWidget>(find.byType(MoodRingWidget))) {
        expect(ring.colorValue, isTrue); // 数値も帯色 (Figma 5:227 / 5:234)
      }
    });
  });

  group('文字倍率 2.0', () {
    for (final locale in const [Locale('ja'), Locale('es')]) {
      for (final entry in <(String, Widget)>[
        ('Calibration 学習', const CalibrationHomePage()),
        ('Calibration 記録', const CalibrationFeedbackPage()),
        ('Calibration プロファイル', const CalibrationProfilePage()),
        ('Twin 検索', const TwinSearchPage()),
        ('Twin マップ', const TwinMapPage(targetMri: 64)),
      ]) {
        testWidgets('${entry.$1}: 溢れない (${locale.languageCode})',
            (tester) async {
          // 390 幅 (Figma と同寸) のまま縦だけ伸ばす。レイアウト溢れが 1 つでも
          // あれば flutter_test が例外を積む。
          tester.view.physicalSize = const Size(390, 8000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final prefs = await _mockPrefs();
          await tester.pumpWidget(_app(
            overrides: _overrides(prefs),
            home: entry.$2,
            textScale: 2.0,
            locale: locale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final locale in const [Locale('ja'), Locale('es')]) {
      testWidgets('Twin 比較: 溢れない (${locale.languageCode})', (tester) async {
        tester.view.physicalSize = const Size(390, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await _mockPrefs();
        await tester.pumpWidget(_app(
          overrides: _overrides(prefs),
          home: TwinComparePage(other: _candidates().first),
          textScale: 2.0,
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
