// lib/presentation/settings/plus_settings_page.dart
//
// 設定 > Plus (Figma v1.3 `Settings — Plus Free` 6:154・Light 24:1225・
// JP 77:1172 実測)。加入者には状態 (ティア / 更新日 / 猶予) と管理・復元を、
// 未加入者にはアップグレード導線 (Paywall) と復元を出す。
//
// 構成 (Figma 6:154):
//   見出し    「More signal, less noise」(Fraunces) + リード文
//   パネル    「CURRENT PLAN」mono + プラン名 (Fraunces 42) + 本文
//   カード ×3 commerce/plus のドット + 特典名 + 説明
//   主 CTA    action/primary の塗りボタン (1 画面 1 つ)
//   副導線    action/tertiary のテキストボタン
//
// **色 (§2.3 / §2.4 / §6)**: この画面の色は `commerce/plus`(#8B7BD8) と無彩色のみ。
// 状態色 (state/*) は **0 個** — 課金 UI に体感の色を持ち込むと「色がついている =
// 体感か危険」の規則が壊れ、熱中症通知が Plus 限定と誤読される審査リスクになる。
//
// 緊急通知は課金に無関係 (spec §12.2.1) のため、本画面は制限を示唆しない。

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/entitlement.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/entitlement_provider.dart';
import '../paywall/paywall_page.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 特典カードの間隔 (Figma: 369 → 463 = 94 − 82)。
const double _kCardGap = 12;

class PlusSettingsPage extends ConsumerStatefulWidget {
  const PlusSettingsPage({super.key});

  @override
  ConsumerState<PlusSettingsPage> createState() => _PlusSettingsPageState();
}

class _PlusSettingsPageState extends ConsumerState<PlusSettingsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ent = ref.watch(entitlementProvider);
    final isPlus = ent.hasPlus;

    return QuietPage(
      title: t.settingsTitle,
      headline: t.paywallHeadline,
      intro: t.paywallSubtitle,
      children: [
        if (ent.isInGracePeriod) ...[
          _GraceBanner(message: t.plusGraceBanner),
          const SizedBox(height: _kCardGap),
        ],

        // === 現在のプラン ===
        _CurrentPlanPanel(
          label: t.plusCurrentPlanLabel,
          plan: isPlus ? _tierLabel(t, ent.tier) : t.plusTierFree,
          body: isPlus && ent.expiresAt != null
              ? _renewalLine(t, ent)
              : t.paywallSafetyDisclaimer,
        ),
        const SizedBox(height: 26),

        // === 特典 (ドットは commerce/plus。状態色は使わない) ===
        // v1.3.0 は多地点のみ (決裁 D7。先行アラート / ピンポイント補正は配信側未実装)。
        QuietDotCard(
          dotColor: MrwTokens.of(context).plusBase,
          title: t.plusFeatureMultiLocationTitle,
          body: t.plusFeatureMultiLocationBody,
        ),
        const SizedBox(height: 26),

        // === 主 CTA (1 画面 1 つ) + 副導線 ===
        QuietPrimaryButton(
          label: isPlus ? t.plusManageSubscription : t.plusUpgradeTitle,
          onPressed: _busy
              ? null
              : isPlus
                  ? _manage
                  : () => showPaywall(context),
        ),
        const SizedBox(height: 8),
        QuietTertiaryButton(
          label: t.paywallRestore,
          onPressed: _busy ? null : _restore,
        ),
      ],
    );
  }

  String _tierLabel(AppLocalizations t, EntitlementTier tier) => switch (tier) {
        EntitlementTier.pro => t.plusTierPro,
        EntitlementTier.plus => t.plusTierPlus,
        EntitlementTier.free => t.plusTierFree,
      };

  String _renewalLine(AppLocalizations t, EntitlementState ent) {
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).format(ent.expiresAt!.toLocal());
    return ent.willRenew ? t.plusRenewsOn(date) : t.plusExpiresOn(date);
  }

  Future<void> _manage() async {
    setState(() => _busy = true);
    final ok = await ref.read(billingGatewayProvider).openManageSubscriptions();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      final t = AppLocalizations.of(context);
      final ent = ref.read(entitlementProvider);
      final isGoogle = ent.store == 'play_store' ||
          (ent.store == null &&
              defaultTargetPlatform == TargetPlatform.android);
      _showSnack(isGoogle ? t.plusManageHintGoogle : t.plusManageHintApple);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await ref.read(billingGatewayProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    final t = AppLocalizations.of(context);
    final restored = result.isSuccess && (result.entitlement?.hasPlus ?? false);
    if (restored) {
      await ref.read(entitlementProvider.notifier).refresh();
      if (!mounted) return;
      _showSnack(t.paywallRestoreSuccess);
    } else {
      _showSnack(t.paywallRestoreNone);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 現在のプラン (Figma 6:163)。
class _CurrentPlanPanel extends StatelessWidget {
  const _CurrentPlanPanel({
    required this.label,
    required this.plan,
    required this.body,
  });

  final String label;
  final String plan;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final meta = MrwType.of(context).meta;
    return QuietPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuietLabel(label, small: true, color: tokens.textMono),
          const SizedBox(height: 8),
          QuietDisplayNumber(plan, size: 36),
          const SizedBox(height: 10),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: meta.fontSize(11),
                  height: meta.height(15 / 11, paragraph: true),
                  color: tokens.textMid,
                ),
          ),
        ],
      ),
    );
  }
}

/// 支払い不備の警告 (破壊的な色はテキストのみ。塗りは無彩色)。
class _GraceBanner extends StatelessWidget {
  const _GraceBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: caption.fontSize(12),
              height: caption.height(17 / 12, paragraph: true),
              color: tokens.actionDestructiveLabel,
            ),
      ),
    );
  }
}
