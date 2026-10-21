// test/widget/settings_page_test.dart
//
// Settings (Top / 一般 / 通知) のスモークテスト + 温度単位が Home に
// 実反映されることの検証。SharedPreferences はモックで注入する。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/regional_unit_defaults.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';

Widget _app({
  required List<Override> overrides,
  required Widget home,
  UnitRegion region = kTestUnitRegionJp,
}) {
  return ProviderScope(
    // 単位の初期値は端末の地域で決まる (既定は日本の端末 = °C・m/s)。
    overrides: [...overrides, unitRegionOverride(region)],
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

WeatherSnapshot _snapshot() => WeatherSnapshot(
      timestamp: DateTime.now(),
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

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// セグメント [label] が選択中か (QuietSegmented の Semantics.selected)。
bool _isSelected(WidgetTester tester, String label) {
  final semantics = tester.widget<Semantics>(find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected != null,
        ),
      )
      .first);
  return semantics.properties.selected!;
}

void main() {
  testWidgets('Settings Top はゲストプロフィールと全メニューを表示する', (tester) async {
    // グラスカード化でメニューが縦に伸びたため、全件が組み立てられる高さにする。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('About MRI'), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text('Locations'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('Privacy をタップすると本実装のプライバシー要約画面へ遷移する', (tester) async {
    // グラスカード化でメニューが縦に伸びたため、全件が組み立てられる高さにする。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Location, minimally'), findsOneWidget);
    expect(find.text('No ads, no tracking'), findsOneWidget);
  });

  testWidgets('一般: °F を選ぶと永続化される', (tester) async {
    // 風速の単位の区画が増えて、テーマは既定の 600px より下にくる。
    _useTallView(tester);
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    // v1.3: mono の区画ラベルは大文字化される (Home / Detail と同じ)。
    expect(find.text('TEMPERATURE UNIT'), findsOneWidget);
    expect(find.text('WIND SPEED UNIT'), findsOneWidget);
    expect(find.text('THEME'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsOneWidget);

    await tester.tap(find.text('°F'));
    await tester.pumpAndSettle();
    expect(prefs.getString(kPrefKeyTemperatureUnit), 'fahrenheit');
  });

  testWidgets('一般: 風速の単位は温度の単位の直下の 3 択 (m/s | km/h | mph) で、選ぶと永続化される',
      (tester) async {
    _useTallView(tester);
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const GeneralSettingsPage(),
    ));
    await tester.pumpAndSettle();

    // 並び: 温度の単位 → 風速の単位 → 言語。切替は m/s | km/h | mph の順で、
    // 記号は大文字にしない。
    final temperature = tester.getRect(find.text('TEMPERATURE UNIT'));
    final wind = tester.getRect(find.text('WIND SPEED UNIT'));
    final language = tester.getRect(find.text('LANGUAGE'));
    expect(wind.top, greaterThan(temperature.bottom));
    expect(language.top, greaterThan(wind.bottom));
    final xs = [
      for (final s in ['m/s', 'km/h', 'mph']) tester.getCenter(find.text(s)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    for (final s in ['m/s', 'km/h', 'mph']) {
      final y = tester.getCenter(find.text(s)).dy;
      expect(y, greaterThan(wind.bottom));
      expect(y, lessThan(language.top));
    }
    expect(find.text('M/S'), findsNothing);

    // 日本の端末の初期値は m/s。初期値は保存しない (まだ選んでいない)。
    expect(_isSelected(tester, 'm/s'), isTrue);
    expect(prefs.getString(kPrefKeyWindSpeedUnit), isNull);

    await tester.tap(find.text('mph'));
    await tester.pumpAndSettle();
    expect(prefs.getString(kPrefKeyWindSpeedUnit), 'milesPerHour');
    expect(_isSelected(tester, 'mph'), isTrue);
    expect(_isSelected(tester, 'm/s'), isFalse);

    await tester.tap(find.text('km/h'));
    await tester.pumpAndSettle();
    expect(prefs.getString(kPrefKeyWindSpeedUnit), 'kilometersPerHour');
    expect(_isSelected(tester, 'km/h'), isTrue);
  });

  for (final (region, temperature, wind) in const [
    (UnitRegion(countryCode: 'US', languageCode: 'en'), '°F', 'mph'),
    (UnitRegion(countryCode: 'GB', languageCode: 'en'), '°C', 'mph'),
    (UnitRegion(countryCode: 'ES', languageCode: 'es'), '°C', 'km/h'),
    (UnitRegion(countryCode: 'JP', languageCode: 'ja'), '°C', 'm/s'),
    (UnitRegion(languageCode: 'en'), '°C', 'km/h'),
  ]) {
    testWidgets('一般: 端末の地域 $region の初期値は $temperature・$wind', (tester) async {
      _useTallView(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const GeneralSettingsPage(),
        region: region,
      ));
      await tester.pumpAndSettle();
      expect(_isSelected(tester, temperature), isTrue);
      expect(_isSelected(tester, wind), isTrue);
      // 初期値は保存しない (地域が変われば初期値も変わる)。
      expect(prefs.getString(kPrefKeyTemperatureUnit), isNull);
      expect(prefs.getString(kPrefKeyWindSpeedUnit), isNull);
    });
  }

  for (final (locale, spoken, symbols) in const [
    (
      Locale('en'),
      [
        'Celsius',
        'Fahrenheit',
        'meters per second',
        'kilometers per hour',
        'miles per hour',
      ],
      ['°C', '°F', 'm/s', 'km/h', 'mph'],
    ),
    (
      Locale('ja'),
      ['摂氏', '華氏', 'メートル毎秒', 'キロメートル毎時', 'マイル毎時'],
      ['℃', '℉', 'm/s', 'km/h', 'mph'],
    ),
  ]) {
    testWidgets('一般 (${locale.languageCode}): 温度・風速の切替は記号ではなく読み方で読み上げる (QA-24)',
        (tester) async {
      _useTallView(tester);
      final semantics = tester.ensureSemantics();
      final prefs = await _mockPrefs();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          unitRegionOverride(),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ja')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GeneralSettingsPage(),
        ),
      ));
      await tester.pumpAndSettle();

      for (final label in spoken) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      // 記号そのものは読み上げに出さない (見た目の文字は記号のまま)。
      for (final symbol in symbols) {
        expect(find.bySemanticsLabel(symbol), findsNothing, reason: symbol);
        expect(find.text(symbol), findsOneWidget, reason: symbol);
      }
      // 選択中 (日本の端末の初期値 = 摂氏・m/s) も読める。
      expect(
        tester.getSemantics(find.bySemanticsLabel(spoken[0])),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(spoken[2])),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(spoken[4])),
        isSemantics(isSelected: false, isButton: true),
      );
      semantics.dispose();
    });
  }

  testWidgets('一般 (ja): 温度の単位の切替は「℃ / ℉」、風速の見出しは「風速の単位」', (tester) async {
    _useTallView(tester);
    final prefs = await _mockPrefs();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        unitRegionOverride(),
      ],
      child: const MaterialApp(
        locale: Locale('ja'),
        supportedLocales: [Locale('ja')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: GeneralSettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    // ja の書体の全角「°」で「° C」と割れるため 1 字の「℃」「℉」(§0-10)。
    expect(find.text('℃'), findsOneWidget);
    expect(find.text('℉'), findsOneWidget);
    expect(find.text('°C'), findsNothing);
    expect(find.text('風速の単位'), findsOneWidget);
    // 風速の記号は訳さない。
    for (final s in ['m/s', 'km/h', 'mph']) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('一般: テーマ Dark を選ぶと永続化される', (tester) async {
    // v1.3: 言語が 5 行のリストになり、テーマのセグメントは既定の 600px
    // ビューポートより下にくるため、画面を縦に伸ばして可視化する。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(prefs.getString(kPrefKeyThemeMode), 'dark');
  });

  testWidgets('通知: 緊急通知のカードだけを出し、配信の仕組みが無い設定は出さない (P1-5)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 以前の版で保存した通知設定 (天気の変化オフ・気圧急変オン・静音 23:30〜6:00・
    // 上限 5 件)。画面からは外すが、保存データは消さない。
    const saved = '{"weatherChangeEnabled":false,"personalEnabled":true,'
        '"personalToggles":{"pressure":true},'
        '"quietHours":{"start":"23:30","end":"06:00"},"dailyLimit":5}';
    final prefs = await _mockPrefs({kPrefKeyNotificationPrefs: saved});
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    // 設定 Top の副題は緊急通知の 3 種だけ (天気・パーソナルは言わない)。
    expect(find.text('Heatstroke, violent wind, heavy snow'), findsOneWidget);
    expect(find.text('Safety, weather and personal alerts'), findsNothing);

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency alerts'), findsOneWidget);
    expect(find.text('Always on · Free'), findsOneWidget);

    // 天気の変化・パーソナル通知 (マスター + 個別)・静音時間・1 日の上限は出さない
    // (compliance §8 N1〜N3)。
    for (final label in [
      'Weather changes',
      'Personal alerts',
      'Pressure drops',
      'Humidity spikes',
      'Air quality (PM2.5)',
      'Strong UV',
      'Pollen surges',
      'QUIET HOURS',
      'Start',
      'End',
      '23:30',
      '06:00',
      'DAILY LIMIT',
      '5 / day',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
    // 操作できるスイッチ・スライダーは 1 つも無い (緊急通知はオフにできない)。
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Slider), findsNothing);

    // 保存データはそのまま (将来戻せるように)。
    expect(prefs.getString(kPrefKeyNotificationPrefs), saved);
  });

  testWidgets('通知: 緊急通知は常時ON・無料の固定表示でトグル不可 (spec §12.2.1)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const SettingsPage(),
    ));

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    // 常時ON・無料バッジと、免責 (独自判定・公式警報ではない) の併記。
    expect(find.text('Always on · Free'), findsOneWidget);
    expect(
      find.textContaining('always delivered for free, on every plan. '
          'They cannot be turned off.'),
      findsOneWidget,
    );
    // 静音時間の設定が画面に無いので「静音時間も貫通」とは書かない (compliance §8-4-3)。
    expect(find.textContaining('quiet hours'), findsNothing);
    expect(
      find.textContaining('not an official government warning'),
      findsOneWidget,
    );

    // 緊急通知行にスイッチは存在しない (OFF にできない)。
    expect(
      find.widgetWithText(SwitchListTile, 'Emergency alerts'),
      findsNothing,
    );

    // タップしても設定値は変化しない (操作不可。永続化も発生しない)。
    await tester.tap(find.text('Emergency alerts'));
    await tester.pumpAndSettle();
    expect(prefs.getString(kPrefKeyNotificationPrefs), isNull);
  });

  for (final (tag, shown, symbol) in const [
    ('metersPerSecond', '2.0', 'm/s'),
    ('kilometersPerHour', '7', 'km/h'),
    ('milesPerHour', '4', 'mph'),
  ]) {
    testWidgets('Home: 風のタイルは風速の単位の設定に従う ($symbol)', (tester) async {
      _useTallView(tester);
      final prefs = await _mockPrefs({kPrefKeyWindSpeedUnit: tag});
      await tester.pumpWidget(_app(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          weatherSnapshotProvider.overrideWith((ref) async => _snapshot()),
          cityNameProvider.overrideWith((ref) async => 'Tokyo'),
        ],
        home: const MainShell(),
      ));
      await tester.pumpAndSettle();

      Finder value(String s) => find.byWidgetPredicate(
            (w) => w is Text && w.data == s && w.style?.fontSize == 18,
          );
      // 風 2 m/s → 2.0 m/s / 7 km/h / 4 mph。UV・空気質は段階語。
      expect(value(shown), findsOneWidget);
      expect(find.text(symbol), findsOneWidget);
      expect(value('3'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      expect(value('42'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('index'), findsNothing);
      expect(find.text('AQI'), findsNothing);
    });
  }

  testWidgets('一般: 「ライブ壁紙」はテーマの下。トグルは既定オンで、行でもスイッチでも切り替わり保存される',
      (tester) async {
    _useTallView(tester);
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const GeneralSettingsPage(),
    ));
    await tester.pumpAndSettle();

    // 区画ラベル (大文字) → トグル行 (見出し + 説明)。テーマの下、デバッグの区画の上。
    final theme = tester.getRect(find.text('THEME'));
    final section = tester.getRect(find.text('LIVE WALLPAPER'));
    final title = find.text('Show weather on wallpaper');
    expect(title, findsOneWidget);
    expect(find.text('At the top right of the live wallpaper'), findsOneWidget);
    expect(section.top, greaterThan(theme.bottom));
    expect(tester.getRect(title).top, greaterThan(section.bottom));
    // デバッグの区画 (テストは kDebugMode) はトグル行の下。
    final debug = find.text('[DEBUG] OVERRIDE PLUS STATE');
    expect(debug, findsOneWidget);
    expect(
        tester.getRect(debug).top, greaterThan(tester.getRect(title).bottom));

    Switch toggle() => tester.widget<Switch>(find.byType(Switch));
    expect(toggle().value, isTrue);
    expect(prefs.getBool(kPrefKeyWallpaperWeather), isNull); // 既定は保存しない

    await tester.tap(title); // 行のどこでも
    await tester.pumpAndSettle();
    expect(toggle().value, isFalse);
    expect(prefs.getBool(kPrefKeyWallpaperWeather), isFalse);

    await tester.tap(find.byType(Switch)); // スイッチでも
    await tester.pumpAndSettle();
    expect(toggle().value, isTrue);
    expect(prefs.getBool(kPrefKeyWallpaperWeather), isTrue);
  });

  testWidgets('一般: 保存済みのオフを表示する', (tester) async {
    _useTallView(tester);
    final prefs = await _mockPrefs({kPrefKeyWallpaperWeather: false});
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const GeneralSettingsPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('一般: iOS (ライブ壁紙なし) では「ライブ壁紙」の区画を出さない', (tester) async {
    _useTallView(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const GeneralSettingsPage(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('LIVE WALLPAPER'), findsNothing);
      expect(find.text('Show weather on wallpaper'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('THEME'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('一般 (ja): トグル行は 1 つにまとめて読み上げる (見出し・説明・スイッチ・オン)', (tester) async {
    _useTallView(tester);
    final semantics = tester.ensureSemantics();
    final prefs = await _mockPrefs();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        unitRegionOverride(),
      ],
      child: const MaterialApp(
        locale: Locale('ja'),
        supportedLocales: [Locale('ja')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: GeneralSettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ライブ壁紙'), findsOneWidget);
    final node = tester.getSemantics(find.text('壁紙に天気と気温を表示'));
    expect(node.label, contains('壁紙に天気と気温を表示'));
    expect(node.label, contains('ライブ壁紙の右上に表示します'));
    expect(
      node,
      isSemantics(
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('Home: 温度単位 °F が気温・体感表示に反映される (22°C → 72°)', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs({kPrefKeyTemperatureUnit: 'fahrenheit'});
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        weatherSnapshotProvider.overrideWith((ref) async => _snapshot()),
        cityNameProvider.overrideWith((ref) async => 'Tokyo'),
      ],
      home: const MainShell(),
    ));
    await tester.pumpAndSettle();

    // 22°C → 71.6 → 72° (ヘッダの大気温。天気レールにも同値が出うるため style で特定)
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == '72°' && w.style?.fontSize == 64,
      ),
      findsOneWidget,
    );
    // 体感は Figma v1.3 の mono ラベル (大文字化。Figma 24:6 の「FEELS nn°」)。
    expect(find.text('FEELS 72°'), findsOneWidget);
    // ボトムナビは 3 タブ (ホーム / 詳細 / 設定。MainShell が常時保持)
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
