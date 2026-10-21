// test/qa/metric_units_rc_test.dart
//
// 1.3.0 (versionCode 11) の QA (2026-09-30) で追加した回帰テスト。指標タイルの単位・
// 段階語、風速の単位の設定、通知設定の整理を、画面の組み立てと操作で確かめる。
// 実通信なし。結果は docs/qa-report-saved-places-2026-09-29.md の §U。
//
//   U-1 指標タイルの全区分 (UV 5 区分 × 空気質 6 区分。区分ごとに桁の多い値) ×
//       風の 3 単位 (45 m/s = 「45.0 m/s」「162 km/h」「101 mph」) × 4 言語 ×
//       倍率 1.0 / 1.3 / 2.0 × 幅 360 / 320dp × ホーム・詳細。es「104 Deficiente」、
//       en「300 Very unhealthy」を含む (既存の metric_tile_overflow_test は各言語の
//       最長の語だけで、空気質の区分 1〜3 と 320dp を見ていない)。
//       判定: 溢れ例外なし・値と後ろの文字は省略なし・どの文字も 1 行 (語の途中で
//       折れない)・タイルの内側・単位は値と同じ行・段階語は値と同じ行か値の真下・
//       同じ行の 2 枚は同じ高さ・360dp の倍率 1.0 は 1 行 (en「Very unhealthy」だけ
//       例外、compliance-review-v1.3.0 §9-2)・360dp では縮小しても倍率 1.0 の大きさを
//       下回らない (大きい文字の設定で、逆に元より小さくならない)。
//   U-2 設定 › 一般の「風速の単位」(es「Unidad de velocidad del viento」) と m/s・
//       km/h・mph の切替: 360dp × 倍率 1.0 / 1.3 / 2.0 × 4 言語で溢れず、見出しは
//       語の途中で折れず、切替の文字は省略されず 1 行で枠の内側。記号は大文字にしない。
//   U-3 設定トップの「通知」の副題 (熱中症・暴風・大雪): 360dp × 倍率 2.0 まで
//       4 言語とも省略されない (副題は 2 行まで)。
//   U-4 Comfort-Twin の比較の「風 (単位)」: 360dp × 倍率 2.0 まで 4 言語 × 3 単位で
//       溢れず、単位の記号が途中で折れない。
//   U-5 設定 › 一般で風速の単位を切り替えると、同じアプリの中でホーム・詳細・Twin の
//       比較・暴風の緊急通知 (設定 › 通知のデバッグ発火。実機手順書 D-21 と同じ操作) が
//       追従する。通知の本文は単位込み (U+00A0) で、免責文が続く。
//
// --dart-define=MRW_QA_VERBOSE=true で U-1 の縮小率の一覧 (QA11_TILE|...) を出す。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/comfort_twin/twin_compare_page.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_metric_tile.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';
import '../type_scale/type_scale_scenarios.dart';

const bool _verbose = bool.fromEnvironment('MRW_QA_VERBOSE');

const _locales = [Locale('ja'), Locale('en'), Locale('es'), Locale('zh')];
const _scales = [1.0, 1.3, 2.0];

/// U-1 の組み合わせ (名前, UV, US AQI, 風速の単位, 詳細の気温 °C, 温度の単位)。
/// 風は 45 m/s (「45.0 m/s」「162 km/h」「101 mph」= 各単位で最も桁が多い表示)。
const _combos = <(String, double, int, WindSpeedUnit, double, TemperatureUnit)>[
  (
    'UV2・AQI50 (区分1)・45.0 m/s',
    2.0,
    50,
    WindSpeedUnit.metersPerSecond,
    -12.0,
    TemperatureUnit.celsius,
  ),
  (
    'UV5・AQI100 (区分2)・162 km/h',
    5.0,
    100,
    WindSpeedUnit.kilometersPerHour,
    -12.0,
    TemperatureUnit.celsius,
  ),
  (
    'UV7・AQI104 (区分3)・101 mph',
    7.0,
    104,
    WindSpeedUnit.milesPerHour,
    40.0,
    TemperatureUnit.fahrenheit,
  ),
  (
    'UV10・AQI200 (区分4)・45.0 m/s',
    10.0,
    200,
    WindSpeedUnit.metersPerSecond,
    -12.0,
    TemperatureUnit.celsius,
  ),
  (
    'UV11・AQI300 (区分5)・162 km/h',
    11.0,
    300,
    WindSpeedUnit.kilometersPerHour,
    -12.0,
    TemperatureUnit.celsius,
  ),
  (
    'UV14・AQI500 (区分6)・101 mph',
    14.0,
    500,
    WindSpeedUnit.milesPerHour,
    40.0,
    TemperatureUnit.fahrenheit,
  ),
];
const double _windMs = 45;

