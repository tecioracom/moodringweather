// lib/domain/metrics/metric_levels.dart
//
// UV と空気質の段階 (指標タイルの段階語。docs/design-metric-units-proposal.md
// §2.2・§2.3)。公式の区分だけを使う (独自の健康判断を作らない):
//   UV     … WHO「Global Solar UV Index」・気象庁の 5 区分
//   空気質 … US EPA AQI の 6 区分 (値は Open-Meteo の `us_aqi`)
// MRI の採点 (docs/mri-spec.md §2.3 / §2.4) も同じ区分に合わせてある。
//
// 段階は **表示している整数** で決める (「3」と表示して「弱い」にならないように)。
// UV は uvIndex の四捨五入 ([shownUvIndex])、空気質は整数の US AQI をそのまま。
// 純 Dart (Flutter 非依存) — ユニットテスト対象。

/// タイルに表示する UV の整数 (uvIndex の四捨五入)。段階もこの値で決める。
int shownUvIndex(double uvIndex) => uvIndex.round();

/// UV インデックスの 5 区分 (WHO・気象庁)。
enum UvLevel {
  /// 0〜2 (夜間の 0 も含む)。弱い / Low。
  low,

  /// 3〜5。中程度 / Moderate。
  moderate,

  /// 6〜7。強い / High。
  high,

  /// 8〜10。非常に強い / Very high。
  veryHigh,

  /// 11 以上。極端に強い / Extreme。
  extreme;

  /// 表示している整数 [shownUv] の区分。負の値 (データの誤り) は [low]。
  static UvLevel of(int shownUv) {
    if (shownUv <= 2) return UvLevel.low;
    if (shownUv <= 5) return UvLevel.moderate;
    if (shownUv <= 7) return UvLevel.high;
    if (shownUv <= 10) return UvLevel.veryHigh;
    return UvLevel.extreme;
  }
}

/// US AQI の 6 区分 (US EPA)。
enum AqiLevel {
  /// 0〜50。Good。
  good,

  /// 51〜100。Moderate。
  moderate,

  /// 101〜150。Unhealthy for Sensitive Groups (タイルの en は短縮語)。
  unhealthyForSensitiveGroups,

  /// 151〜200。Unhealthy。
  unhealthy,

  /// 201〜300。Very Unhealthy (タイルの en は短縮語)。
  veryUnhealthy,

  /// 301 以上。Hazardous。
  hazardous;

  /// 整数の US AQI [usAqi] の区分。負の値 (データの誤り) は [good]。
  static AqiLevel of(int usAqi) {
    if (usAqi <= 50) return AqiLevel.good;
    if (usAqi <= 100) return AqiLevel.moderate;
    if (usAqi <= 150) return AqiLevel.unhealthyForSensitiveGroups;
    if (usAqi <= 200) return AqiLevel.unhealthy;
    if (usAqi <= 300) return AqiLevel.veryUnhealthy;
    return AqiLevel.hazardous;
  }
}
