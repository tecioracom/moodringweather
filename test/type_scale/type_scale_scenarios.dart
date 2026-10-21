// test/type_scale/type_scale_scenarios.dart
//
// 型スケール (現状 / 案1 / 案2) の比較・溢れ検出・計測で共用する画面の組み立て。
// golden と同じ固定データ (golden_harness.dart / saved_places_fixtures.dart) で、
// 実行時刻・ネットワークに依存しない。
//
//   ホーム保存なし 保存 0 件・無料 (Figma E1)
//   ホーム現在地   Plus 5 地点・現在地を表示中 (Figma E3)
//   ホーム保存地点 Plus 5 地点・那覇を表示中 (Figma E4)
//   詳細           ホーム現在地から下部ナビで詳細へ
//   設定トップ     ホーム現在地から下部ナビで設定へ
//   設定地点       設定 › 地点 (A3: Plus 4 / 5)
//   設定地点無料0件 設定 › 地点 (A1: 無料 0 件。保存地点は Plus 限定で、件数を出さず
//                  Plus カードだけ)
//   設定地点無料1件 設定 › 地点 (A5: 無料で 1 件残っている。無料 1 件の時期に保存)
//   設定通知       設定 › 通知
//   一般設定       設定 › 一般
//   Paywall / CalibrationHome / TwinSearch
//   地点追加シート B1 (「京都」/「Kyoto」の候補あり)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_feedback_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_profile_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_compare_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_map_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_search_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/about_app_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_mri_page.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/notification_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/plus_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

/// iPhone 相当の safe area (上 47 / 下 34)。「1 画面に収まるか」の計測に使う。
const FakeViewPadding kPhoneSafeArea = FakeViewPadding(top: 47, bottom: 34);

/// 1 つの描画条件 (画面は別に選ぶ)。
class TypeScaleCase {
  const TypeScaleCase({
    required this.brightness,
    required this.locale,
    required this.typeScale,
    this.textScale = 1.0,
    this.viewport = kGoldenSize,
    this.safeArea,
    this.condition,
    this.temperature,
    this.unit,
    this.uvIndex,
    this.aqi,
    this.windSpeed,
    this.humidity,
    this.windUnit,
  });

  final Brightness brightness;
  final Locale locale;
  final MrwTypeScale typeScale;
  final double textScale;
  final Size viewport;

  /// 端末の safe area (null は golden と同じ 0)。
  final FakeViewPadding? safeArea;

  /// ホームの現在地の概況 ('sunny' 等。null は固定データのまま)。
  final String? condition;

  /// ホームの現在地の気温 (摂氏。null は固定データの 22°)。
  final double? temperature;

  /// 温度単位の設定 (null は既定の摂氏)。
  final TemperatureUnit? unit;

  /// ホームの現在地の UV・US AQI・風速 (m/s)・湿度 (null は固定データのまま)。
  /// 指標タイルの段階語・単位の最長の組み合わせを見るのに使う。
  final double? uvIndex;
  final int? aqi;
  final double? windSpeed;
  final double? humidity;

  /// 風速の単位の設定 (null は既定 = 日本の端末の m/s)。
  final WindSpeedUnit? windUnit;

  /// 現在地のスナップショットを固定データから変えるか。
  bool get tweaksCurrent =>
      condition != null ||
      temperature != null ||
      uvIndex != null ||
      aqi != null ||
      windSpeed != null ||
      humidity != null;

  bool get ja => locale.languageCode == 'ja';
}

bool _isCjk(int c) =>
    (c >= 0x2E80 && c <= 0x9FFF) ||
    (c >= 0xAC00 && c <= 0xD7AF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFF00 && c <= 0xFFEF);

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWordChar(String ch) =>
    ch.isNotEmpty && !_isCjk(ch.codeUnitAt(0)) && _wordChar.hasMatch(ch);

