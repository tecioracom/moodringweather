// test/qa/saved_places_matrix_test.dart
//
// リリース候補 QA のレイアウト・マトリクス (保存地点リリース、2026-09-29)。
// **既定では実行しない** (1,600 ケース超で数分かかるため CI の対象外):
//
//   flutter test test/qa/saved_places_matrix_test.dart \
//     --dart-define=MRW_QA_MATRIX=true
//
// 軸: 言語 en / ja / es / zh × テーマ Dark / Light × 文字倍率 1.0 / 1.3 / 2.0 ×
//     幅 360 / 390 / 430 (高さ 780 / 844 / 932、safe area 上 47 / 下 34)。
// 画面: ホーム E1〜E7 (+ 長い地名)・詳細 (現在地 / 保存地点)・地点追加シート
//       B0 / B1 / B1b (同名 10 件) / B3 / B4・地点管理 A1〜A5・設定トップ・Paywall。
//       保存地点は Plus 限定 (無料 0 件、2026-09-30 ユーザー決裁) なので、E2 と A2 は
//       「無料で 1 件残っている」(無料 1 件の時期に保存) 状態、A1 は件数なし・Plus カード。
// 固定データは golden と同じ (golden_harness.dart / saved_places_fixtures.dart)。
//
// 検出するもの (1 行ずつ QA_MATRIX|種類|画面|言語|テーマ|倍率|幅|内容 で出力):
//   exception  溢れ (RenderFlex overflow 等) の例外         → 失敗
//   midword    語の途中で折れる段落 (倍率 1.0 / 1.3)       → 失敗 (2.0 は出力のみ)
//   overlap    同じ画面の 2 つの文字の字面が重なる          → 出力のみ
//   offscreen  文字の字面が画面の左右の外に出る            → 出力のみ
//   ellipsis   行数の上限で省略された文字 (…)              → 出力のみ
// 横スクロールの中 (地点タブ) は overlap / offscreen の対象外 (はみ出しが仕様)。
// overlap は横 = 字面、縦 = 段落のレイアウト枠で判定する。JA の気温「22°」の
// 全角「°」は字面の右半分が空きなので、気温行の overlap は画像で確かめる。
// 出力の集計は docs/qa-report-saved-places-2026-09-29.md §4。
//
// 画像も欲しいとき (条件を --name で絞る):
//   flutter test test/qa/saved_places_matrix_test.dart \
//     --dart-define=MRW_QA_MATRIX=true \
//     --dart-define=MRW_QA_SHOTS=/abs/path/to/dir \
//     --name 'home_E5_alert ja\|dark\|2\.0\|360'

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/detail/detail_page.dart';
import 'package:mood_ring_weather/presentation/home/home_page.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';
import '../type_scale/type_scale_scenarios.dart'
    show PreviewBillingGateway, kPhoneSafeArea, midWordBreaks;

const bool _run = bool.fromEnvironment('MRW_QA_MATRIX');

/// 画面の PNG を書き出す先 (空なら書き出さない)。
const String _shotsDir = String.fromEnvironment('MRW_QA_SHOTS');

const List<Locale> _locales = [
  Locale('en'),
  Locale('ja'),
  Locale('es'),
  Locale('zh'),
];
const List<Brightness> _themes = [Brightness.dark, Brightness.light];
const List<double> _scales = [1.0, 1.3, 2.0];
const List<Size> _sizes = [Size(360, 780), Size(390, 844), Size(430, 932)];

/// 1 つの描画条件。
class _Case {
  const _Case(this.locale, this.brightness, this.textScale, this.size);

  final Locale locale;
  final Brightness brightness;
  final double textScale;
  final Size size;

  String get lang => locale.languageCode;

  String get tag => '$lang|${brightness == Brightness.dark ? 'dark' : 'light'}|'
      '$textScale|${size.width.toInt()}';

  String get city => switch (lang) {
        'ja' => '東京',
        'es' => 'Tokio',
        'zh' => '东京',
        _ => 'Tokyo',
      };
}

/// 画面を組み立て、検査する範囲 (その画面のルート) を返す。
typedef _Scenario = Future<List<Finder>> Function(WidgetTester t, _Case c);

