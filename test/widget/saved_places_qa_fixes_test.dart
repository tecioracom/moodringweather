// test/widget/saved_places_qa_fixes_test.dart
//
// 保存地点 RC の QA (docs/qa-report-saved-places-2026-09-29.md) で見つかった不具合の
// 修正の回帰テスト。QA の再現テストは test/qa/saved_places_rc_regression_test.dart。
//   QA-02 地点管理: 削除アイコンの連打・処理中の再入で別の地点を消さない
//   QA-07 地点管理: 削除の「元に戻す」は戻す時点の上限で判定し直し、戻せなければ理由を出す
//         (保存地点は Plus 限定 = 無料 0 件。無料で戻せないときは「0 件まで」ではなく
//         「増やすには Plus が必要」)
//   QA-03 G4 バナー: 文字倍率 2.0 でも種別 (熱中症・暴風・大雪) が省略されない。
//         倍率 1.0 (Figma E5) は修正前と同じ行数・高さ
//   QA-01 zh の地点追加: 英語名でも検索できると案内し、390dp で余計に折れない

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/domain/places/saved_place_rules.dart';
import 'package:mood_ring_weather/domain/safety/emergency_advisor.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/current_location_cues.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/current_alert_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

const _en = Locale('en');

const City _lisbon = City(
  id: 'lisbon',
  name: 'Lisbon',
  country: 'Portugal',
  latitude: 38.72,
  longitude: -9.14,
  emoji: 'PT',
);

List<Override> _locationsOverrides() => [
      currentLocationProvider
          .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
      savedPlaceMriOverride(),
    ];

Future<ProviderContainer> _pumpLocations(
  WidgetTester tester, {
  required int saved,
  bool plus = true,
  List<Override>? entitlement,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: const LocationsPage(),
    brightness: Brightness.dark,
    locale: _en,
    overrides: [
      ...await placesBaseOverrides(savedCount: saved, locale: _en),
      ...entitlement ?? entitlementOverrides(plus: plus),
      ..._locationsOverrides(),
    ],
  ));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(LocationsPage)));
}

List<String> _savedIds(ProviderContainer c) =>
    [for (final p in c.read(savedPlacesProvider)) p.id];

/// 段落の [0, length) の文字が載っている行の数。書体が混ざる行 (漢字の代替字形と
/// 英字) は箱の上端が 1〜2px ずれるので、上端が 8px 以内の箱は同じ行とみなす。
int _lineCount(RenderParagraph p, int length) {
  final tops = p
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
      .map((b) => b.top)
      .toList()
    ..sort();
  var lines = 0;
  double? lineTop;
  for (final top in tops) {
    if (lineTop == null || top - lineTop > 8) {
      lines++;
      lineTop = top;
    }
  }
  return lines;
}

RenderParagraph _paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text);

