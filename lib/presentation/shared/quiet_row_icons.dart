// lib/presentation/shared/quiet_row_icons.dart
//
// 設定系の行アイコン (Figma v1.3 `Settings — Quiet Top` 3:356 / `Settings — General`
// 3:473 の `row icon` / `chevron` を書き出した SVG)。
// **このファイルの `_rowIconSpecs` は scratchpad の SVG→Dart 変換スクリプトで生成した**
// (座標は Figma の書き出し SVG そのまま。手で編集せず、変更は Figma → 再生成で行う)。
//
// 20px グリッドの線画を任意サイズへ拡縮する。線幅は比例縮小しつつ 1.1px を下限にする。
// 色は既定で副文字色 (Figma 実測 #AEB2BA / chevron は #8A8F98)。状態色は使わない
// (codex-fixes_v1.3_unified.md §4.1: 状態色は弧・帯ドット・MRI 数値のみ)。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';

/// 設定行・言語行・ヘッダで使う線画アイコン。
enum QuietRowIcon { sliders, bell, globe, scale, place, lock, info, chevron }

class QuietRowIconMark extends StatelessWidget {
  const QuietRowIconMark(this.icon, {super.key, this.size = 20, this.color});

  final QuietRowIcon icon;
  final double size;

  /// 省略時は行アイコン = 副文字色、chevron = mono メタ色 (Figma 実測)。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final spec = _rowIconSpecs[icon]!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RowIconPainter(
          spec: spec,
          color: color ??
              (icon == QuietRowIcon.chevron ? tokens.textMono : tokens.textMid),
        ),
      ),
    );
  }
}

class _RowIconStroke {
  const _RowIconStroke({
    required this.width,
    required this.roundCap,
    required this.build,
  });
  final double width;
  final bool roundCap;
  final Path Function() build;
}

class _RowIconSpec {
  const _RowIconSpec({required this.strokes});
  final List<_RowIconStroke> strokes;

  /// Figma の書き出しはすべて 20px グリッド。
  static const double viewBox = 20;
}

class _RowIconPainter extends CustomPainter {
  _RowIconPainter({required this.spec, required this.color});

