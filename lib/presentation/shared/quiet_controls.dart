// lib/presentation/shared/quiet_controls.dart
//
// v1.3「Quiet Instrument」の設定系・Calibration・Comfort-Twin で共用する部品
// (Figma 3:356 / 3:473 / 3:572 / 5:2 / 5:56 / 5:89 / 5:133 / 5:167 / 5:213 /
// 6:2 / 6:34 / 6:63 / 6:123 / 6:154 実測)。
//
// 厳守 (codex-fixes_v1.3_unified.md §4.1):
//   状態色 (state/*) が付くのは ①ゲージの弧 ②行頭の帯ドット ③MRI 数値テキスト だけ。
//   カード地・見出し・アイコン・区切り線・タブ・スイッチ・チェックは常にニュートラル。
//   ここに定義する部品は既定でニュートラルであり、状態色は呼び出し側が
//   [QuietListRow.trailing] の数値や [QuietDotCard.dotColor] に明示的に渡したときだけ付く。
//
// 寸法 (Figma 実測):
//   行カード    角丸 16 / 高さ 52 (アイコン無し) or 58 (アイコン有り)
//   ドットカード 角丸 18 / 高さ 82 / ドット 8 / 本文 11
//   パネル      角丸 22 / 内側余白 20・22 / 地は surfaceLow
//   セグメント  外 48 角丸 16 / 選択ピル 32 角丸 12 / ラベル mono 11 字間 0.66
//   ボタン      高さ 46 / 角丸 23 / ラベル Inter SemiBold 13
//
// 高さはいずれも「最小」として持ち、文字倍率が大きいときは伸びる
// (quiet_metric_tile.dart と同じ方針。固定にすると倍率 1.6 以上で溢れる)。

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'glass_card.dart';
import 'quiet_row_icons.dart';

/// 1 行のカード。アイコン / 副題 / 右要素 / 見出しのバッジ / シェブロンは任意。
class QuietListRow extends StatelessWidget {
  const QuietListRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.titleBadge,
    this.chevron = false,
    this.onTap,
    this.emphasizeTitle = false,
    this.enabled = true,
    this.iconColor,
  });

  final String title;
  final QuietRowIcon? icon;

  /// 行アイコンの色。既定はニュートラル。commerce/plus を渡してよいのは
  /// 課金導線だけ (§6.1「Plus ロゴ・特典アイコンは commerce/plus/base」)。
  /// 状態色 (state/*) は絶対に渡さない (§4.1: アイコンは常にニュートラル)。
  final Color? iconColor;

  final String? subtitle;

  /// 右端 (シェブロンの左 8px、無ければ行の右端) に置く要素。バッジ / 値 / スイッチ。
  /// 幅は内容ぶん (上限は行の内側の幅の [trailingMaxFraction])。題が残りの幅を取る。
  final Widget? trailing;

  /// 右要素が取れる幅の上限 (行の内側の幅に対する比)。
  static const double trailingMaxFraction = 0.5;

  /// 見出しの横に置く状態のバッジ ([QuietBadge]。設定 › 一般「ライブ壁紙を設定」の
  /// 「設定中」)。見出しと同じ行に収まれば文字の列の右端 (シェブロンの左) に寄せ、
  /// 収まらなければ見出しの下へ折り返す (左寄せ)。[trailing] と違って説明の幅を
  /// 食わないので、360dp・文字倍率 2.0 でも見出しが語の途中で折れない。
  final Widget? titleBadge;

  final bool chevron;
  final VoidCallback? onTap;

  /// true で Inter SemiBold 15 (Figma の設定 Top / 言語行)。
  /// false で Inter Regular 13 (Figma の 6:* 系リスト行)。
  final bool emphasizeTitle;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final dim = enabled ? 1.0 : 0.45;

    // 型スケール: 強調 (設定行の題) = section、通常 (行タイトル) = body。
    final titleStyle = (emphasizeTitle
            ? text.titleMedium?.copyWith(
                fontSize: type.section.fontSize(15),
                height: type.section.height(20 / 15),
              )
            : text.bodyMedium?.copyWith(
                fontSize: type.body.fontSize(13),
                height: type.body.height(17 / 13),
              ))
        ?.copyWith(color: tokens.textHi.withValues(alpha: dim));

    final row = Padding(
      padding: EdgeInsets.fromLTRB(icon == null ? 16 : 13, 9, 10, 9),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (icon != null) ...[
              Opacity(
                opacity: dim,
                child: QuietRowIconMark(icon!, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (titleBadge == null)
                    Text(title, style: titleStyle)
                  else
                    // 幅いっぱいの Wrap + spaceBetween: 1 行に収まればバッジは右端、
                    // 収まらなければ次の行の左端。
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(title, style: titleStyle),
                          Opacity(opacity: dim, child: titleBadge),
                        ],
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      // Figma の副題は 1 行 (幅 230)。文字倍率が上がったときだけ
                      // 2 行まで折り返し、それ以上は省略する (行の高さの暴走を防ぐ)。
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontSize: type.caption.fontSize(12),
                        height: type.caption.height(16 / 12),
                        color: tokens.textLo.withValues(alpha: dim),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              // 内容ぶんの幅で右端に寄せる (Flexible で題と 1:1 に分けると
              // 行の中ほどに浮く)。上限は内側の幅の半分 (倍率が大きいときは縮む)。
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * trailingMaxFraction,
                ),
                child: trailing!,
              ),
            ],
            if (chevron) ...[
              const SizedBox(width: 8),
              Opacity(
                opacity: dim,
                child: const QuietRowIconMark(QuietRowIcon.chevron, size: 20),
              ),
            ],
          ],
        ),
      ),
    );

    return QuietCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: subtitle == null ? 52 : 58),
        child: onTap == null || !enabled
            ? row
            : InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: row,
              ),
      ),
    );
  }
}

