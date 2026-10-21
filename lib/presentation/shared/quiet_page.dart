// lib/presentation/shared/quiet_page.dart
//
// 設定系・キャリブレーション・Comfort-Twin のサブ画面に共通する骨格
// (Figma v1.3 `Settings — Locations` 6:2 / `Settings — Privacy` 6:34 /
// `Settings — About MRI` 6:63 / `Settings — About App` 6:123 /
// `Settings — Plus Free` 6:154 / `Calibration — *` 5:2・5:56・5:89 /
// `Twin — *` 5:133・5:167・5:213 実測)。
//
//   ヘッダ    `‹` (Inter 28) + 画面名 (Inter SemiBold 15)        … top 54 / 58
//   見出し    Fraunces 28 (字間 −0.28、JA は Plex Sans JP)        … top 107
//   リード文  Inter 12 / 行送り 17 / 副文字色 (任意)              … top 146
//   本体      呼び出し側の children
//
// AppBar は使わない (Figma にツールバーが無く、見出しは本文の一部として組まれている)。
//
// **Figma との差異 (意図的)**: Figma には 2 系統のヘッダがある —
//   (A) `Settings — General` 3:473 / `Settings — Notifications` 3:572:
//       戻りが「‹ Settings」の 14px テキストリンク・左余白 19。
//   (B) 6:* 系: `‹` グリフ + 画面名・左余白 27。
// 本実装は全サブ画面で (B) に統一した。理由: 1 つのアプリに 2 種類の戻り導線を
// 置くのはユーザビリティ上の欠陥であり、(B) の方が多数派 (7 画面中 5) かつ
// タップ領域を確保しやすいため。見出しサイズも Figma の 28 / 29 / 30 を 28
// (Detail と同じ) に揃えた。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'app_background.dart';

/// サブ画面の左右マージン (Figma 6:* 系の 27/28px)。
const double kQuietEdgePadding = 28;

/// タブ本体 (Home / Detail / Settings Top) の左右マージン (Figma 3:* 系の 19/20px)。
const double kQuietTabEdgePadding = 20;

/// 戻る導線のキー (Material の BackButton ではなく Figma の `‹` グリフを使うため、
/// テストからはこのキーで特定する)。
const Key kQuietBackKey = ValueKey('quiet-back');

class QuietPage extends StatelessWidget {
  const QuietPage({
    super.key,
    required this.headline,
    required this.children,
    this.title,
    this.intro,
    this.edgePadding = kQuietEdgePadding,
    this.showBack = true,
    this.headlineTrailing,
    this.footer,
    this.bottomPadding = 28,
  });

  /// ヘッダの小見出し (Inter SemiBold 15)。null なら行ごと出さない。
  final String? title;

  /// Fraunces の大見出し。
  final String headline;

  /// 見出し直下のリード文 (Inter 12 / 副文字色)。
  final String? intro;

  /// 見出しの右に並べる要素 (Calibration のリング等)。
  final Widget? headlineTrailing;

  final List<Widget> children;

  /// スクロールしない下部固定要素 (主 CTA)。
  final Widget? footer;

  final double edgePadding;
  final bool showBack;

  /// スクロール末尾の余白。タブ本体 (ピル型ナビの裏まで描く) は大きくする。
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final headlineWidget = Text(
      headline,
      style: text.headlineMedium?.copyWith(
        fontSize: 28, // 型スケール対象外 (display: 見出し)
        letterSpacing: -0.28,
        height: 34 / 28,
        color: tokens.textHi,
      ),
    );

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    edgePadding,
                    10,
                    edgePadding,
                    footer == null ? bottomInset + bottomPadding : 16,
                  ),
                  children: [
                    if (showBack || title != null) ...[
                      _QuietPageHeader(title: title, showBack: showBack),
                      const SizedBox(height: 14),
                    ] else
                      // タブ本体はヘッダ行を持たないので、Figma の見出し位置
                      // (y=91、セーフエリア下 44) に合わせて空ける (Detail と同じ)。
                      const SizedBox(height: 34),
                    if (headlineTrailing == null)
                      headlineWidget
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: headlineWidget),
                          const SizedBox(width: 12),
                          headlineTrailing!,
                        ],
                      ),
                    if (intro != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        intro!,
                        style: text.bodyMedium?.copyWith(
                          fontSize: type.caption.fontSize(12),
                          height: type.caption.height(17 / 12, paragraph: true),
                          color: tokens.textMid,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    ...children,
                  ],
                ),
              ),
              if (footer != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    edgePadding,
                    0,
                    edgePadding,
                    bottomInset + 18,
                  ),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietPageHeader extends StatelessWidget {
  const _QuietPageHeader({required this.title, required this.showBack});

  final String? title;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final section = MrwType.of(context).section;
    final text = Theme.of(context).textTheme;
    final materialL10n = MaterialLocalizations.of(context);

    return Row(
      children: [
        if (showBack)
          Semantics(
            button: true,
            label: materialL10n.backButtonTooltip,
            child: InkResponse(
              key: kQuietBackKey,
              radius: 24,
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(
                width: 34,
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Text(
                      '‹',
                      style: text.bodyLarge?.copyWith(
                        fontSize: 28, // 型スケール対象外 (記号 ‹)
                        height: 30 / 28,
                        color: tokens.textHi,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (title != null)
          Expanded(
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                fontSize: section.fontSize(15),
                height: section.height(20 / 15),
                color: tokens.textHi,
              ),
            ),
          ),
      ],
    );
  }
}

/// セクション見出し (Figma: Inter SemiBold 15 / 行送り 19 / 主文字色)。
class QuietSectionTitle extends StatelessWidget {
  const QuietSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final section = MrwType.of(context).section;
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: section.fontSize(15),
            height: section.height(19 / 15),
            color: tokens.textHi,
          ),
    );
  }
}

/// mono の区画ラベル (Figma: IBM Plex Mono Medium 11 / 字間 0.88 / text-lo)。
/// [small] はパネル内の小ラベル (現状 10。CURRENT / CURRENT PLAN / TARGET 等)。
/// 型スケール: 区画ラベル = label、小ラベル = status (Plus ラベルと同じ扱い)。
///
/// Figma の mono ラベルはすべて大文字なので既定で大文字化する (Home / Detail の
/// `t.mriFullName.toUpperCase()` と同じ扱い)。日本語・中国語では no-op になる。
/// 大文字にしたくない箇所 (Compare の「Humidity (%)」等) は [upper] を false に。
class QuietLabel extends StatelessWidget {
  const QuietLabel(
    this.label, {
    super.key,
    this.small = false,
    this.color,
    this.upper = true,
  });

  final String label;

  /// true でパネル内の小ラベル (現状 10)、false で区画ラベル (現状 11)。
  final bool small;
  final Color? color;
  final bool upper;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final spec = small ? type.status : type.label;
    return Text(
      upper ? label.toUpperCase() : label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: spec.fontSize(small ? 10 : 11),
            letterSpacing: spec.letterSpacing(0.88),
            height: spec.height(14 / 11),
            color: color ?? tokens.textLo,
          ),
    );
  }
}

/// 注記 (Figma: IBM Plex Mono Regular 10 / 行送り 1.5 / note-text)。型スケールは tag。
class QuietNote extends StatelessWidget {
  const QuietNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: tag.fontSize(10),
            letterSpacing: 0,
            fontWeight: FontWeight.w400,
            height: tag.height(1.5),
            color: tokens.noteText,
          ),
    );
  }
}
