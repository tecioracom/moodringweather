// lib/presentation/shared/mri_line_chart.dart
//
// MRI の折れ線 (Home 3:73 Sparkline Card / Detail 3:287)。capsule bar の後継。
// 諮問記録: docs/home-sparkline-line-consult.md (designer と Codex が独立に折れ線で一致)。
//
//   - 頂点は毎時。x は時刻ラベル・天気レールと同じスロット幾何に載せる
//     (スロット i の中心 = barW/2 + i × (barW + gap)。頂点 k はスロット k / verticesPerSlot)
//   - y は MriBarScale の表示範囲を高さ全体に写像する。capsule bar の下駄 (0.5) は
//     廃止 — bar は「0 からの長さ」を約束する記号で自動スケールと両立しなかった。
//     線は位置で読むので、軸 (MriValueAxis) さえあれば切り詰めた目盛りが正当
//   - 快適帯 (bandMin〜bandMax) と下端の基準線を、線と同じ写像で背面に敷く
//   - 現在は無彩ドット (地色で抜く) + 縦ヘアライン
//   - 過去区間は「破線 + 背景の淡い wash」の二重の手掛かりで示す (採用案 C、2026-09-19
//     ユーザー決裁)。α は落とさない — 線は刺激面積が小さく、薄くすると 3:1 を割る。
//     破線 3/3 (案 A と同じ細かさ)、wash inkMid 4%、現在の縦線 28% → 40%
//   - 色は inkMid / textHi のみ。指示書 §4.1: 状態色は弧・帯ドット・MRI 数値だけ。
//     規則 3 (色付き要素には数値かバンドラベルを隣接) も満たせないので線に状態色は使わない
//   - null は欠測として線を切る
//
// 不採用: 面塗り (帯と濁る)、帯の右端ラベル (線と衝突する)、ドットの微光 (α0.10 では見えない)。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';
import 'mri_bar_scale.dart';

/// 過去区間の描き分け。
enum PastLineStyle {
  /// α を落とすだけ。
  dim,

  /// α を落とし、さらに破線にする (色に頼らず「済んだ」が分かる)。
  dashed,
}

/// 幾何 (純 Dart。テストで検証しやすいよう painter から分離)。
class MriLineGeometry {
  const MriLineGeometry({
    required this.size,
    required this.scale,
    required this.slotCount,
    required this.verticesPerSlot,
    required this.gap,
    required this.strokeWidth,
  });

  final Size size;
  final MriBarScale scale;
  final int slotCount;
  final double verticesPerSlot;
  final double gap;
  final double strokeWidth;

  double get slotWidth => (size.width - gap * (slotCount - 1)) / slotCount;

  /// 頂点 [index] の x (スロット中心に載る)。
  double xAt(int index) =>
      slotWidth / 2 + (index / verticesPerSlot) * (slotWidth + gap);

  /// 値 [value] の y。線幅の半分だけ内側に寄せ、端の頂点が切れないようにする。
  double yAt(double value) {
    final pad = strokeWidth / 2;
    final norm = ((value - scale.lo) / scale.span).clamp(0.0, 1.0);
    return pad + (size.height - 2 * pad) * (1 - norm);
  }

  /// 参照バンドの矩形。表示範囲に掛からなければ null。片側が範囲外なら端まで伸ばす。
  Rect? bandRect(double? min, double? max) {
    if (min == null || max == null || max <= min) return null;
    if (max <= scale.lo || min >= scale.hi) return null;
    final top = max >= scale.hi ? 0.0 : yAt(max);
    final bottom = min <= scale.lo ? size.height : yAt(min);
    if (bottom - top <= 0) return null;
    return Rect.fromLTRB(0, top, size.width, bottom);
  }

  /// 基準線 (バンド下端) を引くか。下端が表示範囲の外なら引かない。
  bool bandEdgeVisible(double? min) => min != null && min > scale.lo;
}

