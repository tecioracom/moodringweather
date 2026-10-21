// test/type_scale/type_scale_overflow_test.dart
//
// 型スケールのプリセットごとの溢れ検出 (文字倍率 1.0 / 1.3 / 2.0 × ja / es)。
// 画面は既存の文字倍率テスト (settings_v13_test / calibration_twin_v13_test) の
// 14 画面 + ホーム (現在地 / 保存地点)・詳細・地点追加シート B1・Paywall・
// 地点管理の無料 (A1 0 件 / A5 1 件。保存地点は Plus 限定)。
// 地点管理の無料の文言は 360dp ×2.0 × 4 言語でも見る (2026-09-30 の Plus 限定化)。
// 390 幅 (Figma と同寸) のまま縦だけ伸ばし、横方向の溢れを検出する。
// qa 検収 (2026-09-29) の Sev2 の回帰: 幅 360 / 375 / 390 で
//   - ホームの気温・天気レールの末尾の「°」が消えない (JA の全角「°」)
//   - Paywall のプラン名が省略されず、BEST VALUE と価格が重ならない
// 溢れ (RenderFlex overflow 等の例外) に加えて、語の途中で折れる段落
// (「TEMPERATUR / A」・1 文字ずつ折れる時刻) も倍率 1.0 / 1.3 では失敗にする
// (2.0 は TYPE_SCALE_MIDWORD|... の出力だけ)。
//
// プリセットは --dart-define=MRW_TYPE_SCALE (未指定は既定の案2 = plus2)。
// 旧 v1.3 (current) / 案1 と比べるとき:
//   flutter test test/type_scale/type_scale_overflow_test.dart \
//     --dart-define=MRW_TYPE_SCALE=current
// 溢れたときは 1 行の要約 (TYPE_SCALE_OVERFLOW|...) を出して失敗させる。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';
import 'type_scale_scenarios.dart';

const Size _tall = Size(390, 8000);

