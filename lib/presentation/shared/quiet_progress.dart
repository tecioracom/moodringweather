// lib/presentation/shared/quiet_progress.dart
//
// 不確定型の細い進捗トラック (Figma: 地点タブ E6a の「取得中…」`491:326〜`、
// 地点を追加 B2「検索中…」実測)。
//   トラック 2px = 浮いた面 surfaceHigh、区間 100px = 副文字色 (無彩色)。
// 区間は左右に往復する。アニメーション無効 (アクセシビリティ設定) では
// Figma と同じ「先頭 100px」の静止表示にする。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';

class QuietIndeterminateTrack extends StatefulWidget {
  const QuietIndeterminateTrack({super.key, this.segmentWidth = 100});

  /// 動く区間の幅 (Figma: 100)。
  final double segmentWidth;

  @override
  State<QuietIndeterminateTrack> createState() =>
      _QuietIndeterminateTrackState();
}

class _QuietIndeterminateTrackState extends State<QuietIndeterminateTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return Semantics(
      // 進捗の値を持たない (読み上げは周りの文言に任せる)。
      excludeSemantics: true,
      child: SizedBox(
        height: 2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final segment = widget.segmentWidth.clamp(0.0, width);
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_controller.value);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surfaceHigh,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (width - segment) * t,
                      top: 0,
                      bottom: 0,
                      width: segment,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.textMid,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