class MriLineChart extends StatelessWidget {
  const MriLineChart({
    super.key,
    required this.values,
    required this.nowIndex,
    required this.slotCount,
    required this.verticesPerSlot,
    required this.scale,
    this.height = 36,
    this.gap = 8,
    this.strokeWidth = 1.75,
    this.futureAlpha,
    this.pastAlpha,
    this.pastStyle = PastLineStyle.dashed,
    this.bandMin,
    this.bandMax,
    this.bandAlpha = 0.08,
    this.bandEdgeAlpha = 0.18,
    this.nowLineAlpha = 0.40,
    this.nowDotRadius = 2.5,
    this.nowKnockoutRadius = 4,
    this.dashOn = 3,
    this.dashOff = 3,
    this.bandTopEdgeAlpha = 0,
    this.pastWashAlpha = 0.04,
    this.nowGlowRadius = 0,
    this.nowGlowAlpha = 0.10,
    this.bandLabel,
    this.bandLabelStyle,
  });

  /// 毎時の値 (rangeMin〜rangeMax)。null は欠測。
  final List<double?> values;

  /// 現在の頂点 index。
  final int nowIndex;

  /// 時刻ラベル・天気レールと共有するスロット数 (Home 9 / Detail 12)。
  final int slotCount;

  /// 1 スロットあたりの頂点数 (Home: 1.5h スロットに毎時 → 1.5 / Detail: 2h → 2)。
  final double verticesPerSlot;

  final MriBarScale scale;
  final double height;
  final double gap;
  final double strokeWidth;

  /// 線の α。null ならテーマ既定 (Dark 0.60 / Light 0.68 = 対カード地 3.6:1)。
  /// bar と同じ α0.42 では線は刺激面積が小さく Dark で 2.48:1 しか出ない。
  final double? futureAlpha;

  /// 過去区間の α。null なら破線のときは未来と同じ、実線 (dim) のときは
  /// テーマ既定で薄く (Dark 0.34 / Light 0.40)。
  final double? pastAlpha;
  final PastLineStyle pastStyle;

  /// 背面に敷く参照バンドの値域 (両方 null で非表示)。
  final double? bandMin;
  final double? bandMax;
  final double bandAlpha;
  final double bandEdgeAlpha;

  /// 現在の縦ヘアラインの α。
  final double nowLineAlpha;
  final double nowDotRadius;
  final double nowKnockoutRadius;

  /// 過去区間を破線にするときの線分 / 空白の長さ。
  final double dashOn;
  final double dashOff;

  /// 帯の上端 (bandMax) にも細線を引くときの α (0 で無し)。
  final double bandTopEdgeAlpha;

  /// 過去区間の背景 wash の α (0 で無し)。現在の x までを淡く塗る。
  final double pastWashAlpha;

  /// 現在ドットの外周 (微光) の半径と α (半径 0 で無し)。無彩。
  final double nowGlowRadius;
  final double nowGlowAlpha;

  /// 帯の右端に置く極小ラベル ("COMFORT" / "快適")。null で無し。
  final String? bandLabel;
  final TextStyle? bandLabelStyle;

  MriLineGeometry geometryFor(Size size) => MriLineGeometry(
        size: size,
        scale: scale,
        slotCount: slotCount,
        verticesPerSlot: verticesPerSlot,
        gap: gap,
        strokeWidth: strokeWidth,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _MriLinePainter(
          chart: this,
          ink: tokens.inkMid,
          dot: tokens.textHi,
          knockout: tokens.surface,
          futureAlpha: futureAlpha ?? (dark ? 0.60 : 0.68),
          pastAlpha: pastAlpha ??
              (pastStyle == PastLineStyle.dashed
                  ? (futureAlpha ?? (dark ? 0.60 : 0.68))
                  : (dark ? 0.34 : 0.40)),
        ),
      ),
    );
  }
}

class _MriLinePainter extends CustomPainter {
  const _MriLinePainter({
    required this.chart,
    required this.ink,
    required this.dot,
    required this.knockout,
    required this.futureAlpha,
    required this.pastAlpha,
  });

  final MriLineChart chart;
  final Color ink;
  final Color dot;
  final Color knockout;
  final double futureAlpha;
  final double pastAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final g = chart.geometryFor(size);
    final values = chart.values;
    if (values.isEmpty) return;

    final now = chart.nowIndex.clamp(0, values.length - 1);
    final xNow = g.xAt(now);

