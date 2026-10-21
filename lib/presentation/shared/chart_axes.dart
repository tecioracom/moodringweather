// lib/presentation/shared/chart_axes.dart
//
// capsule bar 列に添える軸 (Home 3:73 / Detail 3:287 共通)。
// docs/home-sparkline-decisions.md の決定 ① / ② と申し送り 2・3 の実装。
//
//   formatAxisHour — 時刻の書式。ロケールと端末の 12 / 24 時間設定に従う
//   TimeAxisLabels — バー列の下の時刻ラベル行
//     - ラベルは担当バーの中心に合わせ、両端はカード枠の内側へ寄せる
//       (Figma 3:90 / 77:263 が枠外へ 14px はみ出していた件の是正)
//     - 実測幅で衝突を判定し、衝突するなら「現在」を起点に間引く。
//       文字スケール 2.0 でも現在のラベルは必ず残る
//   BarSlotRow     — 同じ幾何で任意のウィジェット (天気レール) を並べる行。
//                    [BarSlotRow.follow] で時刻ラベルと同じ間引きに従う
//   AxisCompanionRow — 時刻ラベルの下の行 (天気レール) の項目幅。TimeAxisLabels に
//                    渡すと、ラベルどうしだけでなくレールの項目どうしも接しない
//                    間引き・置き方を選ぶ (QA-10: グリフ + 気温はラベルより幅が
//                    広いことがあり、ラベルが収まってもレールが隣と接していた)
//   MriValueAxis   — 右端の上限 / 下限ラベル列 (自動スケールの拡大率を示す)
//   axisLabelStyle — 軸ラベルの書体 (JA でも Plex Mono。Figma JP の実測に合わせる)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../theme/mrw_type.dart';
import 'mri_bar_scale.dart';

/// 軸ラベル (時刻・上限 / 下限) の書体。
///
/// Figma は EN / JA とも軸の数字を **IBM Plex Mono** で組む (JA 画面 `77:64` の実測:
/// 時刻 `77:129`〜`132` と上限下限 `422:62` / `63` が Plex Mono、他の文言は Plex Sans JP)。
/// 一方 TextTheme の labelMedium は JA だと Plex Sans JP に振られるため、軸だけは
/// ロケールに関係なく Plex Mono を明示する。数字と ":" / AM・PM しか載らないので
/// CJK の字形は不要だが、後段に Plex Sans JP を置いておく。
/// 現在のラベルは weight 600 (同梱の Plex Mono SemiBold。Figma も SemiBold)。
/// サイズ・行送りは型スケールの axis (既定の案2 は 12 / 14。v1.3 は 10 / 12)、字間 0。
/// Home / 詳細の時刻軸と Calibration の 24 時間ミニチャートの時刻で共用する。
TextStyle axisLabelStyle(
  BuildContext context, {
  required Color color,
  FontWeight weight = FontWeight.w400,
}) {
  final axis = MrwType.of(context).axis;
  final base = Theme.of(context).textTheme.labelMedium ?? const TextStyle();
  return base.copyWith(
    fontFamily: MrwFonts.plexMono,
    fontFamilyFallback: const [MrwFonts.plexSansJp],
    fontSize: axis.fontSize(10),
    letterSpacing: 0,
    fontWeight: weight,
    height: axis.height(12 / 10),
    color: color,
  );
}

/// 時刻軸のラベル書式。
/// 24 時間制 (ja / de、または端末が 24 時間表示) → "15:00"。
/// 12 時間制 (en-US 等) → "3 PM"。":00 PM" は冗長で 1 スロットに収まらない。
///
/// 裸の「15」を避ける理由は整列ではなく型の曖昧さの解消: MRI のカードに並ぶ
/// 裸の数字は MRI 値 (0–100 の整数) と読み違えられる。
/// 時間別の軸に出す時刻を、地点の現地時刻にする (海外の保存地点で「15:00」が
/// 現地の 15 時になるように)。[utcOffsetSeconds] が null なら端末の時刻のまま
/// (現在地)。返り値は年月日時分だけが意味を持つ値 ([formatAxisHour] に渡す)。
DateTime axisLocalTime(DateTime instant, int? utcOffsetSeconds) =>
    utcOffsetSeconds == null
        ? instant
        : instant.toUtc().add(Duration(seconds: utcOffsetSeconds));

String formatAxisHour(BuildContext context, DateTime at) {
  final locale = Localizations.localeOf(context).toString();
  return (uses24HourClock(context)
          ? DateFormat.Hm(locale)
          : DateFormat.j(locale))
      .format(at);
}

