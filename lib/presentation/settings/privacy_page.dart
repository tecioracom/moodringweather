// lib/presentation/settings/privacy_page.dart
//
// 設定 > プライバシー (spec.md §4.4 / §13 / Figma v1.3 `Settings — Privacy` 6:34・
// Light 24:1105・JP 77:1052 実測)。アプリ内プライバシー要約。
// 内容は docs/privacy-policy.md §1 (TL;DR) / docs/data-safety.md と整合:
//   - 位置情報は最小限 (COARSE のみ・履歴非保持)
//   - 体感データ (キャリブレーション・記録) はオンデバイス完結
//   - 広告 ID / 広告 SDK / 第三者アナリティクス不使用
//   - アカウント不要 (匿名ゲスト。個人識別情報を尋ねない)
//
// 構成 (Figma): 行頭ドット + 見出し 13 + 本文 11 のカード ×4 → 「プライバシー
// ポリシー全文」の行 (chevron)。
//
// **C5 (codex-fixes_v1.3_unified.md §4.2)**: この画面は全面ニュートラル。
// 行頭ドットは Dark #AEB2BA / Light #4A4E56 (= MrwTokens.inkMid)。
// 状態色 (state/*) は **0 個**。
//
// フルポリシー URL は AppLinks.privacyPolicyUrl (未公開の間は「準備中」)。
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。
//
// 「データを削除」(決裁 D3、プライバシーポリシー §5): 確認ダイアログ → サーバー側の
// 記録 2 件 + 端末内データを削除 (data/privacy/data_deletion.dart)。破壊的操作は
// テキストのみのボタン (指示書 §2.3: 塗り禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_links.dart';
import '../../core/utils/external_url.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/privacy_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';

/// カード間のガター (Figma: 203 → 297 = 94 − 82)。
const double _kGutter = 12;

class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hasUrl = AppLinks.privacyPolicyUrl.isNotEmpty;

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsPrivacy,
      children: [
        QuietDotCard(
          title: t.privacyLocationTitle,
          body: t.privacyLocationBody,
        ),
        const SizedBox(height: _kGutter),
        QuietDotCard(
          title: t.privacyOnDeviceTitle,
          body: t.privacyOnDeviceBody,
        ),
        const SizedBox(height: _kGutter),
        QuietDotCard(
          title: t.privacyNoAdsTitle,
          body: t.privacyNoAdsBody,
        ),
        const SizedBox(height: _kGutter),
        QuietDotCard(
          title: t.privacyAnonymousTitle,
          body: t.privacyAnonymousBody,
        ),
        const SizedBox(height: 26),

        // === フルポリシーへの導線 (URL 公開までは「準備中」) ===
        QuietListRow(
          title: t.privacyFullPolicy,
          trailing: hasUrl ? null : QuietBadge(t.settingsComingSoon),
          chevron: hasUrl,
          enabled: hasUrl,
          onTap:
              hasUrl ? () => openExternalUrl(AppLinks.privacyPolicyUrl) : null,
        ),
        const SizedBox(height: 26),

        // === データの削除 (決裁 D3) ===
        QuietDotCard(
          title: t.privacyDeleteDataTitle,
          body: t.privacyDeleteDataBody,
        ),
        const SizedBox(height: 6),
        QuietTertiaryButton(
          label:
              _busy ? t.privacyDeleteDataInProgress : t.privacyDeleteDataTitle,
          destructive: true,
          onPressed: _busy ? null : _confirmDelete,
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.privacyDeleteDataConfirmTitle),
        content: Text(t.privacyDeleteDataConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.privacyDeleteDataCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MrwTokens.of(context).actionDestructiveLabel,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.privacyDeleteDataConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final outcome = await ref.read(dataDeletionServiceProvider).deleteAll();
    if (!mounted) return;
    invalidateLocalStateAfterDeletion(ref);
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(outcome.isComplete
            ? t.privacyDeleteDataDone
            : t.privacyDeleteDataPartial),
      ));
  }
}