void main() {
  setUpAll(loadAppFonts);

  group('QA-02 地点管理: 削除の連打・処理中の再入', () {
    testWidgets('150ms の連打: 消えるのは押した地点 1 件だけ。スナックバーはその地点で、元に戻せる',
        (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      expect(_savedIds(c), [kNahaId, kKyotoId, kSapporoId]);

      final first = tester.getCenter(find.byIcon(Icons.delete_outline).first);
      await tester.tapAt(first);
      await tester.pump(const Duration(milliseconds: 150));
      // 行が繰り上がり、同じ位置は京都の削除アイコン。受け付けない。
      expect(find.text('Naha'), findsNothing);
      await tester.tapAt(first);
      await settle(tester);

      expect(_savedIds(c), [kKyotoId, kSapporoId]);
      expect(find.text('Removed Naha.'), findsOneWidget);
      expect(find.text('Removed Kyoto.'), findsNothing);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), [kNahaId, kKyotoId, kSapporoId]);
    });

    testWidgets('同じフレームの 2 回 (処理中の再入) も 1 件だけ', (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      final first = tester.getCenter(find.byIcon(Icons.delete_outline).first);
      await tester.tapAt(first);
      await tester.tapAt(first);
      await settle(tester);
      expect(_savedIds(c), [kKyotoId, kSapporoId]);
    });

    testWidgets(
        '間を置けば (${kLocationsDeleteCooldown.inMilliseconds}ms 以上) 続けて削除できる',
        (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      final first = tester.getCenter(find.byIcon(Icons.delete_outline).first);
      await tester.tapAt(first);
      await tester.pump(kLocationsDeleteCooldown);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(first);
      await settle(tester);

      expect(_savedIds(c), [kSapporoId]);
      // スナックバーは後に消した地点 (前のものは閉じる)。
      expect(find.text('Removed Kyoto.'), findsOneWidget);
      expect(find.text('Removed Naha.'), findsNothing);
    });

    testWidgets('削除アイコンは行の地点 ID で消す (行の位置ではない)', (tester) async {
      final c = await _pumpLocations(tester, saved: 3);
      // 3 行目 (札幌) を消すと札幌だけが消える。
      await tester.tap(find.byIcon(Icons.delete_outline).at(2));
      await settle(tester);
      expect(_savedIds(c), [kNahaId, kKyotoId]);
      expect(find.text('Removed Sapporo.'), findsOneWidget);
    });
  });

  group('QA-07 地点管理: 削除の「元に戻す」の上限', () {
    // 無料 (上限 0) で戻せないときの理由。「0 件まで」とは出さない。
    const reason = 'Couldn’t restore Naha. Saving more places needs Plus.';

    testWidgets(
        'Plus 1 / 5: 削除 → Comfort-Twin で保存 → 解約 → 元に戻す は戻さず、'
        '「Plus が必要」と出す', (tester) async {
      final plus = StateProvider<bool>((ref) => true);
      final c = await _pumpLocations(
        tester,
        saved: 1,
        entitlement: switchableEntitlementOverrides(plus),
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await settle(tester);
      expect(find.text('Removed Naha.'), findsOneWidget);

      expect(
        await c
            .read(savedPlacesControllerProvider)
            .saveCatalogCity(_lisbon, 70),
        SavedPlaceAddCheck.allowed,
      );
      c.read(plus.notifier).state = false; // 解約
      await tester.pump();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), ['place-lisbon']);
      expect(find.text(reason), findsOneWidget);
      expect(find.textContaining('(0 of 0)'), findsNothing);
      expect(find.text('1 saved'), findsOneWidget);
    });

    testWidgets('Plus 5 / 5: 削除 → 別の地点を追加 → 元に戻す は戻さず「5 of 5」と出す',
        (tester) async {
      final c = await _pumpLocations(tester, saved: 5);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await settle(tester);
      expect(find.text('Removed Naha.'), findsOneWidget);

      await c.read(savedPlacesControllerProvider).saveCatalogCity(_lisbon, 70);
      await tester.pump();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), hasLength(5));
      expect(_savedIds(c), isNot(contains(kNahaId)));
      expect(
        find.text('Couldn’t restore Naha. Saved places are full (5 of 5).'),
        findsOneWidget,
      );
    });

    testWidgets('無料で 1 件残っている: 削除 → 元に戻す は戻せる (理由は出さない)', (tester) async {
      final c = await _pumpLocations(tester, saved: 1, plus: false);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await settle(tester);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), [kNahaId]);
      expect(find.text(reason), findsNothing);
    });

    testWidgets('grandfathering: 解約後に持ち越した 5 件から消した地点は元に戻せる', (tester) async {
      final c = await _pumpLocations(tester, saved: 5, plus: false);
      expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);
      await tester.tap(find.byIcon(Icons.delete_outline).at(1));
      await settle(tester);
      expect(_savedIds(c), hasLength(4));
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), [for (final p in kFixturePlaces) p.id]);
    });

    testWidgets('地点管理を閉じた後に「元に戻す」を押しても、戻せない理由を出す', (tester) async {
      final plus = StateProvider<bool>((ref) => true);
      useGoldenViewport(tester);
      await tester.pumpWidget(goldenApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const ValueKey('open-locations'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const LocationsPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        brightness: Brightness.dark,
        locale: _en,
        overrides: [
          ...await placesBaseOverrides(savedCount: 1, locale: _en),
          ...switchableEntitlementOverrides(plus),
          ..._locationsOverrides(),
        ],
      ));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('open-locations')));
      await settle(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.byType(LocationsPage))).pop();
      await settle(tester);
      expect(find.byType(LocationsPage), findsNothing);

      final c = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('open-locations'))));
      await c.read(savedPlacesControllerProvider).saveCatalogCity(_lisbon, 70);
      c.read(plus.notifier).state = false; // 解約
      await tester.pump();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(_savedIds(c), ['place-lisbon']);
      expect(find.text(reason), findsOneWidget);
    });
  });

  group('QA-03 G4 バナー: 種別が必ず読める', () {
    const kinds = <String, List<String>>{
      'ja': ['熱中症アラート', '暴風アラート', '大雪アラート'],
      'zh': ['中暑警示', '狂风警示', '暴雪警示'],
      'en': ['Heat alert', 'Wind alert', 'Snow alert'],
      'es': [
        'Alerta de golpe de calor',
        'Alerta de viento violento',
        'Alerta de nevada intensa',
      ],
    };
    const cities = {'ja': '東京', 'zh': '东京', 'en': 'Tokyo', 'es': 'Tokio'};

    for (final MapEntry(key: lang, value: labels) in kinds.entries) {
      for (final kind in EmergencyKind.values) {
        final label = labels[kind.index];
        testWidgets('$lang ×2.0 / 360dp: ${kind.name}「$label」が省略されず、バナーの中に収まる',
            (tester) async {
          tester.view.physicalSize = const Size(360, 780);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final locale = Locale(lang);
          await tester.pumpWidget(goldenApp(
            home: const MainShell(),
            brightness: Brightness.dark,
            locale: locale,
            textScale: 2.0,
            overrides: [
              ...await placesBaseOverrides(
                savedCount: 1,
                locale: locale,
                city: cities[lang]!,
              ),
              ...entitlementOverrides(plus: true),
              ...savedPlaceWeatherOverrides(),
              currentTopEmergencyAlertProvider.overrideWithValue(
                EmergencyAlert(
                  kind: kind,
                  severity: EmergencySeverity.danger,
                  metricValue: 1,
                ),
              ),
            ],
          ));
          await settle(tester);
          ProviderScope.containerOf(tester.element(find.byType(MainShell)))
              .read(selectedPlaceIdProvider.notifier)
              .select(kNahaId);
          await settle(tester);
          expect(tester.takeException(), isNull);

          final banner = find.byKey(CurrentAlertBanner.bannerKey);
          final message = find
              .descendant(of: banner, matching: find.byType(RichText))
              .evaluate()
              .map((e) => e.renderObject! as RenderParagraph)
              .firstWhere((p) => p.text.toPlainText().contains(label));
          expect(message.didExceedMaxLines, isFalse);
          // 種別の字の箱がすべてバナーの中 (Material の角丸で切られない) かつ画面内。
          final plain = message.text.toPlainText();
          final start = plain.indexOf(label);
          final boxes = message.getBoxesForSelection(TextSelection(
              baseOffset: start, extentOffset: start + label.length));
          expect(boxes, isNotEmpty);
          final bannerRect = tester.getRect(banner);
          final toGlobal = message.getTransformTo(null);
          for (final box in boxes) {
            final rect = MatrixUtils.transformRect(toGlobal, box.toRect());
            expect(rect.left, greaterThanOrEqualTo(bannerRect.left - 0.5));
            expect(rect.right, lessThanOrEqualTo(bannerRect.right + 0.5));
            expect(rect.top, greaterThanOrEqualTo(bannerRect.top - 0.5));
            expect(rect.bottom, lessThanOrEqualTo(bannerRect.bottom + 0.5));
            expect(rect.right, lessThanOrEqualTo(360 + 0.5));
          }
        });
      }
    }

    // 倍率 1.0 は修正前と同じ行数・高さ (golden E5 と同じ。JA 1 行 = Figma 44 高、
    // EN は案2 の文字サイズで修正前から 2 行 = 56 高)。
    for (final (locale, lines, height) in const [
      (Locale('ja'), 1, 44.0),
      (Locale('en'), 2, 56.0),
    ]) {
      testWidgets(
          '${locale.languageCode} ×1.0 / 390dp (Figma E5): 文言は $lines 行、'
          'バナーの高さは ${height.toInt()} のまま', (tester) async {
        useGoldenViewport(tester);
        await tester.pumpWidget(goldenApp(
          home: const MainShell(),
          brightness: Brightness.dark,
          locale: locale,
          overrides: [
            ...await placesBaseOverrides(
              savedCount: 5,
              locale: locale,
              current: dangerousHeatSnapshot,
              city: locale.languageCode == 'ja' ? '東京' : 'Tokyo',
            ),
            ...entitlementOverrides(plus: true),
            ...savedPlaceWeatherOverrides(),
          ],
        ));
        await settle(tester);
        ProviderScope.containerOf(tester.element(find.byType(MainShell)))
            .read(selectedPlaceIdProvider.notifier)
            .select(kNahaId);
        await settle(tester);

        final banner = find.byKey(CurrentAlertBanner.bannerKey);
        expect(tester.getSize(banner).height, height);
        final t = AppLocalizations.of(tester.element(banner));
        final text = t.homeAlertHeat(
            t.homeAlertPlace(locale.languageCode == 'ja' ? '東京' : 'Tokyo'));
        final p = _paragraph(
            tester, find.descendant(of: banner, matching: find.text(text)));
        expect(_lineCount(p, text.length), lines);
        expect(p.didExceedMaxLines, isFalse);
      });
    }
  });

  group('QA-01 zh の地点追加: 英語名でも検索できると案内する', () {
    testWidgets('390dp ×1.0: 案内 (B0) と 0 件 (B3) は 3 行のまま (余計に折れない)',
        (tester) async {
      useGoldenViewport(tester);
      const zh = Locale('zh');
      await tester.pumpWidget(goldenApp(
        home: const MainShell(),
        brightness: Brightness.dark,
        locale: zh,
        overrides: [
          ...await placesBaseOverrides(savedCount: 1, locale: zh, city: '东京'),
          ...entitlementOverrides(plus: true),
          ...savedPlaceWeatherOverrides(),
          placeSearchOverride({'xqzv': const []}),
        ],
      ));
      await settle(tester);
      await tester.tap(find.byKey(kPlaceTabAddKey));
      await settle(tester);
      final t = AppLocalizations.of(tester.element(find.byType(AddPlaceSheet)));

      for (final text in [t.addPlaceGuide, t.addPlaceNoResults]) {
        expect(text, contains('英文名'));
        expect(text, contains('Tokyo'));
        expect('\n'.allMatches(text), hasLength(2), reason: text);
      }

      final guide = _paragraph(tester, find.text(t.addPlaceGuide));
      expect(_lineCount(guide, t.addPlaceGuide.length), 3);

      await tester.enterText(find.byKey(kAddPlaceFieldKey), 'xqzv');
      await settle(tester);
      final none = _paragraph(tester, find.text(t.addPlaceNoResults));
      expect(_lineCount(none, t.addPlaceNoResults.length), 3);
      expect(tester.takeException(), isNull);
    });
  });
}
