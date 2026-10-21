// lib/domain/calibration/calibration_feedback.dart
//
// 体感フィードバックの 5 段階 (v1.0 Figma の Calibration Tag 画面)。
// mri-spec.md §6.2 の y ∈ {+1: 暑すぎ, 0: ちょうど, −1: 寒すぎ} へ写像する。
// 「やや暑/やや寒」は同方向 y のまま学習量 (intensity) を半分にする拡張。
//
// 純 Dart (Flutter 非依存)。

enum CalibrationFeedback {
  /// 暑すぎ (y = +1)
  tooHot(direction: 1, intensity: 1.0),

  /// やや暑 (y = +1、学習量 1/2)
  slightlyHot(direction: 1, intensity: 0.5),

  /// ちょうど (y = 0)
  justRight(direction: 0, intensity: 1.0),

  /// やや寒 (y = −1、学習量 1/2)
  slightlyCool(direction: -1, intensity: 0.5),

  /// 寒すぎ (y = −1)
  tooCold(direction: -1, intensity: 1.0);

  const CalibrationFeedback({required this.direction, required this.intensity});

  /// mri-spec.md §6.2 の y。
  final int direction;

  /// 更新則に乗じる学習量係数 (やや暑/やや寒 = 0.5)。
  final double intensity;
}
