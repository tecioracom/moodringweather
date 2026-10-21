// lib/domain/mri/mri_calculator.dart
//
// MRI (Mood Ring Index) 算出ロジック。docs/mri-spec.md v1.0 を厳密に踏襲する。
// 式・係数を変更する場合は必ず mri-spec.md を先に改訂すること。
//
// 純 Dart (Flutter 非依存)。ユニットテスト: test/unit/mri_calculator_test.dart
// (mri-spec.md §8 の qa 期待値テーブルと 1:1 対応)。
//
// パイプライン (mri-spec.md §1):
//   ① サブスコア score_xxx() ∈ [0,100]            … §2
//   ② MRI_base = Σ w_i × s_i                      … §3.1
//   ③ raw = k_anchor × MRI_base + Δcool − Δheat   … §3.2
//   ④ パーソナル補正 (v1.0 は weights 差し替えのみ) … §6
//   ⑤ clamp(0,100) → round → MRI(int)
//   ⑥ バンド判定 MriBand.fromValue()              … §4

import '../../data/models/mood_ring_index.dart';
import '../../data/models/personal_profile.dart';
import '../../data/models/pollen_level.dart';
import '../../data/models/weather_snapshot.dart';
import 'mri_band.dart';

class MriCalculator {
  MriCalculator._();

  /// デフォルト重み (mri-spec.md §3.1。合計 1.0)。
  static const Map<String, double> defaultWeights = {
    'temp': 0.30,
    'humid': 0.20,
    'uv': 0.10,
    'aqi': 0.15,
    'pollen': 0.10,
    'wind': 0.05,
    'pressure': 0.10,
  };

  /// 参照快適日 (22°C/50%/UV3/AQI42/low/2m/s/気圧安定) の MRI_base 94.61 を
  /// デザインアンカー MRI 64 へ写像する縮尺係数 (mri-spec.md §3.2)。
  static const double kAnchor = 0.68;

  /// 欠測時フォールバック score (mri-spec.md §2.8)。
  static const double fallbackHumidScore = 80;
  static const double fallbackUvScore = 100;
  static const double fallbackAqiScore = 75;
  static const double fallbackPollenScore = 90;
  static const double fallbackWindScore = 95;
  static const double fallbackPressureScore = 70;

  /// パーソナル補正の表示差分上限 (mri-spec.md §6.4):
  /// |MRI_personal − MRI_default| ≤ 15 を設計保証する安全クランプ。
  static const double maxPersonalDelta = 15.0;

  /// MRI を計算する。
  ///
  /// [weights] はカスタム重み (未学習時は null → [defaultWeights])。合計が
  /// 1.0 でない場合は正規化し、合計 0 以下ならデフォルト重みへ
  /// フォールバックする。
  ///
  /// [profile] は学習済みの感受性ベクトル θ (mri-spec.md §6)。ランプイン
  /// (§6.3-1) を内部で適用するため、n < 5 ではデフォルト計算と一致する。
  /// null または θ が既定値のままならパーソナル補正なし。
  static MoodRingIndex calculate(
    WeatherSnapshot snapshot, {
    Map<String, double>? weights,
    PersonalProfile? profile,
  }) {
    // §6.3-1 ランプイン適用後の実効 θ。既定値のままなら補正なし扱い。
    final theta = profile?.rampScaled();
    final personalized = theta != null && !theta.isNeutral;

    final defaultRaw = _rawMri(snapshot, _normalizedWeights(weights), null);
    final result = personalized
        ? _rawMri(snapshot, _normalizedWeights(weights), theta)
        : defaultRaw;

    // §6.4 ガード: 補正前後の差を ±15 にクランプ (qa プロパティテスト要件)。
    var raw = result.raw;
    if (personalized) {
      raw = raw.clamp(
        defaultRaw.raw - maxPersonalDelta,
        defaultRaw.raw + maxPersonalDelta,
      );
    }

    final value = raw.clamp(0.0, 100.0).round();
    return MoodRingIndex(
      value: value,
      band: MriBand.fromValue(value),
      factorContributions: result.contributions,
      thermalAdjustment: result.thermalAdjustment,
      isPersonalized: personalized,
      calculatedAt: snapshot.timestamp,
    );
  }

  /// パイプライン ①〜③ (＋④ θ 適用) を実行し、丸め前の raw を返す。
  static _RawMri _rawMri(
    WeatherSnapshot snapshot,
    Map<String, double> baseWeights,
    PersonalProfile? theta,
  ) {
    // §6.1 正規化: w'_i = w_i × (1 + β_i) → 合計 1.0 に再正規化。
    var w = baseWeights;
    if (theta != null) {
      final betas = theta.betaByFactor;
      w = _normalizedWeights(
        baseWeights.map((k, v) => MapEntry(k, v * (1 + (betas[k] ?? 0.0)))),
      );
    }

    // §6.1: T_opt = 22 + δT。
    final deltaTShift = theta?.deltaT ?? 0.0;
    final scores = computeFactorScores(snapshot, tOpt: 22.0 + deltaTShift);

    var base = 0.0;
    final contributions = <String, double>{};
    for (final entry in w.entries) {
      final s = scores[entry.key] ?? 50.0;
      final contribution = s * entry.value;
      contributions[entry.key] = contribution;
      base += contribution;
    }

    // §3.2 アンカー縮尺 + 温冷方向補正。体感温度欠測時は気温で代用 (§2.8)。
    // ピボット 18/28 は δT に追従、λ_cool/λ_heat はキャリブレーション係数。
    final tApp = snapshot.apparentTemperature ?? snapshot.temperature;
    final deltaCool = (theta?.lambdaCool ?? 1.0) *
        2.2 *
        (18.0 + deltaTShift - tApp).clamp(0.0, 22.0);
    final deltaHeat = (theta?.lambdaHeat ?? 1.0) *
        1.5 *
        (tApp - (28.0 + deltaTShift)).clamp(0.0, 15.0);
    // personalOffset は v1.0 では 0 固定 (将来拡張用フック。§3.2)。
    final raw = kAnchor * base + deltaCool - deltaHeat;
    return _RawMri(
      raw: raw,
      contributions: contributions,
      thermalAdjustment: deltaCool - deltaHeat,
    );
  }

