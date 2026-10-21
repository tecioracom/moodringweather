// lib/presentation/paywall/paywall_page.dart
//
// Plus の Paywall (docs/pricing-decision.md §4 / spec.md §12.11.7)。
//
// コンプラ要点 (App Store 1.4.1 / 3.1.2、docs/release-plan-billing.md §5 Step 8):
//   - 固定免責文 (paywallSafetyDisclaimer) を**常時表示**、ヘッドライン直下 = 特典リストの外。
//     「無料の緊急通知はそのまま全員に届く」を必ず明示し、安全を煽らない。
//   - 自動更新の開示 (paywallAutoRenewNotice) を CTA 直上に**常時表示** (トライアル有無を問わない)。
//   - 利用規約 / プライバシーポリシーへの実リンク。独自規約が未公開の間の Apple 標準 EULA
//     フォールバックは iOS 限定 (Android で apple.com を開かない)。
//   - 価格は SDK 整形済みの現地価格 (priceString) をそのまま表示。既定選択は月額。
//   - 色は commerce/plus (紫) と無彩のみ。状態色・Heat Alert 色・状態ランプを置かない (v1.3 S7)。
//
// 鍵未設定 / Offering 無しのときは「準備中」表示にフォールバックする。
//
// 縦の詰め (designer 2026-09-29、案2 採用時): スクロールで CTA に届く構成のまま、
// 上端 8 / 副題→特典 12 / 特典カードの内側 上下 12 / 特典→「プランを選ぶ」16 /
// プランカードの内側 上下 12 / プラン→トライアル注記 12 (注記なしは開示文まで 16)。
// 免責文と自動更新の開示は位置・文字サイズとも変えない (compliance)。「購入を復元」
// と規約リンク行は最下部のまま。CTA は Quiet の主ボタン (本文書体 15/20・高さ 46)。
// プラン行: プラン名 + BEST VALUE は Wrap (並ばない幅ではバッジが下の行へ)。
// プラン名は省略しない。価格は縮めず右端に固定 (qa 検収 Sev2、2026-09-29)。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_links.dart';
import '../../core/utils/external_url.dart';
import '../../data/billing/billing_models.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/entitlement_provider.dart';
import '../shared/app_background.dart';
import '../shared/glass_card.dart';
import '../shared/quiet_controls.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 独自規約が未公開の間のフォールバック (Apple 標準 EULA)。
const String _kAppleStandardEula =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

const double _kEdgePadding = 24;

/// Paywall をモーダルで開く。Plus 導線はすべてここを通す。
Future<void> showPaywall(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const PaywallPage(),
    ),
  );
}

