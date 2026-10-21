// lib/data/models/city.dart
//
// Comfort-Twin の候補都市 (assets/cities.json の 1 エントリ)。純 Dart。
// カタログはアプリ同梱の静的データで、ユーザー位置情報とは無関係
// (spec.md §13: 位置の履歴は保持しない)。

class City {
  const City({
    required this.id,
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.emoji,
  });

  /// カタログ内で一意な安定 ID (例: 'tokyo')。保存記録の参照キー。
  final String id;

  /// 都市名 (英語表記。固有名詞のため翻訳しない)。
  final String name;

  /// 国名 (英語表記)。
  final String country;

  final double latitude;
  final double longitude;

  /// 国旗等の絵文字 (リスト・マップ表示用)。
  final String emoji;

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      id: json['id'] as String,
      name: json['name'] as String,
      country: json['country'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      emoji: (json['emoji'] as String?) ?? '🌍',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'emoji': emoji,
      };
}
