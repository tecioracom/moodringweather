// test/store/store_shots_harness.dart
//
// App Store のスクリーンショット (iOS 1.3.0、6.9 インチ = 1320×2868 縦) を、
// 実際の画面ウィジェットから golden の仕組みで描き出す共通部分。
// シミュレーターは使わない。本番コード (lib/) は変えず、データだけ固定する。
//
// **既定では実行しない** (CI・通常の flutter test の対象外):
//
//   flutter test test/store --update-goldens --dart-define=MRW_STORE_SHOTS=true
//
// 出力: store-listings/ios-1.3.0/screenshots/6.9/{言語}_{番号}_{画面}.png
//   1 home        ホーム (Plus・保存地点 5 件・現在地を表示中・快適)
//   2 detail      詳細タブ (時間別 MRI のグラフ + 指標タイル)
//   3 calibration キャリブレーション (学習 12 件 = 60%)
//   4 twin        Comfort-Twin の検索結果 (同梱カタログ 69 都市)
//   5 paywall     Plus の Paywall (無料ユーザー・月額 / 年額・トライアル注記)
//
// 端末: iPhone 6.9 インチ (440×956 pt、DPR 3)。safe area は上 62 pt / 下 34 pt。
// テーマ: Dark (マーケティングの既定の見た目)。
//
// フォント: flutter_test はシステムフォントへのフォールバックを止めているため、
// 同梱フォントに無い字は豆腐 (□) になる。
//   - zh (簡体字): 端末では Plex Sans JP に無い字を PingFang SC へフォールバックして
//     描く。テストでは IBMPlexSansJP の名前で macOS の PingFang SC を読み込み、
//     CJK をすべて PingFang SC で描く (app_store_screenshots_zh_test.dart。同じ
//     プロセスで ja の Plex Sans JP と両立できないのでファイルを分ける)。
//   - 絵文字 (Comfort-Twin の国旗): 読み込める枠が無いので描かない (storeTwinCandidates)。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/regional_unit_defaults.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/personal_profile.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/comfort_twin/twin_matcher.dart';
import 'package:mood_ring_weather/domain/mri/mri_calculator.dart';
import 'package:mood_ring_weather/presentation/calibration/calibration_home_page.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_search_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

/// `--dart-define=MRW_STORE_SHOTS=true` のときだけ撮る。
const bool kStoreShotsEnabled = bool.fromEnvironment('MRW_STORE_SHOTS');

/// iPhone 6.9 インチ (1320×2868 px = 440×956 pt × 3)。
const Size kStorePhysicalSize = Size(1320, 2868);
const double kStorePixelRatio = 3.0;

/// safe area (物理ピクセル): ステータスバー + Dynamic Island 62 pt / ホームインジケーター 34 pt。
const FakeViewPadding kStoreSafeArea =
    FakeViewPadding(top: 62 * 3, bottom: 34 * 3);

/// 出力先 (このファイルのディレクトリ test/store/ からの相対)。
const String kStoreShotsDir = '../../store-listings/ios-1.3.0/screenshots/6.9';

const Brightness kStoreBrightness = Brightness.dark;

const Locale kStoreZh =
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

// ---------------------------------------------------------------------------
// フォント
// ---------------------------------------------------------------------------