class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key});

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  late Future<List<PlusPackage>> _packagesFuture;
  String? _selectedPackageId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _packagesFuture = ref.read(billingGatewayProvider).fetchPackages();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // 直書きの TextStyle も型スケール経由 (見出しはテーマの headlineSmall = display 固定)。
    final body = MrwType.of(context).body;
    return AuroraScaffold(
      title: t.plusBrandName,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                _kEdgePadding,
                8,
                _kEdgePadding,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              children: [
                Text(t.paywallHeadline,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                // 免責文は特典リストより前 (Plus 特典の外にあることが compliance 条件)。
                _safetyDisclaimer(t),
                const SizedBox(height: 12),
                Text(
                  t.paywallSubtitle,
                  style: TextStyle(
                    fontSize: body.fontSize(13),
                    height: body.height(null, paragraph: true),
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                // v1.3.0 の Plus 特典は多地点のみ (決裁 D7)。先行アラートと
                // ピンポイント補正は配信側 (Workers) が未実装のため、実装するまで
                // paywall に載せない (対価を取る以上、動かない特典は約束しない)。
                _featureCard(
                    Icons.travel_explore,
                    t.plusFeatureMultiLocationTitle,
                    t.plusFeatureMultiLocationBody),
                const SizedBox(height: 16),
                _plansSection(t),
                const SizedBox(height: 4),
                // 副導線は v1.3 の tertiary ボタン (塗りなし・本文書体)。
                // 既定の TextButton だと labelLarge (mono 太字) になり Figma と揃わない。
                QuietTertiaryButton(
                  label: t.paywallNotNow,
                  onPressed:
                      _busy ? null : () => Navigator.of(context).maybePop(),
                ),
                QuietTertiaryButton(
                  label: t.paywallRestore,
                  onPressed: _busy ? null : _restore,
                ),
                _legalRow(t),
              ],
            ),
            if (_busy)
              const ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    final type = MrwType.of(context);
    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: MrwTokens.of(context).plusTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: MrwTokens.of(context).plusBase),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: type.bodyLg.fontSize(14),
                        height: type.bodyLg.height(null),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: type.caption.fontSize(12),
                        height: type.caption.height(1.4, paragraph: true),
                        color: scheme.onSurface.withValues(alpha: 0.72))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// spec §12.11.7 の固定免責文。**常時表示** (課金状態・A/B 群を問わず)。
  Widget _safetyDisclaimer(AppLocalizations t) {
    final scheme = Theme.of(context).colorScheme;
    final caption = MrwType.of(context).caption;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.paywallSafetyDisclaimer,
              style: TextStyle(
                  fontSize: caption.fontSize(12),
                  height: caption.height(1.45, paragraph: true),
                  color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plansSection(AppLocalizations t) {
    return FutureBuilder<List<PlusPackage>>(
      future: _packagesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final packages = snap.data ?? const <PlusPackage>[];
        if (packages.isEmpty) {
          return _comingSoon(t);
        }
        _selectedPackageId ??= _defaultSelection(packages);
        // トライアル注記は「選択中のプラン」にオファーが付いているときだけ。
        // 別プランのオファーで注記を出すと、月額だけ選んだ人に誤表示になる。
        // 資格 (新規のみ等) はストアが判定するので、文言側で断定しない (compliance 1-5)。
        final selected = packages.firstWhere(
          (p) => p.packageId == _selectedPackageId,
          orElse: () => packages.first,
        );
        final hasTrial = selected.hasIntroOffer;
        final type = MrwType.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.paywallChoosePlan,
                style: TextStyle(
                    fontSize: type.section.fontSize(15),
                    height: type.section.height(null),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            for (var i = 0; i < packages.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _planCard(t, packages[i]),
            ],
            if (hasTrial) ...[
              const SizedBox(height: 12),
              Text(t.paywallTrialNote,
                  style: TextStyle(
                      fontSize: type.caption.fontSize(12),
                      height: type.caption.height(null),
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7))),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 16),
            // 自動更新の開示。Offering / トライアルの有無に関係なく常時表示する。
            Text(
              t.paywallAutoRenewNotice,
              style: TextStyle(
                fontSize: type.meta.fontSize(11),
                height: type.meta.height(1.45, paragraph: true),
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 12),
            // 主ボタンは Quiet の主ボタン (本文書体 15/20・高さ 46)。1 画面に 1 つ。
            QuietPrimaryButton(
              label: t.paywallStartCta,
              onPressed:
                  (_busy || _selectedPackageId == null) ? null : _purchase,
            ),
          ],
        );
      },
    );
  }

  Widget _planCard(AppLocalizations t, PlusPackage p) {
    final scheme = Theme.of(context).colorScheme;
    final type = MrwType.of(context);
    final selected = p.packageId == _selectedPackageId;
    final isAnnual = p.period == PlusBillingPeriod.annual;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap:
          _busy ? null : () => setState(() => _selectedPackageId = p.packageId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: selected ? 0.55 : 0.28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? MrwTokens.of(context).plusBase
                : scheme.onSurface.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color:
                  selected ? MrwTokens.of(context).plusBase : scheme.onSurface,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              // プラン名 + BEST VALUE。並ばない幅 (360dp × 1.3・390dp × 1.5 以上) では
              // バッジをプラン名の下の行へ落とす。プラン名は省略しない (契約期間が
              // 読めないのは App Store 3.1.2 / Play の定期購入要件に反する)。
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_periodLabel(t, p.period),
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: type.bodyLg.fontSize(14),
                          height: type.bodyLg.height(null),
                          fontWeight: FontWeight.w600)),
                  if (isAnnual) _bestValueChip(t),
                ],
              ),
            ),
            // 価格は縮めず、右端に固定 (左側と重ねない)。
            const SizedBox(width: 8),
            Text(p.priceString,
                style: TextStyle(
                    fontSize: type.section.fontSize(15),
                    height: type.section.height(null),
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// 年額の「BEST VALUE」(Figma 6:214)。Quiet のバッジ (mono 大文字・型スケール tag)
  /// に揃える。色は Paywall の commerce/plus のまま (状態色は使わない)。
  /// 1 行ぶんの幅にも入らない文字倍率 (360dp × 2.0 の es「MEJOR VALOR」) では
  /// 省略せず縮める。
  Widget _bestValueChip(AppLocalizations t) {
    final tokens = MrwTokens.of(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: QuietBadge(
        t.paywallBestValue.toUpperCase(),
        fill: tokens.plusTint,
        labelColor: tokens.plusBase,
      ),
    );
  }

  Widget _comingSoon(AppLocalizations t) {
    final body = MrwType.of(context).body;
    return GlassCard(
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.paywallComingSoon,
              style: TextStyle(
                fontSize: body.fontSize(13),
                height: body.height(null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legalRow(AppLocalizations t) {
    // 独自規約が未公開の間、Apple 標準 EULA へのフォールバックは iOS だけ。
    // Android で apple.com の EULA を開くのは Play では不適切なので規約行を出さない。
    final showTerms = AppLinks.termsOfUseUrl.isNotEmpty ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    // Figma: 12px の本文書体・tertiary 色。ボタン既定の mono 太字にしない。
    final linkStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: caption.fontSize(12),
          height: caption.height(17 / 12),
          color: tokens.actionTertiaryLabel,
        );
    final linkButtonStyle = TextButton.styleFrom(
      foregroundColor: tokens.actionTertiaryLabel,
      textStyle: linkStyle,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showTerms) ...[
            TextButton(
              style: linkButtonStyle,
              onPressed: () => _openUrl(_termsUrl),
              child: Text(t.paywallTerms),
            ),
            Text('·', style: linkStyle),
          ],
          TextButton(
            style: linkButtonStyle,
            onPressed: () => _openUrl(AppLinks.privacyPolicyUrl),
            child: Text(t.paywallPrivacy),
          ),
        ],
      ),
    );
  }

  String get _termsUrl => AppLinks.termsOfUseUrl.isNotEmpty
      ? AppLinks.termsOfUseUrl
      : _kAppleStandardEula;

  String _periodLabel(AppLocalizations t, PlusBillingPeriod period) =>
      switch (period) {
        PlusBillingPeriod.monthly => t.paywallPeriodMonthly,
        PlusBillingPeriod.annual => t.paywallPeriodAnnual,
        PlusBillingPeriod.unknown => t.paywallPeriodMonthly,
      };

  /// 既定選択は月額。手取りは月額 ¥541/月 vs 年額 ¥225/月 で 2.4 倍差があり、
  /// 月額比率 40〜50% を目標にする (accounting、release-plan §5 Step 8 #4)。
  String _defaultSelection(List<PlusPackage> packages) {
    for (final p in packages) {
      if (p.period == PlusBillingPeriod.monthly) return p.packageId;
    }
    return packages.first.packageId;
  }

  Future<void> _purchase() async {
    final id = _selectedPackageId;
    if (id == null) return;
    setState(() => _busy = true);
    final result = await ref.read(billingGatewayProvider).purchase(id);
    if (!mounted) return;
    setState(() => _busy = false);
    final t = AppLocalizations.of(context);
    switch (result.status) {
      case PurchaseStatus.purchased:
        await ref.read(entitlementProvider.notifier).refresh();
        if (!mounted) return;
        _showSnack(t.paywallPurchaseSuccess);
        unawaited(Navigator.of(context).maybePop());
      case PurchaseStatus.pending:
        _showSnack(t.paywallPurchasePending);
        unawaited(Navigator.of(context).maybePop());
      case PurchaseStatus.cancelled:
        break; // 明示キャンセルは無言
      case PurchaseStatus.billingUnavailable:
        _showSnack(t.paywallUnavailable);
      case PurchaseStatus.error:
        _showSnack(t.paywallPurchaseError);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await ref.read(billingGatewayProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    final t = AppLocalizations.of(context);
    if (result.status == PurchaseStatus.billingUnavailable) {
      _showSnack(t.paywallUnavailable);
      return;
    }
    final restored = result.isSuccess && (result.entitlement?.hasPlus ?? false);
    if (restored) {
      await ref.read(entitlementProvider.notifier).refresh();
      if (!mounted) return;
      _showSnack(t.paywallRestoreSuccess);
      unawaited(Navigator.of(context).maybePop());
    } else {
      _showSnack(t.paywallRestoreNone);
    }
  }

  Future<void> _openUrl(String url) async {
    final ok = await openExternalUrl(url);
    if (!ok && mounted) {
      _showSnack(AppLocalizations.of(context).paywallComingSoon);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
