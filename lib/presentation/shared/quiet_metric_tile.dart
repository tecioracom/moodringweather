// lib/presentation/shared/quiet_metric_tile.dart
//
// 指標タイル (Figma v1.3 Home 3:91 Humidity Tile 169×72 / Detail 3:313 Temp Tile 169×84):
//   icon 18 (13,11) + mono ラベル (41,11) / 値 数字書体 18 (15、下端から 10)
//   + 値の後ろの文字 (単位 / 段階語)。面は QuietCard (角丸 16)。
//
// 値の後ろの文字 (docs/design-metric-units-proposal.md §3・§4):
//   - 値の実際の送り幅の直後に置く (値の欄の最小 74・最大 118 はやめた)。間隔は
//     `%` 1px (es だけ 4px)、それ以外 4px。値とアルファベットのベースラインを揃える。
//   - 書体は caption (字間 0、Regular)、色は textMono (14px で AA 4.5:1)。単位と
//     段階語は同じ組み方 (同じタイルに並ぶことはない)。
//   - **単位** (% / m/s / km/h / mph / hPa) は値から離さない。1 行に入らなければ
//     値といっしょに縮小する (左寄せ)。
//   - **段階語** (UV・空気質) は 1 行に入らなければ値の下の行へ回す (左端は値と
//     同じ、行間の足し増しなし)。回した語が 1 語でも入らなければ、その語を縮小する。
//   - 省略記号と語の途中の改行はどこでも使わない。値も入らなければ縮小する。
//   - 同じ行の 2 枚は [QuietMetricTileRow] で高い方に高さを揃える (値の行は
//     どちらも下揃えのまま)。
// 読み上げはタイル 1 枚を 1 つにまとめる (見出し + 値 + 後ろの文字。§3.6)。
// 値が「—」のとき (取得中・失敗・欠測) は後ろの文字を渡さない (呼び出し側、
// metric_tiles.dart)。
//
// 型スケール: 見出し = label、後ろの文字 = caption (字間 0 のまま)。値 18 は display
// (固定)。見出しは 1 行。収まらない (es「TEMPERATURA」× 案2 など) ときは折り返さず
// 縮小する (2 行にすると語中で「TEMPERATUR / A」と折れる)。
//
// 高さは Figma の値を「最小」として持ち、文字倍率が大きいときは伸びる。
// 倍率 1.0 では Figma の 72 / 84 のまま。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'glass_card.dart';
import 'quiet_glyphs.dart';