/// 同梱フォントを読み込む。[simplifiedChinese] が true なら IBMPlexSansJP の代わりに
/// macOS の PingFang SC (Regular / Medium / Semibold) をその名前で読み込む。
Future<void> loadStoreFonts({required bool simplifiedChinese}) async {
  if (!simplifiedChinese) {
    await loadAppFonts();
    return;
  }
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (family == 'IBMPlexSansJP') continue;
    final loader = FontLoader(family);
    for (final font
        in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  final ttc = _findPingFang().readAsBytesSync();
  final loader = FontLoader('IBMPlexSansJP');
  for (final face in const [
    'PingFangSC-Regular',
    'PingFangSC-Medium',
    'PingFangSC-Semibold',
  ]) {
    loader.addFont(Future.value(extractTtcFace(ttc, face)));
  }
  await loader.load();
}

/// macOS の PingFang.ttc。古い macOS は /System/Library/Fonts、新しい macOS は
/// Font アセット (/System/Library/AssetsV2/com_apple_MobileAsset_Font*/…) にある。
File _findPingFang() {
  final legacy = File('/System/Library/Fonts/PingFang.ttc');
  if (legacy.existsSync()) return legacy;
  final assets = Directory('/System/Library/AssetsV2');
  if (assets.existsSync()) {
    for (final dir in assets.listSync().whereType<Directory>()) {
      if (!dir.path.contains('com_apple_MobileAsset_Font')) continue;
      try {
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (f.path.endsWith('/PingFang.ttc')) return f;
        }
      } on FileSystemException {
        // 読めないアセットは飛ばす。
      }
    }
  }
  throw StateError('PingFang.ttc が見つからない (zh の撮影は macOS が前提)');
}

/// TrueType / OpenType Collection (.ttc) から PostScript 名が [postScriptName] の
/// 1 書体を取り出し、単体の sfnt にする (FontLoader は .ttc の先頭の書体しか読まない)。
ByteData extractTtcFace(Uint8List ttc, String postScriptName) {
  final src = ByteData.sublistView(ttc);
  if (src.getUint32(0) != 0x74746366) {
    throw ArgumentError('ttcf ではない');
  }
  final numFonts = src.getUint32(8);
  for (var f = 0; f < numFonts; f++) {
    final dir = src.getUint32(12 + 4 * f);
    final numTables = src.getUint16(dir + 4);
    final tables = <(int tag, int checksum, int offset, int length)>[
      for (var t = 0; t < numTables; t++)
        (
          src.getUint32(dir + 12 + 16 * t),
          src.getUint32(dir + 12 + 16 * t + 4),
          src.getUint32(dir + 12 + 16 * t + 8),
          src.getUint32(dir + 12 + 16 * t + 12),
        ),
    ];
    final name = tables.where((t) => t.$1 == 0x6E616D65).firstOrNull; // 'name'
    if (name == null || _postScriptName(src, name.$3) != postScriptName) {
      continue;
    }
    // 単体の sfnt を組み立てる (表の中身はそのまま。オフセットだけ詰め直す)。
    final headerSize = 12 + 16 * numTables;
    var size = headerSize;
    for (final t in tables) {
      size += (t.$4 + 3) & ~3;
    }
    final out = Uint8List(size);
    final view = ByteData.sublistView(out);
    out.setRange(0, 12, ttc, dir);
    var offset = headerSize;
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      view
        ..setUint32(12 + 16 * i, t.$1)
        ..setUint32(12 + 16 * i + 4, t.$2)
        ..setUint32(12 + 16 * i + 8, offset)
        ..setUint32(12 + 16 * i + 12, t.$4);
      out.setRange(offset, offset + t.$4, ttc, t.$3);
      offset += (t.$4 + 3) & ~3;
    }
    return view;
  }
  throw ArgumentError('$postScriptName が .ttc に無い');
}

/// name 表の nameID 6 (PostScript 名)。
String? _postScriptName(ByteData src, int table) {
  final count = src.getUint16(table + 2);
  final strings = table + src.getUint16(table + 4);
  for (var r = 0; r < count; r++) {
    final rec = table + 6 + 12 * r;
    if (src.getUint16(rec + 6) != 6) continue;
    final platform = src.getUint16(rec);
    final length = src.getUint16(rec + 8);
    final start = strings + src.getUint16(rec + 10);
    if (platform == 0 || platform == 3) {
      return String.fromCharCodes([
        for (var i = 0; i < length; i += 2) src.getUint16(start + i),
      ]);
    }
    return String.fromCharCodes([
      for (var i = 0; i < length; i++) src.getUint8(start + i),
    ]);
  }
  return null;
}

// ---------------------------------------------------------------------------
// 固定データ
// ---------------------------------------------------------------------------

