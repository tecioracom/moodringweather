// lib/presentation/shared/quiet_glyphs.dart
//
// v1.3「Quiet Atmos Glyphs」(Figma 23:2) と Home の小アイコン (3:2) を Path で描く。
// **このファイルは scratchpad の SVG→Dart 変換スクリプトで生成した** (座標は Figma の
// 書き出し SVG そのまま。手で編集せず、変更は Figma → 再生成で行う)。
//
// 色の規則 (codex-fixes_v1.3_unified.md §4.4): 天気グリフは MRI 値ではないため原則
// ニュートラル。Clear / Partly / Storm = 主文字色、Cloud / Rain / Snow / Fog = 副文字色、
// **Heat のみ state/danger** (危険の意味を持つ唯一の例外)。
// 小アイコン (pin / settings / 湿度 / 風 / UV / 空気) は Dark #AEB2BA / Light #6D7480 (実測)。
//
// 24px / 48px グリッドの線画を任意サイズへ拡縮する。線幅は比例縮小しつつ 1.1px を下限に
// する (9.5px のレールでも潰れない)。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';

/// 天気グリフ (Figma 23:2 の 10 種)。
enum QuietGlyph {
  clear,
  partly,
  cloud,
  rain,
  heavyRain,
  snow,
  heavySnow,
  storm,
  fog,
  heat
}

/// Home / Detail の小アイコン (Figma 3:2 / 3:243)。
enum QuietIcon { pin, settings, humidity, wind, uv, air }

/// WeatherSnapshot.condition ('sunny' 等) → グリフ。[heat] が true なら Heat を優先する。
QuietGlyph glyphForCondition(String condition, {bool heat = false}) {
  if (heat) return QuietGlyph.heat;
  switch (condition) {
    case 'sunny':
      return QuietGlyph.clear;
    case 'partly':
      return QuietGlyph.partly;
    case 'cloudy':
      return QuietGlyph.cloud;
    case 'foggy':
      return QuietGlyph.fog;
    case 'rainy':
      return QuietGlyph.rain;
    case 'snowy':
      return QuietGlyph.snow;
    case 'stormy':
      return QuietGlyph.storm;
    default:
      return QuietGlyph.cloud;
  }
}

/// [glyph] を [canvas] の正方形 [rect] に [color] 1 色で描く (ウィジェットの外で描く
/// とき用。ライブ壁紙の重ね描き)。役割の色 (Heat = state/danger など) は使わず、各線の
/// 不透明度だけを保つ。線の太さの下限 1.1 は [rect] の座標系 (論理 px) で保つ。
/// **手で足した関数** (生成スクリプトの対象外。再生成するときは残す)。
void paintQuietGlyph(Canvas canvas, QuietGlyph glyph, Rect rect, Color color) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  _GlyphPainter(spec: _glyphSpecs[glyph]!, color: color, opacity: 1)
      .paint(canvas, rect.size);
  canvas.restore();
}

class QuietGlyphIcon extends StatelessWidget {
  const QuietGlyphIcon(this.glyph,
      {super.key, this.size = 24, this.opacity = 1});

  final QuietGlyph glyph;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final spec = _glyphSpecs[glyph]!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(
            spec: spec, color: _roleColor(spec.role, tokens), opacity: opacity),
      ),
    );
  }
}

class QuietIconMark extends StatelessWidget {
  const QuietIconMark(this.icon, {super.key, this.size = 18, this.color});

  final QuietIcon icon;
  final double size;

  /// 省略時は Dark 副文字色 / Light #6B7480 (Figma 実測 #6D7480 に最も近いトークン)。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spec = _iconSpecs[icon]!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(
          spec: spec,
          color: color ?? (isDark ? tokens.textMid : tokens.textMono),
          opacity: 1,
        ),
      ),
    );
  }
}

Color _roleColor(_Role role, MrwTokens tokens) {
  switch (role) {
    case _Role.hi:
      return tokens.textHi;
    case _Role.mid:
      return tokens.inkMid;
    case _Role.danger:
      return tokens.stateDanger;
  }
}

enum _Role { hi, mid, danger }

class _GlyphStroke {
  const _GlyphStroke({
    required this.width,
    required this.opacity,
    required this.fill,
    required this.roundCap,
    required this.build,
  });
  final double width;
  final double opacity;
  final bool fill;
  final bool roundCap;
  final Path Function() build;
}

