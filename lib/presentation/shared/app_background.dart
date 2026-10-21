// lib/presentation/shared/app_background.dart
//
// 画面全体の地 (Figma v1.3「Quiet Instrument」。Home 3:2 / 24:6、Hot Coral 3:121 / 77:195、
// Settings 3:356 を実測)。
//   - 地: MrwTokens.bg (Dark onyx-900 #0D0E11 / Light #F5F7FA)
//   - State wash: 上部 230px の縦グラデ (9% → 0)。**名前に反して中立色**
//     (Dark onyx-700 / Light pearl-surface) で、Comfortable / Hot Coral の全フレームで
//     同じ値。状態色ではないので指示書 §4.1 (状態色は MRI 値を表す要素にのみ) の算定対象外
//     (docs/v1.3-design-implementation-plan.md §5.3)。
//   - grain: 1px の点 36 個 (主文字色 2%)。Figma 3:2 の座標を 390×844 基準の比率で保持。
// v1.2 までのオーロラ (斜めグラデ + 4 blob) は段階 S3 で廃止。BackdropFilter は使わない。
//
// AppBar を持つサブ画面は [QuietScaffold] でラップすると地が AppBar 裏まで通る。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';

/// AppBar 付き画面用の共通スキャフォールド。地 (AppBackground) を画面全体に通し、
/// Scaffold と AppBar を透過させる。各画面は body (と必要なら actions) を渡すだけでよい。
///
/// MainShell のタブ本体 (詳細 / 設定) はトップレベルなので
/// [automaticallyImplyLeading] を false にして戻る矢印を出さない。
/// push されるサブ画面は既定 (true) のままで戻る矢印が付く。
class QuietScaffold extends StatelessWidget {
  const QuietScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// false でタブ本体用に戻る矢印 (leading) を抑止する。
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: automaticallyImplyLeading,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: actions,
        ),
        body: body,
      ),
    );
  }
}

/// 旧名 (v1.0〜v1.2 のオーロラ背景時代)。呼び出し側は S4 / S5 で順次 QuietScaffold へ置換する。
typedef AuroraScaffold = QuietScaffold;

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return ColoredBox(
      color: tokens.bg,
      child: CustomPaint(
        painter: _QuietWashPainter(
          wash: tokens.wash,
          grain: tokens.textHi.withValues(alpha: 0.02),
        ),
        child: child,
      ),
    );
  }
}

class _QuietWashPainter extends CustomPainter {
  const _QuietWashPainter({required this.wash, required this.grain});

  final Color wash;
  final Color grain;

  /// Figma 3:3「State wash」の高さ。
  static const double _washHeight = 230;

  /// Figma 3:2 の grain 36 点 (x/390, y/844)。
  static const List<Offset> _grainPoints = [
    Offset(340.47 / 390, 487.06 / 844),
    Offset(74.12 / 390, 350.4 / 844),
    Offset(46.38 / 390, 118.39 / 844),
    Offset(341.44 / 390, 619.94 / 844),
    Offset(127 / 390, 505.3 / 844),
    Offset(309.73 / 390, 303.71 / 844),
    Offset(115.59 / 390, 604.54 / 844),
    Offset(302.56 / 390, 335.21 / 844),
    Offset(128.36 / 390, 59.31 / 844),
    Offset(311.55 / 390, 420.24 / 844),
    Offset(188.15 / 390, 573.1 / 844),
    Offset(381.12 / 390, 595.2 / 844),
    Offset(104.53 / 390, 111.91 / 844),
    Offset(65.3 / 390, 764.3 / 844),
    Offset(27.33 / 390, 102.55 / 844),
    Offset(347.61 / 390, 272.63 / 844),
    Offset(105.5 / 390, 310.7 / 844),
    Offset(99.71 / 390, 419.4 / 844),
    Offset(6.37 / 390, 436.55 / 844),
    Offset(206.18 / 390, 426.98 / 844),
    Offset(224.52 / 390, 712.37 / 844),
    Offset(304.29 / 390, 244.12 / 844),
    Offset(113.87 / 390, 803.02 / 844),
    Offset(281.72 / 390, 655.17 / 844),
    Offset(18.27 / 390, 782.98 / 844),
    Offset(375.12 / 390, 116.11 / 844),
    Offset(203.77 / 390, 250.73 / 844),
    Offset(285.93 / 390, 487.9 / 844),
    Offset(265.48 / 390, 391.51 / 844),
    Offset(281.83 / 390, 138.08 / 844),
    Offset(247.57 / 390, 208.56 / 844),
    Offset(10.17 / 390, 396.47 / 844),
    Offset(274.47 / 390, 144.47 / 844),
    Offset(0 / 390, 130.1 / 844),
    Offset(278.81 / 390, 25.88 / 844),
    Offset(345.64 / 390, 724.01 / 844),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final washRect = Rect.fromLTWH(0, 0, size.width, _washHeight);
    canvas.drawRect(
      washRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wash, wash.withValues(alpha: 0)],
        ).createShader(washRect),
    );
    final grainPaint = Paint()..color = grain;
    for (final p in _grainPoints) {
      canvas.drawRect(
        Rect.fromLTWH(p.dx * size.width, p.dy * size.height, 1, 1),
        grainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_QuietWashPainter oldDelegate) =>
      oldDelegate.wash != wash || oldDelegate.grain != grain;
}