/// 言語ごとの見本。地名は各言語で検索したときの表記 (保存地点は検索した言語で保存される)。
class StoreLocaleData {
  const StoreLocaleData({
    required this.city,
    required this.places,
    required this.unitRegion,
    required this.monthly,
    required this.annual,
  });

  /// 現在地の地名 (逆ジオコーディングの表示名)。
  final String city;

  /// kFixturePlaces と同じ順 (那覇 / 京都 / 札幌 / リスボン / レイキャビク)。
  final List<String> places;

  /// 単位の初期値を決める端末の地域 (気温はどれも °C)。
  final UnitRegion unitRegion;

  /// Paywall の価格 (ストアの整形済み文字列。docs/pricing-decision.md §2 /
  /// pricing-localization.md §2)。
  final String monthly;
  final String annual;
}

StoreLocaleData storeLocaleData(Locale locale) {
  switch (locale.languageCode) {
    case 'ja':
      return const StoreLocaleData(
        city: '東京',
        places: ['那覇', '京都', '札幌', 'リスボン', 'レイキャビク'],
        unitRegion: UnitRegion(countryCode: 'JP', languageCode: 'ja'),
        monthly: '¥600',
        annual: '¥3,000',
      );
    case 'es':
      return const StoreLocaleData(
        city: 'Tokio',
        places: ['Naha', 'Kioto', 'Sapporo', 'Lisboa', 'Reikiavik'],
        unitRegion: UnitRegion(countryCode: 'ES', languageCode: 'es'),
        monthly: '5,99 €',
        annual: '29,99 €',
      );
    case 'zh':
      // 中国本土は配信対象外 (pricing-localization.md §6)。簡体字の在外圏 (米国等)
      // を想定して米ドル表記にする。
      return const StoreLocaleData(
        city: '东京',
        places: ['那霸', '京都', '札幌', '里斯本', '雷克雅未克'],
        unitRegion: UnitRegion(languageCode: 'zh'),
        monthly: r'$4.99',
        annual: r'$24.99',
      );
    default:
      return const StoreLocaleData(
        city: 'Tokyo',
        places: ['Naha', 'Kyoto', 'Sapporo', 'Lisbon', 'Reykjavik'],
        unitRegion: UnitRegion(languageCode: 'en'),
        monthly: r'$4.99',
        annual: r'$24.99',
      );
  }
}

/// 現在地の天気 (7 月の過ごしやすい日。昼 24° 前後・湿度 50% 台・UV 中程度)。
/// 時刻 [at] に応じて日変化する (時間別 MRI のグラフが平らにならないように)。
WeatherSnapshot pleasantSnapshot(DateTime at) {
  final h = at.hour + at.minute / 60;
  // 14 時に最高、2 時に最低。
  final phase = math.cos(2 * math.pi * (h - 14) / 24);
  final temperature = 21.0 + 3.0 * phase;
  final daylight = h >= 5 && h < 19;
  final uv = daylight ? 4.0 * math.sin(math.pi * (h - 5) / 14) : 0.0;
  return WeatherSnapshot(
    timestamp: at,
    latitude: 35.68,
    longitude: 139.77,
    temperature: double.parse(temperature.toStringAsFixed(1)),
    apparentTemperature: double.parse((temperature + 0.6).toStringAsFixed(1)),
    humidity: (62 - 10 * phase).roundToDouble(),
    pressure: 1014,
    pressureChange6h: 0,
    windSpeed: double.parse((2.6 + 0.8 * phase).toStringAsFixed(1)),
    uvIndex: uv.roundToDouble(),
    aqi: 34,
    condition: daylight ? 'sunny' : 'cloudy',
  );
}

/// キャリブレーションを 12 回記録したユーザー (学習 60%・θ を半分ほど適用中)。
/// 「涼しめが好き」「暑さに敏感」「湿気に敏感」の 3 つが「わかってきたこと」に出る。
const PersonalProfile kStoreProfile = PersonalProfile(
  deltaT: -0.9,
  lambdaHeat: 1.18,
  betaHumid: 0.14,
  mOpt: 66,
  feedbackCount: 12,
);