/// 中身を自由に置ける小さめの行カード (Figma: About MRI の帯行 6:80 =
/// 角丸 12 / 高さ 36 / 左内側 18)。
class QuietCardRow extends StatelessWidget {
  const QuietCardRow({super.key, required this.child, this.minHeight = 36});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return QuietCard(
      borderRadius: 12,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
          child: child,
        ),
      ),
    );
  }
}

/// 行頭ドット + 見出し + 本文のカード (Figma: Privacy 6:43 / About MRI 6:115 /
/// Plus Free 6:167)。既定のドットはニュートラル (inkMid)。
class QuietDotCard extends StatelessWidget {
  const QuietDotCard({
    super.key,
    required this.title,
    required this.body,
    this.dotColor,
  });

  final String title;
  final String body;

  /// 省略時はニュートラル。Plus 文脈のみ commerce/plus を渡す。
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    return QuietCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor ?? tokens.inkMid,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontSize: type.body.fontSize(13),
                    height: type.body.height(17 / 13),
                    color: tokens.textHi,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: text.bodyMedium?.copyWith(
                    fontSize: type.meta.fontSize(11),
                    height: type.meta.height(16 / 11, paragraph: true),
                    color: tokens.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一段沈んだ面のパネル (Figma: 地 = surfaceLow / 角丸 22)。
/// READING THE SCORE・CURRENT・CURRENT PLAN・LEARNING PROGRESS などの見出し付き箱。
class QuietPanel extends StatelessWidget {
  const QuietPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    const radius = 22.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: tokens.surfaceLow,
          border: Border.all(width: 1, color: tokens.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 本文だけのパネル (空状態・注記)。
class QuietBodyCard extends StatelessWidget {
  const QuietBodyCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: caption.fontSize(12),
              height: caption.height(17 / 12, paragraph: true),
              color: tokens.textMid,
            ),
      ),
    );
  }
}

/// Plus 訴求パネル (Figma: Locations 6:30)。
/// ラベルだけが commerce/plus/base。状態色は使わない (§6.1)。
class QuietPlusCard extends StatelessWidget {
  const QuietPlusCard({
    super.key,
    required this.label,
    required this.title,
    required this.body,
    this.action,
  });

  final String label;
  final String title;
  final String body;

