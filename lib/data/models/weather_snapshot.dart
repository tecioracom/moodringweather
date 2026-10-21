// lib/data/models/weather_snapshot.dart
//
// 現在の気象観測スナップショット (docs/mri-spec.md §1-2 の入力契約)。
// freezed は v1.0 の依存に含めていないため plain Dart の不変クラスで実装する
// (依存追加時に freezed へ移行可能なフィールド設計)。
//
// 欠測許容 (mri-spec.md §2.8): temperature のみ必須。それ以外の nullable
// フィールドは MriCalculator 側でフォールバック値に置き換えられる。

import 'pollen_level.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.temperature,
    this.apparentTemperature,
    this.humidity,
    this.pressure,
    this.pressureChange6h,
    this.windSpeed,
    this.uvIndex,
    this.aqi,
    this.pollen,
    this.solarRadiationWm2,
    this.snowfallCm,
    this.condition = 'unknown',
    this.utcOffsetSeconds,
  });

  /// 観測時刻 (絶対時刻。UTC でも local でも可。表示時に整形)。
  /// Open-Meteo の応答は `utc_offset_seconds` で地点の壁時計から直してある
  /// (weather_api_client.dart)。「今」との比較 (鮮度・時間別の現在位置) に使う。
  final DateTime timestamp;
  final double latitude;
  final double longitude;

  /// 気温 °C (`temperature_2m`)。MRI の必須入力。
  final double temperature;

  /// 体感温度 °C (`apparent_temperature`)。欠測時は temperature で代用。
  final double? apparentTemperature;

  /// 相対湿度 % (`relative_humidity_2m`)。
  final double? humidity;

  /// 海面更正気圧 hPa (`pressure_msl`)。
  final double? pressure;

  /// 6 時間気圧変化 hPa (現在 − 6h 前)。mri-spec.md §2.7。
  final double? pressureChange6h;

  /// 風速 m/s (`wind_speed_10m`, wind_speed_unit=ms)。
  final double? windSpeed;

  /// UV インデックス (`uv_index`)。
  final double? uvIndex;

  /// US AQI (`us_aqi`、Air Quality API)。
  final int? aqi;

  /// 花粉レベル (v1.0 はスタブ供給。欠測可)。
  final PollenLevel? pollen;

  /// 短波放射 W/m² (`shortwave_radiation`)。WBGT の Tg 近似に使用
  /// (mri-spec.md §5.1)。欠測/夜間は 0 扱い。
  final double? solarRadiationWm2;

  /// 直近 1 時間降雪量 cm (`snowfall`)。大雪緊急アラート判定に使用。
  final double? snowfallCm;

  /// 'sunny' | 'cloudy' | 'rainy' | 'snowy' | 'unknown' 等の概況。
  final String condition;

  /// 地点の UTC オフセット秒 (Open-Meteo の `utc_offset_seconds`)。
  /// 海外の保存地点で「現地の時刻」を出すときに使う。不明なら null。
  final int? utcOffsetSeconds;

  /// 地点の現地時刻 (壁時計)。年月日時分だけが意味を持つ値で、`isUtc` は
  /// true になる (例: DateFormat.Hm で「15:00」と整形する用途)。
  /// オフセットが不明なら端末ローカルの [timestamp] をそのまま返す。
  DateTime get placeLocalTime {
    final offset = utcOffsetSeconds;
    if (offset == null) return timestamp;
    return timestamp.toUtc().add(Duration(seconds: offset));
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'temperature': temperature,
        'apparentTemperature': apparentTemperature,
        'humidity': humidity,
        'pressure': pressure,
        'pressureChange6h': pressureChange6h,
        'windSpeed': windSpeed,
        'uvIndex': uvIndex,
        'aqi': aqi,
        'pollen': pollen?.id,
        'solarRadiationWm2': solarRadiationWm2,
        'snowfallCm': snowfallCm,
        'condition': condition,
        'utcOffsetSeconds': utcOffsetSeconds,
      };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();
    return WeatherSnapshot(
      timestamp: DateTime.parse(json['timestamp'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      temperature: (json['temperature'] as num).toDouble(),
      apparentTemperature: asDouble(json['apparentTemperature']),
      humidity: asDouble(json['humidity']),
      pressure: asDouble(json['pressure']),
      pressureChange6h: asDouble(json['pressureChange6h']),
      windSpeed: asDouble(json['windSpeed']),
      uvIndex: asDouble(json['uvIndex']),
      aqi: (json['aqi'] as num?)?.toInt(),
      pollen: json['pollen'] == null
          ? null
          : PollenLevel.parse(json['pollen'] as String),
      solarRadiationWm2: asDouble(json['solarRadiationWm2']),
      snowfallCm: asDouble(json['snowfallCm']),
      condition: (json['condition'] as String?) ?? 'unknown',
      utcOffsetSeconds: (json['utcOffsetSeconds'] as num?)?.toInt(),
    );
  }

  WeatherSnapshot copyWith({
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? temperature,
    double? apparentTemperature,
    double? humidity,
    double? pressure,
    double? pressureChange6h,
    double? windSpeed,
    double? uvIndex,
    int? aqi,
    PollenLevel? pollen,
    double? solarRadiationWm2,
    double? snowfallCm,
    String? condition,
    int? utcOffsetSeconds,
  }) {
    return WeatherSnapshot(
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      temperature: temperature ?? this.temperature,
      apparentTemperature: apparentTemperature ?? this.apparentTemperature,
      humidity: humidity ?? this.humidity,
      pressure: pressure ?? this.pressure,
      pressureChange6h: pressureChange6h ?? this.pressureChange6h,
      windSpeed: windSpeed ?? this.windSpeed,
      uvIndex: uvIndex ?? this.uvIndex,
      aqi: aqi ?? this.aqi,
      pollen: pollen ?? this.pollen,
      solarRadiationWm2: solarRadiationWm2 ?? this.solarRadiationWm2,
      snowfallCm: snowfallCm ?? this.snowfallCm,
      condition: condition ?? this.condition,
      utcOffsetSeconds: utcOffsetSeconds ?? this.utcOffsetSeconds,
    );
  }
}