/// 保存地点 5 件の記録 JSON (地名は [names]。追加順は kFixturePlaces の順)。
String _savedPlacesJson(List<String> names) {
  return jsonEncode([
    // 記録は新しい順に保存される → 逆順に並べる。
    for (var i = kFixturePlaces.length - 1; i >= 0; i--)
      {
        'id': kFixturePlaces[i].id,
        'type': 'place',
        'mri': null,
        'savedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
        'label': names[i],
        'location': {
          'lat': kFixturePlaces[i].lat,
          'lon': kFixturePlaces[i].lon
        },
        'addedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
      },
  ]);
}

/// Comfort-Twin の候補: 同梱カタログ (assets/cities.json) の全都市に、緯度から
/// 決めた 7 月らしい天気を与え、本番と同じ MriCalculator (θ 適用) で MRI を出す。
List<CityComfort> storeTwinCandidates() {
  final raw = jsonDecode(File('assets/cities.json').readAsStringSync())
      as List<dynamic>;
  return [
    for (final json in raw.cast<Map<String, dynamic>>())
      () {
        // 国旗の絵文字は描けない (ファイル冒頭の注記)。結果の行の見出しは
        // 「{絵文字} {都市名}」なので、絵文字を空にすると都市名の前に空白が残り、
        // 下の国名と左端がずれる。都市名を絵文字の欄に入れて「{都市名} 」にする
        // (末尾の空白は見えない。同点の並びは都市名ではなく ID の順になる)。
        final city =
            City.fromJson({...json, 'emoji': json['name'], 'name': ''});
        final snapshot = _cityWeather(city);
        return CityComfort(
          city: city,
          snapshot: snapshot,
          mri: MriCalculator.calculate(snapshot, profile: kStoreProfile),
        );
      }(),
  ];
}

WeatherSnapshot _cityWeather(City c) {
  // 都市 ID から決まる 0〜1 の揺らぎ (実行ごとに変わらない)。
  var seed = 17;
  for (final unit in c.id.codeUnits) {
    seed = (seed * 31 + unit) & 0x7fffffff;
  }
  double wobble(int salt) => ((seed ~/ (salt * 7 + 1)) % 1000) / 1000;

  final lat = c.latitude;
  // 北半球は夏 (北緯 20° 付近が最も暑い)、南半球は冬。
  final base = lat >= 0 ? 32 - 0.32 * (lat - 20).abs() : 24 - 0.42 * lat.abs();
  final temperature = base + (wobble(1) - 0.5) * 6;
  final humidity = 35 + wobble(2) * 50;
  return WeatherSnapshot(
    timestamp: kGoldenNow,
    latitude: c.latitude,
    longitude: c.longitude,
    temperature: double.parse(temperature.toStringAsFixed(1)),
    apparentTemperature: double.parse(temperature.toStringAsFixed(1)),
    humidity: humidity.roundToDouble(),
    pressure: 1012,
    pressureChange6h: 0,
    windSpeed: double.parse((1 + wobble(3) * 5).toStringAsFixed(1)),
    uvIndex: (2 + wobble(6) * 7).roundToDouble(),
    aqi: (15 + wobble(4) * 75).round(),
    condition: wobble(5) > 0.5 ? 'sunny' : 'cloudy',
  );
}

/// Paywall の課金ゲートウェイ (無料ユーザー・月額 / 年額とも 7 日トライアル付き)。
class StoreBillingGateway implements BillingGateway {
  StoreBillingGateway(this.data);

