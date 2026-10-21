// lib/presentation/shared/mood_ring_widget.dart
//
// MRI リング (Figma v1.3 Home 3:2「Mood Ring Track / Active Arc / head dot」実測):
//   - 270° の開いたゲージ (下 45° ずつ開く)。書き出し SVG の幾何: 外径 176 / 線幅 12.32
//     (= 7% of size)、端は角 (butt)。
//   - track は主文字色 14% (Dark pearl / Light #17181C、実測)。
//   - 弧は現在値の帯色 (MrwTokens.stateColorForMri、指示書 §4.3)。長さは MRI/100。
//     弧の先端に 10px (= size × 5/176 半径) の head dot。
//   - 中央: 数値 52px SemiBold (主文字色) + バンド名 (mono 11、字間 0.88、inkMid)。
//     「VERY HOT — HYDRATE」のような「—」を含む帯名は 1 行だとリングの内側 (弦 133)
//     に収まらない (EN 134.6 / JA 135.9 / ES さらに長い) ので、「—」の直後で改行した
//     2 行にする (幅上限 124。数値の中心は 1 行のときと同じ位置で、2 行目は下へ伸びる)。
// 状態色が付くのは弧と head dot のみ (指示書 §4.1: ゲージの弧 / 帯ドット / MRI 数値)。
// Twin — Compare など他画面も同じ部品を使う (size を変える)。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/mood_ring_index.dart';
import '../../domain/mri/mri_band.dart';
import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';

class MoodRingWidget extends StatelessWidget {
  const MoodRingWidget({
    super.key,
    required this.mri,
    this.label,
    this.size = 176,
    this.valueFontSize,
    this.labelFontSize,
    this.dotRadius,
    this.colorValue = false,
  });

  final MoodRingIndex mri;

  /// バンドラベルの上書き (l10n 済み文言)。null なら既定の英語ラベル。
  final String? label;

  final double size;

  /// 中央の数値の文字サイズ。既定は 52 × (size / 176)。
  /// Figma の Twin — Compare (5:227) は 100px のリングに 44px の数値を置くため、
  /// Home と同じ比率にならない。そこだけ明示的に上書きする。
  final double? valueFontSize;

  /// バンドラベルの文字サイズ。既定は 11 × (size / 176)。
  final double? labelFontSize;

  /// head dot の半径。既定は 5 × (size / 176)。Compare (5:226) は 10px 固定。
  final double? dotRadius;

  /// true で中央の数値を帯色にする (指示書 §4.1 規則 1 の ③「MRI 数値」)。
  /// 既定 (false) は主文字色 — Home のリングは数値を無彩色にしている。
  final bool colorValue;

  /// Figma の基準寸法 (176px)。他の寸法はこれに対する比で決める。
  static const double referenceSize = 176;

  /// 2 行にした帯名の幅の上限 (176px のリングで 124。2 行目の下端でのリング内側の弦)。
  static const double twoLineLabelMaxWidth = 124;

  /// 帯名を「—」の直後で 2 行に分ける (Hydrate 系)。「—」を含まない帯名は null。
  static (String, String)? splitLabel(String label) {
    final at = label.indexOf('—');
    if (at < 0) return null;
    final first = label.substring(0, at + 1).trimRight();
    final second = label.substring(at + 1).trim();
    if (first.isEmpty || second.isEmpty) return null;
    return (first, second);
  }

  /// 中央の数値 + バンド名が円の中に収まるか。
  ///
  /// リングは直径が固定の計器なので、文字倍率を上げると中身が円からはみ出す
  /// (92px / 100px のリングは倍率 2.0 で溢れる)。収まらないときだけ
  /// [FittedBox] で縮めて収める。**収まる間は包まない** ので、等倍の描画は
  /// 従来と 1px も変わらない (Home の 176px リングは倍率 2.0 でも収まる)。
  /// 帯名が 2 行のときは、2 行目と数値の位置を保つための上の空き (1 行ぶん) も足す。
  bool _fitsInRing(BuildContext context, {required bool twoLines}) {
    final k = size / referenceSize;
    final scaler = MediaQuery.textScalerOf(context);
    final labelLine = scaler.scale(labelFontSize ?? 11 * k) * (14 / 11);
    final natural = scaler.scale(valueFontSize ?? 52 * k) * (58 / 52) +
        2 * k +
        labelLine * (twoLines ? 3 : 1) +
        12 * k;
    return natural <= size;
  }