  final _RowIconSpec spec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _RowIconSpec.viewBox;
    canvas.save();
    canvas.scale(scale, scale);
    for (final s in spec.strokes) {
      final paint = Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        // 縮小時も 1.1px 以上を保つ (グリフ座標系では 1.1 / scale)。
        ..strokeWidth = s.width < 1.1 / scale ? 1.1 / scale : s.width
        ..strokeCap = s.roundCap ? StrokeCap.round : StrokeCap.butt
        ..strokeJoin = s.roundCap ? StrokeJoin.round : StrokeJoin.miter;
      canvas.drawPath(s.build(), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RowIconPainter old) =>
      old.spec != spec || old.color != color;
}

final Map<QuietRowIcon, _RowIconSpec> _rowIconSpecs = {
  // ed706.svg → sliders
  QuietRowIcon.sliders: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: true,
      build: () => Path()
        ..moveTo(3.33333, 5.83333)
        ..lineTo(11.6667, 5.83333)
        ..moveTo(15, 5.83333)
        ..lineTo(16.6667, 5.83333)
        ..moveTo(3.33333, 14.1667)
        ..lineTo(5.83333, 14.1667)
        ..moveTo(9.16667, 14.1667)
        ..lineTo(16.6667, 14.1667),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(13.3333, 7.5)
        ..cubicTo(14.2538, 7.5, 15, 6.75381, 15, 5.83333)
        ..cubicTo(15, 4.91286, 14.2538, 4.16667, 13.3333, 4.16667)
        ..cubicTo(12.4129, 4.16667, 11.6667, 4.91286, 11.6667, 5.83333)
        ..cubicTo(11.6667, 6.75381, 12.4129, 7.5, 13.3333, 7.5)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(7.5, 15.8333)
        ..cubicTo(8.42047, 15.8333, 9.16667, 15.0871, 9.16667, 14.1667)
        ..cubicTo(9.16667, 13.2462, 8.42047, 12.5, 7.5, 12.5)
        ..cubicTo(6.57953, 12.5, 5.83333, 13.2462, 5.83333, 14.1667)
        ..cubicTo(5.83333, 15.0871, 6.57953, 15.8333, 7.5, 15.8333)
        ..close(),
    ),
  ]),
  // f2dd4.svg → bell
  QuietRowIcon.bell: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(5, 7.5)
        ..cubicTo(5, 6.17392, 5.52678, 4.90215, 6.46447, 3.96447)
        ..cubicTo(7.40215, 3.02678, 8.67392, 2.5, 10, 2.5)
        ..cubicTo(11.3261, 2.5, 12.5979, 3.02678, 13.5355, 3.96447)
        ..cubicTo(14.4732, 4.90215, 15, 6.17392, 15, 7.5)
        ..cubicTo(15, 13.3333, 17.5, 12.5, 17.5, 14.1667)
        ..lineTo(2.5, 14.1667)
        ..cubicTo(2.5, 12.5, 5, 13.3333, 5, 7.5)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(8.33333, 16.6667)
        ..cubicTo(8.33333, 17.1087, 8.50893, 17.5326, 8.82149, 17.8452)
        ..cubicTo(9.13405, 18.1577, 9.55797, 18.3333, 10, 18.3333)
        ..cubicTo(10.442, 18.3333, 10.8659, 18.1577, 11.1785, 17.8452)
        ..cubicTo(11.4911, 17.5326, 11.6667, 17.1087, 11.6667, 16.6667),
    ),
  ]),
  // f96f9.svg → globe
  QuietRowIcon.globe: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(10, 17.5)
        ..cubicTo(14.1421, 17.5, 17.5, 14.1421, 17.5, 10)
        ..cubicTo(17.5, 5.85786, 14.1421, 2.5, 10, 2.5)
        ..cubicTo(5.85786, 2.5, 2.5, 5.85786, 2.5, 10)
        ..cubicTo(2.5, 14.1421, 5.85786, 17.5, 10, 17.5)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(2.5, 10)
        ..lineTo(17.5, 10)
        ..moveTo(10, 2.5)
        ..cubicTo(12.0833, 4.66667, 12.9167, 7.16667, 12.9167, 10)
        ..cubicTo(12.9167, 12.8333, 12.0833, 15.3333, 10, 17.5)
        ..cubicTo(7.91667, 15.3333, 7.08333, 12.8333, 7.08333, 10)
        ..cubicTo(7.08333, 7.16667, 7.91667, 4.66667, 10, 2.5)
        ..close(),
    ),
  ]),
  // 01668.svg → scale
  QuietRowIcon.scale: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: true,
      build: () => Path()
        ..moveTo(4.16667, 7.5)
        ..lineTo(13.3333, 7.5)
        ..cubicTo(13.663, 7.5, 13.9852, 7.40225, 14.2593, 7.21912)
        ..cubicTo(14.5334, 7.03598, 14.747, 6.77568, 14.8731, 6.47114)
        ..cubicTo(14.9993, 6.1666, 15.0323, 5.83148, 14.968, 5.50818)
        ..cubicTo(14.9037, 5.18488, 14.7449, 4.88791, 14.5118, 4.65482)
        ..cubicTo(14.2788, 4.42173, 13.9818, 4.263, 13.6585, 4.19869)
        ..cubicTo(13.3352, 4.13438, 13.0001, 4.16739, 12.6955, 4.29353)
        ..cubicTo(12.391, 4.41968, 12.1307, 4.6333, 11.9476, 4.90738)
        ..cubicTo(11.7644, 5.18147, 11.6667, 5.5037, 11.6667, 5.83333)
        ..moveTo(4.16667, 11.6667)
        ..lineTo(15.8333, 11.6667)
        ..moveTo(4.16667, 15.8333)
        ..lineTo(10.8333, 15.8333)
        ..cubicTo(11.163, 15.8333, 11.4852, 15.7356, 11.7593, 15.5524)
        ..cubicTo(12.0334, 15.3693, 12.247, 15.109, 12.3731, 14.8045)
        ..cubicTo(12.4993, 14.4999, 12.5323, 14.1648, 12.468, 13.8415)
        ..cubicTo(12.4037, 13.5182, 12.2449, 13.2212, 12.0118, 12.9882)
        ..cubicTo(11.7788, 12.7551, 11.4818, 12.5963, 11.1585, 12.532)
        ..cubicTo(10.8352, 12.4677, 10.5001, 12.5007, 10.1955, 12.6269)
        ..cubicTo(9.89098, 12.753, 9.63069, 12.9666, 9.44755, 13.2407)
        ..cubicTo(9.26442, 13.5148, 9.16667, 13.837, 9.16667, 14.1667),
    ),
  ]),
  // adddf.svg → place
  QuietRowIcon.place: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(10, 17.5)
        ..cubicTo(10, 17.5, 15, 13, 15, 8.33333)
        ..cubicTo(15, 7.00725, 14.4732, 5.73548, 13.5355, 4.7978)
        ..cubicTo(12.5979, 3.86012, 11.3261, 3.33333, 10, 3.33333)
        ..cubicTo(8.67392, 3.33333, 7.40215, 3.86012, 6.46447, 4.7978)
        ..cubicTo(5.52678, 5.73548, 5, 7.00725, 5, 8.33333)
        ..cubicTo(5, 13, 10, 17.5, 10, 17.5)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(10, 10)
        ..cubicTo(10.9205, 10, 11.6667, 9.25381, 11.6667, 8.33333)
        ..cubicTo(11.6667, 7.41286, 10.9205, 6.66667, 10, 6.66667)
        ..cubicTo(9.07953, 6.66667, 8.33333, 7.41286, 8.33333, 8.33333)
        ..cubicTo(8.33333, 9.25381, 9.07953, 10, 10, 10)
        ..close(),
    ),
  ]),
  // fc14a.svg → lock
  QuietRowIcon.lock: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(14.1667, 8.33333)
        ..lineTo(5.83333, 8.33333)
        ..cubicTo(4.91286, 8.33333, 4.16667, 9.07953, 4.16667, 10)
        ..lineTo(4.16667, 15)
        ..cubicTo(4.16667, 15.9205, 4.91286, 16.6667, 5.83333, 16.6667)
        ..lineTo(14.1667, 16.6667)
        ..cubicTo(15.0871, 16.6667, 15.8333, 15.9205, 15.8333, 15)
        ..lineTo(15.8333, 10)
        ..cubicTo(15.8333, 9.07953, 15.0871, 8.33333, 14.1667, 8.33333)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.5,
      roundCap: false,
      build: () => Path()
        ..moveTo(6.66667, 8.33333)
        ..lineTo(6.66667, 5.83333)
        ..cubicTo(6.66667, 4.94928, 7.01786, 4.10143, 7.64298, 3.47631)
        ..cubicTo(8.2681, 2.85119, 9.11594, 2.5, 10, 2.5)
        ..cubicTo(10.8841, 2.5, 11.7319, 2.85119, 12.357, 3.47631)
        ..cubicTo(12.9821, 4.10143, 13.3333, 4.94928, 13.3333, 5.83333)
        ..lineTo(13.3333, 8.33333),
    ),
  ]),
  // a0e45.svg → info
  QuietRowIcon.info: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.6,
      roundCap: false,
      build: () => Path()
        ..moveTo(10, 17.5)
        ..cubicTo(14.1421, 17.5, 17.5, 14.1421, 17.5, 10)
        ..cubicTo(17.5, 5.85786, 14.1421, 2.5, 10, 2.5)
        ..cubicTo(5.85786, 2.5, 2.5, 5.85786, 2.5, 10)
        ..cubicTo(2.5, 14.1421, 5.85786, 17.5, 10, 17.5)
        ..close(),
    ),
    _RowIconStroke(
      width: 1.6,
      roundCap: true,
      build: () => Path()
        ..moveTo(10, 9)
        ..lineTo(10, 14)
        ..moveTo(10, 6)
        ..lineTo(10, 6.5),
    ),
  ]),
  // dde36.svg → chevron
  QuietRowIcon.chevron: _RowIconSpec(strokes: [
    _RowIconStroke(
      width: 1.6,
      roundCap: true,
      build: () => Path()
        ..moveTo(7.5, 5)
        ..lineTo(12.5, 10)
        ..lineTo(7.5, 15),
    ),
  ]),
};