const Set<String> _unitSymbols = {'%', 'm/s', 'km/h', 'mph', 'hPa'};

/// 倍率 1.0 でも値の下の行へ回ってよい段階語 (compliance §9-2 で許容した例外)。
const Set<String> _allowedSecondLine = {'Very unhealthy'};

// ── 既知の不具合の再現 (skip。修正したら該当を消して常時実行に戻す) ──────────
// `flutter test test/qa/metric_units_rc_test.dart --run-skipped` で再現する。

/// QA-20 (Sev3): Comfort-Twin の比較の見出し「Wind (km/h)」で、単位の記号が
/// 「(km/」「h)」と行をまたいで折れる (m/s も「(m/」「s)」)。360dp で折れる組。
/// 2026-09-30 に解消 (見出しの記号は WindSpeedUnit.nonBreakingSymbol = 「/」の前後に
/// U+2060)。以前は ('ja', 2.0, 'km/h')・('en', 1.3, 'km/h')・('es', 1.3, 'm/s')・
/// ('zh', 2.0, 'km/h') で折れていた。
final Set<(String, double, String)> _qa20 = {};

/// QA-21 (Sev3): 設定トップの「通知」の副題が en の 360dp × 倍率 2.0 で 3 行
/// 必要になり、2 行目の末尾で省略される (「Heatstroke, violent wind, h…」)。
final Set<(String, double)> _qa21 = {('en', 2.0)};

// ── 計測の部品 ────────────────────────────────────────────────────────────

/// 段落の描画上の矩形 (FittedBox の縮小込み、画面座標)。
Rect _paintedRect(RenderParagraph p) => Rect.fromPoints(
      p.localToGlobal(Offset.zero),
      p.localToGlobal(p.size.bottomRight(Offset.zero)),
    );

/// FittedBox などで縮小された率 (1.0 = 縮小なし)。
double _fit(RenderParagraph p) =>
    p.size.height == 0 ? 1 : _paintedRect(p).height / p.size.height;

/// 段落のアルファベットのベースライン (画面座標。縮小込み)。
double _baseline(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textHeightBehavior: p.textHeightBehavior,
    maxLines: p.maxLines,
  )..layout();
  final distance =
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.dispose();
  return p.localToGlobal(Offset(0, distance)).dy;
}

/// [start, end) の文字が載っている行の数。
int _lines(RenderParagraph p, [int start = 0, int? end]) {
  final to = end ?? p.text.toPlainText().length;
  if (to <= start) return 1;
  return p
      .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: to))
      .map((b) => b.top.round())
      .toSet()
      .length;
}

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isCjk(int c) =>
    (c >= 0x2E80 && c <= 0x9FFF) ||
    (c >= 0xAC00 && c <= 0xD7AF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFF00 && c <= 0xFFEF);

bool _isWordChar(String ch) =>
    ch.isNotEmpty && !_isCjk(ch.codeUnitAt(0)) && _wordChar.hasMatch(ch);

/// 段落 [p] の中で、語の途中 (英数字どうしの間) で折れている箇所。
List<String> _midWordBreaksIn(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final found = <String>[];
  var previousY =
      p.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero).dy;
  for (var i = 1; i < text.length; i++) {
    final y = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
    if (y > previousY + 0.5) {
      final prev = text.substring(i - 1, i);
      final next = text.substring(i, i + 1);
      if (_isWordChar(prev) && _isWordChar(next)) found.add('$prev/$next');
    }
    previousY = y;
  }
  return found;
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 通知の表示を記録するだけのゲートウェイ (プラットフォームの通知は出さない)。
class _RecordingGateway implements NotificationGateway {
  final shown = <({int id, String title, String body, bool critical})>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    shown.add((id: id, title: title, body: body, critical: critical));
  }
}