Future<void> _pumpApp(
  WidgetTester tester,
  _Case c, {
  required Widget home,
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = c.size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = kPhoneSafeArea;
  tester.view.viewPadding = kPhoneSafeArea;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(goldenApp(
    home: home,
    brightness: c.brightness,
    locale: c.locale,
    overrides: overrides,
    textScale: c.textScale,
  ));
  await settle(tester);
}

// ── ホーム / 詳細 / 設定 (MainShell) ────────────────────────────────

Future<ProviderContainer> _shell(
  WidgetTester tester,
  _Case c, {
  int saved = 5,
  bool plus = true,
  String? select,
  WeatherSnapshot Function(DateTime)? current,
  Map<String, PlaceWeatherMode> modes = const {},
  List<Override> extra = const [],
  int tab = 0,
}) async {
  await _pumpApp(
    tester,
    c,
    home: const MainShell(),
    overrides: [
      ...await placesBaseOverrides(
        savedCount: saved,
        locale: c.locale,
        current: current,
        city: c.city,
      ),
      ...entitlementOverrides(plus: plus),
      ...savedPlaceWeatherOverrides(modes: modes),
      ...extra,
    ],
  );
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MainShell)));
  if (select != null) {
    container.read(selectedPlaceIdProvider.notifier).select(select);
    await settle(tester);
  }
  if (tab != 0) {
    await tester.tap(find.byKey(ValueKey('quiet-nav-$tab')));
    await settle(tester);
  }
  return container;
}

/// 長い地名 5 件 (ヘッダの省略と「保存地点」タグ、タブの 8 字省略の確認)。
const List<(String, String)> _longNames = [
  ('place-geo-9000001', 'San Cristóbal de las Casas'),
  ('place-geo-9000002', 'Llanfairpwllgwyngyll'),
  ('place-geo-9000003', 'Villanueva de la Cañada'),
  ('place-geo-9000004', '南アルプス市芦安芦倉'),
  ('place-geo-9000005', 'Saint-Rémy-de-Provence'),
];

Future<List<Override>> _longNameOverrides(_Case c) async {
  SharedPreferences.setMockInitialValues({
    kPrefKeyComfortRecords: jsonEncode([
      for (var i = _longNames.length - 1; i >= 0; i--)
        {
          'id': _longNames[i].$1,
          'type': 'place',
          'mri': null,
          'savedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
          'label': _longNames[i].$2,
          'location': {'lat': 16.74, 'lon': -92.64},
          'addedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
        },
    ]),
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kPlacesNow),
    cityCatalogProvider.overrideWith((ref) async => const <City>[]),
    weatherSnapshotProvider
        .overrideWith((ref) async => comfortableSnapshot(kPlacesNow)),
    hourlyWeatherProvider
        .overrideWith((ref) async => hourlyAround(comfortableSnapshot)),
    cityNameProvider.overrideWith((ref) async => c.city),
    ...entitlementOverrides(plus: true),
    ...savedPlaceWeatherOverrides(),
  ];
}

// ── 地点追加シート ─────────────────────────────────────────────────

String _query(_Case c) => switch (c.lang) {
      'ja' || 'zh' => '京都',
      'es' => 'Kioto',
      _ => 'Kyoto',
    };

PlaceCandidate _candidate(
  int id,
  String name, {
  String? municipality,
  String? admin1,
  required String country,
}) =>
    PlaceCandidate(
      geocodingId: id,
      name: name,
      sourceName: name,
      latitude: 35,
      longitude: 135,
      featureCode: 'PPL',
      municipality: municipality,
      admin1: admin1,
      country: country,
    );

/// B1b: 同名の候補 10 件 (JA は新宿の実測、それ以外は Springfield の実測)。
List<PlaceCandidate> _manyCandidates(_Case c) {
  if (c.lang == 'ja') {
    const rows = [
      ('新宿区', '東京都'),
      ('神川町', '埼玉県'),
      ('逗子市', '神奈川県'),
      ('厚木市', '神奈川県'),
      ('清水町', '静岡県'),
      ('葛飾区', '東京都'),
      ('鮫川村', '福島県'),
      ('大井町', '神奈川県'),
      ('海老名市', '神奈川県'),
      ('御宿町', '千葉県'),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        _candidate(9100 + i, '新宿',
            municipality: rows[i].$1, admin1: rows[i].$2, country: '日本'),
    ];
  }
  final country = switch (c.lang) {
    'es' => 'Estados Unidos',
    'zh' => '美国',
    _ => 'United States',
  };
  const states = [
    'Missouri',
    'Massachusetts',
    'Illinois',
    'Ohio',
    'Tennessee',
    'Missouri',
    'Minnesota',
    'Kentucky',
    'Georgia',
    'Colorado',
  ];
  const names = [
    'Springfield',
    'Springfield',
    'Springfield',
    'Springfield',
    'Springfield',
    'Palmyra',
    'Jackson',
    'Springfield',
    'Springfield',
    'Springfield',
  ];
  return [
    for (var i = 0; i < states.length; i++)
      _candidate(9200 + i, names[i], admin1: states[i], country: country),
  ];
}

