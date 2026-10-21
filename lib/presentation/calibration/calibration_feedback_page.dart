// lib/presentation/calibration/calibration_feedback_page.dart
//
// 体感フィードバック (Figma v1.3 `Calibration — Feedback` 5:56・Light 24:870・
// JP 77:817 実測)。
// 「暑すぎ/やや暑/ちょうど/やや寒/寒すぎ」を選んで記録 → θ 更新 →
// MRI に即時反映 (mri-spec.md §6.2)。同日重複ガード (§6.3-5) に弾かれた
// 場合はその旨を案内する。
//
// 構成 (Figma):
//   パネル  リング (現在の MRI) + 都市 · 気温 mono + 現在値の説明
//   行 ×5   体感の選択肢 (タップで即記録)
//
// **状態色 (§4.1)**: リングの弧と head dot だけ (2 個)。選択肢の行は
// すべてニュートラル (「暑い / 寒い」を色で語らない)。
//
// Figma との差異 (意図的):
//   - Figma は「選んでから保存ボタン」の 2 段階だが、実装は **行タップで即記録**
//     のまま (同日重複ガードと相性がよく、タップ数も少ない)。したがって
//     「Save feedback」の主 CTA は置かない。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/temperature_unit.dart';
import '../../domain/calibration/calibration_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/mri_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/weather_provider.dart';
import '../shared/mood_ring_widget.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 行の間隔 (Figma: 417 → 475 = 58 − 52)。
const double _kRowGap = 10;

class CalibrationFeedbackPage extends ConsumerWidget {
  const CalibrationFeedbackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final snapshot = ref.watch(weatherSnapshotProvider).valueOrNull;
    final mri = ref.watch(mriProvider).valueOrNull;
    final city = ref.watch(cityNameProvider).valueOrNull;
    final unit = ref.watch(temperatureUnitProvider);
    final canSubmit = snapshot != null && mri != null;

    final options = [
      (CalibrationFeedback.tooHot, t.feedbackTooHot),
      (CalibrationFeedback.slightlyHot, t.feedbackSlightlyHot),
      (CalibrationFeedback.justRight, t.feedbackJustRight),
      (CalibrationFeedback.slightlyCool, t.feedbackSlightlyCool),
      (CalibrationFeedback.tooCold, t.feedbackTooCold),
    ];

    return QuietPage(
      title: t.settingsCalibration,
      headline: t.calibrationFeedbackTitle,
      intro: t.calibrationFeedbackQuestion,
      children: [
        // === 現在の体感 (リングの弧と head dot だけが帯色) ===
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: mri == null
              ? Text(
                  t.loadingWeather,
                  style: TextStyle(
                    fontSize: type.body.fontSize(13),
                    height: type.body.height(null),
                    color: tokens.textMid,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    MoodRingWidget(
                      mri: mri,
                      size: 92,
                      valueFontSize: 34,
                      labelFontSize: 9,
                      dotRadius: 4.5,
                      // 92px のリングに帯名は収まらないので短い指標名にする。
                      label: t.mriAbbrev,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (snapshot != null)
                            QuietLabel(
                              '${city ?? t.currentLocation} · '
                              '${unit.formatDegrees(snapshot.temperature)}',
                              small: true,
                              color: tokens.textMono,
                            ),
                          const SizedBox(height: 8),
                          Text(
                            t.calibrationCurrentMri(mri.value),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontSize: type.section.fontSize(15),
                                  height: type.section.height(20 / 15),
                                  color: tokens.textHi,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 26),

        // === 選択肢 (タップで即記録) ===
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: _kRowGap),
          QuietListRow(
            title: options[i].$2,
            emphasizeTitle: true,
            enabled: canSubmit,
            chevron: canSubmit,
            onTap:
                canSubmit ? () => _submit(context, ref, options[i].$1) : null,
          ),
        ],
        const SizedBox(height: 16),
        QuietNote(t.calibrationOnDeviceNote),
      ],
    );
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    CalibrationFeedback feedback,
  ) async {
    final t = AppLocalizations.of(context);
    final snapshot = ref.read(weatherSnapshotProvider).valueOrNull;
    final mri = ref.read(mriProvider).valueOrNull;
    if (snapshot == null || mri == null) return;

    final accepted =
        await ref.read(personalProfileProvider.notifier).submitFeedback(
              feedback: feedback,
              snapshot: snapshot,
              currentMri: mri.value,
            );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? t.calibrationFeedbackSaved
                : t.calibrationFeedbackDuplicate,
          ),
        ),
      );
  }
}
