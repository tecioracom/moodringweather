// lib/presentation/theme/mrw_tokens.dart
//
// v1.3「Quiet Instrument」のセマンティック・カラートークン (Figma
// sthT6fxeWWF33f9vENzFWW、コレクション `MRW Semantic` 16 変数 × Dark/Light、
// および Foundations — Tokens `2:53` の中立色)。値はすべて Figma から実測
// (docs/v1.3-design-implementation-plan.md §2 に出典ノードを記録)。
//
// 原則 (codex-fixes_v1.3_unified.md §2.3 / §4.1):
//   - 「色がついている = 体感か危険。色がないもの = 操作」。操作系は彩度ゼロ。
//   - 状態色は MRI 値そのものを表す要素 (ゲージの弧 / 帯ドット / MRI 数値) にだけ付く。
//     カード地・見出し・アイコン・区切り線・タブ・スイッチは常にニュートラル。
//   - `stateCold` / `stateFresh` はラベルを持たない (ランプの連続性のためだけに存在)。
//     単独のチップ・ドット・バッジには使わない。
//   - `stateDanger` (MRI 0–19「とても暑い」) は WBGT の「危険」とは別物。
//
// 使い方: `MrwTokens.of(context)` (ThemeExtension)。ThemeData への登録は
// app_theme.dart。

import 'package:flutter/material.dart';

@immutable
class MrwTokens extends ThemeExtension<MrwTokens> {
  const MrwTokens({
    required this.bg,
    required this.surfaceLow,
    required this.surface,
    required this.surfaceHigh,
    required this.textHi,
    required this.textMid,
    required this.textLo,
    required this.textMono,
    required this.inkMid,
    required this.noteText,
    required this.border,
    required this.borderSubtle,
    required this.navBackground,
    required this.navActive,
    required this.wash,
    required this.stateCold,
    required this.stateCool,
    required this.stateFresh,
    required this.stateComfortable,
    required this.stateWarm,
    required this.stateHot,
    required this.stateDanger,
    required this.actionPrimaryFill,
    required this.actionPrimaryLabel,
    required this.actionSecondaryFill,
    required this.actionSecondaryLabel,
    required this.actionSecondaryBorder,
    required this.actionTertiaryLabel,
    required this.actionDestructiveLabel,
    required this.plusBase,
    required this.plusTint,
    required this.plusBadge,
  });

  // ── 中立色 (Foundations 2:53 / Home 3:2 / Home Light 24:6) ─────────────
  /// 画面地。Dark onyx-900 / Light #F5F7FA (Home — Light 24:6 実測)。
  final Color bg;

  /// 一段沈んだ面 (Dynamic Island 等)。Dark onyx-800 / Light pearl-surface。
  final Color surfaceLow;

  /// カード地。Dark onyx-700 / Light white。
  final Color surface;

  /// 浮いた面 (ナビの選択ピル・アバター地)。Dark onyx-600 / Light #D8E0E8。
  final Color surfaceHigh;

  /// 主文字。Dark pearl / Light #151922。
  final Color textHi;

  /// 副文字 (本文・状態ラベル)。Dark text-mid / Light #56606B。
  final Color textMid;

  /// ラベル (mono 見出し・行の説明)。Dark text-lo / Light #838B96。
  final Color textLo;

  /// mono のメタ情報 (FEELS / STABLE / 軸数値 / 非選択タブ)。
  final Color textMono;

  /// 帯ラベル・インサイトドット・カプセルバーの基色 (Light は ink-mid)。
  final Color inkMid;

  /// 注記・バッジ文字 (指示書 §7.1 / §9: Dark #71767F / Light #80858E)。
  final Color noteText;

  /// カード枠 1px (9%)。
  final Color border;

  /// 選択ピル枠 1px (6%)。
  final Color borderSubtle;

  /// ボトムナビ地 (92%)。
  final Color navBackground;

  /// ボトムナビの選択ピル塗り。
  final Color navActive;

  /// 画面上部の State wash (グラデ起点、9%)。
  final Color wash;

  // ── 状態色 state/* (MRW Semantic §2.2。Dark = bright / Light = deep) ────
  final Color stateCold; // ランプ上端 (95–100)。ラベルなし
  final Color stateCool; // 80–100 涼しい / Cool
  final Color stateFresh; // ランプ中間 (75–85)。ラベルなし
  final Color stateComfortable; // 60–79 快適 / Comfortable
  final Color stateWarm; // 40–59 やや暑い / Slightly hot
  final Color stateHot; // 20–39 暑い / Hot
  final Color stateDanger; // 0–19 とても暑い / Very hot

  // ── 操作色 action/* (§2.3。彩度ゼロ) ────────────────────────────────────
  /// 塗りボタン。1 画面に 1 つまで。
  final Color actionPrimaryFill;
  final Color actionPrimaryLabel;

  /// 副ボタン。個数制限なし。Light は [actionSecondaryBorder] 1px を併用。
  final Color actionSecondaryFill;
  final Color actionSecondaryLabel;
  final Color actionSecondaryBorder;