class QuietMetricTile extends StatelessWidget {
  const QuietMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.level = '',
    this.semanticsLabel,
    this.height = 72,
    this.muted = false,
    this.labelMaxLines = 1,
  }) : assert(unit == '' || level == '', 'unit と level は同時に使わない');

  final QuietIcon icon;

  /// 見出し (呼び出し側で大文字化済み)。
  final String label;

  /// 値 (単位を含めない。気温は「22°」まで値)。
  final String value;

  /// 単位 (% / m/s / km/h / mph / hPa)。値から離さず、入らなければ値と縮小する。
  final String unit;

  /// 段階語 (UV・空気質)。入らなければ値の下の行へ回る。
  final String level;

  /// 読み上げ (タイル 1 枚で 1 つ)。null は「見出し 値 後ろの文字」。
  final String? semanticsLabel;

  /// true なら値を textLo で出す (取得中・取得失敗・欠測の「—」。Figma E6a / E6b)。
  final bool muted;

  /// Figma の高さ。文字が収まらない倍率ではこれを下限として伸びる。
  final double height;

  /// 見出しの最大行数 (既定 1)。1 行のときは収まらなければ縮小する (省略しない)。
  final int labelMaxLines;

  /// 値と後ろの文字の間隔 (§3.3)。`%` は 1px (es は「58 %」の 4px)、ほかは 4px。
  static double trailingGap(String trailing, Locale? locale) =>
      trailing == '%' && locale?.languageCode != 'es' ? 1 : 4;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final labelStyle = text.labelMedium?.copyWith(
      fontSize: type.label.fontSize(11),
      letterSpacing: type.label.letterSpacing(0.88),
      color: tokens.textLo,
      height: type.label.height(14 / 11),
    );
    final Widget labelText = labelMaxLines == 1
        // 1 行に収まらないときは縮小 (左寄せのまま)。語中で折らない。
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, softWrap: false, style: labelStyle),
          )
        : Text(
            label,
            maxLines: labelMaxLines,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          );
    final trailing = unit.isNotEmpty ? unit : level;
    final spoken = semanticsLabel ??
        [label, value, trailing].where((s) => s.isNotEmpty).join(' ');

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: QuietCard(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
            child: Column(
              // 高さに余りがあれば値を下端へ (倍率 1.0 では Spacer と同じ結果)。
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    QuietIconMark(icon, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: labelText),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: _valueArea(context, tokens, type, text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _valueArea(
    BuildContext context,
    MrwTokens tokens,
    MrwType type,
    TextTheme text,
  ) {
    final valueText = Text(
      value,
      maxLines: 1,
      softWrap: false,
      style: MrwFonts.numeral(
        context,
        size: 18,
        weight: FontWeight.w600,
        height: 22 / 18,
        color: muted ? tokens.textLo : tokens.textHi,
      ),
    );
    final trailingStyle = text.labelMedium?.copyWith(
      fontSize: type.caption.fontSize(12),
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: tokens.textMono,
      height: type.caption.height(14 / 12),
    );
    Text trailingText(String s) =>
        Text(s, maxLines: 1, softWrap: false, style: trailingStyle);
    final locale = Localizations.maybeLocaleOf(context);

    if (level.isNotEmpty) {
      return _ValueWithLevel(
        gap: trailingGap(level, locale),
        value: _ScaleDownLine(child: valueText),
        level: _ScaleDownLine(child: trailingText(level)),
      );
    }
    if (unit.isNotEmpty) {
      // 単位は値から離さない: 1 行に入らなければ値ごと縮小する。
      return _ScaleDownLine(
        alignment: Alignment.bottomLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            valueText,
            SizedBox(width: trailingGap(unit, locale)),
            trailingText(unit),
          ],
        ),
      );
    }
    return _ScaleDownLine(child: valueText);
  }
}