/// 画面内の段落で、語の途中 (英数字どうしの間) で折れている箇所の一覧。
/// 「TEMPERATUR / A」や、棒 1 本ぶんの枠で「1 / 2」と 1 文字ずつ折れる時刻を拾う。
/// CJK どうし・空白・ハイフン・改行 (\n) での折り返しは対象外。
/// 返り値は「段落の全文|前の文字/次の文字」。
List<String> midWordBreaks() {
  final found = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final p = element.renderObject;
    if (p is! RenderParagraph || !p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText(includeSemanticsLabels: false);
    if (text.length < 2) continue;
    // 行頭はキャレットの y が前の文字より下がる位置 (折り返し位置の下流側は次の行)。
    var previousY =
        p.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero).dy;
    for (var i = 1; i < text.length; i++) {
      final y = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
      if (y > previousY + 0.5) {
        final prev = text.substring(i - 1, i);
        final next = text.substring(i, i + 1);
        if (_isWordChar(prev) && _isWordChar(next)) {
          found.add('${text.replaceAll('\n', ' ')}|$prev/$next');
        }
      }
      previousY = y;
    }
  }
  return found;
}

/// 画面を組み立てて落ち着くまで進める関数。
typedef ScenarioPump = Future<void> Function(
  WidgetTester tester,
  TypeScaleCase c,
);

/// 画面の一覧 (名前 → 組み立て)。名前は出力ファイル名にも使う。
final Map<String, ScenarioPump> kTypeScaleScenarios = {
  'ホーム保存なし': _pumpShellEmpty,
  'ホーム現在地': (t, c) => _pumpShell(t, c),
  'ホーム保存地点': (t, c) => _pumpShell(t, c, select: kNahaId),
  '詳細': (t, c) => _pumpShell(t, c, tab: 1),
  '設定トップ': (t, c) => _pumpShell(t, c, tab: 2),
  '設定地点': _pumpLocationsA3,
  '設定地点無料0件': (t, c) => _pumpLocationsFree(t, c, saved: 0),
  '設定地点無料1件': (t, c) => _pumpLocationsFree(t, c, saved: 1),
  '設定通知': (t, c) => _pumpSettingsPage(t, c, const NotificationSettingsPage()),
  '一般設定': (t, c) => _pumpSettingsPage(t, c, const GeneralSettingsPage()),
  'Paywall': _pumpPaywall,
  'CalibrationHome': (t, c) =>
      _pumpSettingsPage(t, c, const CalibrationHomePage()),
  'TwinSearch': (t, c) => _pumpSettingsPage(t, c, const TwinSearchPage()),
  '地点追加シート': _pumpAddPlaceB1,
};

/// 文字倍率テストの 14 画面 (settings_v13_test / calibration_twin_v13_test と同じ)。
final Map<String, Widget Function()> kOverflowSettingsScreens = {
  '設定 Top': () => const SettingsPage(),
  '一般': () => const GeneralSettingsPage(),
  '通知': () => const NotificationSettingsPage(),
  '地点': () => const LocationsPage(),
  'About MRI': () => const AboutMriPage(),
  'About App': () => const AboutAppPage(),
  'Privacy': () => const PrivacyPage(),
  'Plus': () => const PlusSettingsPage(),
  'Calibration 学習': () => const CalibrationHomePage(),
  'Calibration 記録': () => const CalibrationFeedbackPage(),
  'Calibration プロファイル': () => const CalibrationProfilePage(),
  'Twin 検索': () => const TwinSearchPage(),
  'Twin マップ': () => const TwinMapPage(targetMri: 64),
  'Twin 比較': () => TwinComparePage(other: twinCandidates().first),
};

String _city(TypeScaleCase c) => c.ja ? '東京' : 'Tokyo';

