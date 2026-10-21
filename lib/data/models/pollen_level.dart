// lib/data/models/pollen_level.dart
//
// 花粉レベルのアプリ内正規化 enum (docs/mri-spec.md §2.5)。
// Open-Meteo / Google Pollen など供給元の段階表現をこの 5 段階へ写像する。

enum PollenLevel {
  none,
  low,
  moderate,
  high,
  veryHigh;

  /// 永続化・API 用の安定文字列。
  String get id => name;

  static PollenLevel parse(String? raw) {
    if (raw == null) return PollenLevel.low;
    return PollenLevel.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => PollenLevel.low,
    );
  }
}