    // 過去区間の wash (任意)。帯より背面。
    if (chart.pastWashAlpha > 0 && xNow > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, 0, xNow, size.height),
          const Radius.circular(4),
        ),
        Paint()..color = ink.withValues(alpha: chart.pastWashAlpha),
      );
    }

    // 参照バンドと基準線 (線と同じ写像)。
    final band = g.bandRect(chart.bandMin, chart.bandMax);
    if (band != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(4)),
        Paint()..color = ink.withValues(alpha: chart.bandAlpha),
      );
      if (g.bandEdgeVisible(chart.bandMin)) {
        canvas.drawRect(
          Rect.fromLTWH(0, band.bottom - 1, size.width, 1),
          Paint()..color = ink.withValues(alpha: chart.bandEdgeAlpha),
        );
      }
      if (chart.bandTopEdgeAlpha > 0 && band.top > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, band.top, size.width, 1),
          Paint()..color = ink.withValues(alpha: chart.bandTopEdgeAlpha),
        );
      }
      final label = chart.bandLabel;
      if (label != null && chart.bandLabelStyle != null && band.height >= 10) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: chart.bandLabelStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        if (tp.width + 8 < size.width) {
          tp.paint(
            canvas,
            Offset(size.width - tp.width - 4,
                band.top + (band.height - tp.height) / 2),
          );
        }
      }
    }

    // 現在の縦ヘアライン。
    canvas.drawLine(
      Offset(xNow, 0),
      Offset(xNow, size.height),
      Paint()
        ..color = ink.withValues(alpha: chart.nowLineAlpha)
        ..strokeWidth = 1,
    );

    // 折れ線: 過去 (0..now) と未来 (now..末尾)。欠測で切る。
    final past = _polyline(g, values, 0, now);
    final future = _polyline(g, values, now, values.length - 1);
    final futurePaint = _strokePaint(futureAlpha);
    final pastPaint = _strokePaint(pastAlpha);
    for (final p in past) {
      canvas.drawPath(
        chart.pastStyle == PastLineStyle.dashed
            ? _dashed(p, chart.dashOn, chart.dashOff)
            : p,
        pastPaint,
      );
    }
    for (final p in future) {
      canvas.drawPath(p, futurePaint);
    }

    // 現在のドット。地色で抜いてから置く (線と重なっても読める)。
    final v = values[now];
    if (v != null) {
      final c = Offset(xNow, g.yAt(v));
      if (chart.nowGlowRadius > 0) {
        canvas.drawCircle(
          c,
          chart.nowGlowRadius,
          Paint()..color = dot.withValues(alpha: chart.nowGlowAlpha),
        );
      }
      canvas.drawCircle(c, chart.nowKnockoutRadius, Paint()..color = knockout);
      canvas.drawCircle(
        c,
        chart.nowDotRadius,
        Paint()..color = dot.withValues(alpha: 0.95),
      );
    }
  }

  Paint _strokePaint(double alpha) => Paint()
    ..color = ink.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = chart.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// [from]..[to] の頂点を結ぶ。null を挟むごとに別のパスにする。
  List<Path> _polyline(
    MriLineGeometry g,
    List<double?> values,
    int from,
    int to,
  ) {
    final paths = <Path>[];
    Path? current;
    var count = 0;
    for (var i = from; i <= to; i++) {
      final v = values[i];
      if (v == null) {
        if (current != null && count >= 2) paths.add(current);
        current = null;
        count = 0;
        continue;
      }
      final p = Offset(g.xAt(i), g.yAt(v));
      if (current == null) {
        current = Path()..moveTo(p.dx, p.dy);
        count = 1;
      } else {
        current.lineTo(p.dx, p.dy);
        count++;
      }
    }
    if (current != null && count >= 2) paths.add(current);
    return paths;
  }

  Path _dashed(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + on).clamp(0.0, metric.length);
        out.addPath(metric.extractPath(d, end), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_MriLinePainter old) =>
      old.chart.values != chart.values ||
      old.chart.nowIndex != chart.nowIndex ||
      old.chart.scale.lo != chart.scale.lo ||
      old.chart.scale.hi != chart.scale.hi ||
      old.chart.pastStyle != chart.pastStyle ||
      old.chart.bandTopEdgeAlpha != chart.bandTopEdgeAlpha ||
      old.chart.pastWashAlpha != chart.pastWashAlpha ||
      old.chart.nowGlowRadius != chart.nowGlowRadius ||
      old.chart.nowLineAlpha != chart.nowLineAlpha ||
      old.chart.bandLabel != chart.bandLabel ||
      old.ink != ink ||
      old.dot != dot ||
      old.knockout != knockout ||
      old.futureAlpha != futureAlpha ||
      old.pastAlpha != pastAlpha;
}