/// 時刻を 24 時間制で出すか (言語の既定と端末の「24 時間表示」の設定から決める)。
/// 時刻軸・天気レールと、ライブ壁紙の重ね描きの時刻で共用する。
bool uses24HourClock(BuildContext context) {
  final format = MaterialLocalizations.of(context).timeOfDayFormat(
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return switch (format) {
    TimeOfDayFormat.h_colon_mm_space_a ||
    TimeOfDayFormat.a_space_h_colon_mm =>
      false,
    _ => true,
  };
}

/// [TimeAxisLabels] の 1 行ぶんの配置 (バー幅・各ラベルの実測幅と書式・残すラベル・
/// 下の行 ([TimeAxisLabels.companion]) の置き方)。
typedef _AxisLayout = ({
  double barWidth,
  Map<int, double> widths,
  Map<int, TextStyle> styles,
  List<int> kept,
  BarSlotPlacement placement,
});

/// 時刻ラベル行の下に同じ間引きで並べる行 (天気レール) の項目の幅。
/// [TimeAxisLabels.companion] に渡す。
@immutable
class AxisCompanionRow {
  const AxisCompanionRow({
    required this.widths,
    required this.span,
    this.trailingBlanks = const {},
    this.minSpacing = kAxisCompanionMinSpacing,
  });

  /// スロット番号 → 項目の中身の幅 (送り幅。px、文字倍率込み)。置く位置に使う。
  final Map<int, double> widths;

  /// 1 項目に割り当てるスロット数 ([BarSlotRow.span] と同じ値)。
  final int span;

  /// スロット番号 → 中身の右端の空き (字面が送り幅より手前で終わるぶん。例: JA の
  /// 全角「°」)。間隔の判定だけに使う (置く位置は [widths] のまま)。
  final Map<int, double> trailingBlanks;

  /// 隣り合う項目の間に最低これだけ空ける (右端の空きを除いた間隔)。
  final double minSpacing;
}

/// [AxisCompanionRow.minSpacing] の既定。天気レールでは 2.5px 以下だと EN の「22°」と
/// 隣のグリフが接して見える (QA-10: en ×1.3 / 360dp のホーム 2.2px・詳細 2.5px)。
const double kAxisCompanionMinSpacing = 3;

/// [BarSlotRow] の項目の置き方。
enum BarSlotPlacement {
  /// 担当スロットの中心に [BarSlotRow.span] スロットぶんの枠を置き、その中で
  /// 中央寄せ。枠は行の内側へ寄せるので、両端の項目は時刻ラベルより内側に来る。
  /// 既定 (倍率 1.0 の見た目。golden / Figma E1〜E7 と同じ)。
  slot,

  /// 時刻ラベルと同じく、項目の中身の幅で担当スロットの中心に置き、両端は中身の
  /// 幅で行の内側へ寄せる (Figma: 項目の中心 = 時刻ラベルの中心)。[slot] だと
  /// 隣と接するとき (文字倍率が大きい・幅が狭い) だけ使う。
  centered,
}

/// [BarSlotRow] の 1 項目に割り当てる枠の幅 ([span] スロットぶん。行の幅まで)。
double barSlotWidth({
  required double barWidth,
  required double gap,
  required int span,
  required double maxWidth,
}) =>
    (barWidth * span + gap * (span - 1)).clamp(0.0, maxWidth).toDouble();

/// [BarSlotRow] の項目 [index] (中身の幅 [contentWidth]) の左端と置く箱の幅。
({double left, double width}) barSlotItemBox({
  required int index,
  required double contentWidth,
  required double barWidth,
  required double gap,
  required int span,
  required double maxWidth,
  required BarSlotPlacement placement,
}) {
  final width = switch (placement) {
    BarSlotPlacement.slot => barSlotWidth(
        barWidth: barWidth,
        gap: gap,
        span: span,
        maxWidth: maxWidth,
      ),
    // 実測幅ぴったりだと丸め誤差で文字が折れる・切れるので TimeAxisLabels と同じ
    // 余白を足す。
    BarSlotPlacement.centered =>
      (contentWidth + TimeAxisLabels._slack).clamp(0.0, maxWidth).toDouble(),
  };
  final left = barSlotLeft(
    index: index,
    barWidth: barWidth,
    gap: gap,
    width: width,
    maxWidth: maxWidth,
  );
  return (left: left, width: width);
}

/// [BarSlotRow] の項目 [index] の中身が実際に描かれる左右の範囲。
/// 中身は箱の中で中央寄せ。箱より広いときは箱の左端から右へはみ出す
/// (天気レールの気温は softWrap: false / overflow: visible で折らない)。
({double left, double right}) barSlotItemExtent({
  required int index,
  required double contentWidth,
  required double barWidth,
  required double gap,
  required int span,
  required double maxWidth,
  required BarSlotPlacement placement,
}) {
  final box = barSlotItemBox(
    index: index,
    contentWidth: contentWidth,
    barWidth: barWidth,
    gap: gap,
    span: span,
    maxWidth: maxWidth,
    placement: placement,
  );
  if (contentWidth >= box.width) {
    return (left: box.left, right: box.left + contentWidth);
  }
  final inset = (box.width - contentWidth) / 2;
  return (left: box.left + inset, right: box.left + inset + contentWidth);
}

/// バー [index] の中心に幅 [width] の箱を置くときの左端。
/// 枠 (0〜[maxWidth]) の外へは出さない = 両端の要素は内側へ寄る。
double barSlotLeft({
  required int index,
  required double barWidth,
  required double gap,
  required double width,
  required double maxWidth,
}) {
  if (width >= maxWidth) return 0;
  final center = index * (barWidth + gap) + barWidth / 2;
  return (center - width / 2).clamp(0.0, maxWidth - width);
}

class TimeAxisLabels extends StatelessWidget {
  const TimeAxisLabels({
    super.key,
    required this.labels,
    required this.gap,
    required this.style,
    this.anchorIndex = 0,
    this.anchorStyle,
    this.minSpacing = 4,
    this.companion,
  });

  /// 長さ = バー本数。null のスロットにはラベルを置かない。
  final List<String?> labels;
  final double gap;
  final TextStyle? style;

  /// 間引いても必ず残すインデックス (= 現在のバー)。
  final int anchorIndex;

  /// 現在のラベルだけに使う書式。現在の識別を α 差だけに頼らないため
  /// (申し送り 2: 現在が左端でなくなったので位置では分からない)。
  final TextStyle? anchorStyle;

  /// 隣り合うラベルの間に最低これだけ空ける。
  final double minSpacing;

  /// 下に同じ間引きで並ぶ行 (天気レール、[BarSlotRow.follow]) の項目幅。指定すると
  /// ラベルが収まるだけでなく、その行の項目どうしも [AxisCompanionRow.minSpacing]
  /// 以上空き、行からはみ出さない間引きを選ぶ。置き方は [BarSlotPlacement.slot] を
  /// 優先し、接するときだけ [BarSlotPlacement.centered]、それでも接するなら 1 段
  /// 多く間引く。
  final AxisCompanionRow? companion;

  /// 実測幅ぴったりの箱だと丸め誤差で文字が切れるため足す余白。
  /// 枠内判定にも同じ値を使うので、箱ごと枠の内側に収まる。
  static const double _slack = 1;

  @override
  Widget build(BuildContext context) {
    final base = _baseStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight = scaler.scale(base.fontSize ?? 10) * (base.height ?? 1.2);

    return SizedBox(
      height: lineHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final layout = _layout(context, maxWidth);
          if (layout == null) return const SizedBox.shrink();
          final (:barWidth, :widths, :styles, :kept, placement: _) = layout;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final i in kept)
                Positioned(
                  left: barSlotLeft(
                    index: i,
                    barWidth: barWidth,
                    gap: gap,
                    width: widths[i]! + _slack,
                    maxWidth: maxWidth,
                  ),
                  top: 0,
                  width: widths[i]! + _slack,
                  child: Text(
                    labels[i]!,
                    style: styles[i],
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 幅 [maxWidth] の行で実際に出すラベルのインデックス (衝突したときは間引き後。
  /// 昇順)。天気レール ([BarSlotRow.follow]) を同じ間引きに従わせるために使う。
  List<int> visibleIndices(BuildContext context, double maxWidth) =>
      _layout(context, maxWidth)?.kept ?? const [];

  /// 幅 [maxWidth] の行で、下の行 ([companion]) の項目を置く方法。
  BarSlotPlacement companionPlacement(BuildContext context, double maxWidth) =>
      _layout(context, maxWidth)?.placement ?? BarSlotPlacement.slot;

  /// [visibleIndices] と [companionPlacement] を 1 回の計算で ([BarSlotRow] 用)。
  ({List<int> kept, BarSlotPlacement placement}) _companionLayout(
    BuildContext context,
    double maxWidth,
  ) {
    final layout = _layout(context, maxWidth);
    return (
      kept: layout?.kept ?? const [],
      placement: layout?.placement ?? BarSlotPlacement.slot,
    );
  }

  TextStyle _baseStyle(BuildContext context) =>
      style ?? TextStyle(fontSize: MrwType.of(context).axis.fontSize(10));

  _AxisLayout? _layout(BuildContext context, double maxWidth) {
    final count = labels.length;
    if (count == 0 || maxWidth <= 0) return null;
    final barWidth = (maxWidth - gap * (count - 1)) / count;
    if (barWidth <= 0) return null;

    final base = _baseStyle(context);
    final anchor = anchorStyle ?? base;
    final scaler = MediaQuery.textScalerOf(context);
    final widths = <int, double>{};
    final styles = <int, TextStyle>{};
    for (var i = 0; i < count; i++) {
      final label = labels[i];
      if (label == null) continue;
      final resolved = i == anchorIndex ? anchor : base;
      styles[i] = resolved;
      widths[i] = _measure(context, label, resolved, scaler);
    }
    final (kept, placement) = _thin(widths, barWidth, maxWidth);
    return (
      barWidth: barWidth,
      widths: widths,
      styles: styles,
      kept: kept,
      placement: placement,
    );
  }

  double _measure(
    BuildContext context,
    String label,
    TextStyle style,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 衝突するなら [anchorIndex] を起点に間引く。候補は等間隔に並んでいる前提
  /// (例: 2 本おき) なので、その間隔の整数倍へ広げて見た目の等間隔を保つ。
  /// [companion] があれば、その行の項目も収まる間引きと置き方を選ぶ。
  (List<int>, BarSlotPlacement) _thin(
    Map<int, double> widths,
    double barWidth,
    double maxWidth,
  ) {
    final candidates = widths.keys.toList()..sort();
    if (candidates.isEmpty) return (const [], BarSlotPlacement.slot);
    final step = candidates.length >= 2 ? candidates[1] - candidates[0] : 1;
    // 間引きの位相は現在に合わせる。現在にラベルが無い並びなら先頭に合わせる
    // (位相がずれて 1 本しか残らないのを防ぐ)。
    final phase =
        widths.containsKey(anchorIndex) ? anchorIndex : candidates.first;
    for (var factor = 1; factor <= candidates.length; factor++) {
      final stride = step * factor;
      final kept = [
        for (final i in candidates)
          if ((i - phase) % stride == 0) i,
      ];
      if (kept.isEmpty) continue;
      if (!_fits(kept, widths, barWidth, maxWidth)) continue;
      final placement = _companionPlacement(kept, barWidth, maxWidth);
      if (placement != null) return (kept, placement);
    }
    // どう間引いても収まらない: 現在 (無ければ先頭) だけ残す (1 項目なので
    // 隣と接しない。行からはみ出さない置き方にする)。
    return (
      [widths.containsKey(anchorIndex) ? anchorIndex : candidates.first],
      companion == null ? BarSlotPlacement.slot : BarSlotPlacement.centered,
    );
  }

  /// [kept] のとき下の行 ([companion]) の項目が接しない置き方 ([BarSlotPlacement.slot]
  /// を優先)。どちらでも接する・行からはみ出すなら null (もう 1 段間引く)。
  BarSlotPlacement? _companionPlacement(
    List<int> kept,
    double barWidth,
    double maxWidth,
  ) {
    final row = companion;
    if (row == null) return BarSlotPlacement.slot;
    for (final placement in BarSlotPlacement.values) {
      var prevRight = double.negativeInfinity;
      var fits = true;
      for (final i in kept) {
        final width = row.widths[i];
        if (width == null) continue;
        final extent = barSlotItemExtent(
          index: i,
          contentWidth: width,
          barWidth: barWidth,
          gap: gap,
          span: row.span,
          maxWidth: maxWidth,
          placement: placement,
        );
        if (extent.left < prevRight + row.minSpacing ||
            extent.right > maxWidth + 0.5) {
          fits = false;
          break;
        }
        prevRight = extent.right - (row.trailingBlanks[i] ?? 0);
      }
      if (fits) return placement;
    }
    return null;
  }

  bool _fits(
    List<int> kept,
    Map<int, double> widths,
    double barWidth,
    double maxWidth,
  ) {
    var prevRight = double.negativeInfinity;
    for (final i in kept) {
      final width = widths[i]! + _slack;
      final left = barSlotLeft(
        index: i,
        barWidth: barWidth,
        gap: gap,
        width: width,
        maxWidth: maxWidth,
      );
      if (left < prevRight + minSpacing) return false;
      prevRight = left + width;
    }
    return true;
  }
}

/// バー列と同じ幾何で任意のウィジェットを並べる行 (Home の天気レール)。
/// 各要素は担当スロットの中心に置き、幅は [span] スロットぶんを割り当てる
/// (1 スロットだと 9 本構成でグリフ + 気温が切れる)。
class BarSlotRow extends StatelessWidget {
  const BarSlotRow({
    super.key,
    required this.children,
    required this.gap,
    required this.height,
    this.span = 2,
    this.follow,
  });

  /// 長さ = バー本数。null のスロットには何も置かない。
  final List<Widget?> children;
  final double gap;
  final double height;
  final int span;

  /// 同じ幅に並ぶ時刻ラベル行。指定すると、そのラベルが間引かれたスロットの要素も
  /// 出さない (文字倍率が大きいとき、ラベル 2 本に対してレールが 5 個残り、右端が
  /// 内側へ寄って詰まるのを防ぐ)。ラベル行に [TimeAxisLabels.companion] (この行の
  /// 項目幅) があれば、その置き方 ([BarSlotPlacement]) にも従う。
  final TimeAxisLabels? follow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = children.length;
          final maxWidth = constraints.maxWidth;
          if (count == 0 || maxWidth <= 0) return const SizedBox.shrink();
          final barWidth = (maxWidth - gap * (count - 1)) / count;
          if (barWidth <= 0) return const SizedBox.shrink();
          final layout = follow?._companionLayout(context, maxWidth);
          final visible = layout?.kept.toSet();
          final widths = follow?.companion?.widths;
          final placement = layout?.placement ?? BarSlotPlacement.slot;

          return Stack(
            children: [
              for (var i = 0; i < count; i++)
                if (children[i] != null &&
                    (visible == null || visible.contains(i)))
                  _item(
                    i,
                    barWidth: barWidth,
                    maxWidth: maxWidth,
                    // 幅の分からない項目は枠 (slot) に置く。
                    placement:
                        widths?[i] == null ? BarSlotPlacement.slot : placement,
                    contentWidth: widths?[i] ?? 0,
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(
    int index, {
    required double barWidth,
    required double maxWidth,
    required BarSlotPlacement placement,
    required double contentWidth,
  }) {
    final box = barSlotItemBox(
      index: index,
      contentWidth: contentWidth,
      barWidth: barWidth,
      gap: gap,
      span: span,
      maxWidth: maxWidth,
      placement: placement,
    );
    return Positioned(
      left: box.left,
      top: 0,
      width: box.width,
      height: height,
      child: children[index]!,
    );
  }
}

/// 自動スケールの上限 / 下限ラベル列 (バー列の右)。
/// 自動スケールとこの軸は必ず同時に出す (決定 ①)。
class MriValueAxis extends StatelessWidget {
  const MriValueAxis({super.key, required this.scale, required this.style});

  final MriBarScale scale;
  final TextStyle? style;

  /// 2 桁ぶんの列幅。文字スケールに追従させる (base の 1.9 倍で打ち切り)。
  /// [base] を省くと型スケールの列幅 (現状 18 / 案1 20 / 案2 22。「100」が入る幅)。
  static double widthFor(BuildContext context, {double? base}) {
    final b = base ?? MrwType.of(context).layout.valueAxisWidth;
    return MediaQuery.textScalerOf(context)
        .scale(b)
        .clamp(b, b * 1.9)
        .toDouble();
  }

  /// 上限 / 下限の 2 行がちょうど収まる高さ。文字スケールが大きいときは
  /// バー列をこれ以上の高さにしないと軸が入らない (バーが伸びるぶんには
  /// 解像度が上がるだけで害はない)。
  static double minChartHeight(BuildContext context, TextStyle? style) {
    final size = style?.fontSize ?? 10;
    final line = style?.height ?? 1.2;
    return MediaQuery.textScalerOf(context).scale(size) * line * 2;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${scale.hi.round()}', style: style, maxLines: 1),
        const Spacer(),
        Text('${scale.lo.round()}', style: style, maxLines: 1),
      ],
    );
  }
}
