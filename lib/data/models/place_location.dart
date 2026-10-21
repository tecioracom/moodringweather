// lib/data/models/place_location.dart
//
// 保存地点の位置と地域情報 (Plus 多地点。spec.md §12.11.5)。純 Dart の不変値。
//
// 座標は地名検索 (Open-Meteo Geocoding = GeoNames) の代表点か、Comfort-Twin の
// 同梱カタログの座標。ユーザーの現在地ではない (spec.md §13: 現在地の履歴は保持
// しない。保存地点は「人」ではなく「場所」の登録)。ComfortRecord (place) の
// `location` として SharedPreferences にだけ保存し、サーバーへは送らない。

class PlaceLocation {
  const PlaceLocation({
    required this.latitude,
    required this.longitude,
    this.municipality,
    this.admin1,
    this.country,
    this.countryCode,
    this.timezone,
    this.geocodingId,
  });

  final double latitude;
  final double longitude;

  /// 市区町村 (あれば。例: 新宿区 / 逗子市 / 神川町)。
  final String? municipality;

  /// 都道府県・州 (例: 京都府 / California)。
  final String? admin1;

  /// 国名 (検索したときの言語の表記。例: 日本 / Japan)。
  final String? country;

  /// ISO 3166-1 alpha-2 (例: JP)。
  final String? countryCode;

  /// IANA タイムゾーン (例: Asia/Tokyo)。天気の時刻は応答の
  /// `utc_offset_seconds` を正とし、これは表示・参考用。
  final String? timezone;

  /// Open-Meteo Geocoding の id (= GeoNames id)。Comfort-Twin 由来は null。
  final int? geocodingId;

  /// 地域行の要素 (市区町村 → 都道府県・州 → 国)。空文字と重複を除く。
  /// 区切り (「・」/「, 」) は言語ごとに UI 側で決める。
  List<String> get regionParts {
    final parts = <String>[];
    for (final p in [municipality, admin1, country]) {
      final v = p?.trim();
      if (v == null || v.isEmpty || parts.contains(v)) continue;
      parts.add(v);
    }
    return parts;
  }

  /// null のキーは書かない (保存サイズを最小に保つ)。
  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        if (municipality != null) 'municipality': municipality,
        if (admin1 != null) 'admin1': admin1,
        if (country != null) 'country': country,
        if (countryCode != null) 'countryCode': countryCode,
        if (timezone != null) 'timezone': timezone,
        if (geocodingId != null) 'geocodingId': geocodingId,
      };

  /// 保存値から復元する。座標が欠ける・壊れている場合は null
  /// (呼び出し側は「座標なし」として扱う)。
  static PlaceLocation? tryParse(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lon = json['lon'];
    if (lat is! num || lon is! num) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    String? str(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    final id = json['geocodingId'];
    return PlaceLocation(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      municipality: str('municipality'),
      admin1: str('admin1'),
      country: str('country'),
      countryCode: str('countryCode'),
      timezone: str('timezone'),
      geocodingId: id is num ? id.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaceLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.municipality == municipality &&
      other.admin1 == admin1 &&
      other.country == country &&
      other.countryCode == countryCode &&
      other.timezone == timezone &&
      other.geocodingId == geocodingId;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        municipality,
        admin1,
        country,
        countryCode,
        timezone,
        geocodingId,
      );

  /// ログに座標を出さない (agents.md「位置をログに出さない」)。
  @override
  String toString() =>
      'PlaceLocation(${regionParts.join(' / ')}, geo=$geocodingId)';
}
