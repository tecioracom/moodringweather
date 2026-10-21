// lib/presentation/calibration/calibration_home_page.dart
//
// キャリブレーション 学習モード Home (Figma v1.3 `Calibration — Learning Home`
// 5:2・Light 24:819・JP 77:766 実測)。
//
// 構成 (Figma):
//   見出し   + 右にリング (現在の MRI)。リード文はオンデバイス学習の注記
//   パネル   「学習の進み具合」mono + 割合 Fraunces + 件数 + 目盛り + 注記
//   セクション「24 時間の MRI」+ **ニュートラルのバー** のカード
//   セクション「わかってきたこと」+ 行カード
//   主 CTA   体感を記録する / 副導線 感受性プロファイル
//
// **状態色 (§4.2 C2 / §4.1)**: リングの弧と head dot だけ。アクセントは
// シアンではなく **その時点の MRI の帯色** にする (C2 の「state/comfortable」は
// 快適帯のサンプルを指す。実装は値に応じた帯色 = §4.3 の変換表)。
// 24 時間のバーは無彩色 (値そのものではなく推移の形を見せる要素)。
// 進捗バー・アイコン・区切りはすべてニュートラル。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calibration/calibration_insights.dart';
import '../../domain/mri/mri_timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/mri_provider.dart';
import '../shared/chart_axes.dart';
import '../shared/mood_ring_widget.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'calibration_feedback_page.dart';
import 'calibration_profile_page.dart';

/// 行の間隔。
const double _kRowGap = 10;

class CalibrationHomePage extends ConsumerWidget {
  const CalibrationHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    final profile = ref.watch(personalProfileProvider);
    final timeline = ref.watch(mriTimelineProvider);
    final mri = ref.watch(mriProvider).valueOrNull;
    // 表示する気づき。花粉は出さない (_insightLabel が null)。
    final insights = [
      for (final insight in CalibrationInsights.derive(profile))
        if (_insightLabel(t, insight) case final label?) label,
    ];

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsCalibration,
      intro: t.calibrationOnDeviceNote,
      headlineTrailing: mri == null
          ? null
          // Figma 5:8: 見出しの右に小さなリング。状態色は弧と head dot のみ。
          : MoodRingWidget(
              mri: mri,
              size: 92,
              valueFontSize: 34,
              labelFontSize: 9,
              dotRadius: 4.5,
              // 92px のリングに帯名は収まらないので短い指標名にする
              // (帯は弧の色と数値が示す)。
              label: t.mriAbbrev,
            ),
      children: [
        // === 学習の進み具合 ===
        QuietPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuietLabel(
                t.calibrationLearningProgress,
                small: true,
                color: tokens.textMono,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  QuietDisplayNumber(
                    '${(profile.learningProgress * 100).round()}%',
                    size: 42,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      t.calibrationFeedbackCount(profile.feedbackCount),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: caption.fontSize(12),
                            height: caption.height(17 / 12, paragraph: true),
                            color: tokens.textMid,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: QuietProgressTrack(fraction: profile.learningProgress),
              ),
              const SizedBox(height: 10),
              QuietNote(
                profile.rampScale > 0
                    ? t.calibrationAppliedNote
                    : t.calibrationRampInNote,
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === 24 時間の MRI (バーは無彩色) ===
        QuietSectionTitle(t.calibrationChartTitle),
        const SizedBox(height: 10),
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: timeline.when(
            data: (points) => _MiniMriChart(points: points),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => Text(
              t.errorWeatherLoadFailed,
              style: TextStyle(
                fontSize: caption.fontSize(12),
                height: caption.height(null),
                color: tokens.textMid,
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),

        // === わかってきたこと ===
        QuietSectionTitle(t.calibrationInsightsTitle),
        const SizedBox(height: 10),
        if (insights.isEmpty)
          QuietBodyCard(text: t.calibrationInsightNone)
        else
          for (var i = 0; i < insights.length; i++) ...[
            if (i > 0) const SizedBox(height: _kRowGap),
            QuietListRow(title: insights[i]),
          ],
        const SizedBox(height: 26),

        // === 導線 (主 CTA は 1 つ) ===
        QuietPrimaryButton(
          label: t.calibrationGiveFeedback,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CalibrationFeedbackPage(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        QuietTertiaryButton(
          label: t.calibrationViewProfile,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CalibrationProfilePage(),
            ),
          ),
        ),
      ],
    );
  }

  /// 気づきの文言。null は出さない気づき: 花粉は、花粉データが未接続で、手で
  /// スライダーを動かしたときにしか出ない表示だった (compliance-review-v1.3.0
  /// §8 A6)。学習 (θ) と MRI は変えない。
  String? _insightLabel(AppLocalizations t, CalibrationInsight insight) {
    switch (insight) {
      case CalibrationInsight.prefersCooler:
        return t.calibrationInsightPrefersCooler;
      case CalibrationInsight.prefersWarmer:
        return t.calibrationInsightPrefersWarmer;
      case CalibrationInsight.heatSensitive:
        return t.calibrationInsightHeatSensitive;
      case CalibrationInsight.coldSensitive:
        return t.calibrationInsightColdSensitive;
      case CalibrationInsight.humiditySensitive:
        return t.calibrationInsightHumiditySensitive;
      case CalibrationInsight.uvSensitive:
        return t.calibrationInsightUvSensitive;
      case CalibrationInsight.airQualitySensitive:
        return t.calibrationInsightAqiSensitive;
      case CalibrationInsight.pollenSensitive:
        return null;
    }
  }
}

/// 24 時間 MRI のコンパクトなバー (Figma 5:22)。**すべて無彩色**。
/// 現在の 1 本だけ不透明度を上げて位置を示す (色では区別しない)。
class _MiniMriChart extends StatelessWidget {
  const _MiniMriChart({required this.points});

  final List<MriTimelinePoint> points;

  static const double _chartHeight = 88;

  /// 時刻を出す間隔 (時)。ラベルの枠はこの本数ぶんの棒の幅にする。
  static const int _labelEvery = 6;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final tokens = MrwTokens.of(context);
    // 時刻は Home / 詳細の時刻軸と同じ Plex Mono (axisLabelStyle。型スケールの axis)。
    final hourStyle = axisLabelStyle(context, color: tokens.textMono);
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(hourStyle.fontSize ?? 12) *
            (hourStyle.height ?? 1.2);
    final nowIndex = MriTimeline.indexNearest(points);
    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: (_chartHeight * points[i].mri.value / 100)
                          .clamp(4.0, double.infinity),
                      decoration: BoxDecoration(
                        color: tokens.textMid
                            .withValues(alpha: i == nowIndex ? 0.9 : 0.42),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 時刻 (0 / 6 / 12 / 18 時)。棒 1 本ぶんの枠に閉じ込めると「1 / 2」と
        // 1 文字ずつ折れるので、棒 6 本ぶん (= ラベルの間隔) の枠を棒の中心に置き、
        // 折り返さない。
        SizedBox(
          height: labelHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / points.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < points.length; i++)
                    if (points[i].timestamp.hour % _labelEvery == 0)
                      Positioned(
                        left: (i + 0.5) * slot - slot * _labelEvery / 2,
                        width: slot * _labelEvery,
                        top: 0,
                        child: Text(
                          '${points[i].timestamp.hour}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: hourStyle,
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
