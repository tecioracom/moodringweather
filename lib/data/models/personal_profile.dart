// lib/data/models/personal_profile.dart
//
// パーソナルキャリブレーションの感受性ベクトル θ (docs/mri-spec.md §6.1)。
// すべてオンデバイス保存・リセット可能 (spec.md §13 / mri-spec.md §0:
// サーバー・Firestore へは送信しない)。
//
// 純 Dart (Flutter 非依存)。更新則は domain/calibration/calibration_engine.dart、
// MRI への適用は domain/mri/mri_calculator.dart (§6.1 正規化)。

/// 感受性ベクトル θ + 学習メタデータ (mri-spec.md §6.1)。
class PersonalProfile {
  const PersonalProfile({
    this.deltaT = 0.0,
    this.lambdaHeat = 1.0,
    this.lambdaCool = 1.0,
    this.betaHumid = 0.0,
    this.betaUv = 0.0,
    this.betaAqi = 0.0,
    this.betaPollen = 0.0,
    this.mOpt = defaultMOpt,
    this.feedbackCount = 0,
    this.manualOverride = false,
    this.lastFeedbackDayByDirection = const {},
  });

  /// 未学習の既定プロファイル (θ = §6.1 の既定値)。
  factory PersonalProfile.initial() => const PersonalProfile();

  // === クランプ範囲 (mri-spec.md §6.1) ===
  static const double deltaTMin = -3.0;
  static const double deltaTMax = 3.0;
  static const double lambdaMin = 0.7;
  static const double lambdaMax = 1.5;
  static const double betaMin = -0.5;
  static const double betaMax = 0.5;
  static const double mOptMin = 50.0;
  static const double mOptMax = 85.0;

  /// 未学習時の estimatedOptimalMRI (デザインアンカー 64)。
  static const double defaultMOpt = 64.0;

  /// ランプイン境界 (mri-spec.md §6.3-1): n < 5 は不適用、
  /// 5 ≤ n < 20 は線形スケール、n ≥ 20 で全量適用。
  static const int rampInStart = 5;
  static const int rampInFull = 20;

  /// δT: 最適温度シフト (T_opt = 22 + δT。Δcool/Δheat ピボットも同シフト)。
  final double deltaT;

  /// λ_heat: 暑熱感受性 (Δheat 倍率)。
  final double lambdaHeat;

  /// λ_cool: 寒冷感受性 (Δcool 倍率)。
  final double lambdaCool;

  /// β_humid / β_uv / β_aqi / β_pollen: 要素感受性 (重み補正)。
  final double betaHumid;
  final double betaUv;
  final double betaAqi;
  final double betaPollen;

  /// M_opt: estimatedOptimalMRI の連続値 (表示時に round)。
  final double mOpt;

  /// n: 有効フィードバック数。
  final int feedbackCount;

  /// 体感プロファイル画面からの手動調整があった場合 true。
  /// 手動調整はユーザーの明示操作なのでランプインを通さず全量適用する。
  final bool manualOverride;

  /// 同日重複ガード (mri-spec.md §6.3-5) 用: 方向 ('hot'/'neutral'/'cold')
  /// → 最後に受理したカレンダー日 ('yyyy-mm-dd')。
  final Map<String, String> lastFeedbackDayByDirection;

  /// spec §3.4 の派生値 estimatedOptimalMRI (int 表示用)。
  int get estimatedOptimalMri => mOpt.round();

  /// θ が既定値のままか (= 適用しても MRI が変わらない)。
  bool get isNeutral =>
      deltaT == 0.0 &&
      lambdaHeat == 1.0 &&
      lambdaCool == 1.0 &&
      betaHumid == 0.0 &&
      betaUv == 0.0 &&
      betaAqi == 0.0 &&
      betaPollen == 0.0;

  /// ランプイン係数 (mri-spec.md §6.3-1)。手動調整時は常に 1.0。
  double get rampScale {
    if (manualOverride) return 1.0;
    if (feedbackCount < rampInStart) return 0.0;
    if (feedbackCount >= rampInFull) return 1.0;
    return (feedbackCount - rampInStart) / (rampInFull - rampInStart);
  }

  /// 学習進度 (UI 表示用 0–1)。全量適用となる n = 20 を 100% とする。
  double get learningProgress => manualOverride
      ? 1.0
      : (feedbackCount / rampInFull).clamp(0.0, 1.0).toDouble();