class _GlyphSpec {
  const _GlyphSpec(
      {required this.viewBox, required this.role, required this.strokes});
  final double viewBox;
  final _Role role;
  final List<_GlyphStroke> strokes;
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(
      {required this.spec, required this.color, required this.opacity});

  final _GlyphSpec spec;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / spec.viewBox;
    canvas.save();
    canvas.scale(scale, scale);
    for (final s in spec.strokes) {
      final paint = Paint()
        ..color = color.withValues(alpha: color.a * opacity * s.opacity)
        ..isAntiAlias = true;
      if (s.fill) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          // 縮小時も 1.1px 以上を保つ (グリフ座標系では 1.1 / scale)。
          ..strokeWidth = s.width < 1.1 / scale ? 1.1 / scale : s.width
          ..strokeCap = s.roundCap ? StrokeCap.round : StrokeCap.butt
          ..strokeJoin = s.roundCap ? StrokeJoin.round : StrokeJoin.miter;
      }
      canvas.drawPath(s.build(), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.spec != spec || old.color != color || old.opacity != opacity;
}

final Map<QuietGlyph, _GlyphSpec> _glyphSpecs = {
  // glyph-clear.svg (viewBox 48)
  QuietGlyph.clear: _GlyphSpec(viewBox: 48, role: _Role.hi, strokes: [
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 32.4)
          ..cubicTo(28.6392, 32.4, 32.4, 28.6392, 32.4, 24)
          ..cubicTo(32.4, 19.3608, 28.6392, 15.6, 24, 15.6)
          ..cubicTo(19.3608, 15.6, 15.6, 19.3608, 15.6, 24)
          ..cubicTo(15.6, 28.6392, 19.3608, 32.4, 24, 32.4)
          ..close()),
    _GlyphStroke(
        width: 1.6,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 7.5)
          ..lineTo(24, 12.7)
          ..moveTo(24, 35.3)
          ..lineTo(24, 40.5)
          ..moveTo(7.5, 24)
          ..lineTo(12.7, 24)
          ..moveTo(35.3, 24)
          ..lineTo(40.5, 24)
          ..moveTo(12.3, 12.3)
          ..lineTo(16, 16)
          ..moveTo(32, 32)
          ..lineTo(35.7, 35.7)
          ..moveTo(35.7, 12.3)
          ..lineTo(32, 16)
          ..moveTo(16, 32)
          ..lineTo(12.3, 35.7)),
    _GlyphStroke(
        width: 1.2,
        opacity: 0.24,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 38.6)
          ..cubicTo(32.0634, 38.6, 38.6, 32.0634, 38.6, 24)
          ..cubicTo(38.6, 15.9366, 32.0634, 9.4, 24, 9.4)
          ..cubicTo(15.9366, 9.4, 9.4, 15.9366, 9.4, 24)
          ..cubicTo(9.4, 32.0634, 15.9366, 38.6, 24, 38.6)
          ..close()),
  ]),
  // glyph-partly.svg (viewBox 48)
  QuietGlyph.partly: _GlyphSpec(viewBox: 48, role: _Role.hi, strokes: [
    _GlyphStroke(
        width: 1.7,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(18.5, 24.1)
          ..cubicTo(22.1451, 24.1, 25.1, 21.1451, 25.1, 17.5)
          ..cubicTo(25.1, 13.8549, 22.1451, 10.9, 18.5, 10.9)
          ..cubicTo(14.8549, 10.9, 11.9, 13.8549, 11.9, 17.5)
          ..cubicTo(11.9, 21.1451, 14.8549, 24.1, 18.5, 24.1)
          ..close()),
    _GlyphStroke(
        width: 1.35,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(18.5, 6.8)
          ..lineTo(18.5, 10.3)
          ..moveTo(18.5, 24.7)
          ..lineTo(18.5, 28.2)
          ..moveTo(7.8, 17.5)
          ..lineTo(11.3, 17.5)
          ..moveTo(25.7, 17.5)
          ..lineTo(29.2, 17.5)
          ..moveTo(10.9, 9.9)
          ..lineTo(13.4, 12.4)
          ..moveTo(23.6, 22.6)
          ..lineTo(26.1, 25.1)
          ..moveTo(26.1, 9.9)
          ..lineTo(23.6, 12.4)),
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(16.4, 32.6)
          ..lineTo(35.5, 32.6)
          ..cubicTo(39.7, 32.6, 42.5, 30, 42.5, 26.4)
          ..cubicTo(42.5, 22.8, 39.7, 20.1, 36.1, 20.1)
          ..cubicTo(34.8, 20.1, 33.6, 20.4, 32.6, 21.1)
          ..cubicTo(31.1, 17.5, 27.8, 15.2, 24, 15.2)
          ..cubicTo(18.9, 15.2, 15, 19, 14.8, 24)
          ..cubicTo(11.6, 24.4, 9.3, 26.6, 9.3, 29.1)
          ..cubicTo(9.3, 31.2, 11, 32.6, 16.4, 32.6)
          ..close()),
  ]),
  // glyph-cloud.svg (viewBox 48)
  QuietGlyph.cloud: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.9,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(13.1, 31.9)
          ..lineTo(35.2, 31.9)
          ..cubicTo(39.9, 31.9, 43, 29, 43, 24.9)
          ..cubicTo(43, 20.9, 39.9, 17.9, 35.9, 17.9)
          ..cubicTo(34.5, 17.9, 33.1, 18.3, 31.9, 19)
          ..cubicTo(30.2, 15, 26.5, 12.4, 22.2, 12.4)
          ..cubicTo(16.5, 12.4, 12.2, 16.7, 11.9, 22.2)
          ..cubicTo(8.2, 22.7, 5.6, 25.2, 5.6, 28.1)
          ..cubicTo(5.6, 30.4, 7.5, 31.9, 13.1, 31.9)
          ..close()),
    _GlyphStroke(
        width: 1.3,
        opacity: 0.42,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(17.2, 37.5)
          ..lineTo(35.6, 37.5)),
  ]),
  // glyph-rain.svg (viewBox 48)
  QuietGlyph.rain: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(13.6, 27.6)
          ..lineTo(34.3, 27.6)
          ..cubicTo(38.6, 27.6, 41.4, 25, 41.4, 21.3)
          ..cubicTo(41.4, 17.6, 38.6, 14.9, 34.9, 14.9)
          ..cubicTo(33.6, 14.9, 32.3, 15.3, 31.3, 16)
          ..cubicTo(29.7, 12.3, 26.3, 9.9, 22.3, 9.9)
          ..cubicTo(17, 9.9, 13, 13.9, 12.8, 19)
          ..cubicTo(9.4, 19.5, 7, 21.8, 7, 24.4)
          ..cubicTo(7, 26.4, 8.7, 27.6, 13.6, 27.6)
          ..close()),
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(17, 33.5)
          ..lineTo(14.8, 38.1)
          ..moveTo(25, 33.5)
          ..lineTo(22.8, 38.1)
          ..moveTo(33, 33.5)
          ..lineTo(30.8, 38.1)),
  ]),
  // glyph-heavyrain.svg (viewBox 48)
  QuietGlyph.heavyRain: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(12.6, 26.8)
          ..lineTo(34.2, 26.8)
          ..cubicTo(38, 26.8, 41.2, 23.9, 41.2, 20.2)
          ..cubicTo(41.2, 16.6, 38.3, 13.8, 34.8, 13.8)
          ..cubicTo(33.5, 10.7, 30.4, 8.7, 26.9, 8.7)
          ..cubicTo(22.8, 8.7, 19.4, 11.5, 18.5, 15.2)
          ..cubicTo(17.7, 14.9, 16.8, 14.8, 15.9, 14.8)
          ..cubicTo(11.4, 14.8, 7.8, 18.2, 7.8, 22.4)
          ..cubicTo(7.8, 24.9, 9.8, 26.8, 12.6, 26.8)
          ..close()),
    _GlyphStroke(
        width: 1.95,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(14, 32.8)
          ..lineTo(11.9, 36.6)
          ..moveTo(20.3, 32.1)
          ..lineTo(18.2, 36)
          ..moveTo(26.6, 32.8)
          ..lineTo(24.5, 36.6)
          ..moveTo(32.9, 32.1)
          ..lineTo(30.8, 36)),
  ]),
  // glyph-snow.svg (viewBox 48)
  QuietGlyph.snow: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.65,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 8.5)
          ..lineTo(24, 39.5)
          ..moveTo(10.6, 16.2)
          ..lineTo(37.4, 31.8)
          ..moveTo(10.6, 31.8)
          ..lineTo(37.4, 16.2)),
    _GlyphStroke(
        width: 1.25,
        opacity: 0.58,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(18.8, 11.8)
          ..lineTo(24, 15)
          ..lineTo(29.2, 11.8)
          ..moveTo(18.8, 36.2)
          ..lineTo(24, 33)
          ..lineTo(29.2, 36.2)
          ..moveTo(11.2, 22.2)
          ..lineTo(16.6, 19.4)
          ..lineTo(16.9, 13.3)
          ..moveTo(31.1, 34.7)
          ..lineTo(31.4, 28.6)
          ..lineTo(36.8, 25.8)
          ..moveTo(11.2, 25.8)
          ..lineTo(16.6, 28.6)
          ..lineTo(16.9, 34.7)
          ..moveTo(31.1, 13.3)
          ..lineTo(31.4, 19.4)
          ..lineTo(36.8, 22.2)),
    _GlyphStroke(
        width: 1.4,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 27.4)
          ..cubicTo(25.8778, 27.4, 27.4, 25.8778, 27.4, 24)
          ..cubicTo(27.4, 22.1222, 25.8778, 20.6, 24, 20.6)
          ..cubicTo(22.1222, 20.6, 20.6, 22.1222, 20.6, 24)
          ..cubicTo(20.6, 25.8778, 22.1222, 27.4, 24, 27.4)
          ..close()),
  ]),
  // glyph-heavysnow.svg (viewBox 48)
  QuietGlyph.heavySnow: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.65,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 8.2)
          ..lineTo(24, 39.8)
          ..moveTo(12.1, 13.7)
          ..lineTo(35.9, 34.3)
          ..moveTo(35.9, 13.7)
          ..lineTo(12.1, 34.3)),
    _GlyphStroke(
        width: 1.25,
        opacity: 0.58,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(18.4, 11.4)
          ..lineTo(24, 16.2)
          ..lineTo(29.6, 11.4)
          ..moveTo(18.4, 36.6)
          ..lineTo(24, 31.8)
          ..lineTo(29.6, 36.6)
          ..moveTo(10.9, 20.7)
          ..lineTo(18.1, 19.5)
          ..lineTo(20.6, 12.9)
          ..moveTo(37.1, 27.3)
          ..lineTo(29.9, 28.5)
          ..lineTo(27.4, 35.1)
          ..moveTo(37.1, 20.7)
          ..lineTo(29.9, 19.5)
          ..lineTo(27.4, 12.9)
          ..moveTo(10.9, 27.3)
          ..lineTo(18.1, 28.5)
          ..lineTo(20.6, 35.1)),
    _GlyphStroke(
        width: 1.45,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(24, 28)
          ..cubicTo(26.2091, 28, 28, 26.2091, 28, 24)
          ..cubicTo(28, 21.7909, 26.2091, 20, 24, 20)
          ..cubicTo(21.7909, 20, 20, 21.7909, 20, 24)
          ..cubicTo(20, 26.2091, 21.7909, 28, 24, 28)
          ..close()),
    _GlyphStroke(
        width: 1.25,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(16.6, 24)
          ..lineTo(31.4, 24)
          ..moveTo(24, 16.6)
          ..lineTo(24, 31.4)),
  ]),
  // glyph-storm.svg (viewBox 48)
  QuietGlyph.storm: _GlyphSpec(viewBox: 48, role: _Role.hi, strokes: [
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(13.6, 27.1)
          ..lineTo(34.3, 27.1)
          ..cubicTo(38.6, 27.1, 41.4, 24.5, 41.4, 20.8)
          ..cubicTo(41.4, 17.1, 38.6, 14.4, 34.9, 14.4)
          ..cubicTo(33.6, 14.4, 32.3, 14.8, 31.3, 15.5)
          ..cubicTo(29.7, 11.8, 26.3, 9.4, 22.3, 9.4)
          ..cubicTo(17, 9.4, 13, 13.4, 12.8, 18.5)
          ..cubicTo(9.4, 19, 7, 21.3, 7, 23.9)
          ..cubicTo(7, 25.9, 8.7, 27.1, 13.6, 27.1)
          ..close()),
    _GlyphStroke(
        width: 1.9,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(25.2, 29.2)
          ..lineTo(20.4, 40)
          ..lineTo(28.9, 32)
          ..lineTo(23.7, 32)
          ..lineTo(27.6, 24.8)),
  ]),
  // glyph-fog.svg (viewBox 48)
  QuietGlyph.fog: _GlyphSpec(viewBox: 48, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.65,
        opacity: 0.72,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(13.4, 23.7)
          ..lineTo(33.6, 23.7)
          ..cubicTo(37.7, 23.7, 40.4, 21.2, 40.4, 17.7)
          ..cubicTo(40.4, 14.1, 37.7, 11.6, 34.2, 11.6)
          ..cubicTo(32.9, 11.6, 31.7, 11.9, 30.7, 12.6)
          ..cubicTo(29.2, 9.1, 25.9, 6.8, 22.1, 6.8)
          ..cubicTo(17.1, 6.8, 13.3, 10.6, 13, 15.4)
          ..cubicTo(9.8, 15.9, 7.5, 18.1, 7.5, 20.5)
          ..cubicTo(7.5, 22.4, 9.1, 23.7, 13.4, 23.7)
          ..close()),
    _GlyphStroke(
        width: 1.8,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(8.5, 30.6)
          ..lineTo(39.5, 30.6)
          ..moveTo(12.5, 36)
          ..lineTo(35.5, 36)
          ..moveTo(17.5, 41.2)
          ..lineTo(30.5, 41.2)),
  ]),
  // glyph-heat.svg (viewBox 48)
  QuietGlyph.heat: _GlyphSpec(viewBox: 48, role: _Role.danger, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: true,
        roundCap: false,
        build: () => Path()
          ..moveTo(24, 32.5)
          ..cubicTo(28.6944, 32.5, 32.5, 28.6944, 32.5, 24)
          ..cubicTo(32.5, 19.3056, 28.6944, 15.5, 24, 15.5)
          ..cubicTo(19.3056, 15.5, 15.5, 19.3056, 15.5, 24)
          ..cubicTo(15.5, 28.6944, 19.3056, 32.5, 24, 32.5)
          ..close()),
    _GlyphStroke(
        width: 3.3,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(24, 32.5)
          ..cubicTo(28.6944, 32.5, 32.5, 28.6944, 32.5, 24)
          ..cubicTo(32.5, 19.3056, 28.6944, 15.5, 24, 15.5)
          ..cubicTo(19.3056, 15.5, 15.5, 19.3056, 15.5, 24)
          ..cubicTo(15.5, 28.6944, 19.3056, 32.5, 24, 32.5)
          ..close()),
    _GlyphStroke(
        width: 3.3,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(24, 5.5)
          ..lineTo(24, 10.1)
          ..moveTo(24, 37.9)
          ..lineTo(24, 42.5)
          ..moveTo(5.5, 24)
          ..lineTo(10.1, 24)
          ..moveTo(37.9, 24)
          ..lineTo(42.5, 24)
          ..moveTo(10.92, 10.92)
          ..lineTo(14.16, 14.16)
          ..moveTo(33.84, 33.84)
          ..lineTo(37.08, 37.08)
          ..moveTo(37.08, 10.92)
          ..lineTo(33.84, 14.16)
          ..moveTo(14.16, 33.84)
          ..lineTo(10.92, 37.08)),
  ]),
};

