// lib/data/models/place_candidate.dart
//
// 地名検索 (Open-Meteo Geocoding API) の結果。純 Dart。
//
//   - GeocodingHit: API の 1 件をそのまま写した値 (補正前)
//   - PlaceCandidate: 補正・並べ替え後に UI の候補行へ出す値
//     (domain/places/place_search_rules.dart の rankPlaceCandidates が作る)
//
// 候補の時点では天気は取得しない (Figma: 候補行に MRI を出さない)。

import 'place_location.dart';
import 'saved_place.dart';

/// Open-Meteo Geocoding の 1 件 (補正前)。
///
/// 応答例 (2026-09-28 実測、language=ja、「京都市」):
///   {"id":1857910,"name":"京都市","latitude":35.02107,"longitude":135.75385,
///    "feature_code":"PPLA","country_code":"JP","admin1":"京都府",
///    "admin2":"京都市","admin3":"上京区","timezone":"Asia/Tokyo",
///    "population":1463723,"country":"日本", ...}
class GeocodingHit {
  const GeocodingHit({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.featureCode,
    this.countryCode,
    this.country,
    this.admin1,
    this.admin2,
    this.admin3,
    this.admin4,
    this.timezone,
    this.population,
  });

  /// GeoNames id。
  final int id;
  final String name;
  final double latitude;
  final double longitude;

  /// GeoNames の feature code (例: PPLA / PPL / AIRP / PRK)。
  final String? featureCode;
  final String? countryCode;
  final String? country;

  /// 都道府県・州。
  final String? admin1;

  /// 日本では市・郡・特別区 (例: 京都市 / 児玉郡 / 新宿区)。
  final String? admin2;

  /// 日本では区・町・村 (例: 上京区 / 神川町)。
  final String? admin3;
  final String? admin4;
  final String? timezone;
  final int? population;

  /// API の 1 件を読む。id・名前・座標が欠ける項目は null (候補から外す)。
  static GeocodingHit? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final lat = json['latitude'];
    final lon = json['longitude'];
    if (id is! num || name is! String || name.trim().isEmpty) return null;
    if (lat is! num || lon is! num) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    String? str(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final population = json['population'];
    return GeocodingHit(
      id: id.toInt(),
      name: name.trim(),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      featureCode: str('feature_code'),
      countryCode: str('country_code'),
      country: str('country'),
      admin1: str('admin1'),
      admin2: str('admin2'),
      admin3: str('admin3'),
      admin4: str('admin4'),
      timezone: str('timezone'),
      population: population is num ? population.toInt() : null,
    );
  }
}

/// 候補行に出す地点 (補正・並べ替え済み)。
class PlaceCandidate {
  const PlaceCandidate({
    required this.geocodingId,
    required this.name,
    required this.sourceName,
    required this.latitude,
    required this.longitude,
    this.featureCode,
    this.municipality,
    this.admin1,
    this.country,
    this.countryCode,
    this.timezone,
    this.population,
  });

  /// GeoNames id。
  final int geocodingId;

  /// 表示名 (正規化後。例: 京都市 → 京都、東京都 → 東京)。
  final String name;

  /// API が返した名前 (正規化前)。
  final String sourceName;

  final double latitude;
  final double longitude;
  final String? featureCode;

  /// 市区町村 (同名地点の区別用。例: 新宿区 / 神川町)。地点そのものが
  /// 市・首都などのときは null。
  final String? municipality;

  /// 都道府県・州。
  final String? admin1;
  final String? country;
  final String? countryCode;
  final String? timezone;
  final int? population;

  /// 保存したときの ID (`place-geo-{geonamesId}`)。保存済み判定に使う。
  String get placeId => savedPlaceIdForGeocoding(geocodingId);

  /// 保存地点として持つ位置と地域情報。
  PlaceLocation toLocation() => PlaceLocation(
        latitude: latitude,
        longitude: longitude,
        municipality: municipality,
        admin1: admin1,
        country: country,
        countryCode: countryCode,
        timezone: timezone,
        geocodingId: geocodingId,
      );

  /// 地域行の要素 (市区町村 → 都道府県・州 → 国)。
  /// 例: 新宿区・東京都・日本 / 京都府・日本。区切りは UI 側で言語ごとに決める。
  List<String> get regionParts => toLocation().regionParts;

  @override
  bool operator ==(Object other) =>
      other is PlaceCandidate &&
      other.geocodingId == geocodingId &&
      other.name == name &&
      other.sourceName == sourceName &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.featureCode == featureCode &&
      other.municipality == municipality &&
      other.admin1 == admin1 &&
      other.country == country &&
      other.countryCode == countryCode &&
      other.timezone == timezone &&
      other.population == population;

  @override
  int get hashCode => Object.hash(
        geocodingId,
        name,
        sourceName,
        latitude,
        longitude,
        featureCode,
        municipality,
        admin1,
        country,
        countryCode,
        timezone,
        population,
      );

  @override
  String toString() =>
      'PlaceCandidate($geocodingId, $name, ${regionParts.join('・')})';
}