  /// 塗りなしのテキストボタン。
  final Color actionTertiaryLabel;

  /// 破壊的操作。テキストのみ。塗り禁止。
  final Color actionDestructiveLabel;

  // ── 課金色 commerce/plus (§2.4。Dark/Light 共通) ─────────────────────────
  final Color plusBase;
  final Color plusTint;
  final Color plusBadge;

  static const Color _pearl = Color(0xFFF4F2EC);
  static const Color _onyx900 = Color(0xFF0D0E11);
  static const Color _onyx800 = Color(0xFF16181D);
  static const Color _onyx700 = Color(0xFF1E2128);
  static const Color _onyx600 = Color(0xFF262A32);
  static const Color _plus = Color(0xFF8B7BD8);

  /// Dark モード (Figma `MRW Semantic` Dark / Home 3:2 実測)。
  static const MrwTokens dark = MrwTokens(
    bg: _onyx900,
    surfaceLow: _onyx800,
    surface: _onyx700,
    surfaceHigh: _onyx600,
    textHi: _pearl,
    textMid: Color(0xFFAEB2BA),
    textLo: Color(0xFF71767F),
    textMono: Color(0xFF8A8F98),
    inkMid: Color(0xFFAEB2BA),
    noteText: Color(0xFF71767F),
    border: Color(0x17F4F2EC), // pearl 9%
    borderSubtle: Color(0x0FF4F2EC), // pearl 6%
    navBackground: Color(0xEB1E2128), // onyx-700 92%
    navActive: _onyx600,
    wash: Color(0x171E2128), // onyx-700 9%
    stateCold: Color(0xFF7B84F2),
    stateCool: Color(0xFF58A0EE),
    stateFresh: Color(0xFF38C0CC),
    stateComfortable: Color(0xFF46C795),
    stateWarm: Color(0xFFEBAE4A),
    stateHot: Color(0xFFF0795A),
    stateDanger: Color(0xFFE5533D),
    actionPrimaryFill: _pearl,
    actionPrimaryLabel: _onyx900,
    actionSecondaryFill: _onyx700,
    actionSecondaryLabel: _pearl,
    actionSecondaryBorder: Color(0x00000000),
    actionTertiaryLabel: Color(0xFFAEB2BA),
    actionDestructiveLabel: Color(0xFFE5533D),
    plusBase: _plus,
    plusTint: Color(0x1F8B7BD8), // 12%
    plusBadge: Color(0x528B7BD8), // 32%
  );

  /// Light モード (Figma `MRW Semantic` Light / Home — Light 24:6 実測)。
  static const MrwTokens light = MrwTokens(
    bg: Color(0xFFF5F7FA),
    surfaceLow: Color(0xFFFBFAF5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFD8E0E8),
    textHi: Color(0xFF151922),
    textMid: Color(0xFF56606B),
    textLo: Color(0xFF838B96),
    textMono: Color(0xFF6B7480),
    inkMid: Color(0xFF4A4E56),
    noteText: Color(0xFF80858E),
    border: Color(0x1717181C), // #17181C 9%
    borderSubtle: Color(0x0F17181C), // 6%
    navBackground: Color(0xEBFFFFFF), // white 92%
    navActive: Color(0xFFD8E0E8),
    wash: Color(0x17FBFAF5), // pearl-surface 9%
    stateCold: Color(0xFF5B63D6),
    stateCool: Color(0xFF3E7FD4),
    stateFresh: Color(0xFF269DA8),
    stateComfortable: Color(0xFF2FA37A),
    stateWarm: Color(0xFFC9871F),
    stateHot: Color(0xFFE0603C),
    stateDanger: Color(0xFFCE362B),
    actionPrimaryFill: _onyx900,
    actionPrimaryLabel: _pearl,
    actionSecondaryFill: Color(0xFFFBFAF5),
    actionSecondaryLabel: Color(0xFF14161A),
    actionSecondaryBorder: Color(0x1A14161A), // ink-hi 10%
    actionTertiaryLabel: Color(0xFF4A4E56),
    actionDestructiveLabel: Color(0xFFCE362B),
    plusBase: _plus,
    plusTint: Color(0x1F8B7BD8),
    plusBadge: Color(0x528B7BD8),
  );

  /// 現在のテーマのトークン。app_theme.dart で登録済み。
  static MrwTokens of(BuildContext context) =>
      Theme.of(context).extension<MrwTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// Foundations 2:53 のランプ (MRI 昇順: 0 = とても暑い → 100 = 涼〜極寒)。
  /// [rampStops] と対で SweepGradient / LinearGradient に渡す。
  List<Color> get rampColors => [
        stateDanger,
        stateHot,
        stateWarm,
        stateComfortable,
        stateFresh,
        stateCool,
        stateCold,
      ];

  static const List<double> rampStops = [
    0.0,
    0.20,
    0.40,
    0.60,
    0.78,
    0.90,
    1.0
  ];

