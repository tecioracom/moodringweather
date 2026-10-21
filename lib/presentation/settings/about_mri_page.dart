// lib/presentation/settings/about_mri_page.dart
//
// 設定 > MRIとは (spec.md §4.4 / docs/mri-spec.md §1-§4・§6 の平易な要約 /
// Figma v1.3 `Settings — About MRI` 6:63・Light 24:1134・JP 77:1081 実測)。
//
// 構成 (Figma 6:63、390×1080):
//   見出し    Mood Ring Index (Fraunces) + リード文
//   パネル    「スコアの読み方」mono + 快適スイートスポットの値 + 本文 + 目盛り
//   Bands     **5 帯 1 表** (降順)。行 = 帯ドット (帯色) + 範囲 mono + 帯名
//             「快適」行の直下に注記 1 行、表全体の直下に注記 1 行
//             (codex-fixes_v1.3_unified.md §7.1)
//   Factors   7 つのチップ (mono 9)
//   カード    パーソナルキャリブレーション / 免責 (行頭ドットはニュートラル)
//
// **状態色 (§4.1)**: 帯ドット 5 個だけ (規則 1 の ② 行頭の帯ドット)。
// 上限 6 以内。帯名・範囲・見出し・チップ・注記はすべてニュートラル。
//
// 帯の並びは **降順のまま** (80–100 が上)。Foundations のランプが昇順なのは
// 横方向だからで、この非対称は意図的 (§7.2)。
//
// Figma との差異 (意図的):
//   - パネルの大きな数字は Figma の固定値 64 ではなく、学習済みの快適スイート
//     スポット (personalProfile.estimatedOptimalMri。未学習時は 64 = Figma と同値)。
//     実装側に 64 を直書きすると学習結果と食い違う。
//   - リード文は Figma の短縮版ではなく既存 ARB の aboutMriWhatBody を使う
//     (同義の新規キーを増やさないため)。
//
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/temperature_unit.dart';
import '../../domain/mri/cold_label.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/settings_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 帯行の間隔 (Figma: 406 → 452 = 46 − 36)。
const double _kBandGap = 10;

class AboutMriPage extends ConsumerWidget {
  const AboutMriPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final body = MrwType.of(context).body;
    final optimal = ref.watch(personalProfileProvider).estimatedOptimalMri;
    final unit = ref.watch(temperatureUnitProvider);

    return QuietPage(
      title: t.settingsTitle,
      headline: t.mriFullName,
      intro: t.aboutMriWhatBody,
      children: [
        // === スコアの読み方 (Figma 6:72) ===
        QuietPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuietLabel(
                t.aboutMriReadingLabel,
                small: true,
                color: tokens.textMono,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  QuietDisplayNumber('$optimal', size: 50),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      t.aboutMriReadingBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: body.fontSize(13),
                            height: body.height(18 / 13, paragraph: true),
                            color: tokens.textMid,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 目盛り。スイートスポットの位置を示すだけで状態色は使わない。
              ExcludeSemantics(
                child: QuietProgressTrack(fraction: optimal / 100),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === 5 帯 1 表 (§7.1) ===
        QuietSectionTitle(t.aboutMriBandsTitle),
        const SizedBox(height: 10),
        _BandRow(range: '80–100', label: t.bandCool, sampleMri: 90),
        const SizedBox(height: 12),
        // 寒さの側は MRI が 100 付近に張り付くので、区分名は体感温度で分ける
        // (domain/mri/cold_label.dart)。温度は利用者の単位で出す。
        QuietNote(t.aboutMriColdNote(
          unit.formatDegrees(kColdLabelBelowC),
          unit.formatDegrees(kVeryColdLabelAtOrBelowC),
        )),
        const SizedBox(height: 12),
        _BandRow(range: '60–79', label: t.bandComfortable, sampleMri: 70),
        const SizedBox(height: 12),
        // 「最適」は帯ではなくパーソナルな状態なので、快適行の直下に注記で出す。
        QuietNote(t.aboutMriOptimalNote),
        const SizedBox(height: 12),
        _BandRow(range: '40–59', label: t.bandWarm, sampleMri: 50),
        const SizedBox(height: _kBandGap),
        _BandRow(range: '20–39', label: t.bandHot, sampleMri: 30),
        const SizedBox(height: _kBandGap),
        _BandRow(range: '0–19', label: t.bandHotHydrate, sampleMri: 10),
        const SizedBox(height: 12),
        // 熱中症の危険度は MRI ではなく WBGT で判定する (混同を防ぐ)。
        QuietNote(t.aboutMriWbgtNote),
        const SizedBox(height: 26),

        // === 構成要素 (mri-spec §2 のサブスコア) ===
        // 花粉は出さない: 花粉データは未接続で、MRI も花粉の多寡では動かない
        // (欠測時の定数だけ。compliance-review-v1.3.0 §8 A2)。
        QuietSectionTitle(t.aboutMriFactorsTitle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final label in [
              t.statTemperature,
              t.statHumidity,
              t.statUv,
              t.statAqi,
              t.statWind,
              t.statPressure,
            ])
              _FactorChip(label: label),
          ],
        ),
        const SizedBox(height: 26),

        // === パーソナルキャリブレーション / 免責 (行頭ドットはニュートラル) ===
        QuietDotCard(
          title: t.aboutMriCalibrationTitle,
          body: t.aboutMriCalibrationBody,
        ),
        const SizedBox(height: 12),
        QuietDotCard(
          title: t.aboutMriDisclaimerTitle,
          body: t.aboutMriDisclaimerBody,
        ),
      ],
    );
  }
}

/// 帯の 1 行 (Figma 6:80)。**ドットだけが帯色**、範囲と帯名はニュートラル。
class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.range,
    required this.label,
    required this.sampleMri,
  });

  final String range;
  final String label;

  /// 帯の代表 MRI 値 (ドット色の算出に使う)。
  final int sampleMri;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    return QuietCardRow(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tokens.stateColorForMri(sampleMri),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Text(
              range,
              maxLines: 1,
              style: text.labelMedium?.copyWith(
                fontSize: type.label.fontSize(11),
                letterSpacing: 0,
                height: type.label.height(14 / 11),
                color: tokens.inkMid,
              ),
            ),
          ),
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
        ],
      ),
    );
  }
}

/// 構成要素のチップ (Figma 6:101: 高さ 30 / 角丸 15 / mono 9)。
class _FactorChip extends StatelessWidget {
  const _FactorChip({required this.label});

  final String label;

  /// チップの高さ (Figma 6:101)。上下の内側はこれに合わせて行送りから決める。
  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    // 高さ 30 = 枠 1 × 2 + 上下の内側 + 行送り (案2 は 16 → 上下 6。v1.3 は 12 → 8)。
    final vertical = ((_height - 2 - tag.lineHeight(12)) / 2).clamp(4.0, 8.0);
    // alignment は付けない — Wrap の中で親の最大幅まで伸びてしまう。
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: vertical),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(width: 1, color: tokens.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: tag.fontSize(9),
              letterSpacing: 0,
              fontWeight: FontWeight.w400,
              height: tag.height(12 / 9),
              color: tokens.inkMid,
            ),
      ),
    );
  }
}
