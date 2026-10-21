// lib/presentation/calibration/calibration_profile_page.dart
//
// 体感プロファイル (Figma v1.3 `Calibration — Profile` 5:89・Light 24:903・
// JP 77:850 実測)。
//   - 学習した快適スイートスポット (estimatedOptimalMRI)
//   - 感受性バー (好み温度シフト δT / 暑さ λ_heat / 寒さ λ_cool /
//     湿度・日射・空気質の β) をスライダーで表示・手動調整。花粉の β は出さない
//     (花粉データ未接続。compliance-review-v1.3.0 §8 A5)
//   - リセット (mri-spec.md §6.3-6: θ をワンタップで全初期化)
// 手動調整は manualOverride としてランプインを介さず全量適用される。
//
// 構成 (Figma):
//   パネル   「最適 MRI」mono + 値 Fraunces 56 (**帯色**) + 帯名 mono + 目盛り
//   セクション「手動調整」+ スライダーのカード
//   副ボタン リセット (action/secondary。Figma も塗りの副ボタンで、
//            破壊的な赤は使っていない。確認ダイアログで取り消せるため)
//
// **状態色 (§4.2 C1 / §4.1)**: 「最適 MRI」の数値 1 個だけ (規則 1 の ③)。
// C1 の指摘 (紫・インディゴのアクセントは「MRI 66 = 快適」の情報を偽る) に
// 対して、値に応じた帯色 (§4.3 の変換表) を使う。スライダー・目盛り・
// ラベルはすべてニュートラル。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/temperature_unit.dart';
import '../../data/models/personal_profile.dart';
import '../../domain/mri/mri_band.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/settings_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// スライダーカードの間隔 (Figma: 413 → 491 = 78 − 68)。
const double _kCardGap = 10;

class CalibrationProfilePage extends ConsumerWidget {
  const CalibrationProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final profile = ref.watch(personalProfileProvider);
    final notifier = ref.read(personalProfileProvider.notifier);
    final unit = ref.watch(temperatureUnitProvider);
    final optimal = profile.estimatedOptimalMri;

