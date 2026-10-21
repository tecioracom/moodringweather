// lib/presentation/settings/settings_page.dart
//
// 設定 Top (spec.md §4.4 / Figma v1.3 `Settings — Quiet Top` 3:356・Light 24:348・
// JP 77:443 実測)。MainShell の「設定」タブ本体 (トップレベルなので戻る矢印なし)。
//
// 構成 (座標は Figma 390×844):
//   見出し      「設定」Fraunces 28 / 字間 −0.28              (20, 91)
//   Profile Card 350×84・角丸 20: avatar 52 角丸 16 (surfaceHigh + 8% 枠)
//               + 名前 Inter SemiBold 15 + mono 10 のサブ行   (20, 132)
//   行 ×8       350×54〜58・角丸 16: icon 20 + 見出し 15 + 副題 12 + chevron
//
// Figma にあって実装しない (理由):
//   - Profile Card 3 行目の「UID anon-7f3a-2b8c」: アプリは匿名ゲストで、画面に
//     出せる UID を保持していない (偽の ID を出すのは誤情報)。名前 + 1 行に縮めた。
// Figma に無くて実装するもの (理由):
//   - Plus の導線行: Figma の設定 Top に Plus 行が無いが、PlusSettingsPage への
//     入口がここ以外に無い。§4.1 の状態色は使わず commerce/plus のバッジのみ。
//
// 厳守: 状態色 (state/*) はこの画面に 0 個 (MRI 値を表す要素が無い)。
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/entitlement_provider.dart';
import '../calibration/calibration_home_page.dart';
import '../comfort_twin/twin_search_page.dart';
import '../shared/glass_card.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../shared/quiet_row_icons.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'about_app_page.dart';
import 'about_mri_page.dart';
import 'general_settings_page.dart';
import 'locations_page.dart';
import 'notification_settings_page.dart';
import 'plus_settings_page.dart';
import 'privacy_page.dart';

/// 行の間隔 (Figma: 231 → 297 = 66 − 58)。
const double _kRowGap = 8;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    void open(WidgetBuilder builder) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

    return QuietPage(
      headline: t.settingsTitle,
      showBack: false,
      edgePadding: kQuietTabEdgePadding,
      // ピル型ナビ (64 + 下 14) の裏まで地を通すぶんの余白。
      bottomPadding: 96,
      children: [
        const _ProfileCard(),
        const SizedBox(height: 16),
        const _PlusEntryRow(),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.sliders,
          title: t.settingsGeneral,
          subtitle: t.settingsGeneralSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const GeneralSettingsPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.bell,
          title: t.settingsNotifications,
          subtitle: t.settingsNotificationsSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const NotificationSettingsPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.sliders,
          title: t.settingsCalibration,
          subtitle: t.settingsCalibrationSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const CalibrationHomePage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.globe,
          title: t.settingsComfortTwin,
          subtitle: t.settingsComfortTwinSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const TwinSearchPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.scale,
          title: t.settingsAboutMri,
          subtitle: t.settingsAboutMriSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const AboutMriPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.place,
          title: t.settingsLocations,
          subtitle: t.settingsLocationsSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const LocationsPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.lock,
          title: t.settingsPrivacy,
          subtitle: t.settingsPrivacySubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const PrivacyPage()),
        ),
        const SizedBox(height: _kRowGap),
        QuietListRow(
          icon: QuietRowIcon.info,
          title: t.settingsAboutApp,
          subtitle: t.settingsAboutAppSubtitle,
          emphasizeTitle: true,
          chevron: true,
          onTap: () => open((_) => const AboutAppPage()),
        ),
      ],
    );
  }
}

/// ゲストのプロフィールカード (Figma 3:399)。アカウント機能は無い。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    return QuietCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          // Figma 3:400: 中身のない 52 角丸 16 のプレースホルダ。
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tokens.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                width: 1,
                color: tokens.textHi.withValues(alpha: 0.08),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.settingsGuest,
                  style: text.titleMedium?.copyWith(
                    fontSize: type.section.fontSize(15),
                    height: type.section.height(20 / 15),
                    color: tokens.textHi,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.settingsGuestSubtitle,
                  style: text.labelSmall?.copyWith(
                    fontSize: type.tag.fontSize(10),
                    letterSpacing: type.tag.letterSpacing(0.4),
                    height: type.tag.height(14 / 10),
                    color: tokens.inkMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plus の導線 (未加入はアップグレード訴求、加入は状態へのリンク)。
/// 色は commerce/plus のバッジのみ。状態色は使わない。
class _PlusEntryRow extends ConsumerWidget {
  const _PlusEntryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final isPlus = ref.watch(isPlusProvider);
    return QuietListRow(
      icon: QuietRowIcon.scale,
      // §6.1「Plus ロゴ・特典アイコンは commerce/plus/base」。
      // バッジを右に置くと JA / ES で見出しが折り返すため、Plus の色は
      // アイコンだけで示す (バッジは通知・地点のロック表示で使う)。
      iconColor: tokens.plusBase,
      title: isPlus ? t.plusBrandName : t.plusUpgradeTitle,
      subtitle: isPlus ? t.plusStatusActiveTitle : t.plusUpgradeSubtitle,
      emphasizeTitle: true,
      chevron: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PlusSettingsPage()),
      ),
    );
  }
}
