// lib/presentation/comfort_twin/twin_world_map.dart
//
// スタイライズした世界マップ (v1.0 デザインのドット表現)。
// 地図 SDK は使わず CustomPaint のみで描く:
//   - 背景: ドット格子の大陸ランドマスク (等経緯度=equirectangular 投影)
//   - 前景: 候補都市のドット (類似度上位ほど大きく + 1 位はハロー)
//
// **色 (codex-fixes_v1.3_unified.md §4.2 C3)**: 地図は線もドットも
// **すべてニュートラル**。MRI の帯色は結果リストの行 (数値) が担う。
// v1.2 までは都市ドットを HslGradient で着色していたが、地図は「値そのもの」を
// 表す要素ではないため §4.1 規則 1 に反していた。

import 'package:flutter/material.dart';

import '../../domain/comfort_twin/twin_matcher.dart';
import '../theme/mrw_tokens.dart';

class TwinWorldMap extends StatelessWidget {
  const TwinWorldMap({super.key, required this.matches});

  final List<TwinMatch> matches;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return AspectRatio(
      aspectRatio: 2.1,
      child: CustomPaint(
        painter: _TwinWorldMapPainter(
          matches: matches,
          landColor: tokens.textHi.withValues(alpha: 0.14),
          cityColor: tokens.inkMid,
          haloColor: tokens.textHi.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _TwinWorldMapPainter extends CustomPainter {
  _TwinWorldMapPainter({
    required this.matches,
    required this.landColor,
    required this.cityColor,
    required this.haloColor,
  });

  final List<TwinMatch> matches;
  final Color landColor;
  final Color cityColor;
  final Color haloColor;

  /// 60×24 の簡易ランドマスク ('#'=陸)。等経緯度投影:
  /// 列 c → 経度 −180+6c、行 r → 緯度 84−6r (上端 87°N / 下端 57°S)。
  static const List<String> _landMask = [
    '....................#######.................................',
    '...........########.#######.....####........................',
    '........###########.######.......###########################',
    '..##################......#...##############################',
    '..###################.........#############################.',
    '........#############........##############################.',
    '.........############........##########################.....',
    '.........##########.........##########################......',
    '..........########...........#########################......',
    '..........#######...........#######################.........',
    '...........###.............########################.........',
    '............####...........############...###.###.#.........',
    '..............###..........############...##..#####.........',
    '.................#####......###########......#######........',
    '................######.........#######........########......',
    '................#########.......#####..........#########....',
    '.................#######........#####.............#####.....',
    '..................######........#######..........#######....',
    '..................#####.........####............########....',
    '..................####..........####.............#######....',
    '.................####...............................####....',
    '.................###..................................#...#.',
    '.................###.....................................##.',
    '.................##.........................................',
  ];

  /// マスク上端の緯度 / 全行で覆う緯度幅 (24 行 × 6°)。
  static const double _topLat = 87.0;
  static const double _latSpan = 144.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = _landMask.length;
    final cols = _landMask.first.length;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final dotR = (cellW < cellH ? cellW : cellH) * 0.26;

    // === 大陸ドット ===
    final landPaint = Paint()..color = landColor;
    for (var r = 0; r < rows; r++) {
      final row = _landMask[r];
      for (var c = 0; c < cols; c++) {
        if (row.codeUnitAt(c) != 0x23 /* '#' */) continue;
        canvas.drawCircle(
          Offset((c + 0.5) * cellW, (r + 0.5) * cellH),
          dotR,
          landPaint,
        );
      }
    }

    // === 都市ドット (類似度下位から描き、上位を前面に) ===
    for (final m in matches.reversed) {
      final x = (m.city.longitude + 180.0) / 360.0 * size.width;
      final y = ((_topLat - m.city.latitude) / _latSpan * size.height)
          .clamp(0.0, size.height);
      final radius = m.rank == 1
          ? dotR * 3.2
          : m.rank <= 3
              ? dotR * 2.4
              : dotR * 1.6;

      if (m.rank == 1) {
        canvas.drawCircle(
          Offset(x, y),
          radius + dotR,
          Paint()
            ..color = haloColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = cityColor);
    }
  }

  @override
  bool shouldRepaint(_TwinWorldMapPainter oldDelegate) =>
      oldDelegate.matches != matches ||
      oldDelegate.landColor != landColor ||
      oldDelegate.cityColor != cityColor ||
      oldDelegate.haloColor != haloColor;
}