  final StoreLocaleData data;
  final _controller = StreamController<EntitlementState>.broadcast();

  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;
  @override
  Future<List<PlusPackage>> fetchPackages() async => [
        PlusPackage(
          packageId: r'$rc_monthly',
          period: PlusBillingPeriod.monthly,
          priceString: data.monthly,
          productIdentifier: 'mrw.plus.monthly',
          hasIntroOffer: true,
        ),
        PlusPackage(
          packageId: r'$rc_annual',
          period: PlusBillingPeriod.annual,
          priceString: data.annual,
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

/// 画面共通の override (prefs・時計・現在地の天気・保存地点・学習・Twin 候補)。
/// 構成は saved_places_fixtures.dart の placesBaseOverrides と同じで、天気・地名・
/// 単位の地域・記録だけを差し替える。
Future<List<Override>> storeOverrides(Locale locale,
    {required bool plus}) async {
  final data = storeLocaleData(locale);
  SharedPreferences.setMockInitialValues({
    kPrefKeyComfortRecords: _savedPlacesJson(data.places),
    kPrefKeyPersonalProfile: jsonEncode(kStoreProfile.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kPlacesNow),
    cityCatalogProvider.overrideWith((ref) async => const <City>[]),
    currentLocationProvider
        .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
    weatherSnapshotProvider
        .overrideWith((ref) async => pleasantSnapshot(kPlacesNow)),
    hourlyWeatherProvider
        .overrideWith((ref) async => hourlyAround(pleasantSnapshot)),
    cityNameProvider.overrideWith((ref) async => data.city),
    unitRegionProvider.overrideWithValue(data.unitRegion),
    twinCandidatesProvider.overrideWith((ref) async => storeTwinCandidates()),
    ...entitlementOverrides(plus: plus),
    ...savedPlaceWeatherOverrides(),
  ];
}

// ---------------------------------------------------------------------------
// 撮影
// ---------------------------------------------------------------------------

void _useStoreViewport(WidgetTester tester) {
  tester.view.physicalSize = kStorePhysicalSize;
  tester.view.devicePixelRatio = kStorePixelRatio;
  tester.view.padding = kStoreSafeArea;
  tester.view.viewPadding = kStoreSafeArea;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Locale locale, {
  required Widget home,
  required List<Override> overrides,
}) async {
  _useStoreViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: home,
    brightness: kStoreBrightness,
    locale: locale,
    overrides: overrides,
  ));
  await settle(tester);
}

Future<void> _expectShot(
    WidgetTester tester, Locale locale, String name) async {
  // 溢れ (RenderFlex overflow 等) があれば撮らずに失敗させる。
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$kStoreShotsDir/${locale.languageCode}_$name.png'),
  );
}

/// [locales] の 5 画面を撮るテストを登録する。
void defineStoreShots(List<Locale> locales) {
  const skip = !kStoreShotsEnabled;

  for (final locale in locales) {
    final lang = locale.languageCode;

    testWidgets('$lang 1 home', skip: skip, (tester) async {
      await _pump(tester, locale,
          home: const MainShell(),
          overrides: await storeOverrides(locale, plus: true));
      await _expectShot(tester, locale, '1_home');
    });

    testWidgets('$lang 2 detail', skip: skip, (tester) async {
      await _pump(tester, locale,
          home: const MainShell(),
          overrides: await storeOverrides(locale, plus: true));
      await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
      await settle(tester);
      await _expectShot(tester, locale, '2_detail');
    });

    testWidgets('$lang 3 calibration', skip: skip, (tester) async {
      await _pump(tester, locale,
          home: const CalibrationHomePage(),
          overrides: await storeOverrides(locale, plus: true));
      await _expectShot(tester, locale, '3_calibration');
    });

    testWidgets('$lang 4 twin', skip: skip, (tester) async {
      await _pump(tester, locale,
          home: const TwinSearchPage(),
          overrides: await storeOverrides(locale, plus: true));
      // 「世界中から探す」→ 結果 (ターゲット = 現在の体感)。
      await tester.tap(find.byType(QuietPrimaryButton));
      await settle(tester);
      await _expectShot(tester, locale, '4_twin');
    });

    testWidgets('$lang 5 paywall', skip: skip, (tester) async {
      await _pump(tester, locale, home: const PaywallPage(), overrides: [
        ...await storeOverrides(locale, plus: false),
        billingGatewayProvider
            .overrideWithValue(StoreBillingGateway(storeLocaleData(locale))),
      ]);
      await _expectShot(tester, locale, '5_paywall');
    });
  }
}
