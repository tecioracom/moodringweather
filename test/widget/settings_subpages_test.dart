// test/widget/settings_subpages_test.dart
//
// 設定サブ画面 (MRIとは / 地点管理 / プライバシー / About) のスモークテスト。
//   - 表示: 主要セクション・免責・プレースホルダ (準備中) の表示
//   - 導線: 保存地点の削除、ライセンス画面 (showLicensePage) への遷移
// 位置・都市名 provider はモックし、実通信・プラグイン呼び出しは行わない。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/about_app_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_mri_page.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/core/constants/app_links.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart' show savedPlaceMriOverride;

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

void main() {
  testWidgets('MRIとは: 説明・バンド・構成要素・免責を表示する', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const AboutMriPage(),
    ));

    // v1.3: 見出しは Fraunces の "Mood Ring Index"、説明はリード文になった。
    expect(find.text('Mood Ring Index'), findsOneWidget);
    expect(find.textContaining('0–100 score'), findsOneWidget);
    // 5 帯 1 表の直下に置く注記 2 行 (指示書 §7.1)
    expect(find.textContaining('comfort sweet spot'), findsOneWidget);
    expect(find.textContaining('WBGT'), findsOneWidget);
    // バンド 5 区分 (mri-spec §4)
    expect(find.text('COOL'), findsOneWidget);
    expect(find.text('COMFORTABLE'), findsOneWidget);
    expect(find.text('SLIGHTLY HOT'), findsOneWidget);
    expect(find.text('HOT'), findsOneWidget);
    expect(find.text('VERY HOT — HYDRATE'), findsOneWidget);
    expect(find.text('80–100'), findsOneWidget);
    // 涼しい行の下の注記: 寒さの側は体感温度で「寒い / とても寒い」(band_label.dart)。
    // 温度の単位は地域の初期値 (テスト環境は en_US = °F) で変わるので、ここでは見ない。
    expect(
      find.textContaining(RegExp(
          r'^When the feels-like temperature is below -?\d+°, we show “Cold”; at -?\d+° or below, '
          r'“Very cold — bundle up”\. This is the app’s own guide, not an official alert\. '
          r'The color doesn’t change\.$')),
      findsOneWidget,
    );
    // 構成要素 6 チップ。花粉は出さない (データ未接続。compliance §8 A2)
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Wind'), findsOneWidget);
    expect(find.text('Pressure'), findsOneWidget);
    expect(find.text('Pollen'), findsNothing);
    // キャリブレーションと免責 (独自判定・医療ではない)
    expect(find.text('Personal calibration'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);
    expect(find.textContaining('independent estimate'), findsOneWidget);
  });

  testWidgets('MRIとは: 寒さの注記の温度は利用者の単位 (°C / °F) で出す', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs({'settings_temperature_unit': 'celsius'});
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const AboutMriPage(),
    ));
    expect(find.textContaining('is below 6°,'), findsOneWidget);
    expect(find.textContaining('at -10° or below'), findsOneWidget);

    await prefs.setString('settings_temperature_unit', 'fahrenheit');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const AboutMriPage(),
    ));

    // 6 °C = 42.8 °F → 43°、−10 °C = 14 °F
    expect(find.textContaining('is below 43°,'), findsOneWidget);
    expect(find.textContaining('at 14° or below'), findsOneWidget);
  });

  testWidgets('地点管理: 現在地・COARSE 注記・保存地点の一覧と削除', (tester) async {
    final saved = jsonEncode([
      {
        'id': 'place-lisbon',
        'type': 'place',
        'mri': 72,
        'savedAt': '2026-06-01T10:00:00.000',
        'label': 'Lisbon',
        'emoji': '🇵🇹',
      },
      {
        'id': 'day-1',
        'type': 'day',
        'mri': 64,
        'savedAt': '2026-06-02T10:00:00.000',
      },
    ]);
    final prefs = await _mockPrefs({kPrefKeyComfortRecords: saved});
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentLocationProvider
            .overrideWith((ref) async => const GeoPoint(35.681, 139.767)),
        cityNameProvider.overrideWith((ref) async => 'Tokyo'),
        // 行の MRI は保存地点の現在値 (実通信しないよう固定)。
        savedPlaceMriOverride(values: const {'place-lisbon': 72}),
      ],
      home: const LocationsPage(),
    ));
    await tester.pumpAndSettle();

    // 現在地 (COARSE) と注記 (A1〜A5: 「おおよその位置」+ 地名で追加できる)
    // v1.3: mono の区画ラベルは大文字化される。
    expect(find.text('CURRENT LOCATION'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.textContaining('approximate'), findsOneWidget);

    // 保存地点: place のみ一覧表示 (day 記録は出さない)。無料 (保存地点は Plus
    // 限定 = 上限 0) で残っている地点は消さず、件数は上限なしの「n saved」(A5)。
    // Figma A1〜A5: 行は地名だけ (絵文字なし)。MRI は現在値。
    expect(find.text('Lisbon'), findsOneWidget);
    expect(find.text('1 saved'), findsOneWidget);
    expect(find.textContaining('MRI 72'), findsOneWidget);
    expect(find.textContaining('MRI 64'), findsNothing);

    // 削除 → 一覧から消え、永続化からも消える。スナックバーで元に戻せる。
    // 無料で 0 件になると、空状態ではなく Plus カード (A1) を出す。
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Lisbon'), findsNothing);
    expect(find.textContaining('No saved places yet'), findsNothing);
    expect(find.textContaining('Add up to 5 places with Plus'), findsOneWidget);
    expect(prefs.getString(kPrefKeyComfortRecords), isNot(contains('Lisbon')));
    expect(find.text('Removed Lisbon.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Lisbon'), findsOneWidget);
    expect(prefs.getString(kPrefKeyComfortRecords), contains('place-lisbon'));
  });

  testWidgets('地点管理: フォールバック位置では注意書きを表示する', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentLocationProvider
            .overrideWith((ref) async => LocationDataSource.fallback),
        cityNameProvider.overrideWith((ref) async => null),
      ],
      home: const LocationsPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('default area'), findsOneWidget);
  });

  testWidgets('プライバシー: 4 つの要約とフルポリシー URL を表示する', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const PrivacyPage(),
    ));

    expect(find.text('Location, minimally'), findsOneWidget);
    expect(find.text('Comfort data stays on this device'), findsOneWidget);
    expect(find.text('No ads, no tracking'), findsOneWidget);
    expect(find.text('No account required'), findsOneWidget);
    // v1.3 (Figma 6:59): URL は出さず、行ごとタップで外部ブラウザへ開く。
    // 公開済み (AppLinks.privacyPolicyUrl) なので「準備中」バッジは出ない。
    expect(find.text('Full privacy policy'), findsOneWidget);
    expect(AppLinks.privacyPolicyUrl, isNotEmpty);
    expect(find.text('Coming soon'), findsNothing);
    // §4.2 C5: この画面は全面ニュートラル (行頭ドットは inkMid)。
    expect(find.byType(QuietDotCard), findsNWidgets(4));
  });

  testWidgets('About: バージョン・各導線・クレジットとライセンス画面遷移', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const AboutAppPage(),
    ));

    expect(find.text('Mood-Ring Weather'), findsOneWidget);
    expect(find.text('VERSION ${AppLinks.appVersion}'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    // 規約・プライバシーとも公開済み (2026-09-27) → 準備中バッジは出ない。サポートはメール表示
    expect(find.text('Coming soon'), findsNothing);
    expect(find.text(AppLinks.supportEmail), findsOneWidget);
    expect(find.textContaining('Open-Meteo'), findsOneWidget);

    // ライセンス (Flutter 標準画面) への遷移
    await tester.tap(find.text('Open source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('About: Privacy 行からプライバシー要約画面へ遷移する', (tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const AboutAppPage(),
    ));

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Location, minimally'), findsOneWidget);
  });
}
