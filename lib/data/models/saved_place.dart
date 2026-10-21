// lib/data/models/saved_place.dart
//
// 保存地点 (Plus 多地点。spec.md §12.11.5) の表示・取得用の値。純 Dart。
//
// 正本は ComfortRecord (type = place) で、本クラスはそこから解決した読み取り
// 専用のビュー (domain/places/saved_place_rules.dart の resolveSavedPlaces)。
// 旧記録で座標を補えない地点は [location] が null になる。
//
// 値の等価性を持つ (Riverpod の Provider が「中身が同じなら再通知しない」ため。
// 無関係な記録の追加で保存地点の天気を取り直さない)。

import 'place_location.dart';

/// 保存地点 ID の接頭辞。
const String kSavedPlaceIdPrefix = 'place-';

/// 地名検索 (Open-Meteo Geocoding) 由来の保存地点 ID の接頭辞。
const String kGeocodedPlaceIdPrefix = 'place-geo-';

/// 地名検索の結果 (GeoNames id) から保存地点 ID を作る。
String savedPlaceIdForGeocoding(int geocodingId) =>
    '$kGeocodedPlaceIdPrefix$geocodingId';

/// Comfort-Twin の同梱カタログ都市から保存地点 ID を作る (既存の命名)。
String savedPlaceIdForCatalogCity(String cityId) =>
    '$kSavedPlaceIdPrefix$cityId';

/// 保存地点の出どころ。
enum SavedPlaceSource {
  /// 地名検索 (Open-Meteo Geocoding) で追加。
  geocoding,

  /// Comfort-Twin の比較画面「この場所を保存」(同梱カタログの都市)。
  comfortTwin,
}

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.addedAt,
    this.location,
    this.emoji,
    this.recordedMri,
  });

  /// `place-geo-{geonamesId}` / `place-{cityId}`。
  final String id;

  /// 表示名 (例: 京都)。
  final String name;

  /// 位置と地域情報。旧記録でカタログから補えない場合は null。
  final PlaceLocation? location;

  /// 追加した時刻 (並び順 = 追加順)。
  final DateTime addedAt;

  /// 国旗など (Comfort-Twin 由来のみ)。
  final String? emoji;

  /// Comfort-Twin で保存した時点の MRI (**現在値ではない**)。地名検索由来は null。
  final int? recordedMri;

  SavedPlaceSource get source => id.startsWith(kGeocodedPlaceIdPrefix)
      ? SavedPlaceSource.geocoding
      : SavedPlaceSource.comfortTwin;

  /// 天気を取得できる座標があるか。
  bool get hasCoordinates => location != null;

  /// Comfort-Twin 由来ならカタログの都市 ID (例: 'lisbon')。それ以外は null。
  String? get catalogCityId {
    if (source != SavedPlaceSource.comfortTwin) return null;
    if (!id.startsWith(kSavedPlaceIdPrefix)) return null;
    final cityId = id.substring(kSavedPlaceIdPrefix.length);
    return cityId.isEmpty ? null : cityId;
  }

  /// 地域行の要素 (市区町村 → 都道府県・州 → 国)。座標なしの旧記録は空。
  List<String> get regionParts => location?.regionParts ?? const [];

  @override
  bool operator ==(Object other) =>
      other is SavedPlace &&
      other.id == id &&
      other.name == name &&
      other.location == location &&
      other.addedAt == addedAt &&
      other.emoji == emoji &&
      other.recordedMri == recordedMri;

  @override
  int get hashCode =>
      Object.hash(id, name, location, addedAt, emoji, recordedMri);

  @override
  String toString() => 'SavedPlace($id, $name)';
}
