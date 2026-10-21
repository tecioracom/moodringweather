// lib/domain/safety/wbgt_calculator.dart
//
// WBGT (暑さ指数) 近似計算。docs/mri-spec.md §5 / spec.md §12.10 準拠。
// MRI とは独立の安全指標として並走計算する。純 Dart (Flutter 非依存)。
//
//   WBGT ≈ 0.7 × Tw + 0.2 × Tg + 0.1 × Ta
//   Tw: Stull (2011) の湿球温度近似
//   Tg: 屋外晴天近似 Tg = Ta + 0.038 × SR (SR 欠測・夜間は Tg = Ta)
//
// 注意 (mri-spec.md §5.4): 本判定は環境省・気象庁の公式「熱中症警戒アラート」
// ではなく Open-Meteo 由来データからの独自判定。ユーザー向け表示には必ず
// 免責文を併記すること。

import 'dart:math' as math;

/// 環境省 4 段階 + 安全域 (mri-spec.md §5.2。境界は下端含む)。
///
/// 本 enum は**アプリ内表示 (色・レベルラベル) 専用**の重症度分類であり、
/// 緊急通知をいつ出すかはここから導出しない。発火しきい値は EmergencyAdvisor
/// (WBGT ≥ 31 severe / ≥ 33 danger。mri-spec.md §5.3.1) が独立に定める。
enum WbgtLevel {
  /// WBGT < 21
  safe,

  /// 21 ≤ WBGT < 25: 注意 (Step-1 表示)
  caution,

  /// 25 ≤ WBGT < 28: 警戒 (Step-2 表示)
  warning,

  /// 28 ≤ WBGT < 31: 厳重警戒 (Step-3 表示)
  severe,

  /// WBGT ≥ 31: 危険 (Step-4 表示)
  danger,
}

class WbgtCalculator {
  WbgtCalculator._();

  /// WBGT (°C) を計算する。
  ///
  /// [tempC] 気温 Ta (°C)、[humidityPercent] 相対湿度 RH (%)、
  /// [solarRadiationWm2] 短波放射 SR (W/m²。null/夜間 = 0 扱い)。
  static double compute({
    required double tempC,
    required double humidityPercent,
    double? solarRadiationWm2,
  }) {
    final tw = wetBulbStull(tempC, humidityPercent);
    final tg = tempC + 0.038 * (solarRadiationWm2 ?? 0);
    return 0.7 * tw + 0.2 * tg + 0.1 * tempC;
  }

  /// Stull (2011) 湿球温度近似 (mri-spec.md §5.1)。
  static double wetBulbStull(double ta, double rh) {
    return ta * math.atan(0.151977 * math.sqrt(rh + 8.313659)) +
        math.atan(ta + rh) -
        math.atan(rh - 1.676331) +
        0.00391838 * math.pow(rh, 1.5) * math.atan(0.023101 * rh) -
        4.686035;
  }

  /// 環境省基準の段階判定 (下端含む)。
  static WbgtLevel level(double wbgt) {
    if (wbgt >= 31) return WbgtLevel.danger;
    if (wbgt >= 28) return WbgtLevel.severe;
    if (wbgt >= 25) return WbgtLevel.warning;
    if (wbgt >= 21) return WbgtLevel.caution;
    return WbgtLevel.safe;
  }
}