    return QuietPage(
      title: t.settingsCalibration,
      headline: t.calibrationProfileTitle,
      intro: t.calibrationEstimatedOptimal(optimal),
      children: [
        // === 快適スイートスポット (数値だけが帯色) ===
        QuietPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuietLabel(
                '${t.bandOptimal} ${t.mriAbbrev}',
                small: true,
                color: tokens.textMono,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  QuietDisplayNumber(
                    '$optimal',
                    size: 56,
                    color: tokens.stateColorForMri(optimal),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: QuietLabel(
                      _bandLabel(t, optimal),
                      small: true,
                      color: tokens.inkMid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: QuietProgressTrack(fraction: optimal / 100),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === 手動調整 (感受性バー。すべてニュートラル) ===
        QuietSectionTitle(t.calibrationManualAdjust),
        const SizedBox(height: 10),
        for (final (i, s) in _sliders(t, profile, notifier, unit).indexed) ...[
          if (i > 0) const SizedBox(height: _kCardGap),
          s,
        ],
        const SizedBox(height: 26),

        // === リセット ===
        QuietSecondaryButton(
          label: t.calibrationReset,
          onPressed: () => _confirmReset(context, ref),
        ),
        const SizedBox(height: 12),
        QuietNote(t.calibrationOnDeviceNote),
      ],
    );
  }

  List<Widget> _sliders(
    AppLocalizations t,
    PersonalProfile profile,
    PersonalProfileController notifier,
    TemperatureUnit unit,
  ) {
    return [
      _SensitivityCard(
        label: t.calibrationOptimalTemp,
        // 好みの温度の差は温度の単位に従う (°F は差なので ×1.8 だけ。32 は足さない)。
        // 表記はアプリの気温と同じ「+1.5°」(単位記号なし)。スライダーの値は °C のまま。
        valueLabel: unit.formatDegreesDelta(profile.deltaT),
        value: profile.deltaT,
        min: PersonalProfile.deltaTMin,
        max: PersonalProfile.deltaTMax,
        onChanged: (v) => notifier.adjustManually((p) => p.copyWith(deltaT: v)),
      ),
      _SensitivityCard(
        label: t.calibrationHeatSensitivity,
        valueLabel: '×${profile.lambdaHeat.toStringAsFixed(2)}',
        value: profile.lambdaHeat,
        min: PersonalProfile.lambdaMin,
        max: PersonalProfile.lambdaMax,
        onChanged: (v) =>
            notifier.adjustManually((p) => p.copyWith(lambdaHeat: v)),
      ),
      _SensitivityCard(
        label: t.calibrationColdSensitivity,
        valueLabel: '×${profile.lambdaCool.toStringAsFixed(2)}',
        value: profile.lambdaCool,
        min: PersonalProfile.lambdaMin,
        max: PersonalProfile.lambdaMax,
        onChanged: (v) =>
            notifier.adjustManually((p) => p.copyWith(lambdaCool: v)),
      ),
      _SensitivityCard(
        label: t.statHumidity,
        valueLabel: _betaLabel(profile.betaHumid),
        value: profile.betaHumid,
        min: PersonalProfile.betaMin,
        max: PersonalProfile.betaMax,
        onChanged: (v) =>
            notifier.adjustManually((p) => p.copyWith(betaHumid: v)),
      ),
      _SensitivityCard(
        label: t.statUv,
        valueLabel: _betaLabel(profile.betaUv),
        value: profile.betaUv,
        min: PersonalProfile.betaMin,
        max: PersonalProfile.betaMax,
        onChanged: (v) => notifier.adjustManually((p) => p.copyWith(betaUv: v)),
      ),
      _SensitivityCard(
        label: t.statAqi,
        valueLabel: _betaLabel(profile.betaAqi),
        value: profile.betaAqi,
        min: PersonalProfile.betaMin,
        max: PersonalProfile.betaMax,
        onChanged: (v) =>
            notifier.adjustManually((p) => p.copyWith(betaAqi: v)),
      ),
      // 花粉のスライダーは出さない: 花粉データは未接続で、動かしても花粉とは
      // 無関係に定数項の重みが変わるだけ (compliance-review-v1.3.0 §8 A5)。
      // 学習 (β_pollen) と保存データはそのまま。
    ];
  }

  String _bandLabel(AppLocalizations t, int mri) {
    switch (MriBand.fromValue(mri)) {
      case MriBand.cool:
        return t.bandCool;
      case MriBand.comfortable:
        return t.bandComfortable;
      case MriBand.warm:
        return t.bandWarm;
      case MriBand.hot:
        return t.bandHot;
      case MriBand.hotAlert:
        return t.bandHotHydrate;
    }
  }

  /// β を体感的な % 表示にする (+0.25 → "+25%")。
  static String _betaLabel(double beta) {
    final pct = (beta * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct%';
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.calibrationResetConfirmTitle),
        content: Text(t.calibrationResetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.calibrationResetCancel),
          ),
          TextButton(
            // 破壊的操作は **テキストのみ** (指示書 §2.3: 塗り禁止)。
            style: TextButton.styleFrom(
              foregroundColor: MrwTokens.of(context).actionDestructiveLabel,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.calibrationResetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(personalProfileProvider.notifier).reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.calibrationResetDone)));
  }
}

/// 感受性のスライダーカード (Figma 5:103)。ラベル・値・つまみはニュートラル。
class _SensitivityCard extends StatelessWidget {
  const _SensitivityCard({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    return QuietCardRow(
      minHeight: 68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    fontSize: type.body.fontSize(13),
                    height: type.body.height(17 / 13),
                    color: tokens.textHi,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                valueLabel,
                style: text.labelMedium?.copyWith(
                  fontSize: type.tag.fontSize(10),
                  letterSpacing: 0,
                  height: type.tag.height(13 / 10),
                  color: tokens.textMono,
                ),
              ),
            ],
          ),
          QuietSlider(
            value: value,
            min: min,
            max: max,
            label: valueLabel,
            semanticFormatterCallback: (_) => '$label $valueLabel',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