void main() {
  setUpAll(loadAppFonts);

  final preset = MrwTypeScale.fromEnvironment;
  const scales = [1.0, 1.3, 2.0];
  const locales = [Locale('ja'), Locale('es')];
  const locales3 = [Locale('ja'), Locale('en'), Locale('es')];

  Future<void> check(
    WidgetTester tester,
    String screen,
    TypeScaleCase c,
    Future<void> Function() pump,
  ) async {
    await pump();
    final error = tester.takeException();
    if (error != null) {
      final first = '$error'.split('\n').firstWhere(
            (l) => l.contains('overflowed'),
            orElse: () => '$error'.split('\n').first,
          );
      // ignore: avoid_print
      print('TYPE_SCALE_OVERFLOW|${preset.name}|${c.locale.languageCode}|'
          '${c.textScale}|$screen|${first.trim()}');
    }
    expect(error, isNull);

    // 語の途中で折れる段落 (「TEMPERATUR / A」、棒 1 本ぶんの枠で 1 文字ずつ
    // 折れる時刻「1 / 2」など)。溢れ例外にはならないので別に見る。
    // 倍率 2.0 は長い 1 語 (都市名・メールアドレス) が枠より広くなりうるので
    // 出力だけにする (×2.0 の省略と同じ扱い)。
    final breaks = midWordBreaks();
    for (final b in breaks) {
      // ignore: avoid_print
      print('TYPE_SCALE_MIDWORD|${preset.name}|${c.locale.languageCode}|'
          '${c.textScale}|$screen|$b');
    }
    if (c.textScale < 2.0) expect(breaks, isEmpty);
  }

  group('語中改行の検出器 (midWordBreaks)', () {
    Widget column(List<Widget> children) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
    const style = TextStyle(fontSize: 10);

    testWidgets('幅が足りない 1 語・1 文字ずつ折れる数字は拾う', (tester) async {
      await tester.pumpWidget(column(const [
        SizedBox(width: 40, child: Text('TEMPERATURA', style: style)),
      ]));
      expect(midWordBreaks(), isNotEmpty);
      await tester.pumpWidget(column(const [
        SizedBox(width: 7, child: Text('12', style: style)),
      ]));
      expect(midWordBreaks(), isNotEmpty);
    });

    testWidgets('語間・ハイフン・CJK・改行での折り返しは拾わない', (tester) async {
      await tester.pumpWidget(column(const [
        SizedBox(width: 80, child: Text('Mood-Ring Weather', style: style)),
        SizedBox(width: 30, child: Text('体感温度です', style: style)),
        Text('VERY HOT —\nHYDRATE', style: style),
      ]));
      expect(midWordBreaks(), isEmpty);
    });
  });

  for (final locale in locales) {
    for (final scale in scales) {
      final tag = '${preset.name} ${locale.languageCode} ×$scale';
      final c = TypeScaleCase(
        brightness: Brightness.dark,
        locale: locale,
        typeScale: preset,
        textScale: scale,
        viewport: _tall,
      );

      for (final entry in kOverflowSettingsScreens.entries) {
        testWidgets('${entry.key}: 溢れない ($tag)', (tester) async {
          await check(tester, entry.key, c, () async {
            tester.view.physicalSize = _tall;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(goldenApp(
              home: entry.value(),
              brightness: c.brightness,
              locale: c.locale,
              overrides: await settingsOverrides(),
              typeScale: c.typeScale,
              textScale: c.textScale,
            ));
            await tester.pumpAndSettle();
          });
        });
      }

      for (final screen in const [
        'ホーム現在地',
        'ホーム保存地点',
        '詳細',
        '地点追加シート',
        'Paywall',
        '設定地点無料0件',
        '設定地点無料1件',
      ]) {
        testWidgets('$screen: 溢れない ($tag)', (tester) async {
          await check(
            tester,
            screen,
            c,
            () => kTypeScaleScenarios[screen]!(tester, c),
          );
        });
      }
    }
  }

  group('ホームの気温の「°」が消えない (qa Sev2-1)', () {
    // JA の数字書体 (Plex Sans JP) は「°」が全角で右半分が空き。FEELS 列 150 で
    // 気温の枠が 170 (360dp)〜185 (375dp) に狭まると、送り幅が収まらず「°」だけが
    // 見えない 2 行目へ折れていた。1 行で組み、空きの分だけ枠からはみ出させる。
    const temperatures = [
      (-12.0, TemperatureUnit.celsius, '-12°'),
      (37.8, TemperatureUnit.fahrenheit, '100°'),
      (22.0, TemperatureUnit.celsius, '22°'),
    ];
    for (final width in const [360.0, 375.0, 390.0]) {
      for (final scale in const [1.0, 1.3]) {
        for (final locale in locales3) {
          for (final (celsius, unit, shown) in temperatures) {
            testWidgets(
                '${width.toInt()}dp ×$scale ${locale.languageCode} 「$shown」',
                (tester) async {
              await kTypeScaleScenarios['ホーム現在地']!(
                tester,
                TypeScaleCase(
                  brightness: Brightness.dark,
                  locale: locale,
                  typeScale: preset,
                  textScale: scale,
                  viewport: Size(width, 844),
                  temperature: celsius,
                  unit: unit,
                ),
              );
              expect(tester.takeException(), isNull);

              // 気温: 1 行で、末尾の「°」も 1 行目に組まれている。
              final temperature = find.byWidgetPredicate((w) =>
                  w is Text && w.data == shown && w.style?.fontSize == 64);
              expect(temperature, findsOneWidget);
              final p = tester.renderObject<RenderParagraph>(temperature);
              expect(p.didExceedMaxLines, isFalse);
              final lines = _lineTops(p, shown.length);
              expect(lines, hasLength(1), reason: '「$shown」が 2 行に折れた');
              final degree = _charBox(p, shown.length - 1);
              final origin = p.localToGlobal(Offset.zero);
              // 字面の右端 (全角「°」は欧文の「°」の幅ぶんが字面)。
              final inkRight = origin.dx +
                  degree.left +
                  _latinDegreeWidth(tester, temperature, scale);
              expect(inkRight, lessThanOrEqualTo(width - 20 + 0.5));

              // 右列 (FEELS) と重ならない: 並ぶときは字面の右 16px 以上空く。
              final row = find
                  .byWidgetPredicate(
                      (w) => w.runtimeType.toString() == '_TemperatureRow')
                  .first;
              final paragraphs = find
                  .descendant(of: row, matching: find.byType(RichText))
                  .evaluate()
                  .map((e) => e.renderObject! as RenderParagraph)
                  .toList();
              final feels =
                  paragraphs[1].localToGlobal(Offset.zero) & paragraphs[1].size;
              final tempRect = origin & p.size;
              final stacked = feels.top >= tempRect.bottom - 0.5;
              if (!stacked) {
                expect(inkRight + 16, lessThanOrEqualTo(feels.left + 0.5));
              }

              // 天気レールの気温も 1 行で「°」まで組まれている。
              final rails = find.descendant(
                of: find.byType(BarSlotRow),
                matching: find.byWidgetPredicate(
                    (w) => w is Text && (w.data?.endsWith('°') ?? false)),
              );
              expect(rails, findsWidgets);
              for (final e in rails.evaluate()) {
                final text = (e.widget as Text).data!;
                final rail = e.renderObject! as RenderParagraph;
                expect(_lineTops(rail, text.length), hasLength(1),
                    reason: 'レールの「$text」が 2 行に折れた');
              }
            });
          }
        }
      }
    }
  });

  group('地点管理 (無料・保存地点は Plus 限定) の文言: 360dp ×2.0 (4 言語)', () {
    // 2026-09-30 (無料 0 件): 無料 0 件の Plus カード本文 (locationsAddLockedNote)、
    // 無料で残っている地点の件数と Plus カード本文 (locationsCountOver /
    // locationsOverLimitBody の 1 件の形)、元に戻せない理由 (placeRestoreNeedsPlus)
    // が、最大の文字倍率と狭い幅で溢れず、省略されず、枠の外に出ず、語の途中で
    // 折れないこと。
    const locales4 = [
      Locale('en'),
      Locale('ja'),
      Locale('es'),
      Locale('zh'),
    ];
    const width = 360.0;

    for (final locale in locales4) {
      final lang = locale.languageCode;
      for (final (screen, kept) in const [
        ('設定地点無料0件', 0),
        ('設定地点無料1件', 1),
      ]) {
        testWidgets('$screen $lang', (tester) async {
          await kTypeScaleScenarios[screen]!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: preset,
              textScale: 2.0,
              viewport: const Size(width, 2400),
            ),
          );
          expect(tester.takeException(), isNull);
          final t =
              AppLocalizations.of(tester.element(find.byType(LocationsPage)));

          final card = tester.getRect(find.byType(QuietPlusCard));
          expect(card.left, greaterThanOrEqualTo(-0.5));
          expect(card.right, lessThanOrEqualTo(width + 0.5));
          final body = kept == 0
              ? t.locationsAddLockedNote
              : t.locationsOverLimitBody(kept);
          final texts = [body, t.locationsSeePlus];
          for (final text in texts) {
            _expectInside(tester, find.text(text), card);
          }
          if (kept > 0) {
            final count = t.locationsCountOver(kept);
            _expectInside(tester, find.text(count),
                const Rect.fromLTWH(0, 0, width, 2400));
            texts.add(count);
          } else {
            // 無料 0 件は件数を出さない (「0 / 0」にしない)。
            expect(find.text(t.locationsCount(0, 0)), findsNothing);
          }
          final breaks = midWordBreaks()
              .where((b) => texts.any(
                  (text) => b.startsWith('${text.replaceAll('\n', ' ')}|')))
              .toList();
          expect(breaks, isEmpty, reason: '語中改行: $breaks');
        });
      }

      testWidgets('元に戻せない理由 (無料・placeRestoreNeedsPlus) $lang', (tester) async {
        tester.view.physicalSize = const Size(width, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final plus = StateProvider<bool>((ref) => true);
        await tester.pumpWidget(goldenApp(
          home: const LocationsPage(),
          brightness: Brightness.dark,
          locale: locale,
          typeScale: preset,
          textScale: 2.0,
          overrides: [
            ...await placesBaseOverrides(savedCount: 1, locale: locale),
            ...switchableEntitlementOverrides(plus),
            currentLocationProvider
                .overrideWith((ref) async => const GeoPoint(35.68, 139.77)),
            savedPlaceMriOverride(),
          ],
        ));
        await settle(tester);
        final t =
            AppLocalizations.of(tester.element(find.byType(LocationsPage)));
        final c = ProviderScope.containerOf(
            tester.element(find.byType(LocationsPage)));
        final place = c.read(savedPlacesProvider).single;

        // Plus で 1 件 → 削除 → Comfort-Twin で保存 → 解約 → 元に戻す (戻せない)。
        await tester.ensureVisible(find.byIcon(Icons.delete_outline));
        await settle(tester);
        await tester.tap(find.byIcon(Icons.delete_outline));
        await settle(tester);
        await c.read(savedPlacesControllerProvider).saveCatalogCity(
              const City(
                id: 'lisbon',
                name: 'Lisbon',
                country: 'Portugal',
                latitude: 38.72,
                longitude: -9.14,
                emoji: 'PT',
              ),
              70,
            );
        c.read(plus.notifier).state = false;
        await tester.pump();
        await tester.tap(find.text(t.placeUndo));
        await settle(tester);

        expect(tester.takeException(), isNull);
        final message = t.placeRestoreNeedsPlus(place.name);
        _expectInside(
            tester, find.text(message), const Rect.fromLTWH(0, 0, width, 780));
        final breaks =
            midWordBreaks().where((b) => b.startsWith('$message|')).toList();
        expect(breaks, isEmpty, reason: '語中改行: $breaks');
      });
    }
  });

  group('Paywall のプラン行 (qa Sev2-2)', () {
    // 360dp × 1.3・390dp × 1.5 でプラン名が「Ye…」「A…」に、×1.7〜2.0 で
    // BEST VALUE が価格に重なっていた。プラン名は省略しない (契約期間が読める
    // こと)、バッジと価格は重ねない。
    for (final width in const [360.0, 375.0, 390.0]) {
      for (final scale in const [1.0, 1.3, 1.7, 2.0]) {
        for (final locale in locales3) {
          testWidgets('${width.toInt()}dp ×$scale ${locale.languageCode}',
              (tester) async {
            await kTypeScaleScenarios['Paywall']!(
              tester,
              TypeScaleCase(
                brightness: Brightness.dark,
                locale: locale,
                typeScale: preset,
                textScale: scale,
                viewport: Size(width, 3000),
              ),
            );
            expect(tester.takeException(), isNull);
            final t =
                AppLocalizations.of(tester.element(find.byType(PaywallPage)));

            for (final (period, price) in [
              (t.paywallPeriodMonthly, '¥600'),
              (t.paywallPeriodAnnual, '¥3,000'),
            ]) {
              final name = tester.renderObject<RenderParagraph>(
                find.text(period),
              );
              expect(name.didExceedMaxLines, isFalse,
                  reason: 'プラン名「$period」が省略された');
              final nameRect = tester.getRect(find.text(period));
              final priceRect = tester.getRect(find.text(price));
              expect(nameRect.overlaps(priceRect), isFalse, reason: period);
              final card = tester.getRect(find
                  .ancestor(
                      of: find.text(price), matching: find.byType(InkWell))
                  .first);
              expect(priceRect.right, lessThanOrEqualTo(card.right + 0.5));
              expect(nameRect.left, greaterThanOrEqualTo(card.left - 0.5));
            }

            final badge = tester.getRect(find.byType(QuietBadge));
            final annualPrice = tester.getRect(find.text('¥3,000'));
            expect(badge.overlaps(annualPrice), isFalse,
                reason: 'BEST VALUE が価格に重なった');
            final annualCard = tester.getRect(find
                .ancestor(
                    of: find.text('¥3,000'), matching: find.byType(InkWell))
                .first);
            expect(badge.left, greaterThanOrEqualTo(annualCard.left - 0.5));
            expect(badge.bottom, lessThanOrEqualTo(annualCard.bottom + 0.5));
          });
        }
      }
    }
  });
}