Future<List<Finder>> _sheet(
  WidgetTester tester,
  _Case c, {
  String? query,
  Object? result,
}) async {
  await _shell(
    tester,
    c,
    saved: 1,
    extra: [
      if (query != null) placeSearchOverride({query: result!}),
    ],
  );
  await tester.tap(find.byKey(kPlaceTabAddKey));
  await settle(tester);
  if (query != null) {
    await tester.enterText(find.byKey(kAddPlaceFieldKey), query);
    await settle(tester);
  }
  return [find.byType(AddPlaceSheet)];
}

// ── 地点管理 ───────────────────────────────────────────────────────

Future<List<Finder>> _locations(
  WidgetTester tester,
  _Case c, {
  required int saved,
  required bool plus,
}) async {
  await _pumpApp(
    tester,
    c,
    home: const LocationsPage(),
    overrides: [
      ...await placesBaseOverrides(
        savedCount: saved,
        locale: c.locale,
        city: c.city,
      ),
      ...entitlementOverrides(plus: plus),
      currentLocationProvider
          .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
      savedPlaceMriOverride(),
    ],
  );
  return [find.byType(LocationsPage)];
}

final Map<String, _Scenario> _scenarios = {
  'home_E1_empty': (t, c) async {
    await _shell(t, c, saved: 0, plus: false);
    return [find.byType(HomePage)];
  },
  // 無料で 1 件残っている (grandfathering)。
  'home_E2_free': (t, c) async {
    await _shell(t, c, saved: 1, plus: false);
    return [find.byType(HomePage)];
  },
  'home_E3_plus': (t, c) async {
    await _shell(t, c);
    return [find.byType(HomePage)];
  },
  'home_E4_switched': (t, c) async {
    await _shell(t, c, select: kNahaId);
    return [find.byType(HomePage)];
  },
  'home_E5_alert': (t, c) async {
    await _shell(t, c, select: kNahaId, current: dangerousHeatSnapshot);
    return [find.byType(HomePage)];
  },
  'home_E6a_loading': (t, c) async {
    await _shell(t, c,
        select: kSapporoId, modes: {kSapporoId: PlaceWeatherMode.loading});
    return [find.byType(HomePage)];
  },
  'home_E6b_failed': (t, c) async {
    await _shell(t, c,
        select: kReykjavikId, modes: {kReykjavikId: PlaceWeatherMode.error});
    return [find.byType(HomePage)];
  },
  'home_E7_limit': (t, c) async {
    await _shell(t, c);
    await t.drag(find.byType(PlaceTabBar), const Offset(-900, 0));
    await settle(t);
    await t.tap(find.byKey(kPlaceTabAddKey));
    // スナックバーの表示アニメーションを進める (4 秒で閉じるので 1 秒だけ)。
    await settle(t);
    return [find.byType(HomePage), find.byType(SnackBar)];
  },
  'home_long_names': (t, c) async {
    await _pumpApp(t, c,
        home: const MainShell(), overrides: await _longNameOverrides(c));
    ProviderScope.containerOf(t.element(find.byType(MainShell)))
        .read(selectedPlaceIdProvider.notifier)
        .select(_longNames.first.$1);
    await settle(t);
    return [find.byType(HomePage)];
  },
  'detail_current': (t, c) async {
    await _shell(t, c, tab: 1);
    return [find.byType(DetailPage)];
  },
  'detail_saved': (t, c) async {
    await _shell(t, c, select: kNahaId, tab: 1);
    return [find.byType(DetailPage)];
  },
  'settings_top': (t, c) async {
    await _shell(t, c, tab: 2);
    return [find.byType(SettingsPage)];
  },
  'sheet_B0': (t, c) => _sheet(t, c),
  'sheet_B1': (t, c) => _sheet(t, c, query: _query(c), result: [
        fixtureCandidate(kFixturePlaces[1], c.locale,
            admin1: c.lang == 'ja' ? '京都府' : 'Kyoto'),
      ]),
  'sheet_B1b_many': (t, c) => _sheet(t, c,
      query: c.lang == 'ja' ? '新宿' : 'Springfield', result: _manyCandidates(c)),
  'sheet_B3_none': (t, c) =>
      _sheet(t, c, query: 'xqzv', result: const <PlaceCandidate>[]),
  'sheet_B4_error': (t, c) =>
      _sheet(t, c, query: _query(c), result: kPlaceNetworkError),
  'locations_A1': (t, c) => _locations(t, c, saved: 0, plus: false),
  // 無料で 1 件残っている (旧 A2「1 / 1」。今は A5 と同じ「保存 1 件」+ Plus カード)。
  'locations_A2': (t, c) => _locations(t, c, saved: 1, plus: false),
  'locations_A3': (t, c) => _locations(t, c, saved: 4, plus: true),
  'locations_A4': (t, c) => _locations(t, c, saved: 5, plus: true),
  'locations_A5': (t, c) => _locations(t, c, saved: 5, plus: false),
  'paywall': (t, c) async {
    await _pumpApp(
      t,
      c,
      home: const PaywallPage(),
      overrides: [
        ...await goldenOverrides(),
        billingGatewayProvider.overrideWithValue(PreviewBillingGateway()),
      ],
    );
    return [find.byType(PaywallPage)];
  },
};

