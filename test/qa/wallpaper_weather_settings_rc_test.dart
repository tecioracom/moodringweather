// test/qa/wallpaper_weather_settings_rc_test.dart
//
// 1.3.0 (13) の回帰テスト: 設定 › 一般の「ライブ壁紙」の区画とトグル行
// (docs/design-wallpaper-weather-overlay.md §6。2026-09-30 決裁)。
// 360dp × 文字倍率 1.0 / 1.3 / 2.0 × 4 言語 (ja・en・es・zh) で:
//   - 溢れ例外なし
//   - 区画ラベル (EN / ES は大文字) と見出しは省略されず、語の途中で折れない
//   - 説明は 2 行まで (QuietListRow の決まり)。倍率 1.0 / 1.3 では省略しない
//     (×2.0 の en「At the top right of the live wallpaper」・es は 2 行で省略される。
//     設計書 §6 の「説明は 2 行まで」どおり。見出しは省略しない)
//   - スイッチは行の内側で、見出し・説明と重ならない。行の高さは 58 以上
//   - 区画はテーマの下
// 画面の組み立ては type_scale_scenarios.dart の「一般設定」と同じ。
//
// 1.3.0 (14): 区画の先頭の「ライブ壁紙を設定」の行 (2026-10-01 Galaxy で発見。One UI は
// 他社アプリのライブ壁紙を壁紙設定の一覧に出さない)。同じ 360dp × 3 倍率 × 4 言語 ×
// 未設定 / 設定中 で:
//   - 溢れ例外なし。見出しは省略されず、語の途中で折れない
//   - 説明は 2 行まで。倍率 1.0 / 1.3 では省略しない
//   - 「設定中」のバッジは省略されない。見出し・説明・シェブロンと重ならない。等倍では
//     見出しの右 (シェブロンの左)、1 行に収まらない倍率では見出しの下 (説明の上)
//   - シェブロンは行の内側。行はトグル行の上

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/shared/glass_card.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_row_icons.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';

import '../golden/golden_harness.dart';
import '../type_scale/type_scale_scenarios.dart';