  static String defaultLabel(MriBand band) {
    switch (band) {
      case MriBand.cool:
        return 'COOL';
      case MriBand.comfortable:
        return 'COMFORTABLE';
      case MriBand.warm:
        return 'SLIGHTLY HOT';
      case MriBand.hot:
        return 'HOT';
      case MriBand.hotAlert:
        return '⚠ VERY HOT — HYDRATE';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final k = size / referenceSize;
    final bandColor = tokens.stateColorForMri(mri.value);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: labelFontSize ?? 11 * k,
          letterSpacing: 0.88 * k,
          color: tokens.inkMid,
          height: 14 / 11,
        );
    final bandLabel = label ?? defaultLabel(mri.band);
    final lines = splitLabel(bandLabel);
    final labelLine =
        MediaQuery.textScalerOf(context).scale(labelFontSize ?? 11 * k) *
            (14 / 11);
    final center = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 帯名が 2 行のときは、増えた 1 行ぶんを上にも空けて中央寄せの位置を
        // 相殺する (数値の中心は 1 行のときのまま、2 行目は下へ伸びる)。
        if (lines != null) SizedBox(height: labelLine),
        Text(
          '${mri.value}',
          style: MrwFonts.numeral(
            context,
            size: valueFontSize ?? 52 * k,
            weight: FontWeight.w600,
            height: 58 / 52,
            color: colorValue ? bandColor : tokens.textHi,
          ),
        ),
        SizedBox(height: 2 * k),
        if (lines == null)
          Text(
            bandLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          )
        else
          // 改行は「—」の直後に固定 (語の途中では折らない)。幅上限 124 を超える
          // 文字倍率では 2 行のまま縮める。
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: twoLineLabelMaxWidth * k),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${lines.$1}\n${lines.$2}',
                textAlign: TextAlign.center,
                softWrap: false,
                style: labelStyle,
              ),
            ),
          ),
      ],
    );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: (mri.value.clamp(0, 100)) / 100,
          trackColor: tokens.textHi.withValues(alpha: 0.14),
          arcColor: bandColor,
          strokeWidth: 12.32 * k,
          dotRadius: dotRadius ?? 5 * k,
        ),
        child: Center(
          child: Padding(
            // Figma: 数値の中心はリング中心、バンド名はその下 (352−226=126 → 中心 88 の +38)。
            padding: EdgeInsets.only(top: 12 * k),
            child: _fitsInRing(context, twoLines: lines != null)
                ? center
                : FittedBox(child: center),
          ),
        ),
      ),
    );
  }
}

/// 値の無いリング (Figma 地点タブ E6a / E6b: track だけを残し、弧・head dot・
/// 帯名を消して中央に「—」を textLo で置く)。取得中・取得失敗の表示用。
/// 状態色は持たない (§4.1)。
class MoodRingPlaceholder extends StatelessWidget {
  const MoodRingPlaceholder({super.key, this.size = 176});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final k = size / MoodRingWidget.referenceSize;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: 0,
          trackColor: tokens.textHi.withValues(alpha: 0.14),
          arcColor: const Color(0x00000000),
          strokeWidth: 12.32 * k,
          dotRadius: 0,
        ),
        child: Center(
          child: Text(
            '—',
            maxLines: 1,
            style: MrwFonts.numeral(
              context,
              size: 52 * k,
              weight: FontWeight.w600,
              height: 58 / 52,
              color: tokens.textLo,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.trackColor,
    required this.arcColor,
    required this.strokeWidth,
    required this.dotRadius,
  });

  final double fraction;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;
  final double dotRadius;

  /// 開始角 (左下 135°) と全長 (270°)。SVG の端点 (25.77, 150.23) / (150.23, 150.23) から算出。
  static const double _start = 3 * math.pi / 4;
  static const double _sweep = 3 * math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = trackColor;
    canvas.drawArc(rect, _start, _sweep, false, track);

    final sweep = _sweep * fraction;
    if (sweep > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = arcColor;
      canvas.drawArc(rect, _start, sweep, false, arc);
    }

    // head dot: 弧の先端 (弧の中心線上)。値の無いリングでは描かない。
    if (dotRadius <= 0) return;
    final end = _start + sweep;
    final dot = Offset(
      center.dx + radius * math.cos(end),
      center.dy + radius * math.sin(end),
    );
    canvas.drawCircle(dot, dotRadius, Paint()..color = arcColor);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.arcColor != arcColor ||
      old.strokeWidth != strokeWidth ||
      old.dotRadius != dotRadius;
}
