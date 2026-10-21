// lib/presentation/settings/notification_settings_page.dart
//
// 設定 > 通知 (spec.md §12.5 / §12.6 / §12.9 / Figma v1.3
// `Settings — Notifications` 3:572・Light 24:654・JP 77:659 実測)。
//
// 構成: **緊急通知のカードだけ** (lock アイコン + 見出し + 「常時オン・無料」バッジ +
// 説明・配信範囲・免責。操作不可)。
//
// 出さないもの (2026-09-30 ユーザー決裁 P1-5、compliance-review-v1.3.0 §8 N1〜N3):
//   「天気の変化」「パーソナル通知」(マスター + 気圧急変・湿度急上昇・空気質・強い紫外線・
//   花粉激増)・「静音時間」・「1 日の上限」。どれも配信の仕組みが無く (端末のローカル通知は
//   緊急の 1 経路だけ、FCM も緊急以外は捨てる、Workers のパーソナル通知は対象 0 件)、
//   オンにしても何も届かない操作だった。**表示と操作だけ外し**、保存データ
//   (settings_notification_prefs) とモデル (NotificationPreferences)・provider は残す
//   (配信を作ったら戻せるように)。戻すときは compliance の再審査のうえ、
//   test/qa/notification_settings_hidden_static_test.dart を外す。
//
// Figma に無くて実装するもの (理由):
//   - 緊急行の免責 2〜3 行 (compliance レビュー §1.6 / §12.10.4 で必須)。
//
// 緊急通知は課金状態に関わらず永久無料・常時 ON (spec §12.2.1)。トグルは置かない。
// 静音時間の設定が画面に無いので、説明文に「静音時間も貫通」とは書かない (端末の
// おやすみモードを常に貫通する約束に読めるため。compliance §8-4-3)。
// 配信可能範囲の説明は **プラットフォームで分岐** する:
//   Android = FCM でアプリ終了時も届く (2026-09-15 実機 V3 で確認)
//   iOS     = 現状はアプリ利用中の判定・配信のみ
// いずれも「必ず届く」とは書かない (OS 都合の遅延・不達がある)。
//
// 厳守: 状態色 (state/*) はこの画面に 0 個。文言はすべて AppLocalizations 経由。

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/emergency_alert_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../shared/quiet_row_icons.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'debug_emergency_triggers.dart';

/// 行の間隔 (Figma 3:572 実測)。
const double _kRowGap = 8;

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsNotifications,
      children: [
        // === 緊急 (常時オン・無料。トグル無し) ===
        const _EmergencyCard(),

        // 天気の変化・パーソナル通知・静音時間・1 日の上限は出さない (配信の仕組みが
        // 無い。P1-5 決裁)。Plus の先行アラート / ピンポイント補正も同じ理由で出さない
        // (決裁 D7)。

        // === デバッグ: テスト緊急通知 (kDebugMode 限定) ===
        // リリースビルドには絶対に出さない (kDebugMode はリリースでコンパイル時
        // 定数 false となり、このサブツリーごと除去される)。
        // ラベルは kDebugMode 限定のため l10n 不要 (英語固定)。
        if (kDebugMode) ...[
          const SizedBox(height: 26),
          const QuietLabel('Debug: fire test emergency alert'),
          const SizedBox(height: 10),
          for (final trigger in debugEmergencyTriggers) ...[
            _DebugEmergencyTriggerRow(trigger: trigger),
            const SizedBox(height: _kRowGap),
          ],
        ],
      ],
    );
  }
}

/// 緊急通知 (Figma 3:575)。操作不可・常時オン。配信範囲の説明は OS ごとに変える。
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    // Android は FCM でアプリ終了時も届く (2026-09-15 実機 V3)。iOS は未対応。
    // Theme 経由で見るのでテストから override できる。
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final deliveryNote =
        isIos ? t.notifEmergencyForegroundNote : t.notifEmergencyBackgroundNote;

    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: QuietRowIconMark(QuietRowIcon.lock, size: 20),
              ),
              const SizedBox(width: 14),
              // 倍率が上がると「常時オン・無料」バッジが 1 行に収まらないので
              // Wrap で折り返す (等倍・Figma では 1 行のまま)。
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t.notifEmergency,
                      style: text.titleMedium?.copyWith(
                        fontSize: type.section.fontSize(15),
                        height: type.section.height(20 / 15),
                        color: tokens.textHi,
                      ),
                    ),
                    QuietBadge(t.notifEmergencyAlwaysOn),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${t.notifEmergencyAlwaysOnDesc}\n'
            '$deliveryNote\n'
            '${t.emergencyDisclaimer}',
            style: text.bodyMedium?.copyWith(
              fontSize: type.meta.fontSize(11),
              height: type.meta.height(16 / 11, paragraph: true),
              color: tokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

/// デバッグ専用: 合成入力で緊急通知を強制発火する行 (kDebugMode 限定)。
class _DebugEmergencyTriggerRow extends ConsumerWidget {
  const _DebugEmergencyTriggerRow({required this.trigger});

  final DebugEmergencyTrigger trigger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QuietListRow(
      title: trigger.label,
      subtitle: trigger.description,
      chevron: true,
      onTap: () async {
        final controller = ref.read(emergencyAlertControllerProvider);
        final messenger = ScaffoldMessenger.of(context);
        // 本番と同じ経路: NotificationGateway.initialize() が権限を要求する。
        final alerts = await controller.debugFire(trigger.buildSnapshot());
        final summary = alerts.isEmpty
            ? 'No alert generated (unexpected)'
            : alerts
                .map((a) => 'Fired ${a.kind.name} (${a.severity.name}, '
                    '${a.metricValue.toStringAsFixed(1)})')
                .join(' / ');
        messenger.showSnackBar(SnackBar(content: Text(summary)));
      },
    );
  }
}