void _useViewport(WidgetTester tester, TypeScaleCase c) {
  tester.view.physicalSize = c.viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final safeArea = c.safeArea;
  if (safeArea != null) {
    tester.view.padding = safeArea;
    tester.view.viewPadding = safeArea;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  TypeScaleCase c, {
  required Widget home,
  required List<Override> overrides,
}) async {
  _useViewport(tester, c);
  await tester.pumpWidget(goldenApp(
    home: home,
    brightness: c.brightness,
    locale: c.locale,
    overrides: overrides,
    typeScale: c.typeScale,
    textScale: c.textScale,
  ));
  await settle(tester);
}

/// ホーム (Plus 5 地点)。[select] で保存地点を表示、[tab] で下部ナビを切り替える。
Future<void> _pumpShell(
  WidgetTester tester,
  TypeScaleCase c, {
  String? select,
  int tab = 0,
}) async {
  final overrides = [
    ...await placesBaseOverrides(
      savedCount: 5,
      locale: c.locale,
      city: _city(c),
      current: !c.tweaksCurrent
          ? null
          : (at) => comfortableSnapshot(at).copyWith(
                condition: c.condition,
                temperature: c.temperature,
                uvIndex: c.uvIndex,
                aqi: c.aqi,
                windSpeed: c.windSpeed,
                humidity: c.humidity,
              ),
    ),
    ...entitlementOverrides(plus: true),
    ...savedPlaceWeatherOverrides(),
  ];
  // 温度・風速の単位は設定 (SharedPreferences) から読まれるので、組み立て前に書いておく。
  final unit = c.unit;
  final windUnit = c.windUnit;
  if (unit != null || windUnit != null) {
    final prefs = await SharedPreferences.getInstance();
    if (unit != null) {
      await prefs.setString(kPrefKeyTemperatureUnit, unit.toTag());
    }
    if (windUnit != null) {
      await prefs.setString(kPrefKeyWindSpeedUnit, windUnit.toTag());
    }
  }
  await _pumpApp(tester, c, home: const MainShell(), overrides: overrides);
  if (select != null) {
    ProviderScope.containerOf(tester.element(find.byType(MainShell)))
        .read(selectedPlaceIdProvider.notifier)
        .select(select);
    await settle(tester);
  }
  if (tab != 0) {
    await tester.tap(find.byKey(ValueKey('quiet-nav-$tab')));
    await settle(tester);
  }
}

/// ホーム (保存 0 件・無料。タブ列は「現在地 | ＋ 地点を追加…」)。
Future<void> _pumpShellEmpty(WidgetTester tester, TypeScaleCase c) async {
  await _pumpApp(
    tester,
    c,
    home: const MainShell(),
    overrides: [
      ...await placesBaseOverrides(locale: c.locale, city: _city(c)),
      ...entitlementOverrides(plus: false),
      ...savedPlaceWeatherOverrides(),
    ],
  );
}

Future<void> _pumpLocationsA3(WidgetTester tester, TypeScaleCase c) async {
  await _pumpApp(
    tester,
    c,
    home: const LocationsPage(),
    overrides: [
      ...await placesBaseOverrides(
        savedCount: 4,
        locale: c.locale,
        city: _city(c),
      ),
      ...entitlementOverrides(plus: true),
      currentLocationProvider.overrideWith(
        (ref) async => const GeoPoint(35.68, 139.77),
      ),
      savedPlaceMriOverride(),
    ],
  );
}

/// 設定 › 地点 (無料。保存地点は Plus 限定 = 上限 0)。[saved] = 0 は A1、1 以上は
/// 地点が残っている A5 (Plus 解約後・無料 1 件の時期に保存した地点)。
Future<void> _pumpLocationsFree(
  WidgetTester tester,
  TypeScaleCase c, {
  required int saved,
}) async {
  await _pumpApp(
    tester,
    c,
    home: const LocationsPage(),
    overrides: [
      ...await placesBaseOverrides(
        savedCount: saved,
        locale: c.locale,
        city: _city(c),
      ),
      ...entitlementOverrides(plus: false),
      currentLocationProvider.overrideWith(
        (ref) async => const GeoPoint(35.68, 139.77),
      ),
      savedPlaceMriOverride(),
    ],
  );
}

/// 設定サブ画面 (settings_golden_test と同じ固定データ)。
Future<void> _pumpSettingsPage(
  WidgetTester tester,
  TypeScaleCase c,
  Widget page,
) async {
  await _pumpApp(tester, c, home: page, overrides: await settingsOverrides());
}

Future<void> _pumpPaywall(WidgetTester tester, TypeScaleCase c) async {
  await _pumpApp(
    tester,
    c,
    home: const PaywallPage(),
    overrides: [
      ...await goldenOverrides(),
      billingGatewayProvider.overrideWithValue(PreviewBillingGateway()),
    ],
  );
}

Future<void> _pumpAddPlaceB1(WidgetTester tester, TypeScaleCase c) async {
  final query = c.ja ? '京都' : 'Kyoto';
  final kyoto = fixtureCandidate(
    kFixturePlaces[1],
    c.locale,
    admin1: c.ja ? '京都府' : 'Kyoto',
  );
  await _pumpApp(
    tester,
    c,
    home: const MainShell(),
    overrides: [
      ...await placesBaseOverrides(
        savedCount: 1,
        locale: c.locale,
        city: _city(c),
      ),
      ...entitlementOverrides(plus: true),
      ...savedPlaceWeatherOverrides(),
      placeSearchOverride({
        query: [kyoto]
      }),
    ],
  );
  await tester.tap(find.byKey(kPlaceTabAddKey));
  await settle(tester);
  await tester.enterText(find.byKey(kAddPlaceFieldKey), query);
  await settle(tester);
}

// ── 設定サブ画面の固定データ (settings_golden_test.dart と同じ) ─────────────

final String _savedRecords = jsonEncode([
  {
    'id': 'place-lisbon',
    'type': 'place',
    'mri': 72,
    'savedAt': '2026-06-01T10:00:00.000',
    'label': 'Lisbon',
    'emoji': '🇵🇹',
  },
]);

CityComfort _candidate({
  required String id,
  required String name,
  required int mri,
  required double temperature,
  required double latitude,
  required double longitude,
}) {
  return CityComfort(
    city: City(
      id: id,
      name: name,
      country: 'Testland',
      latitude: latitude,
      longitude: longitude,
      emoji: '🌍',
    ),
    snapshot: WeatherSnapshot(
      timestamp: kGoldenNow,
      latitude: latitude,
      longitude: longitude,
      temperature: temperature,
      humidity: 62,
      pressure: 1009,
      windSpeed: 4.6,
      uvIndex: 5,
      condition: 'cloudy',
    ),
    mri: MoodRingIndex(
      value: mri,
      band: MriBand.fromValue(mri),
      factorContributions: const {},
      calculatedAt: kGoldenNow,
    ),
  );
}

List<CityComfort> twinCandidates() => [
      _candidate(
          id: 'vancouver',
          name: 'Vancouver',
          mri: 65,
          temperature: 22.2,
          latitude: 49.28,
          longitude: -123.12),
      _candidate(
          id: 'sanfrancisco',
          name: 'San Francisco',
          mri: 62,
          temperature: 19.4,
          latitude: 37.77,
          longitude: -122.42),
      _candidate(
          id: 'lisbon',
          name: 'Lisbon',
          mri: 60,
          temperature: 24.1,
          latitude: 38.72,
          longitude: -9.14),
    ];

/// 設定サブ画面・Calibration・Comfort-Twin の固定データ。
Future<List<Override>> settingsOverrides() async {
  // goldenOverrides() は中で setMockInitialValues({}) を呼ぶので、その後に
  // 記録入りの prefs を差し込む (順序を逆にすると空になる)。
  final base = await goldenOverrides();
  SharedPreferences.setMockInitialValues({
    kPrefKeyComfortRecords: _savedRecords,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    ...base.skip(1),
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentLocationProvider
        .overrideWith((ref) async => const GeoPoint(35.681, 139.767)),
    twinCandidatesProvider.overrideWith((ref) async => twinCandidates()),
    savedPlaceMriOverride(values: const {'place-lisbon': 72}),
  ];
}

/// Paywall の課金ゲートウェイ (paywall_golden_test と同じ 2 プラン)。
class PreviewBillingGateway implements BillingGateway {
  final _controller = StreamController<EntitlementState>.broadcast();
  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;
  @override
  Future<List<PlusPackage>> fetchPackages() async => const [
        PlusPackage(
          packageId: r'$rc_monthly',
          period: PlusBillingPeriod.monthly,
          priceString: '¥600',
          productIdentifier: 'mrw.plus.monthly',
          hasIntroOffer: true,
        ),
        PlusPackage(
          packageId: r'$rc_annual',
          period: PlusBillingPeriod.annual,
          priceString: '¥3,000',
          productIdentifier: 'mrw.plus.yearly',
          hasIntroOffer: true,
        ),
      ];
  @override
  Future<PurchaseResult> purchase(String packageId) async =>
      const PurchaseResult(PurchaseStatus.cancelled);
  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.error);
  @override
  Future<bool> openManageSubscriptions() async => true;
  @override
  Future<void> dispose() async => _controller.close();
}
