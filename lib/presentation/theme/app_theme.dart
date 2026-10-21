// lib/presentation/theme/app_theme.dart
//
// アプリの ThemeData を 1 箇所で組み立てる (main.dart とゴールデンテストで共用)。
//
// 段階 S1 (docs/v1.3-design-implementation-plan.md §3): v1.3 のトークン (MrwTokens)
// を ThemeData に登録し、Material 3 の ColorScheme を「Quiet Instrument」の
// ニュートラルへ対応付ける。
// 段階 S2: 書体を v1.3 に (Figma 3:2 / 24:6 / 3:356 / 77:195 実測)。
//   EN: 見出し = Fraunces (可変: wght 400 / opsz = 文字サイズ / SOFT 0 / WONK 1)、
//       数値・本文 = Inter (可変: wght)、ラベル・メタ = IBM Plex Mono Medium (大文字・字間)。
//   JA: IBM Plex Sans JP (見出し・本文 Regular / 見出し強調 Bold / ラベル Medium)。
//       例外はグラフの軸ラベル: Figma JP でも Plex Mono で組まれているため、
//       shared/chart_axes.dart の axisLabelStyle がロケールに関係なく Plex Mono を指定する。
//   es / zh: EN と同じ (Figma に専用ページなし)。zh の簡体字は Plex Sans JP に無い字形が
//   あるため、端末のシステム CJK フォントへ自動フォールバックする (従来どおり)。
// 可変フォントは pubspec で weight を宣言できないため、TextStyle.fontVariations で
// 軸を指定する。fontWeight も併せて指定する (フォント照合と意味付けのため)。
//
// ColorScheme の対応 (Figma → M3 の役割):
//   surface / scaffold        = bg (onyx-900 / #F5F7FA)
//   surfaceContainer*         = surfaceLow / surface / surfaceHigh (onyx-800/700/600)
//   onSurface / onSurfaceVariant = textHi / textMid
//   primary / onPrimary       = action/primary/fill / label (無彩色。塗りボタン)
//   secondaryContainer        = surfaceHigh (ナビの選択ピル・チップ地)
//   error                     = action/destructive/label
//   outline / outlineVariant  = border 9% / 6%
//   surfaceTint               = 透明 (M3 の紫がかった elevation tint を消す)
//
// 型スケール (mrw_type.dart): 文字サイズの役割トークン MrwType を ThemeExtension として
// 登録する。typeScale (省略時は --dart-define=MRW_TYPE_SCALE、未指定は既定の plus2 =
// 案2。2026-09-29 決裁) で案2 / 現状 (旧 v1.3) / 案1 を切り替える。TextTheme 自体
// (Material の既定サイズ) は変えない (ダイアログ・ピッカー等は designer の確定表で対象外)。

import 'package:flutter/material.dart';

import 'mrw_tokens.dart';
import 'mrw_type.dart';

/// 同梱フォントのファミリ名 (pubspec.yaml の fonts 宣言と一致させる)。
class MrwFonts {
  const MrwFonts._();

  static const String fraunces = 'Fraunces';
  static const String inter = 'Inter';
  static const String plexMono = 'IBMPlexMono';
  static const String plexSansJp = 'IBMPlexSansJP';

  /// JA ロケールか (Plex Sans JP を基底にする)。
  static bool isJa(Locale? locale) => locale?.languageCode == 'ja';

  /// Fraunces の軸 (Figma: fontVariationSettings "SOFT" 0, "WONK" 1)。
  /// opsz は文字サイズに合わせる (Flutter は自動適用しない)。
  static List<FontVariation> frauncesVariations(double size) => [
        const FontVariation('wght', 400),
        FontVariation('opsz', size.clamp(9, 144)),
        const FontVariation('SOFT', 0),
        const FontVariation('WONK', 1),
      ];

  /// Inter の wght 軸。
  static List<FontVariation> interVariations(FontWeight weight) =>
      [FontVariation('wght', weight.value.toDouble())];

  /// 数値用スタイル (温度・MRI・割合)。EN Inter / JA Plex Sans JP。
  /// 既存の呼び出し箇所の size / weight を保ったまま書体だけ切り替えるための入口。
  static TextStyle numeral(
    BuildContext context, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double? height,
    Color? color,
  }) {
    final ja = isJa(Localizations.maybeLocaleOf(context));
    return TextStyle(
      fontFamily: ja ? plexSansJp : inter,
      fontFamilyFallback: ja ? const [inter] : const [plexSansJp],
      fontVariations: ja ? null : interVariations(weight),
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color,
    );
  }
}