/// 1 行を、幅が足りなければ縮小して収める (省略しない・折り返さない)。
class _ScaleDownLine extends StatelessWidget {
  const _ScaleDownLine({
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}

/// 値 + 段階語。1 行に入れば値の直後にベースラインを揃えて置き、入らなければ
/// 段階語を値の下の行へ回す (§4.1)。各行は [_ScaleDownLine] で 1 行に縮小済み。
class _ValueWithLevel extends MultiChildRenderObjectWidget {
  _ValueWithLevel({
    required Widget value,
    required Widget level,
    required this.gap,
  }) : super(children: [value, level]);

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderValueWithLevel(gap: gap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderValueWithLevel renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _ValueLevelParentData extends ContainerBoxParentData<RenderBox> {}

/// 配置の結果 (実レイアウトと dry レイアウトで共用)。
typedef _ValueLevelLayout = ({Size size, Offset value, Offset level});

class _RenderValueWithLevel extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ValueLevelParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ValueLevelParentData> {
  _RenderValueWithLevel({required double gap}) : _gap = gap;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  RenderBox get _value => firstChild!;
  RenderBox get _level => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ValueLevelParentData) {
      child.parentData = _ValueLevelParentData();
    }
  }

  /// 値と段階語が [width] の 1 行に入るか (自然な送り幅で比べる)。
  bool _fitsOneLine(double width) {
    final natural = _value.getMaxIntrinsicWidth(double.infinity) +
        gap +
        _level.getMaxIntrinsicWidth(double.infinity);
    return natural <= width + 0.001;
  }

  _ValueLevelLayout _computeLayout(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    Size sizeOf(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    double baselineOf(RenderBox child, BoxConstraints c, Size size) =>
        (dry
            ? child.getDryBaseline(c, TextBaseline.alphabetic)
            : child.getDistanceToBaseline(TextBaseline.alphabetic)) ??
        size.height;

    if (_fitsOneLine(constraints.maxWidth)) {
      // 1 行: 縮小なし (自然な大きさ) でベースラインを揃える。
      const natural = BoxConstraints();
      final valueSize = sizeOf(_value, natural);
      final levelSize = sizeOf(_level, natural);
      final valueBase = baselineOf(_value, natural, valueSize);
      final levelBase = baselineOf(_level, natural, levelSize);
      final top = math.max(valueBase, levelBase);
      final value = Offset(0, top - valueBase);
      final level = Offset(valueSize.width + gap, top - levelBase);
      final height = math.max(
        value.dy + valueSize.height,
        level.dy + levelSize.height,
      );
      return (
        size: constraints.constrain(
          Size(valueSize.width + gap + levelSize.width, height),
        ),
        value: value,
        level: level,
      );
    }

    // 2 行: 段階語を値の下へ。どちらも入らなければそれぞれ縮小される。
    final line = BoxConstraints(maxWidth: constraints.maxWidth);
    final valueSize = sizeOf(_value, line);
    final levelSize = sizeOf(_level, line);
    return (
      size: constraints.constrain(Size(
        math.max(valueSize.width, levelSize.width),
        valueSize.height + levelSize.height,
      )),
      value: Offset.zero,
      level: Offset(0, valueSize.height),
    );
  }

  @override
  void performLayout() {
    final layout = _computeLayout(constraints, dry: false);
    (_value.parentData! as _ValueLevelParentData).offset = layout.value;
    (_level.parentData! as _ValueLevelParentData).offset = layout.level;
    size = layout.size;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _computeLayout(constraints, dry: true).size;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final layout = _computeLayout(constraints, dry: true);
    final valueBase = _value.getDryBaseline(
      _fitsOneLine(constraints.maxWidth)
          ? const BoxConstraints()
          : BoxConstraints(maxWidth: constraints.maxWidth),
      baseline,
    );
    return valueBase == null ? null : valueBase + layout.value.dy;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
        _value.getMinIntrinsicWidth(height),
        _level.getMinIntrinsicWidth(height),
      );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _value.getMaxIntrinsicWidth(height) +
      gap +
      _level.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// 指標タイル 2 枚の行 (幅は (全幅 − [gap]) ÷ 2)。**高い方に高さを揃える**
/// (片方だけ段階語が次の行に回ったとき、隣が短いまま浮かないように。§4.1-4)。
/// 低い方は同じ高さで組み直すので、値の行はどちらも下揃えのまま。
class QuietMetricTileRow extends MultiChildRenderObjectWidget {
  QuietMetricTileRow({
    super.key,
    required Widget left,
    required Widget right,
    this.gap = 12,
  }) : super(children: [left, right]);

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightPair(gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderEqualHeightPair).gap = gap;
  }
}

class _PairParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightPair extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PairParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PairParentData> {
  _RenderEqualHeightPair({required double gap}) : _gap = gap;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  RenderBox get _left => firstChild!;
  RenderBox get _right => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PairParentData) {
      child.parentData = _PairParentData();
    }
  }

  double _tileWidth(double width) => math.max(0, (width - gap) / 2);

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth, 'QuietMetricTileRow には幅の上限が要る');
    final width = _tileWidth(constraints.maxWidth);
    final loose = BoxConstraints.tightFor(width: width);
    _left.layout(loose, parentUsesSize: true);
    _right.layout(loose, parentUsesSize: true);
    final height = math.max(_left.size.height, _right.size.height);
    // 低い方を高い方の高さで組み直す (タイルは最小高さの仕組みで伸び、値は下端)。
    final tight = BoxConstraints.tightFor(width: width, height: height);
    if (_left.size.height != height) _left.layout(tight, parentUsesSize: true);
    if (_right.size.height != height) {
      _right.layout(tight, parentUsesSize: true);
    }
    (_left.parentData! as _PairParentData).offset = Offset.zero;
    (_right.parentData! as _PairParentData).offset = Offset(width + gap, 0);
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = _tileWidth(constraints.maxWidth);
    final loose = BoxConstraints.tightFor(width: width);
    final height = math.max(
      _left.getDryLayout(loose).height,
      _right.getDryLayout(loose).height,
    );
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      2 *
          math.max(
            _left.getMinIntrinsicWidth(height),
            _right.getMinIntrinsicWidth(height),
          ) +
      gap;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      2 *
          math.max(
            _left.getMaxIntrinsicWidth(height),
            _right.getMaxIntrinsicWidth(height),
          ) +
      gap;

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
        _left.getMinIntrinsicHeight(_tileWidth(width)),
        _right.getMinIntrinsicHeight(_tileWidth(width)),
      );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
        _left.getMaxIntrinsicHeight(_tileWidth(width)),
        _right.getMaxIntrinsicHeight(_tileWidth(width)),
      );

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