const _locales = [
  Locale('ja'),
  Locale('en'),
  Locale('es'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];
const _scales = [1.0, 1.3, 2.0];

Rect _painted(RenderParagraph p) => Rect.fromPoints(
      p.localToGlobal(Offset.zero),
      p.localToGlobal(p.size.bottomRight(Offset.zero)),
    );

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isCjk(int c) =>
    (c >= 0x2E80 && c <= 0x9FFF) ||
    (c >= 0xAC00 && c <= 0xD7AF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFF00 && c <= 0xFFEF);

bool _isWordChar(String ch) =>
    ch.isNotEmpty && !_isCjk(ch.codeUnitAt(0)) && _wordChar.hasMatch(ch);

/// 段落 [p] の中で、語の途中 (英数字どうしの間) で折れている箇所。
List<String> _midWordBreaks(RenderParagraph p) {
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

void main() {
  setUpAll(loadAppFonts);
  final preset = MrwTypeScale.fromEnvironment;

  group('設定 › 一般: ライブ壁紙のトグル行 (360dp)', () {
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
          final page = tester.getRect(find.byType(GeneralSettingsPage));

          // 区画ラベル: テーマの下。省略されず、語の途中で折れない。
          final label = find.text(t.settingsLiveWallpaper.toUpperCase());
          expect(label, findsOneWidget);
          final lp = tester.renderObject<RenderParagraph>(label);
          expect(lp.didExceedMaxLines, isFalse);
          expect(_midWordBreaks(lp), isEmpty);
          expect(_painted(lp).right, lessThanOrEqualTo(page.right));
          final theme = find.text(t.settingsTheme.toUpperCase());
          expect(_painted(lp).top,
              greaterThan(_painted(tester.renderObject(theme)).bottom));

          // 見出し: 折り返してよいが、語の途中では折れない。
          final title = find.text(t.settingsWallpaperWeather);
          expect(title, findsOneWidget);
          final tp = tester.renderObject<RenderParagraph>(title);
          expect(tp.didExceedMaxLines, isFalse);
          expect(_midWordBreaks(tp), isEmpty,
              reason: '「${t.settingsWallpaperWeather}」が語の途中で折れた');

          // 説明: 2 行まで。倍率 1.0 / 1.3 では省略しない (×2.0 の en・es は省略される)。
          final hint = find.text(t.settingsWallpaperWeatherHint);
          expect(hint, findsOneWidget);
          final hp = tester.renderObject<RenderParagraph>(hint);
          expect(_midWordBreaks(hp), isEmpty);
          if (scale <= 1.3) {
            expect(hp.didExceedMaxLines, isFalse,
                reason: '「${t.settingsWallpaperWeatherHint}」が省略された');
          }

          // スイッチ: 行の内側で、見出し・説明と重ならない。行の高さは 58 以上。
          final row =
              find.ancestor(of: title, matching: find.byType(QuietCard));
          final rowRect = tester.getRect(row.first);
          expect(rowRect.height, greaterThanOrEqualTo(58));
          expect(rowRect.right, lessThanOrEqualTo(page.right));
          final toggle = tester.getRect(find.byType(Switch));
          expect(toggle.left, greaterThanOrEqualTo(rowRect.left));
          expect(toggle.right, lessThanOrEqualTo(rowRect.right + 0.5));
          expect(toggle.top, greaterThanOrEqualTo(rowRect.top - 0.5));
          expect(toggle.bottom, lessThanOrEqualTo(rowRect.bottom + 0.5));
          expect(_painted(tp).right, lessThanOrEqualTo(toggle.left));
          expect(_painted(hp).right, lessThanOrEqualTo(toggle.left));
        });
      }
    }
  });

  group('設定 › 一般: 「ライブ壁紙を設定」の行 (360dp)', () {
    for (final active in const [false, true]) {
      for (final locale in _locales) {
        for (final scale in _scales) {
          final state = active ? '設定中' : '未設定';
          testWidgets('$state ${locale.languageCode} ×$scale', (tester) async {
            tester.view.physicalSize = const Size(360, 3000);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(goldenApp(
              home: const GeneralSettingsPage(),
              brightness: Brightness.dark,
              locale: locale,
              overrides: [
                ...await settingsOverrides(),
                liveWallpaperSetupBridgeProvider
                    .overrideWithValue(_FixedSetup(active: active)),
              ],
              typeScale: preset,
              textScale: scale,
            ));
            await settle(tester);
            expect(tester.takeException(), isNull);

            final t = AppLocalizations.of(
                tester.element(find.byType(GeneralSettingsPage)));
            final page = tester.getRect(find.byType(GeneralSettingsPage));

            // 見出し: 省略されず、語の途中で折れない。
            final title = find.text(t.settingsLiveWallpaperSet);
            expect(title, findsOneWidget);
            final tp = tester.renderObject<RenderParagraph>(title);
            expect(tp.didExceedMaxLines, isFalse);
            expect(_midWordBreaks(tp), isEmpty,
                reason: '「${t.settingsLiveWallpaperSet}」が語の途中で折れた');

            // 説明: 2 行まで。倍率 1.0 / 1.3 では省略しない。
            final hintText = active
                ? t.settingsLiveWallpaperSetActiveHint
                : t.settingsLiveWallpaperSetHint;
            final hint = find.text(hintText);
            expect(hint, findsOneWidget);
            final hp = tester.renderObject<RenderParagraph>(hint);
            expect(_midWordBreaks(hp), isEmpty);
            if (scale <= 1.3) {
              expect(hp.didExceedMaxLines, isFalse,
                  reason: '「$hintText」が省略された');
            }

            // 行: 区画の先頭 (トグル行の上)。シェブロンは行の内側で、文字と重ならない。
            final row =
                find.ancestor(of: title, matching: find.byType(QuietCard));
            final rowRect = tester.getRect(row.first);
            expect(rowRect.right, lessThanOrEqualTo(page.right));
            final toggleRow = tester.getRect(find
                .ancestor(
                  of: find.text(t.settingsWallpaperWeather),
                  matching: find.byType(QuietCard),
                )
                .first);
            expect(toggleRow.top, greaterThanOrEqualTo(rowRect.bottom));
            final chevron = tester.getRect(find.descendant(
              of: row.first,
              matching: find.byWidgetPredicate((w) =>
                  w is QuietRowIconMark && w.icon == QuietRowIcon.chevron),
            ));
            expect(chevron.right, lessThanOrEqualTo(rowRect.right + 0.5));
            expect(chevron.top, greaterThanOrEqualTo(rowRect.top - 0.5));
            expect(chevron.bottom, lessThanOrEqualTo(rowRect.bottom + 0.5));
            expect(_painted(tp).right, lessThanOrEqualTo(chevron.left));
            expect(_painted(hp).right, lessThanOrEqualTo(chevron.left));

            // 「設定中」: 省略されない。見出し・説明・シェブロンと重ならず、説明より上。
            // 見出しと 1 行に収まれば見出しの右 (倍率 1.0 ではどの言語も)、収まらなければ
            // 見出しの下。
            final badge = find.text(t.settingsLiveWallpaperActive);
            if (!active) {
              expect(badge, findsNothing);
              return;
            }
            expect(badge, findsOneWidget);
            final bp = tester.renderObject<RenderParagraph>(badge);
            expect(bp.didExceedMaxLines, isFalse,
                reason: '「${t.settingsLiveWallpaperActive}」が省略された');
            final badgeBox = tester.getRect(find
                .ancestor(of: badge, matching: find.byType(QuietBadge))
                .first);
            expect(badgeBox.overlaps(_painted(tp)), isFalse);
            expect(badgeBox.overlaps(_painted(hp)), isFalse);
            expect(badgeBox.right, lessThanOrEqualTo(chevron.left));
            expect(badgeBox.top, greaterThanOrEqualTo(rowRect.top));
            expect(badgeBox.bottom, lessThanOrEqualTo(_painted(hp).top + 0.5));
            final sameLine = badgeBox.center.dy < _painted(tp).bottom;
            if (sameLine) {
              expect(badgeBox.left, greaterThanOrEqualTo(_painted(tp).right));
            } else {
              expect(badgeBox.top,
                  greaterThanOrEqualTo(_painted(tp).bottom - 0.5));
            }
            if (scale == 1.0) {
              expect(sameLine, isTrue, reason: '等倍で「設定中」が見出しの右に収まらない');
            }
          });
        }
      }
    }
  });
}

/// 「設定中」を固定で返す壁紙の設定 (ネイティブを呼ばない)。
class _FixedSetup implements LiveWallpaperSetupBridge {
  const _FixedSetup({required this.active});
  final bool active;

  @override
  Future<bool> openPicker() async => true;

  @override
  Future<bool> isActive() async => active;
}
