// lib/domain/mri/cold_label.dart
//
// 寒さの区分名の判定 (docs/mri-spec.md §4「cool 帯のラベル細分」)。純 Dart。
//
// MRI は体感 −4 °C 前後で Δcool が上限に達し、それより寒いと値が横ばいになる
// ため、値だけでは「快適な冷涼」と「危険な酷寒」を区別できない (§10)。表示する
// 区分名だけを体感温度 T_app (§3.2 と同じ。欠測時は気温) で決める。MRI の値・
// 帯の境界・色は変えない。判定は丸める前の T_app で行う。

import 'mri_band.dart';

/// cool 帯で「寒い」にする体感温度 (°C)。これ未満で寒い。
/// 「気温 10 °C 未満 = 寒い」を体感温度に換算した値 (冬の気温 − 体感温度は
/// 中央値 4.0–4.6 °C。東京・札幌の 12–2 月、2016–2025)。
const double kColdLabelBelowC = 6.0;

/// 「とても寒い — 防寒を」にする体感温度 (°C)。これ以下 (帯を問わない)。
/// Environment Canada の風冷指数の moderate risk の下端。
const double kVeryColdLabelAtOrBelowC = -10.0;

/// 寒さの区分名。
enum ColdLabel {
  /// 寒さで区分名を変えない (帯の区分名のまま)。
  none,

  /// 「寒い」(cool 帯の中だけ)。
  cold,

  /// 「とても寒い — 防寒を」。**帯を問わず、OPTIMAL の昇格より優先**する。
  /// キャリブレーションで寒さに強いと学習した人は、厳寒でも comfortable (緑) に
  /// なり得るため (寒さの側には WBGT のような独立した安全指標が無い)。
  veryCold,
}

/// [band] と体感温度 [apparentTemperature] (°C。分からなければ null) から
/// 寒さの区分名を決める。体感温度が分からなければ [ColdLabel.none]。
ColdLabel coldLabelFor(MriBand band, double? apparentTemperature) {
  final tApp = apparentTemperature;
  if (tApp == null || tApp.isNaN) return ColdLabel.none;
  if (tApp <= kVeryColdLabelAtOrBelowC) return ColdLabel.veryCold;
  if (band == MriBand.cool && tApp < kColdLabelBelowC) return ColdLabel.cold;
  return ColdLabel.none;
}