// ── 検査 ───────────────────────────────────────────────────────────

bool _inHorizontalScroll(Element element) {
  var found = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Scrollable &&
        (w.axisDirection == AxisDirection.left ||
            w.axisDirection == AxisDirection.right)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 画面内の文字の検査結果 (種類|内容)。
List<String> _inspect(List<Finder> scopes, Size view) {
  final out = <String>[];
  for (final scope in scopes) {
    final glyphs = <(String, Rect)>[];
    for (final e in find
        .descendant(of: scope, matching: find.byType(RichText))
        .evaluate()) {
      final p = e.renderObject;
      if (p is! RenderParagraph || !p.attached || !p.hasSize) continue;
      final raw = p.text.toPlainText(includeSemanticsLabels: false);
      final text = raw.replaceAll('\n', ' ');
      if (text.trim().isEmpty) continue;
      if (p.didExceedMaxLines) out.add('ellipsis|$text');
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: raw.length),
      );
      if (boxes.isEmpty) continue;
      // 横は字面 (実際に文字がある範囲)、縦は段落のレイアウト枠 (行送り)。
      // 字形の箱 (ascent/descent) は和文書体で行送りより背が高く、縦に並んだ
      // 行どうしが 1〜2px 重なって見えるため縦には使わない。
      var left = boxes.first.left;
      var right = boxes.first.right;
      for (final b in boxes.skip(1)) {
        if (b.left < left) left = b.left;
        if (b.right > right) right = b.right;
      }
      final rect = Rect.fromLTRB(left, 0, right, p.size.height);
      // FittedBox などの縮小も含めて画面座標へ (localToGlobal は原点だけ)。
      final global = MatrixUtils.transformRect(p.getTransformTo(null), rect);
      if (_inHorizontalScroll(e)) continue;
      if (global.left < -0.5 || global.right > view.width + 0.5) {
        out.add('offscreen|$text|${global.left.toStringAsFixed(1)}'
            '..${global.right.toStringAsFixed(1)}');
      }
      glyphs.add((text, global));
    }
    for (var i = 0; i < glyphs.length; i++) {
      for (var j = i + 1; j < glyphs.length; j++) {
        final inter = glyphs[i].$2.intersect(glyphs[j].$2);
        if (inter.width > 1 && inter.height > 1) {
          out.add('overlap|${glyphs[i].$1}|${glyphs[j].$1}');
        }
      }
    }
  }
  return out;
}

void _print(String kind, String screen, _Case c, String detail) {
  // ignore: avoid_print
  print('QA_MATRIX|$kind|$screen|${c.tag}|$detail');
}

/// 画面全体 (モーダル・スナックバーを含む) を PNG で書き出す。
Future<void> _writeShot(WidgetTester tester, String screen, _Case c) async {
  final image = await tester.runAsync(
    () => captureImage(find.byType(MaterialApp).evaluate().single),
  );
  final bytes = await tester.runAsync(() async {
    final data = await image!.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final name = '${screen}__${c.tag.replaceAll('|', '_')}.png';
  File('$_shotsDir/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

void main() {
  setUpAll(loadAppFonts);

  const skip = _run ? null : '--dart-define=MRW_QA_MATRIX=true のときだけ実行する';

  for (final locale in _locales) {
    for (final brightness in _themes) {
      for (final scale in _scales) {
        for (final size in _sizes) {
          final c = _Case(locale, brightness, scale, size);
          for (final entry in _scenarios.entries) {
            testWidgets('${entry.key} ${c.tag}', skip: skip != null,
                (tester) async {
              final scopes = await entry.value(tester, c);
              final error = tester.takeException();
              if (error != null) {
                final first = '$error'.split('\n').firstWhere(
                      (l) => l.contains('overflowed'),
                      orElse: () => '$error'.split('\n').first,
                    );
                _print('exception', entry.key, c, first.trim());
              }
              for (final f in _inspect(scopes, c.size)) {
                final i = f.indexOf('|');
                _print(f.substring(0, i), entry.key, c, f.substring(i + 1));
              }
              final breaks = midWordBreaks();
              for (final b in breaks) {
                _print('midword', entry.key, c, b);
              }
              if (_shotsDir.isNotEmpty) await _writeShot(tester, entry.key, c);
              expect(error, isNull, reason: '溢れの例外 (${entry.key} ${c.tag})');
              if (scale < 2.0) {
                expect(breaks, isEmpty, reason: '語中改行 (${entry.key} ${c.tag})');
              }
            });
          }
        }
      }
    }
  }
}