  /// MRI 値 → 帯色 (指示書 §4.3。境界は下限を含む: 79 は快適、80 は涼しい)。
  /// ラベルを持たない cold / fresh は返さない (単独要素に使ってはならないため)。
  Color stateColorForMri(int mri) {
    final v = mri.clamp(0, 100);
    if (v >= 80) return stateCool;
    if (v >= 60) return stateComfortable;
    if (v >= 40) return stateWarm;
    if (v >= 20) return stateHot;
    return stateDanger;
  }

  @override
  MrwTokens copyWith({
    Color? bg,
    Color? surfaceLow,
    Color? surface,
    Color? surfaceHigh,
    Color? textHi,
    Color? textMid,
    Color? textLo,
    Color? textMono,
    Color? inkMid,
    Color? noteText,
    Color? border,
    Color? borderSubtle,
    Color? navBackground,
    Color? navActive,
    Color? wash,
    Color? stateCold,
    Color? stateCool,
    Color? stateFresh,
    Color? stateComfortable,
    Color? stateWarm,
    Color? stateHot,
    Color? stateDanger,
    Color? actionPrimaryFill,
    Color? actionPrimaryLabel,
    Color? actionSecondaryFill,
    Color? actionSecondaryLabel,
    Color? actionSecondaryBorder,
    Color? actionTertiaryLabel,
    Color? actionDestructiveLabel,
    Color? plusBase,
    Color? plusTint,
    Color? plusBadge,
  }) {
    return MrwTokens(
      bg: bg ?? this.bg,
      surfaceLow: surfaceLow ?? this.surfaceLow,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      textHi: textHi ?? this.textHi,
      textMid: textMid ?? this.textMid,
      textLo: textLo ?? this.textLo,
      textMono: textMono ?? this.textMono,
      inkMid: inkMid ?? this.inkMid,
      noteText: noteText ?? this.noteText,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      navBackground: navBackground ?? this.navBackground,
      navActive: navActive ?? this.navActive,
      wash: wash ?? this.wash,
      stateCold: stateCold ?? this.stateCold,
      stateCool: stateCool ?? this.stateCool,
      stateFresh: stateFresh ?? this.stateFresh,
      stateComfortable: stateComfortable ?? this.stateComfortable,
      stateWarm: stateWarm ?? this.stateWarm,
      stateHot: stateHot ?? this.stateHot,
      stateDanger: stateDanger ?? this.stateDanger,
      actionPrimaryFill: actionPrimaryFill ?? this.actionPrimaryFill,
      actionPrimaryLabel: actionPrimaryLabel ?? this.actionPrimaryLabel,
      actionSecondaryFill: actionSecondaryFill ?? this.actionSecondaryFill,
      actionSecondaryLabel: actionSecondaryLabel ?? this.actionSecondaryLabel,
      actionSecondaryBorder:
          actionSecondaryBorder ?? this.actionSecondaryBorder,
      actionTertiaryLabel: actionTertiaryLabel ?? this.actionTertiaryLabel,
      actionDestructiveLabel:
          actionDestructiveLabel ?? this.actionDestructiveLabel,
      plusBase: plusBase ?? this.plusBase,
      plusTint: plusTint ?? this.plusTint,
      plusBadge: plusBadge ?? this.plusBadge,
    );
  }

  @override
  MrwTokens lerp(ThemeExtension<MrwTokens>? other, double t) {
    if (other is! MrwTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MrwTokens(
      bg: l(bg, other.bg),
      surfaceLow: l(surfaceLow, other.surfaceLow),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      textHi: l(textHi, other.textHi),
      textMid: l(textMid, other.textMid),
      textLo: l(textLo, other.textLo),
      textMono: l(textMono, other.textMono),
      inkMid: l(inkMid, other.inkMid),
      noteText: l(noteText, other.noteText),
      border: l(border, other.border),
      borderSubtle: l(borderSubtle, other.borderSubtle),
      navBackground: l(navBackground, other.navBackground),
      navActive: l(navActive, other.navActive),
      wash: l(wash, other.wash),
      stateCold: l(stateCold, other.stateCold),
      stateCool: l(stateCool, other.stateCool),
      stateFresh: l(stateFresh, other.stateFresh),
      stateComfortable: l(stateComfortable, other.stateComfortable),
      stateWarm: l(stateWarm, other.stateWarm),
      stateHot: l(stateHot, other.stateHot),
      stateDanger: l(stateDanger, other.stateDanger),
      actionPrimaryFill: l(actionPrimaryFill, other.actionPrimaryFill),
      actionPrimaryLabel: l(actionPrimaryLabel, other.actionPrimaryLabel),
      actionSecondaryFill: l(actionSecondaryFill, other.actionSecondaryFill),
      actionSecondaryLabel: l(actionSecondaryLabel, other.actionSecondaryLabel),
      actionSecondaryBorder:
          l(actionSecondaryBorder, other.actionSecondaryBorder),
      actionTertiaryLabel: l(actionTertiaryLabel, other.actionTertiaryLabel),
      actionDestructiveLabel:
          l(actionDestructiveLabel, other.actionDestructiveLabel),
      plusBase: l(plusBase, other.plusBase),
      plusTint: l(plusTint, other.plusTint),
      plusBadge: l(plusBadge, other.plusBadge),
    );
  }
}