  /// ランプイン適用後の実効 θ。各パラメータを既定値との線形補間で縮小する。
  PersonalProfile rampScaled() {
    final s = rampScale;
    if (s >= 1.0) return this;
    return copyWith(
      deltaT: deltaT * s,
      lambdaHeat: 1.0 + (lambdaHeat - 1.0) * s,
      lambdaCool: 1.0 + (lambdaCool - 1.0) * s,
      betaHumid: betaHumid * s,
      betaUv: betaUv * s,
      betaAqi: betaAqi * s,
      betaPollen: betaPollen * s,
    );
  }

  /// MriCalculator の重み補正用 (mri-spec.md §6.1):
  /// β を持たない temp/wind/pressure は 0 扱い。
  Map<String, double> get betaByFactor => {
        'humid': betaHumid,
        'uv': betaUv,
        'aqi': betaAqi,
        'pollen': betaPollen,
      };

  /// 全パラメータを §6.1 のハードレンジへクランプした複製。
  PersonalProfile clamped() => copyWith(
        deltaT: deltaT.clamp(deltaTMin, deltaTMax),
        lambdaHeat: lambdaHeat.clamp(lambdaMin, lambdaMax),
        lambdaCool: lambdaCool.clamp(lambdaMin, lambdaMax),
        betaHumid: betaHumid.clamp(betaMin, betaMax),
        betaUv: betaUv.clamp(betaMin, betaMax),
        betaAqi: betaAqi.clamp(betaMin, betaMax),
        betaPollen: betaPollen.clamp(betaMin, betaMax),
        mOpt: mOpt.clamp(mOptMin, mOptMax),
      );

  PersonalProfile copyWith({
    double? deltaT,
    double? lambdaHeat,
    double? lambdaCool,
    double? betaHumid,
    double? betaUv,
    double? betaAqi,
    double? betaPollen,
    double? mOpt,
    int? feedbackCount,
    bool? manualOverride,
    Map<String, String>? lastFeedbackDayByDirection,
  }) {
    return PersonalProfile(
      deltaT: deltaT ?? this.deltaT,
      lambdaHeat: lambdaHeat ?? this.lambdaHeat,
      lambdaCool: lambdaCool ?? this.lambdaCool,
      betaHumid: betaHumid ?? this.betaHumid,
      betaUv: betaUv ?? this.betaUv,
      betaAqi: betaAqi ?? this.betaAqi,
      betaPollen: betaPollen ?? this.betaPollen,
      mOpt: mOpt ?? this.mOpt,
      feedbackCount: feedbackCount ?? this.feedbackCount,
      manualOverride: manualOverride ?? this.manualOverride,
      lastFeedbackDayByDirection:
          lastFeedbackDayByDirection ?? this.lastFeedbackDayByDirection,
    );
  }

  Map<String, dynamic> toJson() => {
        'deltaT': deltaT,
        'lambdaHeat': lambdaHeat,
        'lambdaCool': lambdaCool,
        'betaHumid': betaHumid,
        'betaUv': betaUv,
        'betaAqi': betaAqi,
        'betaPollen': betaPollen,
        'mOpt': mOpt,
        'feedbackCount': feedbackCount,
        'manualOverride': manualOverride,
        'lastFeedbackDayByDirection': lastFeedbackDayByDirection,
      };

  factory PersonalProfile.fromJson(Map<String, dynamic> json) {
    double asDouble(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    final rawDays = json['lastFeedbackDayByDirection'];
    final days = <String, String>{};
    if (rawDays is Map) {
      rawDays.forEach((k, v) {
        if (k is String && v is String) days[k] = v;
      });
    }
    // 破損・将来仕様変更に備え、復元時もハードレンジへクランプする。
    return PersonalProfile(
      deltaT: asDouble(json['deltaT'], 0.0),
      lambdaHeat: asDouble(json['lambdaHeat'], 1.0),
      lambdaCool: asDouble(json['lambdaCool'], 1.0),
      betaHumid: asDouble(json['betaHumid'], 0.0),
      betaUv: asDouble(json['betaUv'], 0.0),
      betaAqi: asDouble(json['betaAqi'], 0.0),
      betaPollen: asDouble(json['betaPollen'], 0.0),
      mOpt: asDouble(json['mOpt'], defaultMOpt),
      feedbackCount: json['feedbackCount'] is int
          ? json['feedbackCount'] as int
          : (json['feedbackCount'] as num?)?.toInt() ?? 0,
      manualOverride: json['manualOverride'] == true,
      lastFeedbackDayByDirection: days,
    ).clamped();
  }
}
