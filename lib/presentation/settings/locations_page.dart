// lib/presentation/settings/locations_page.dart
//
// 設定 > 地点管理 (spec.md §4.4 / Figma v1.3 `Settings — Locations` 6:2・
// Light 24:1073・JP 77:1020、多地点 A1〜A5 = docs/codex-figma_locations-add-place.md
// 実測)。
//   - 現在地 (COARSE のみ。spec §13) の表示と再取得
//   - 保存地点 (追加順) の一覧・削除 (元に戻す付き)・「地点を追加」(ボトムシート)
//       削除は対象の地点 ID で行い、処理中と直後 0.5 秒は画面のどの削除も受け付けない
//       (QA-02: 1 件消すと次の行が繰り上がり、連打の 2 回目が別の地点に当たっていた)。
//       「元に戻す」は戻す時点の上限で判定し直し、戻せなければ理由を出す (QA-07)
//   - 上限: 保存地点は Plus 限定 (無料 0 / Plus 5。2026-09-30 ユーザー決裁)。
//     件数は見出しの右に「n / 上限」(Plus)、無料で残っている地点は「保存 n 件」
//       A1 無料 0 件   : 件数・空状態・追加ボタンを出さず、Plus カード (多地点モニタ:
//                        無料版は現在地のみ・Plus なら最大 5 地点 / Plus を見る) だけ
//       A3 Plus 4 / 5  : 追加ボタン (Plus 0 件は空状態 + 追加ボタン)
//       A4 Plus 5 / 5  : 追加ボタンを無効化 (塗りはそのまま) + 理由
//       A5 無料で地点が残っている (Plus 解約後、または無料 1 件の時期 (〜1.3.0 (11))
//          に保存した地点。1 件でも): 件数は「保存 n 件」+ Plus カード (Plus を見る)。
//          地点は消さない。表示・削除はできる、追加はできない
//     (旧 A2「無料 1 / 1」は無くなった。無料で 1 件ある状態は A5 と同じ扱い)
//     Figma の A1 / A2 は旧仕様 (無料 1 件) のまま。更新は CODEX で後日。
//   - 課金導線は commerce/plus 色のみ。状態色は使わない
//
// 構成 (Figma):
//   パネル    「CURRENT」mono + 都市名 Fraunces 28 + 再取得ボタン (action/secondary)
//   セクション「保存済み地点」Inter SemiBold 15 + 件数 (mono 10、右端)
//   行        名前 Inter 13 + **MRI 値 (mono 10・帯色)** + 削除 (textMono)
//   PLUS カード「PLUS」mono (commerce/plus/base) + 見出し + 本文 (+ Plus を見る)
//
// MRI は保存地点の**現在値** (saved_place_weather_provider.dart。θ 込み。一覧を開くと
// 取得し、10 分ほど使い回す)。取得中・失敗は無彩色の「MRI —」。
//
// **状態色 (§4.1)**: 保存地点の行の「MRI nn」テキストだけが帯色を持つ (規則 1 の
// ③ MRI 数値)。規則 2 の上限 6 を超える件数 (grandfathering で 5 件超もあり得る)
// では、数値を主文字色に戻し、行頭の帯ドットだけに縮小する。
//
// Figma にあって実装しない (理由):
//   - 行右端の chevron (6:21 ほか): 遷移先が無い行なので誤誘導になる。削除操作を置く。
//   - 現在地カードの mono メタ「approximate · updated 2 min ago」: 取得時刻を保持
//     していない。位置が既定値のときだけ locationsFallbackNotice を出す。
//   - 見出し・戻るの文言は他の設定サブ画面と同じ (「‹ 設定」+ 画面名) に揃えている。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/saved_place.dart';
import '../../domain/places/saved_place_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/saved_place_weather_provider.dart';
import '../../providers/saved_places_provider.dart';
import '../../providers/weather_provider.dart';
import '../paywall/paywall_page.dart';
import '../places/place_actions.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../shared/quiet_snackbar.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 行の間隔 (Figma: 383 → 445 = 62 − 52)。
const double _kRowGap = 10;

/// §4.1 規則 2 の上限。これを超えたら数値の着色をやめ、帯ドットだけにする。
const int _kMaxStateColoredRows = 6;

/// 「地点を追加」ボタンのキー (テスト用)。
const Key kLocationsAddKey = ValueKey('locations-add');

/// 削除した直後、画面のどの削除も受け付けない時間 (QA-02)。1 件消すと次の行が
/// 繰り上がり、連打の 2 回目が同じ位置 = 次の地点の削除アイコンに当たるため。
/// ダブルタップとみなされる間隔 (Android 300ms・iOS 約 350ms) より長くとる。
const Duration kLocationsDeleteCooldown = Duration(milliseconds: 500);