  /// 7 要素のサブスコアを欠測フォールバック込みで算出する (mri-spec.md §2)。
  /// [tOpt] はキャリブレーション後の最適温度 (22 + δT。§6.1)。
  static Map<String, double> computeFactorScores(
    WeatherSnapshot s, {
    double tOpt = 22.0,
  }) {
    return {
      'temp': scoreTemperature(s.temperature, tOpt: tOpt),
      'humid': s.humidity == null
          ? fallbackHumidScore
          : scoreHumidity(s.humidity!, s.temperature),
      'uv': s.uvIndex == null ? fallbackUvScore : scoreUv(s.uvIndex!),
      'aqi': s.aqi == null ? fallbackAqiScore : scoreAqi(s.aqi!),
      'pollen': s.pollen == null ? fallbackPollenScore : scorePollen(s.pollen!),
      'wind': s.windSpeed == null
          ? fallbackWindScore
          : scoreWind(s.windSpeed!, s.temperature),
      'pressure': s.pressureChange6h == null
          ? fallbackPressureScore
          : scorePressure(s.pressureChange6h!),
    };
  }

  /// §2.1 気温: 22°C 頂点の対称な釣鐘曲線。
  static double scoreTemperature(double t, {double tOpt = 22.0}) =>
      _clamp(100 - 3.5 * (t - tOpt).abs());

  /// §2.2 湿度: 50% 最適。多湿側は高温ほど勾配 a(T) が急になる。
  static double scoreHumidity(double h, double t) {
    if (h >= 50) {
      final double a = t < 24
          ? 0.6
          : t < 28
              ? 1.2
              : t < 32
                  ? 1.8
                  : 2.4;
      return _clamp(100 - a * (h - 50));
    }
    return _clamp(100 - 0.7 * (50 - h));
  }

  /// §2.3 UV: WHO UV インデックス区分に整合する線形。
  static double scoreUv(double uv) => _clamp(105 - 10 * uv);

  /// §2.4 空気質: US AQI 区分準拠の折れ線 (連続・単調減少)。
  static double scoreAqi(int a) {
    if (a <= 50) return _clamp(100 - 0.30 * a);
    if (a <= 100) return _clamp(85 - 0.50 * (a - 50));
    if (a <= 150) return _clamp(60 - 0.40 * (a - 100));
    if (a <= 200) return _clamp(40 - 0.40 * (a - 150));
    if (a <= 300) return _clamp(20 - 0.20 * (a - 200));
    return 0;
  }

  /// §2.5 花粉: 段階テーブル。
  static double scorePollen(PollenLevel p) {
    switch (p) {
      case PollenLevel.none:
        return 100;
      case PollenLevel.low:
        return 90;
      case PollenLevel.moderate:
        return 60;
      case PollenLevel.high:
        return 30;
      case PollenLevel.veryHigh:
        return 10;
    }
  }

  /// §2.6 風: 強風 (P_gust)・高温無風 (P_stag)・低温風冷 (P_chill)。
  static double scoreWind(double v, double t) {
    final gust = 4.5 * _max0(v - 3);
    final stagnation = t >= 28 ? 8 * _max0(1 - v) : 0.0;
    final chill = t <= 10 ? 2.0 * _max0(v - 1) : 0.0;
    return _clamp(100 - gust - stagnation - chill);
  }

  /// §2.7 気圧: 6 時間変化 Δp6h。低下を重く (×12)、上昇を軽く (×6)。
  static double scorePressure(double deltaP6h) {
    if (deltaP6h.abs() <= 1) return 100;
    if (deltaP6h < -1) return _clamp(100 - 12 * (deltaP6h.abs() - 1));
    return _clamp(100 - 6 * (deltaP6h - 1));
  }

  static Map<String, double> _normalizedWeights(Map<String, double>? weights) {
    if (weights == null) return defaultWeights;
    final sum = weights.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return defaultWeights;
    if ((sum - 1.0).abs() < 1e-9) return weights;
    return weights.map((k, v) => MapEntry(k, v / sum));
  }

  static double _clamp(double x) => x.clamp(0.0, 100.0);

  static double _max0(double x) => x > 0 ? x : 0.0;
}

/// _rawMri の内部結果 (丸め前)。
class _RawMri {
  const _RawMri({
    required this.raw,
    required this.contributions,
    required this.thermalAdjustment,
  });

  final double raw;
  final Map<String, double> contributions;
  final double thermalAdjustment;
}
