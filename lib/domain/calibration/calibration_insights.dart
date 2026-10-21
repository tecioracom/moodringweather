// lib/domain/calibration/calibration_insights.dart
//
// 学習済み θ から「わかってきたこと」(Calibration Home の洞察リスト) を
// 導出する純 Dart ヘルパー。閾値は v1.0 暫定 (UI 表示のみに使用し、
// MRI 計算には影響しない)。

import '../../data/models/personal_profile.dart';

enum CalibrationInsight {
  /// δT が負: 本人の最適温度は標準 (22°C) より低い = 暑がり傾向。
  prefersCooler,

  /// δT が正: 最適温度は標準より高い = 寒がり傾向。
  prefersWarmer,

  /// λ_heat が高い: 暑さを強く感じる。
  heatSensitive,

  /// λ_cool が高い: 寒さを強く感じる。
  coldSensitive,

  /// β_humid が高い: 湿度に敏感。
  humiditySensitive,

  /// β_uv が高い: 日射 (UV) に敏感。
  uvSensitive,

  /// β_aqi が高い: 空気質に敏感。
  airQualitySensitive,

  /// β_pollen が高い: 花粉に敏感。
  pollenSensitive,
}

class CalibrationInsights {
  CalibrationInsights._();

  static const double _deltaTThreshold = 0.5;
  static const double _lambdaThreshold = 1.08;
  static const double _betaThreshold = 0.08;

  /// 表示順 = 影響の大きい順 (温度シフト → 倍率 → 要素感受性)。
  static List<CalibrationInsight> derive(PersonalProfile p) {
    final insights = <CalibrationInsight>[];
    if (p.deltaT <= -_deltaTThreshold) {
      insights.add(CalibrationInsight.prefersCooler);
    } else if (p.deltaT >= _deltaTThreshold) {
      insights.add(CalibrationInsight.prefersWarmer);
    }
    if (p.lambdaHeat >= _lambdaThreshold) {
      insights.add(CalibrationInsight.heatSensitive);
    }
    if (p.lambdaCool >= _lambdaThreshold) {
      insights.add(CalibrationInsight.coldSensitive);
    }
    if (p.betaHumid >= _betaThreshold) {
      insights.add(CalibrationInsight.humiditySensitive);
    }
    if (p.betaUv >= _betaThreshold) {
      insights.add(CalibrationInsight.uvSensitive);
    }
    if (p.betaAqi >= _betaThreshold) {
      insights.add(CalibrationInsight.airQualitySensitive);
    }
    if (p.betaPollen >= _betaThreshold) {
      insights.add(CalibrationInsight.pollenSensitive);
    }
    return insights;
  }
}
