// lib/presentation/shared/band_label.dart
//
// ホームのリングの下に出す帯名 (区分名)。ライブ壁紙の重ね描きの 2 行目も同じ語を
// 使う (docs/design-wallpaper-weather-overlay.md §1: 壁紙とアプリで同じ状態を別の語で
// 呼ばない)。色は区分のまま (最適も快適の緑。stateColorForMri / 壁紙の配色)。

import '../../data/models/mood_ring_index.dart';
import '../../domain/mri/cold_label.dart';
import '../../domain/mri/mri_band.dart';
import '../../l10n/app_localizations.dart';

/// 最適 (OPTIMAL) に昇格する、推定最適 MRI からの距離の上限 (mri-spec.md §4)。
const int kOptimalBandTolerance = 4;

/// 帯名。OPTIMAL は固定バンドではなくパーソナル状態 (mri-spec.md §4): comfortable
/// かつ |MRI − estimatedOptimalMRI| ≤ 4 のときだけ昇格表示する (未学習時の推定最適は
/// 64)。とても暑いは「— 水分補給を」まで (bandHotHydrate)。
///
/// 寒さの側は体感温度 [apparentTemperature] (°C。無ければ気温) で区分名を変える
/// (domain/mri/cold_label.dart、mri-spec.md §4)。MRI は寒さで 100 付近に張り付き、
/// 南極点 (体感 −62°) でも「涼しい」と出ていたため。体感 −10° 以下は帯を問わず
/// 「とても寒い — 防寒を」(OPTIMAL より優先)、cool 帯で体感 6° 未満は「寒い」。
/// 色は帯のまま。体感温度が分からないとき (推定最適値などの値だけ) は従来どおり。
String mriBandLabel(
  AppLocalizations t,
  MoodRingIndex mri, {
  required int optimalMri,
  double? apparentTemperature,
}) {
  switch (coldLabelFor(mri.band, apparentTemperature)) {
    case ColdLabel.veryCold:
      return t.bandVeryColdBundleUp;
    case ColdLabel.cold:
      return t.bandCold;
    case ColdLabel.none:
      break;
  }
  if (mri.band == MriBand.comfortable &&
      (mri.value - optimalMri).abs() <= kOptimalBandTolerance) {
    return t.bandOptimal;
  }
  switch (mri.band) {
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