  /// 本文の下に置く操作 (Figma 地点管理 A2 / A5 の tertiary「Plus を見る」)。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: text.labelMedium?.copyWith(
              fontSize: type.status.fontSize(10),
              letterSpacing: type.status.letterSpacing(0.88),
              height: type.status.height(13 / 10),
              color: tokens.plusBase,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: text.titleMedium?.copyWith(
              fontSize: type.bodyLg.fontSize(14),
              height: type.bodyLg.height(18 / 14),
              color: tokens.textHi,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: text.bodyMedium?.copyWith(
              fontSize: type.meta.fontSize(11),
              height: type.meta.height(15 / 11, paragraph: true),
              color: tokens.textMid,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 塗りなしの左揃えテキストボタン (Figma 地点管理 A2 の「Plus を見る」:
/// ヒット領域 120×44、ラベルは縦中央・左揃え、action/tertiary)。
class QuietInlineTextButton extends StatelessWidget {
  const QuietInlineTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              label,
              style: quietButtonTextStyle(context).copyWith(
                color: onPressed == null
                    ? tokens.textLo
                    : tokens.actionTertiaryLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小さなピル型バッジ (Figma §9.3: 角丸 999 / 高さ 18 / 左右 8 /
/// 塗り Dark pearl 16%・Light ink 10% / 文字 mono 10 note-text)。型スケールは tag。
class QuietBadge extends StatelessWidget {
  const QuietBadge(
    this.label, {
    super.key,
    this.fill,
    this.labelColor,
  });

  final String label;
  final Color? fill;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // alignment / constraints は付けない — 付けると Flexible の下で
    // 親の最大幅まで伸びてしまう (バッジは内容ぴったりの幅で止める)。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fill ?? tokens.textHi.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: tag.fontSize(10),
              letterSpacing: tag.letterSpacing(0.4),
              height: tag.height(13 / 10),
              color: labelColor ?? tokens.noteText,
            ),
      ),
    );
  }
}

/// セグメント切替 (Figma: 温度単位 3:518 / テーマ 3:562)。
class QuietSegmented<T> extends StatelessWidget {
  const QuietSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticsLabelOf,
  });

  /// (値, 表示ラベル) の並び。
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 読み上げ用のラベル (null・未指定は表示ラベルをそのまま読む)。記号のラベル
  /// (m/s・km/h・℃ など) に読み方を与える (TalkBack が「エム スラッシュ エス」と
  /// 記号のまま読まないように。QA-24)。
  final String? Function(T value)? semanticsLabelOf;

  /// [child] (表示ラベルの Text) の読み上げを [semanticsLabelOf] の読み方に置き換える。
  /// Text の外側で包むので、Text の中の組み (RichText) は変わらない。
  Widget _withSpokenLabel(T value, Widget child) {
    final spoken = semanticsLabelOf?.call(value);
    if (spoken == null) return child;
    return Semantics(label: spoken, excludeSemantics: true, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final label = MrwType.of(context).label;
    final text = Theme.of(context).textTheme;
    return QuietCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final (value, segmentLabel) in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(value),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: value == selected
                          ? tokens.navActive
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _withSpokenLabel(
                      value,
                      Text(
                        segmentLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.labelMedium?.copyWith(
                          fontSize: label.fontSize(11),
                          letterSpacing: label.letterSpacing(0.66),
                          height: label.height(14 / 11),
                          color: value == selected
                              ? tokens.textHi
                              : tokens.textMono,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// スイッチ (Figma 3:570: トラック surfaceHigh + pearl 12% の 1px 枠 / つまみ pearl)。
/// 幾何は Material のものを使い、色だけ Figma に合わせる (操作部品は無彩色)。
class QuietSwitch extends StatelessWidget {
  const QuietSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return tokens.textLo;
        }
        return states.contains(WidgetState.selected)
            ? tokens.textHi
            : tokens.textMono;
      }),
      trackColor: WidgetStateProperty.all(tokens.surfaceHigh),
      trackOutlineColor:
          WidgetStateProperty.all(tokens.textHi.withValues(alpha: 0.12)),
      trackOutlineWidth: WidgetStateProperty.all(1),
    );
  }
}

/// 塗りの主ボタン (action/primary)。**1 画面に 1 つまで** (§2.3)。
class QuietPrimaryButton extends StatelessWidget {
  const QuietPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: tokens.actionPrimaryFill,
          foregroundColor: tokens.actionPrimaryLabel,
          disabledBackgroundColor: tokens.surfaceHigh,
          disabledForegroundColor: tokens.textLo,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
          ),
          textStyle: quietButtonTextStyle(context),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// 塗りの副ボタン (action/secondary)。個数制限なし。
class QuietSecondaryButton extends StatelessWidget {
  const QuietSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.keepFillWhenDisabled = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// false で内容ぴったりの幅にする (Figma の「今日の体感を使う」チップ 5:143)。
  final bool expand;

  /// true なら無効時も塗りを変えず、ラベルだけ textLo にする
  /// (Figma 地点管理 A4「塗りはそのまま、ラベル色を textLo」)。
  final bool keepFillWhenDisabled;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return SizedBox(
      width: expand ? double.infinity : null,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: tokens.actionSecondaryFill,
          foregroundColor: tokens.actionSecondaryLabel,
          disabledBackgroundColor: keepFillWhenDisabled
              ? tokens.actionSecondaryFill
              : tokens.surfaceLow,
          disabledForegroundColor: tokens.textLo,
          minimumSize: expand ? const Size.fromHeight(46) : const Size(0, 34),
          padding: EdgeInsets.symmetric(
            horizontal: expand ? 16 : 14,
            vertical: expand ? 12 : 8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(expand ? 23 : 17),
            side: BorderSide(color: tokens.actionSecondaryBorder),
          ),
          textStyle: quietButtonTextStyle(context),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// 塗りなしのテキストボタン (action/tertiary)。[destructive] で破壊的操作の文字色。
class QuietTertiaryButton extends StatelessWidget {
  const QuietTertiaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: destructive
              ? tokens.actionDestructiveLabel
              : tokens.actionTertiaryLabel,
          disabledForegroundColor: tokens.textLo,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
          ),
          textStyle: quietButtonTextStyle(context),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// ボタン文字 (titleSmall 13 / 行高 17。型スケールは body)。塗り・枠・tertiary の
/// 各ボタンと、スナックバーの操作 (showQuietSnackBar) で共通。
TextStyle quietButtonTextStyle(BuildContext context) {
  final body = MrwType.of(context).body;
  return Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: body.fontSize(13),
            height: body.height(17 / 13),
          ) ??
      TextStyle(fontSize: body.fontSize(13));
}

/// スライダー (Figma: トラック surfaceHigh 4px / つまみ pearl 16)。無彩色。
class QuietSlider extends StatelessWidget {
  const QuietSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.semanticFormatterCallback,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: tokens.textMid,
        inactiveTrackColor: tokens.surfaceHigh,
        thumbColor: tokens.textHi,
        overlayColor: tokens.textHi.withValues(alpha: 0.08),
        valueIndicatorColor: tokens.surfaceHigh,
        valueIndicatorTextStyle: TextStyle(
          color: tokens.textHi,
          fontSize: caption.fontSize(12),
        ),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}

/// 読み取り専用の進捗バー (Figma: About MRI 6:76 / Calibration 5:* の目盛り)。
/// 状態色は使わない。
class QuietProgressTrack extends StatelessWidget {
  const QuietProgressTrack({super.key, required this.fraction});

  /// 0.0–1.0。
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final f = fraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 16,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.surfaceHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                height: 4,
                width: width * f,
                decoration: BoxDecoration(
                  color: tokens.textMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Positioned(
                left: (width * f - 8).clamp(0.0, width - 16),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: tokens.textHi,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 数値 (Fraunces / JA は Plex Sans JP)。カード内の大きな値に使う。
/// [color] を渡すのは **MRI 値そのもの** のときだけ (§4.1 規則 1 の ③)。
class QuietDisplayNumber extends StatelessWidget {
  const QuietDisplayNumber(
    this.value, {
    super.key,
    this.size = 42,
    this.color,
    this.maxLines = 1,
  });

  final String value;
  final double size;
  final Color? color;

  /// 最大行数 (既定 1)。null で行数を制限しない (語間で折り返す。縮小しない)。
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final ja = MrwFonts.isJa(Localizations.maybeLocaleOf(context));
    return Text(
      value,
      maxLines: maxLines,
      style: TextStyle(
        fontFamily: ja ? MrwFonts.plexSansJp : MrwFonts.fraunces,
        fontFamilyFallback:
            ja ? const [MrwFonts.inter] : const [MrwFonts.plexSansJp],
        fontVariations: ja ? null : MrwFonts.frauncesVariations(size),
        fontWeight: FontWeight.w400,
        fontSize: size,
        height: 1.1,
        color: color ?? tokens.textHi,
      ),
    );
  }
}