/// [text] の段落が省略されず、字面がすべて [bounds] (画面座標) の内側にある。
void _expectInside(WidgetTester tester, Finder text, Rect bounds) {
  expect(text, findsOneWidget);
  final p = tester.renderObject<RenderParagraph>(text);
  final plain = p.text.toPlainText(includeSemanticsLabels: false);
  expect(p.didExceedMaxLines, isFalse, reason: '省略された: $plain');
  final toGlobal = p.getTransformTo(null);
  for (final box in p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length))) {
    final rect = MatrixUtils.transformRect(toGlobal, box.toRect());
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.5), reason: plain);
    expect(rect.right, lessThanOrEqualTo(bounds.right + 0.5), reason: plain);
    expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.5), reason: plain);
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.5), reason: plain);
  }
}

/// 段落の [0, length) の文字が載っている行の上端の一覧 (行数の確認用)。
Set<int> _lineTops(RenderParagraph p, int length) => p
    .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
    .map((b) => b.top.round())
    .toSet();

/// 段落の [index] の 1 文字の箱。
TextBox _charBox(RenderParagraph p, int index) => p
    .getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1))
    .single;

/// 気温と同じ大きさ・太さの欧文 (Inter) の「°」の幅 (文字倍率込み)。
double _latinDegreeWidth(
    WidgetTester tester, Finder temperature, double scale) {
  final style = tester.widget<Text>(temperature).style!;
  final painter = TextPainter(
    text: TextSpan(
      text: '°',
      style: style.copyWith(
        fontFamily: MrwFonts.inter,
        fontFamilyFallback: const [],
        fontVariations: MrwFonts.interVariations(
          style.fontWeight ?? FontWeight.w600,
        ),
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