class LocationsPage extends ConsumerStatefulWidget {
  const LocationsPage({super.key});

  @override
  ConsumerState<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends ConsumerState<LocationsPage> {
  /// 削除の処理中、または直後の [kLocationsDeleteCooldown] の間 (削除を受け付けない)。
  /// 表示は変えない (0.5 秒のために削除アイコンを薄くすると明滅して見える)。
  bool _deleteLocked = false;
  Timer? _deleteUnlock;

  @override
  void dispose() {
    _deleteUnlock?.cancel();
    super.dispose();
  }

  /// [place] を削除し、「元に戻す」付きのスナックバーを出す。削除は行の位置ではなく
  /// 対象の地点 ID で行う。処理中の再入・連打は受け付けない (QA-02)。
  Future<void> _remove(SavedPlace place) async {
    if (_deleteLocked) return;
    _deleteLocked = true;
    _deleteUnlock?.cancel();
    final t = AppLocalizations.of(context);
    final controller = ref.read(savedPlacesControllerProvider);
    // 「元に戻す」はこの画面を閉じた後 (スナックバーは前の画面に残る) でも押せる。
    // 戻せなかった理由は、閉じても残るアプリの Navigator の context で出す。
    final appContext = Navigator.of(context).context;
    try {
      final removal = await controller.remove(place.id);
      if (removal == null || !mounted) return;
      showQuietSnackBar(
        context,
        message: t.placeRemoved(place.name),
        actionLabel: t.placeUndo,
        onAction: () => _undoRemove(appContext, controller, removal, place),
      );
    } finally {
      if (mounted) {
        _deleteUnlock =
            Timer(kLocationsDeleteCooldown, () => _deleteLocked = false);
      }
    }
  }

  /// 削除の「元に戻す」。戻す時点の課金状態と件数で上限を判定し直し (QA-07)、
  /// 戻せなければ理由を出す。理由は Plus なら「保存地点は 5 件まで」、無料なら
  /// 「増やすには Plus が必要」(無料の上限 0 件を「0 件まで」とは出さない)。
  static Future<void> _undoRemove(
    BuildContext appContext,
    SavedPlacesController controller,
    SavedPlaceRemoval removal,
    SavedPlace place,
  ) async {
    final check = await controller.restore(removal);
    if (check != SavedPlaceRestoreCheck.limitReached || !appContext.mounted) {
      return;
    }
    final t = AppLocalizations.of(appContext);
    final quota = controller.quota;
    showQuietSnackBar(
      appContext,
      message: quota.isPlus
          ? t.placeRestoreLimitReached(place.name, quota.limit)
          : t.placeRestoreNeedsPlus(place.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final places = ref.watch(savedPlacesProvider);
    final quota = ref.watch(savedPlaceQuotaProvider);
    // 上限 6 を超えるときは「行頭の帯ドットのみ」に縮小する (§4.1 規則 2)。
    final useDots = places.length > _kMaxStateColoredRows;
    final count = _countLabel(t, quota);

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsLocations,
      intro: t.locationsCoarseNote,
      children: [
        const _CurrentLocationPanel(),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: QuietSectionTitle(t.locationsSavedSection)),
            if (count != null) ...[
              const SizedBox(width: 12),
              Text(
                count,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: tag.fontSize(10),
                      letterSpacing: 0,
                      fontWeight: FontWeight.w400,
                      height: tag.height(13 / 10),
                      color: tokens.textMono,
                    ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // 空状態 (Plus 0 件)。「地名で追加するか、Comfort-Twin から保存」と誘う
        // 文言なので、追加できない無料 (A1) では出さない (Plus カードで伝える)。
        if (places.isEmpty && quota.canAddNew)
          QuietBodyCard(text: t.locationsEmpty),
        for (var i = 0; i < places.length; i++) ...[
          if (i > 0) const SizedBox(height: _kRowGap),
          _SavedPlaceRow(
            key: ValueKey(places[i].id),
            place: places[i],
            useDot: useDots,
            onDelete: () => _remove(places[i]),
          ),
        ],
        ..._addSection(context, t, tokens, quota, places.isEmpty),
      ],
    );
  }

  /// 見出しの右の件数。Plus は「n / 5」、無料で地点が残っているときは
  /// 「保存 n 件」(上限を出さない)、無料で 0 件なら出さない (保存地点は Plus の
  /// 機能なので「0 / 0」にしない。A1)。
  static String? _countLabel(AppLocalizations t, SavedPlaceQuota quota) {
    if (quota.isOverLimit) return t.locationsCountOver(quota.count);
    if (quota.limit <= 0) return null;
    return t.locationsCount(quota.count, quota.limit);
  }

  /// 追加ボタン (または無効化 + 理由) と、無料版の Plus カード。
  List<Widget> _addSection(
    BuildContext context,
    AppLocalizations t,
    MrwTokens tokens,
    SavedPlaceQuota quota,
    bool empty,
  ) {
    final caption = MrwType.of(context).caption;
    final seePlus = QuietInlineTextButton(
      label: t.locationsSeePlus,
      onPressed: () => showPaywall(context),
    );
    return [
      if (quota.canAddNew) ...[
        const SizedBox(height: 14),
        QuietSecondaryButton(
          key: kLocationsAddKey,
          label: t.locationsAddPlace,
          onPressed: () =>
              openAddPlace(context, ref, origin: AddPlaceOrigin.locations),
        ),
      ] else if (quota.isPlus) ...[
        // A4: Plus の上限。塗りはそのまま、ラベルを textLo にして理由を添える。
        const SizedBox(height: 14),
        QuietSecondaryButton(
          key: kLocationsAddKey,
          label: t.locationsAddPlace,
          onPressed: null,
          keepFillWhenDisabled: true,
        ),
        const SizedBox(height: 8),
        Text(
          t.locationsPlusFullNote(quota.limit),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: caption.fontSize(12),
                height: caption.height(17 / 12, paragraph: true),
                color: tokens.textMid,
              ),
        ),
      ],
      // 無料: 保存地点は Plus の機能だと Plus カードで伝え、Paywall へ誘う。
      // 行も空状態も無い A1 は見出しの直下 (見出しとの間は上の 10)。
      if (!quota.isPlus) ...[
        if (!empty || quota.canAddNew)
          SizedBox(height: quota.canAddNew ? 26 : 14),
        QuietPlusCard(
          label: t.plusBadge,
          title: t.plusFeatureMultiLocationTitle,
          body: empty
              // A1: 無料・0 件。「無料版は現在地のみ。Plusなら最大5地点を追加
              // できます。緊急アラートは無料のままです。」
              ? t.locationsAddLockedNote
              // A5: Plus 解約後・無料 1 件の時期に保存した地点が残っている
              // (1 件でも。消さない)。
              : t.locationsOverLimitBody(quota.count),
          action: seePlus,
        ),
      ],
    ];
  }
}

/// 現在地 (COARSE) のパネル (Figma 6:11)。
class _CurrentLocationPanel extends ConsumerWidget {
  const _CurrentLocationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final location = ref.watch(currentLocationProvider);
    final cityName = ref.watch(cityNameProvider).valueOrNull;
    final isFallback = location.valueOrNull?.isFallback ?? false;

    return QuietPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QuietLabel(
                  t.locationsCurrentSection,
                  small: true,
                  color: tokens.textMono,
                ),
                const SizedBox(height: 10),
                QuietDisplayNumber(cityName ?? t.currentLocation, size: 28),
                if (isFallback) ...[
                  const SizedBox(height: 8),
                  QuietNote(t.locationsFallbackNotice),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (location.isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            // Figma 6:15: 36×46 角丸 23 の action/secondary ボタン。
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: t.locationsRefresh,
              // 依存する天気 / 都市名 provider は連鎖的に再取得される。
              onPressed: () => ref.invalidate(currentLocationProvider),
              style: IconButton.styleFrom(
                backgroundColor: tokens.actionSecondaryFill,
                foregroundColor: tokens.actionSecondaryLabel,
                fixedSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: tokens.border),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 保存地点の 1 行 (Figma 6:18 / A3)。MRI 値 (現在値) だけが帯色を持つ。
class _SavedPlaceRow extends ConsumerWidget {
  const _SavedPlaceRow({
    super.key,
    required this.place,
    required this.useDot,
    required this.onDelete,
  });

  final SavedPlace place;

  /// true なら数値を無彩色にし、行頭に帯ドットを出す (§4.1 規則 2)。
  final bool useDot;

  /// 削除アイコン。削除・連打の抑止・元に戻すは画面 (_LocationsPageState) が持つ。
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    // 現在値 (取得中・失敗は「MRI —」を無彩色で。Figma: 取得中は MRI — / 状態色なし)。
    final mri = ref.watch(savedPlaceMriProvider(place.id)).valueOrNull?.value;
    final band = mri == null ? tokens.textLo : tokens.stateColorForMri(mri);

    return QuietListRow(
      title: place.name,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useDot && mri != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: band, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${t.mriAbbrev} ${mri ?? '—'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: tag.fontSize(10),
                  letterSpacing: 0,
                  fontWeight: FontWeight.w400,
                  height: tag.height(13 / 10),
                  color: useDot && mri != null ? tokens.textHi : band,
                ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: tokens.textMono,
            visualDensity: VisualDensity.compact,
            tooltip: t.locationsDeleteTooltip,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
