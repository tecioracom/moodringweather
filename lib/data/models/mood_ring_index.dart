// lib/data/models/mood_ring_index.dart
//
// MRI 計算結果 (docs/mri-spec.md §1, §9)。純 Dart。

import '../../domain/mri/mri_band.dart';

class MoodRingIndex {
  const MoodRingIndex({
    required this.value,
    required this.band,
    required this.factorContributions,
    required this.calculatedAt,
    this.thermalAdjustment = 0.0,
    this.isPersonalized = false,
  });

  /// 最終 MRI (0–100 の int。途中計算は丸めず最終値のみ round)。
  final int value;

  final MriBand band;

  /// MRI_base への寄与 (w_i × s_i)。詳細画面の要素分解カード用
  /// (mri-spec.md §9: Δcool/Δheat は含めない)。
  final Map<String, double> factorContributions;

  /// 温冷方向補正 Δcool − Δheat (mri-spec.md §3.2 / §9 thermalAdjustment)。
  final double thermalAdjustment;

  /// パーソナル補正 (感受性ベクトル θ) が適用されたか (mri-spec.md §6.4:
  /// 「あなたの感受性プロファイル適用済み」ラベルの表示判定)。
  final bool isPersonalized;

  final DateTime calculatedAt;
}
