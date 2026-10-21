// lib/presentation/places/place_actions.dart
//
// 「地点を追加」の導線 (ホームの「+」/ 地点管理の「地点を追加」で共通)。
//
//   1. 上限を先に確かめる (savedPlaceQuotaProvider):
//        追加できる (Plus で 5 件未満) → ボトムシート /
//        無料 → paywall (保存地点は Plus 限定 = 無料 0 件。保存 0 件の
//          「＋ 地点を追加（実家・旅行先など）」も、持ち越した地点がある「+」も) /
//        Plus で上限 → スナックバー「保存地点は 5 件までです。」(ホームは「管理」付き)
//   2. シートの候補タップで即追加 (上限はそこで再判定 = SavedPlacesController)
//   3. 結果: 追加 → ホームならそのタブを選択 + スナックバー「{地名}を追加しました。
//      [元に戻す]」/ 保存済みを選んだ → ホームならそのタブへ /
//      再判定で無料だった (シートを開いている間に解約) → paywall /
//      再判定で Plus の上限 → 理由のスナックバー

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/place_selection_provider.dart';
import '../../providers/saved_places_provider.dart';
import '../paywall/paywall_page.dart';
import '../shared/quiet_snackbar.dart';
import 'add_place_sheet.dart';

/// どこから開いたか (ホームなら追加した地点のタブを選ぶ)。
enum AddPlaceOrigin { home, locations }

/// 「地点を追加」を押したとき。[onManage] はホームの「管理」(地点管理を開く)。
Future<void> openAddPlace(
  BuildContext context,
  WidgetRef ref, {
  required AddPlaceOrigin origin,
  double? sheetTop,
  VoidCallback? onManage,
}) async {
  final quota = ref.read(savedPlaceQuotaProvider);
  if (!quota.canAddNew) {
    if (quota.isPlus) {
      showPlaceLimitSnackBar(context, quota.limit, onManage: onManage);
    } else {
      // 無料は保存地点を追加できない (Plus 限定)。シートは開かない。
      await showPaywall(context);
    }
    return;
  }

  final outcome = await showAddPlaceSheet(context, top: sheetTop);
  if (outcome == null || !context.mounted) return;

  final t = AppLocalizations.of(context);
  final selection = ref.read(selectedPlaceIdProvider.notifier);
  final places = ref.read(savedPlacesControllerProvider);
  switch (outcome) {
    case AddPlaceAdded(:final result, :final name):
      if (origin == AddPlaceOrigin.home) selection.select(result.placeId);
      showQuietSnackBar(
        context,
        message: t.placeAdded(name),
        actionLabel: t.placeUndo,
        onAction: () => places.undo(result),
      );
    case AddPlaceShowExisting(:final placeId):
      if (origin == AddPlaceOrigin.home) selection.select(placeId);
    case AddPlaceNeedsPlus():
      await showPaywall(context);
    case AddPlaceLimitReached():
      showPlaceLimitSnackBar(
        context,
        ref.read(savedPlaceQuotaProvider).limit,
        onManage: onManage,
      );
  }
}

/// Plus の上限のスナックバー (Figma E7: 「保存地点は 5 件までです。」+「管理」)。
void showPlaceLimitSnackBar(
  BuildContext context,
  int limit, {
  VoidCallback? onManage,
}) {
  final t = AppLocalizations.of(context);
  showQuietSnackBar(
    context,
    message: t.placeLimitReached(limit),
    actionLabel: onManage == null ? null : t.placeManage,
    onAction: onManage,
  );
}
