// lib/presentation/shared/glass_card.dart
//
// 汎用カード (Figma v1.3「Quiet Instrument」。Sparkline Card 3:73 / Tile 3:91 /
// Settings 行 3:404 を実測): 面 = MrwTokens.surface (Dark onyx-700 / Light white)、
// 1px 枠 = MrwTokens.border (9%)、角丸 20 (カード) / 16 (タイル・行)。
// v1.2 までのグラスモーフィズム (BackdropFilter blur 24 + 半透明白) は段階 S3 で廃止。
// Home の天気カード / リングパネル / メトリクスタイル / 設定の行で共用する。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';

class QuietCard extends StatelessWidget {
  const QuietCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.blur = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// 旧グラスカードの blur 量。S3 で blur は廃止したため描画には使わない
  /// (呼び出し側の互換のために残す。S4 / S5 で引数ごと削除する)。
  final double blur;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: tokens.surface,
          border: Border.all(width: 1, color: tokens.border),
        ),
        // ListTile / InkWell をカード内に置けるよう透明 Material を挟む
        // (装飾付き Container 直下の ink 描画は Flutter のガードに当たる)。
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 旧名 (グラスモーフィズム時代)。呼び出し側は S4 / S5 で順次 QuietCard へ置換する。
typedef GlassCard = QuietCard;