final Map<QuietIcon, _GlyphSpec> _iconSpecs = {
  // pin.svg (viewBox 18)
  QuietIcon.pin: _GlyphSpec(viewBox: 18, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(9, 15.75)
          ..cubicTo(9, 15.75, 13.5, 11.7, 13.5, 7.5)
          ..cubicTo(13.5, 6.30653, 13.0259, 5.16193, 12.182, 4.31802)
          ..cubicTo(11.3381, 3.47411, 10.1935, 3, 9, 3)
          ..cubicTo(7.80653, 3, 6.66193, 3.47411, 5.81802, 4.31802)
          ..cubicTo(4.97411, 5.16193, 4.5, 6.30653, 4.5, 7.5)
          ..cubicTo(4.5, 11.7, 9, 15.75, 9, 15.75)
          ..close()),
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(9, 9)
          ..cubicTo(9.82843, 9, 10.5, 8.32843, 10.5, 7.5)
          ..cubicTo(10.5, 6.67157, 9.82843, 6, 9, 6)
          ..cubicTo(8.17157, 6, 7.5, 6.67157, 7.5, 7.5)
          ..cubicTo(7.5, 8.32843, 8.17157, 9, 9, 9)
          ..close()),
  ]),
  // settings.svg (viewBox 22)
  QuietIcon.settings: _GlyphSpec(viewBox: 22, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(3.66667, 6.41667)
          ..lineTo(11, 6.41667)
          ..moveTo(14.6667, 6.41667)
          ..lineTo(18.3333, 6.41667)
          ..moveTo(3.66667, 15.5833)
          ..lineTo(7.33333, 15.5833)
          ..moveTo(11, 15.5833)
          ..lineTo(18.3333, 15.5833)),
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(12.8333, 8.25)
          ..cubicTo(13.8459, 8.25, 14.6667, 7.42919, 14.6667, 6.41667)
          ..cubicTo(14.6667, 5.40414, 13.8459, 4.58333, 12.8333, 4.58333)
          ..cubicTo(11.8208, 4.58333, 11, 5.40414, 11, 6.41667)
          ..cubicTo(11, 7.42919, 11.8208, 8.25, 12.8333, 8.25)
          ..close()),
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(9.16667, 17.4167)
          ..cubicTo(10.1792, 17.4167, 11, 16.5959, 11, 15.5833)
          ..cubicTo(11, 14.5708, 10.1792, 13.75, 9.16667, 13.75)
          ..cubicTo(8.15414, 13.75, 7.33333, 14.5708, 7.33333, 15.5833)
          ..cubicTo(7.33333, 16.5959, 8.15414, 17.4167, 9.16667, 17.4167)
          ..close()),
  ]),
  // humidity.svg (viewBox 18)
  QuietIcon.humidity: _GlyphSpec(viewBox: 18, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(9, 2.25)
          ..cubicTo(9, 2.25, 12.75, 6.15, 12.75, 9.75)
          ..cubicTo(12.75, 10.7446, 12.3549, 11.6984, 11.6517, 12.4017)
          ..cubicTo(10.9484, 13.1049, 9.99456, 13.5, 9, 13.5)
          ..cubicTo(8.00544, 13.5, 7.05161, 13.1049, 6.34835, 12.4017)
          ..cubicTo(5.64509, 11.6984, 5.25, 10.7446, 5.25, 9.75)
          ..cubicTo(5.25, 6.15, 9, 2.25, 9, 2.25)
          ..close()),
  ]),
  // wind.svg (viewBox 18)
  QuietIcon.wind: _GlyphSpec(viewBox: 18, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(3, 6)
          ..lineTo(10.5, 6)
          ..cubicTo(10.7967, 6, 11.0867, 5.91203, 11.3334, 5.7472)
          ..cubicTo(11.58, 5.58238, 11.7723, 5.34811, 11.8858, 5.07403)
          ..cubicTo(11.9994, 4.79994, 12.0291, 4.49834, 11.9712, 4.20736)
          ..cubicTo(11.9133, 3.91639, 11.7704, 3.64912, 11.5607, 3.43934)
          ..cubicTo(11.3509, 3.22956, 11.0836, 3.0867, 10.7926, 3.02882)
          ..cubicTo(10.5017, 2.97094, 10.2001, 3.00065, 9.92598, 3.11418)
          ..cubicTo(9.65189, 3.22771, 9.41762, 3.41997, 9.2528, 3.66664)
          ..cubicTo(9.08797, 3.91332, 9, 4.20333, 9, 4.5)
          ..moveTo(3, 9.75)
          ..lineTo(13.5, 9.75)
          ..cubicTo(13.7967, 9.75, 14.0867, 9.83797, 14.3334, 10.0028)
          ..cubicTo(14.58, 10.1676, 14.7723, 10.4019, 14.8858, 10.676)
          ..cubicTo(14.9994, 10.9501, 15.0291, 11.2517, 14.9712, 11.5426)
          ..cubicTo(14.9133, 11.8336, 14.7704, 12.1009, 14.5607, 12.3107)
          ..cubicTo(14.3509, 12.5204, 14.0836, 12.6633, 13.7926, 12.7212)
          ..cubicTo(13.5017, 12.7791, 13.2001, 12.7494, 12.926, 12.6358)
          ..cubicTo(12.6519, 12.5223, 12.4176, 12.33, 12.2528, 12.0834)
          ..cubicTo(12.088, 11.8367, 12, 11.5467, 12, 11.25)
          ..moveTo(3, 13.5)
          ..lineTo(8.25, 13.5)),
  ]),
  // uv.svg (viewBox 18)
  QuietIcon.uv: _GlyphSpec(viewBox: 18, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: false,
        build: () => Path()
          ..moveTo(9, 11.625)
          ..cubicTo(10.4497, 11.625, 11.625, 10.4497, 11.625, 9)
          ..cubicTo(11.625, 7.55025, 10.4497, 6.375, 9, 6.375)
          ..cubicTo(7.55025, 6.375, 6.375, 7.55025, 6.375, 9)
          ..cubicTo(6.375, 10.4497, 7.55025, 11.625, 9, 11.625)
          ..close()),
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(9, 2.25)
          ..lineTo(9, 3.75)
          ..moveTo(9, 14.25)
          ..lineTo(9, 15.75)
          ..moveTo(2.25, 9)
          ..lineTo(3.75, 9)
          ..moveTo(14.25, 9)
          ..lineTo(15.75, 9)
          ..moveTo(4.2, 4.2)
          ..lineTo(5.25, 5.25)
          ..moveTo(12.75, 12.75)
          ..lineTo(13.8, 13.8)
          ..moveTo(13.8, 4.2)
          ..lineTo(12.75, 5.25)
          ..moveTo(5.25, 12.75)
          ..lineTo(4.2, 13.8)),
  ]),
  // air.svg (viewBox 18)
  QuietIcon.air: _GlyphSpec(viewBox: 18, role: _Role.mid, strokes: [
    _GlyphStroke(
        width: 1.5,
        opacity: 1,
        fill: false,
        roundCap: true,
        build: () => Path()
          ..moveTo(3.75, 6.75)
          ..lineTo(12, 6.75)
          ..cubicTo(12.2967, 6.75, 12.5867, 6.66203, 12.8334, 6.4972)
          ..cubicTo(13.08, 6.33238, 13.2723, 6.09811, 13.3858, 5.82403)
          ..cubicTo(13.4994, 5.54994, 13.5291, 5.24834, 13.4712, 4.95736)
          ..cubicTo(13.4133, 4.66639, 13.2704, 4.39912, 13.0607, 4.18934)
          ..cubicTo(12.8509, 3.97956, 12.5836, 3.8367, 12.2926, 3.77882)
          ..cubicTo(12.0017, 3.72094, 11.7001, 3.75065, 11.426, 3.86418)
          ..cubicTo(11.1519, 3.97771, 10.9176, 4.16997, 10.7528, 4.41664)
          ..cubicTo(10.588, 4.66332, 10.5, 4.95333, 10.5, 5.25)
          ..moveTo(3.75, 10.5)
          ..lineTo(14.25, 10.5)
          ..moveTo(3.75, 14.25)
          ..lineTo(9.75, 14.25)
          ..cubicTo(10.0467, 14.25, 10.3367, 14.162, 10.5834, 13.9972)
          ..cubicTo(10.83, 13.8324, 11.0223, 13.5981, 11.1358, 13.324)
          ..cubicTo(11.2494, 13.0499, 11.2791, 12.7483, 11.2212, 12.4574)
          ..cubicTo(11.1633, 12.1664, 11.0204, 11.8991, 10.8107, 11.6893)
          ..cubicTo(10.6009, 11.4796, 10.3336, 11.3367, 10.0426, 11.2788)
          ..cubicTo(9.75166, 11.2209, 9.45006, 11.2506, 9.17598, 11.3642)
          ..cubicTo(8.90189, 11.4777, 8.66762, 11.67, 8.5028, 11.9166)
          ..cubicTo(8.33797, 12.1633, 8.25, 12.4533, 8.25, 12.75)),
  ]),
};