void main() {
  setUpAll(loadAppFonts);

  final preset = MrwTypeScale.fromEnvironment;
  // U-1 の縮小率の最小 (幅 × 倍率ごと。verbose のときだけ出す)。
  final worstFit = <String, (double, String)>{};

  tearDownAll(() {
    if (!_verbose) return;
    for (final e in worstFit.entries) {
      // ignore: avoid_print
      print('QA11_TILE_WORST|${e.key}|eff=${e.value.$1.toStringAsFixed(3)}|'
          '${e.value.$2}');
    }
  });

  group('U-1 指標タイル: 全区分 × 3 単位 × 4 言語 × 倍率 × 360 / 320dp', () {
    for (final screen in const ['ホーム現在地', '詳細']) {
      final detail = screen == '詳細';
      final base = detail ? 84.0 : 72.0;
      for (final width in const [360.0, 320.0]) {
        for (final scale in _scales) {
          for (final locale in _locales) {
            for (final (name, uv, aqi, windUnit, celsius, tempUnit)
                in _combos) {
              testWidgets(
                  '$screen ${width.toInt()}dp ×$scale '
                  '${locale.languageCode} $name', (tester) async {
                await kTypeScaleScenarios[screen]!(
                  tester,
                  TypeScaleCase(
                    brightness: Brightness.dark,
                    locale: locale,
                    typeScale: preset,
                    textScale: scale,
                    // 縦は伸ばして全タイルを組み立てる (横の溢れを見る)。
                    viewport: Size(width, 4000),
                    uvIndex: uv,
                    aqi: aqi,
                    windSpeed: _windMs,
                    humidity: 100,
                    windUnit: windUnit,
                    temperature: celsius,
                    unit: tempUnit,
                  ),
                );
                expect(tester.takeException(), isNull);

                final tiles = find.byType(QuietMetricTile);
                expect(tiles, findsNWidgets(detail ? 6 : 4));
                final t =
                    AppLocalizations.of(tester.element(find.byType(MainShell)));
                Finder inTiles(String text) =>
                    find.descendant(of: tiles, matching: find.text(text));

                // 組み合わせが実際に出ている (値・単位・段階語)。
                expect(inTiles('${uv.round()}'), findsOneWidget);
                // 区分 2 の AQI 100 は湿度 100% の値と同じ文字なので 2 つ。
                expect(inTiles('$aqi'),
                    aqi == 100 ? findsNWidgets(2) : findsOneWidget);
                expect(inTiles(windUnit.formatValue(_windMs)), findsOneWidget);
                expect(inTiles(windUnit.symbol), findsOneWidget);
                if (locale.languageCode == 'es' && aqi == 104) {
                  expect(inTiles('Deficiente'), findsOneWidget);
                }
                if (locale.languageCode == 'en' && aqi == 300) {
                  expect(inTiles('Very unhealthy'), findsOneWidget);
                }
                if (detail) {
                  expect(
                      inTiles(tempUnit.formatDegrees(celsius)), findsOneWidget);
                  expect(inTiles('hPa'), findsOneWidget);
                }
                expect(t.aqiLevelVeryUnhealthy, isNot('Harmful'));

                for (final tile in tiles.evaluate()) {
                  final box = tile.renderObject! as RenderBox;
                  final rect = box.localToGlobal(Offset.zero) & box.size;
                  final texts = find
                      .descendant(
                        of: find.byElementPredicate((e) => e == tile),
                        matching: find.byType(Text),
                      )
                      .evaluate()
                      .toList();
                  // 見出し・値・(後ろの文字) の順。
                  expect(texts.length, inInclusiveRange(2, 3));
                  final paragraphs = [
                    for (final e in texts) e.renderObject! as RenderParagraph,
                  ];
                  for (final (i, e) in texts.indexed) {
                    final text = e.widget as Text;
                    final p = paragraphs[i];
                    expect(p.didExceedMaxLines, isFalse, reason: text.data);
                    if (i > 0) {
                      // 値と後ろの文字は省略しない・1 行。
                      expect(text.overflow, isNot(TextOverflow.ellipsis),
                          reason: text.data);
                      expect(_lines(p), 1, reason: '「${text.data}」が 2 行');
                    }
                    final r = _paintedRect(p);
                    expect(r.left, greaterThanOrEqualTo(rect.left - 0.5),
                        reason: text.data);
                    expect(r.right, lessThanOrEqualTo(rect.right + 0.5),
                        reason: '「${text.data}」がタイルの右にはみ出す');
                    expect(r.bottom, lessThanOrEqualTo(rect.bottom + 0.5),
                        reason: text.data);
                    if (i > 0) {
                      final eff = _fit(p) * scale;
                      if (_verbose) {
                        // ignore: avoid_print
                        print('QA11_TILE|$screen|${width.toInt()}dp|x$scale|'
                            '${locale.languageCode}|${text.data}|'
                            'fit=${_fit(p).toStringAsFixed(3)}|'
                            'eff=${eff.toStringAsFixed(3)}');
                      }
                      final key = '${detail ? 'detail' : 'home'}|'
                          '${width.toInt()}dp|x$scale';
                      final worst = worstFit[key];
                      if (worst == null || eff < worst.$1) {
                        worstFit[key] = (
                          eff,
                          '${locale.languageCode} 「${text.data}」 '
                              'fit=${_fit(p).toStringAsFixed(3)}',
                        );
                      }
                      // 360dp では、縮小しても倍率 1.0 の大きさを下回らない。
                      if (width >= 360) {
                        expect(eff, greaterThanOrEqualTo(0.99),
                            reason: '「${text.data}」が倍率 1.0 より小さい '
                                '(縮小 ${_fit(p).toStringAsFixed(3)})');
                      }
                    }
                  }
                  if (texts.length < 3) continue;
                  final value = paragraphs[1];
                  final trailing = paragraphs[2];
                  final trailingText = (texts[2].widget as Text).data!;
                  final vr = _paintedRect(value);
                  final tr = _paintedRect(trailing);
                  final sameLine =
                      (_baseline(trailing) - _baseline(value)).abs() <= 0.5;
                  if (_unitSymbols.contains(trailingText)) {
                    // 単位は値から離さない (同じ行・値の右)。
                    expect(sameLine, isTrue, reason: '$trailingText が値と別の行');
                    expect(tr.left, greaterThan(vr.right - 0.5),
                        reason: trailingText);
                  } else if (sameLine) {
                    expect(tr.left, greaterThan(vr.right - 0.5),
                        reason: trailingText);
                  } else {
                    // 段階語は値の真下 (左端をそろえる)。
                    expect(tr.top, greaterThanOrEqualTo(vr.bottom - 0.5),
                        reason: '「$trailingText」が値に重なる');
                    expect((tr.left - vr.left).abs(), lessThanOrEqualTo(1.0),
                        reason: trailingText);
                    if (scale == 1.0 && width >= 360) {
                      expect(_allowedSecondLine, contains(trailingText),
                          reason: '倍率 1.0 で「$trailingText」が次の行に回った');
                    }
                  }
                }

                // 同じ行の 2 枚は同じ高さ。360dp の倍率 1.0 は Figma の高さのまま
                // (en「Very unhealthy」の行だけ例外)。
                final rows = find.byType(QuietMetricTileRow);
                expect(rows, findsNWidgets(detail ? 3 : 2));
                for (final row in rows.evaluate()) {
                  final pair = find.descendant(
                    of: find.byElementPredicate((e) => e == row),
                    matching: tiles,
                  );
                  final left = tester.getSize(pair.at(0)).height;
                  final right = tester.getSize(pair.at(1)).height;
                  expect(right, closeTo(left, 0.01));
                  if (scale == 1.0 && width >= 360) {
                    final exception = find
                        .descendant(
                          of: find.byElementPredicate((e) => e == row),
                          matching: find.text('Very unhealthy'),
                        )
                        .evaluate()
                        .isNotEmpty;
                    if (!exception) expect(left, base);
                  }
                }
              });
            }
          }
        }
      }
    }
  });

  group('U-2 設定 › 一般: 風速の単位 (360dp)', () {
    for (final locale in _locales) {
      for (final scale in _scales) {
        testWidgets('${locale.languageCode} ×$scale', (tester) async {
          await kTypeScaleScenarios['一般設定']!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: preset,
              textScale: scale,
              viewport: const Size(360, 3000),
            ),
          );
          expect(tester.takeException(), isNull);
          final t = AppLocalizations.of(
              tester.element(find.byType(GeneralSettingsPage)));

          // 見出し (画面では大文字)。語の途中で折れない・省略しない。
          final heading = find.text(t.settingsWindSpeedUnit.toUpperCase());
          expect(heading, findsOneWidget);
          final hp = tester.renderObject<RenderParagraph>(heading);
          expect(hp.didExceedMaxLines, isFalse);
          expect(_midWordBreaksIn(hp), isEmpty,
              reason: '「${t.settingsWindSpeedUnit}」が語の途中で折れた');
          final pageRect = tester.getRect(find.byType(GeneralSettingsPage));
          expect(_paintedRect(hp).right, lessThanOrEqualTo(pageRect.right));

          // 切替: 記号は訳さず大文字にしない。省略されず 1 行で枠の内側。
          for (final unit in WindSpeedUnit.values) {
            final label = find.text(unit.symbol);
            expect(label, findsOneWidget, reason: unit.symbol);
            final p = tester.renderObject<RenderParagraph>(label);
            expect(p.didExceedMaxLines, isFalse,
                reason: '「${unit.symbol}」が省略された');
            expect(_lines(p), 1, reason: unit.symbol);
            final segment = tester.getRect(
                find.ancestor(of: label, matching: find.byType(InkWell)).first);
            final r = _paintedRect(p);
            expect(r.left, greaterThanOrEqualTo(segment.left - 0.5));
            expect(r.right, lessThanOrEqualTo(segment.right + 0.5));
          }

          // 温度の単位の切替 (ja は「℃ / ℉」、ほかは「°C / °F」)。
          final ja = locale.languageCode == 'ja';
          expect(t.unitCelsius, ja ? '℃' : '°C');
          expect(t.unitFahrenheit, ja ? '℉' : '°F');
          for (final symbol in [t.unitCelsius, t.unitFahrenheit]) {
            final p = tester.renderObject<RenderParagraph>(find.text(symbol));
            expect(p.didExceedMaxLines, isFalse, reason: symbol);
            expect(_lines(p), 1, reason: symbol);
          }
        });
      }
    }
  });

  group('U-3 設定トップ: 通知の副題 (360dp)', () {
    for (final locale in _locales) {
      for (final scale in _scales) {
        testWidgets('${locale.languageCode} ×$scale',
            skip: _qa21.contains((locale.languageCode, scale)), (tester) async {
          await kTypeScaleScenarios['設定トップ']!(
            tester,
            TypeScaleCase(
              brightness: Brightness.dark,
              locale: locale,
              typeScale: preset,
              textScale: scale,
              viewport: const Size(360, 3000),
            ),
          );
          expect(tester.takeException(), isNull);
          final t = AppLocalizations.of(tester.element(find.byType(MainShell)));
          final subtitle = find.text(t.settingsNotificationsSubtitle);
          expect(subtitle, findsOneWidget);
          final p = tester.renderObject<RenderParagraph>(subtitle);
          expect(p.didExceedMaxLines, isFalse,
              reason: '「${t.settingsNotificationsSubtitle}」が省略された');
          expect(_midWordBreaksIn(p), isEmpty);
        });
      }
    }
  });

  group('U-4 Comfort-Twin の比較: 風 (単位) (360dp)', () {
    for (final locale in _locales) {
      for (final scale in _scales) {
        for (final unit in WindSpeedUnit.values) {
          testWidgets('${locale.languageCode} ×$scale ${unit.symbol}',
              skip: _qa20.contains((locale.languageCode, scale, unit.symbol)),
              (tester) async {
            final overrides = await settingsOverrides();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(kPrefKeyWindSpeedUnit, unit.toTag());
            _useViewport(tester, const Size(360, 3000));
            await tester.pumpWidget(goldenApp(
              home: TwinComparePage(other: twinCandidates().first),
              brightness: Brightness.dark,
              locale: locale,
              overrides: overrides,
              typeScale: preset,
              textScale: scale,
            ));
            await settle(tester);
            expect(tester.takeException(), isNull);
            final t = AppLocalizations.of(
                tester.element(find.byType(TwinComparePage)));
            // 見出しの記号は「/」の前後に U+2060 (幅 0) が入る (QA-20 の修正)。
            final symbol = unit.nonBreakingSymbol;
            final text = '${t.statWind} ($symbol)';
            final label = find.text(text);
            expect(label, findsOneWidget, reason: text);
            final p = tester.renderObject<RenderParagraph>(label);
            expect(p.didExceedMaxLines, isFalse);
            // 単位の記号は途中で折れない。
            final start = text.length - symbol.length - 1;
            expect(_lines(p, start, start + symbol.length), 1,
                reason: '「$text」の記号が折れた');
            expect(_midWordBreaksIn(p), isEmpty, reason: text);
          });
        }
      }
    }
  });

  testWidgets(
      'U-5 設定 › 一般で風速の単位を切り替えると、ホーム・詳細・Twin の比較・'
      '暴風の緊急通知 (デバッグ発火) が追従する', (tester) async {
    const locale = Locale('en');
    final gateway = _RecordingGateway();
    final overrides = [
      ...await placesBaseOverrides(locale: locale, city: 'Tokyo'),
      ...entitlementOverrides(plus: false),
      ...savedPlaceWeatherOverrides(),
      notificationGatewayProvider.overrideWithValue(gateway),
    ];
    final prefs = await SharedPreferences.getInstance();
    _useViewport(tester, kGoldenSize);
    await tester.pumpWidget(goldenApp(
      home: const MainShell(),
      brightness: Brightness.light,
      locale: locale,
      overrides: overrides,
    ));
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(MainShell)));
    final wind = comfortableSnapshot(kPlacesNow).windSpeed!;
    Finder inTiles(String text) => find.descendant(
        of: find.byType(QuietMetricTile), matching: find.text(text));

    Future<void> openSettings(String row) async {
      await tester.tap(find.byKey(const ValueKey('quiet-nav-2')));
      await settle(tester);
      await tester.tap(find.text(row));
      await settle(tester);
    }

    Future<void> pop() async {
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await settle(tester);
    }

    // 初期値 (日本の端末) は m/s。
    expect(inTiles(WindSpeedUnit.metersPerSecond.symbol), findsOneWidget);
    expect(prefs.getString(kPrefKeyWindSpeedUnit), isNull);

    // 暴風のデバッグ発火は 25 m/s (debug_emergency_triggers.dart の Storm: severe)。
    const expectations = [
      (WindSpeedUnit.kilometersPerHour, '90 km/h'),
      (WindSpeedUnit.milesPerHour, '56 mph'),
      (WindSpeedUnit.metersPerSecond, '25 m/s'),
    ];
    for (final (unit, storm) in expectations) {
      // 設定 › 一般で切り替える (保存される)。
      await openSettings(t.settingsGeneral);
      await tester.tap(find.text(unit.symbol));
      await settle(tester);
      expect(prefs.getString(kPrefKeyWindSpeedUnit), unit.toTag());
      await pop();

      // ホーム: 風のタイル。
      await tester.tap(find.byKey(const ValueKey('quiet-nav-0')));
      await settle(tester);
      expect(inTiles(unit.symbol), findsOneWidget, reason: 'ホーム ${unit.name}');
      expect(inTiles(unit.formatValue(wind)), findsOneWidget);

      // 詳細: 風のタイル。
      await tester.tap(find.byKey(const ValueKey('quiet-nav-1')));
      await settle(tester);
      expect(inTiles(unit.symbol), findsOneWidget, reason: '詳細 ${unit.name}');
      expect(inTiles(unit.formatValue(wind)), findsOneWidget);

      // Comfort-Twin の比較 (同じアプリの Navigator に積む)。
      unawaited(Navigator.of(tester.element(find.byType(MainShell)))
          .push(MaterialPageRoute<void>(
        builder: (_) => TwinComparePage(other: twinCandidates().first),
      )));
      await settle(tester);
      expect(find.text('${t.statWind} (${unit.nonBreakingSymbol})'),
          findsOneWidget,
          reason: 'Twin ${unit.name}');
      await pop();

      // 暴風の緊急通知: 設定 › 通知のデバッグ発火 (本番と同じ表示経路)。
      await openSettings(t.settingsNotifications);
      gateway.shown.clear();
      final stormRow = find.text('Storm: severe');
      await tester.ensureVisible(stormRow);
      await tester.tap(stormRow);
      await settle(tester);
      expect(gateway.shown, hasLength(1));
      final shown = gateway.shown.single;
      expect(shown.title, t.emergencyStormTitle);
      final lines = shown.body.split('\n');
      expect(lines.first, t.emergencyStormBody(storm), reason: shown.body);
      expect(lines.last, t.emergencyDisclaimer);
      await pop();
    }
  });
}
