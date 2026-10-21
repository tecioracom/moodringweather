// lib/presentation/shared/quiet_snackbar.dart
//
// v1.3 のトースト / スナックバー (Figma: 地点タブ E7 `506:1184`、追加後′ `523:1691`、
// 地点管理 A3 のトースト実測)。
//   地 = 浮いた面 surfaceHigh / 角丸 14 / 1px 枠 (9%) / 高さ 48。本文 Regular 13
//   主文字色 (左 20)、右端に tertiary の操作 (「管理」「元に戻す」。文字は他の
//   tertiary ボタンと同じ Inter SemiBold 13 / JA Bold 13、文字の右端 x=346)。塗りのボタンは
//   置かない。
// 下部ナビのある画面では Scaffold が自動でナビの上に浮かせる (floating)。
//
// 操作は SnackBar.action ではなく本文の行に置く。
//   - SnackBarAction の文字はテーマの labelLarge (mono) になり、Figma と合わない。
//   - Flutter 3.44 の SnackBar は action があると既定で閉じない (persist)。
//     「元に戻す」「管理」は時間 ([duration]) で閉じる。ただしスクリーンリーダー
//     使用中は残し、操作する時間を確保する (閉じるのは操作・下スワイプ・読み上げの
//     「閉じる」)。

import 'package:flutter/material.dart';

import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'quiet_controls.dart';

/// [context] の Scaffold に v1.3 書式のスナックバーを出す (前のものは閉じる)。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showQuietSnackBar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  final tokens = MrwTokens.of(context);
  final body = MrwType.of(context).body;
  final text = Theme.of(context).textTheme;
  final hasAction = actionLabel != null;
  final persist = hasAction && MediaQuery.accessibleNavigationOf(context);

  var triggered = false;
  void handleAction() {
    if (triggered) return; // 連打で 2 回実行しない。
    triggered = true;
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
    onAction?.call();
  }

  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.surfaceHigh,
      elevation: 0,
      duration: duration,
      persist: persist,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: EdgeInsets.fromLTRB(20, 0, hasAction ? 8 : 20, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.border),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    fontSize: body.fontSize(13),
                    height: body.height(17 / 13),
                    color: tokens.textHi,
                  ),
                ),
              ),
            ),
            if (hasAction) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: handleAction,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.actionTertiaryLabel,
                  textStyle: quietButtonTextStyle(context),
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