/// アプリの ThemeData。[typeScale] は文字サイズのプリセット (省略時は
/// `--dart-define=MRW_TYPE_SCALE` の指定、未指定なら既定の [MrwTypeScale.plus2])。
ThemeData buildAppTheme(
  Brightness brightness, {
  Locale? locale,
  MrwTypeScale? typeScale,
}) {
  final isDark = brightness == Brightness.dark;
  final ja = MrwFonts.isJa(locale);
  final tokens = isDark ? MrwTokens.dark : MrwTokens.light;
  final inverse = isDark ? MrwTokens.light : MrwTokens.dark;

  final scheme =
      (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: tokens.actionPrimaryFill,
    onPrimary: tokens.actionPrimaryLabel,
    primaryContainer: tokens.surfaceHigh,
    onPrimaryContainer: tokens.textHi,
    secondary: tokens.textMid,
    onSecondary: tokens.bg,
    secondaryContainer: tokens.surfaceHigh,
    onSecondaryContainer: tokens.textHi,
    tertiary: tokens.textLo,
    onTertiary: tokens.bg,
    tertiaryContainer: tokens.surface,
    onTertiaryContainer: tokens.textHi,
    error: tokens.actionDestructiveLabel,
    onError: tokens.bg,
    errorContainer: tokens.surface,
    onErrorContainer: tokens.actionDestructiveLabel,
    surface: tokens.bg,
    onSurface: tokens.textHi,
    surfaceDim: tokens.bg,
    surfaceBright: tokens.surfaceHigh,
    surfaceContainerLowest: tokens.bg,
    surfaceContainerLow: tokens.surfaceLow,
    surfaceContainer: tokens.surface,
    surfaceContainerHigh: tokens.surfaceHigh,
    surfaceContainerHighest: tokens.surfaceHigh,
    onSurfaceVariant: tokens.textMid,
    outline: tokens.border,
    outlineVariant: tokens.borderSubtle,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: inverse.bg,
    onInverseSurface: inverse.textHi,
    inversePrimary: inverse.actionPrimaryFill,
    surfaceTint: Colors.transparent,
  );

  // 基底書体: EN Inter / JA Plex Sans JP。もう片方をフォールバックに置き、
  // EN 画面の日本語 (都市名など) や JA 画面の英数字が同梱フォントで出るようにする。
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.bg,
    fontFamily: ja ? MrwFonts.plexSansJp : MrwFonts.inter,
    fontFamilyFallback:
        ja ? const [MrwFonts.inter] : const [MrwFonts.plexSansJp],
    extensions: [
      tokens,
      MrwType.forScale(typeScale ?? MrwTypeScale.fromEnvironment),
    ],
  );
  final text = base.textTheme;

  // 見出し (display / headline): EN Fraunces / JA Plex Sans JP Regular。
  TextStyle? heading(TextStyle? s) {
    if (s == null) return null;
    if (ja) {
      return s.copyWith(
        fontFamily: MrwFonts.plexSansJp,
        fontFamilyFallback: const [MrwFonts.fraunces, MrwFonts.inter],
        fontWeight: FontWeight.w400,
      );
    }
    return s.copyWith(
      fontFamily: MrwFonts.fraunces,
      fontFamilyFallback: const [MrwFonts.plexSansJp],
      fontWeight: FontWeight.w400,
      fontVariations: MrwFonts.frauncesVariations(s.fontSize ?? 24),
    );
  }

  // タイトル (title): EN Inter SemiBold / JA Plex Sans JP Bold。
  TextStyle? title(TextStyle? s) {
    if (s == null) return null;
    if (ja) {
      return s.copyWith(
        fontFamily: MrwFonts.plexSansJp,
        fontFamilyFallback: const [MrwFonts.inter],
        fontWeight: FontWeight.w700,
      );
    }
    return s.copyWith(
      fontFamily: MrwFonts.inter,
      fontFamilyFallback: const [MrwFonts.plexSansJp],
      fontWeight: FontWeight.w600,
      fontVariations: MrwFonts.interVariations(FontWeight.w600),
    );
  }

  // 本文 (body): EN Inter Regular / JA Plex Sans JP Regular。
  TextStyle? body(TextStyle? s) {
    if (s == null) return null;
    if (ja) {
      return s.copyWith(
        fontFamily: MrwFonts.plexSansJp,
        fontFamilyFallback: const [MrwFonts.inter],
        fontWeight: FontWeight.w400,
      );
    }
    return s.copyWith(
      fontFamily: MrwFonts.inter,
      fontFamilyFallback: const [MrwFonts.plexSansJp],
      fontWeight: FontWeight.w400,
      fontVariations: MrwFonts.interVariations(FontWeight.w400),
    );
  }

  // ラベル (label): EN IBM Plex Mono Medium / JA Plex Sans JP Medium。
  // Figma のラベルは大文字 + 字間 (0.55〜0.88)。字間だけテーマで持ち、大文字化は
  // 各画面が行う (S4 以降)。
  TextStyle? label(TextStyle? s, double letterSpacing) {
    if (s == null) return null;
    return s.copyWith(
      fontFamily: ja ? MrwFonts.plexSansJp : MrwFonts.plexMono,
      fontFamilyFallback:
          ja ? const [MrwFonts.plexMono] : const [MrwFonts.plexSansJp],
      fontWeight: FontWeight.w500,
      letterSpacing: letterSpacing,
    );
  }

  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: heading(text.displayLarge),
      displayMedium: heading(text.displayMedium),
      displaySmall: heading(text.displaySmall),
      headlineLarge: heading(text.headlineLarge),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: title(text.titleLarge),
      titleMedium: title(text.titleMedium),
      titleSmall: title(text.titleSmall),
      bodyLarge: body(text.bodyLarge),
      bodyMedium: body(text.bodyMedium),
      bodySmall: body(text.bodySmall),
      labelLarge: label(text.labelLarge, 0.88),
      labelMedium: label(text.labelMedium, 0.7),
      labelSmall: label(text.labelSmall, 0.6),
    ),
    // ボトムナビ: 選択ピルは浮いた面 (onyx-600 / #D8E0E8)、ラベルは主/副文字。
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: tokens.navActive,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: tokens.border,
  );
}
