// lib/data/datasources/weather_api_client.dart
//
// Open-Meteo クライアント (API キー不要・無認証。agents.md「クライアントに
// API キーを置かない」と整合)。
//
// TODO(workers): 将来は Cloudflare Workers (`/api/weather`) 経由に切り替え、
// キャッシュ(5 分)とレート制御をサーバー側へ寄せる (programmer-agent.md §4.4)。
// 有償 API (Tomorrow.io 等) を足す場合もキーは Workers の環境変数のみに置く。
// v1.0 MVP はキー不要の Open-Meteo へ直接 https アクセスする。
//
// 時刻 (timezone=auto): Open-Meteo の time 文字列は「地点の壁時計」で UTC
// オフセットを含まない。応答の `utc_offset_seconds` で絶対時刻に直して
// WeatherSnapshot.timestamp に入れる (端末ローカル表現)。これで海外の保存地点
// でも「今」の位置 (時間別の窓) と鮮度判定 (取得から 2 時間) が正しくなる。
// 端末と同じタイムゾーンの地点 (現在地) では従来と同じ値になる。
// `utc_offset_seconds` が無い応答は従来どおり端末ローカルの壁時計として扱う。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../models/weather_snapshot.dart';

class WeatherApiClient {
  WeatherApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _forecastHost = 'api.open-meteo.com';
  static const _airQualityHost = 'air-quality-api.open-meteo.com';
  static const _timeout = Duration(seconds: 12);

  /// 現在の気象スナップショットを取得する。
  ///
  /// 天気本体 (forecast) は必須。空気質 (us_aqi) は取得失敗しても
  /// null のまま続行する (MRI 側で §2.8 のフォールバック)。
  Future<WeatherSnapshot> fetchCurrent(
    double latitude,
    double longitude,
  ) async {
    final forecast = await _getJson(
      Uri.https(_forecastHost, '/v1/forecast', {
        'latitude': latitude.toStringAsFixed(2),
        'longitude': longitude.toStringAsFixed(2),
        // shortwave_radiation / snowfall は緊急アラート判定用
        // (WBGT の Tg 近似と大雪判定。lib/domain/safety/emergency_advisor.dart)。
        'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,'
            'pressure_msl,wind_speed_10m,uv_index,weather_code,'
            'shortwave_radiation,snowfall',
        'hourly': 'pressure_msl',
        'past_days': '1',
        'forecast_days': '1',
        'wind_speed_unit': 'ms',
        'timezone': 'auto',
      }),
    );

    int? aqi;
    try {
      final air = await _getJson(
        Uri.https(_airQualityHost, '/v1/air-quality', {
          'latitude': latitude.toStringAsFixed(2),
          'longitude': longitude.toStringAsFixed(2),
          'current': 'us_aqi',
          'timezone': 'auto',
        }),
      );
      aqi = ((air['current'] as Map<String, dynamic>?)?['us_aqi'] as num?)
          ?.round();
    } on AppException {
      aqi = null; // 空気質は補助データ。欠測フォールバックに任せる。
    }

    return _parseSnapshot(forecast, latitude, longitude, aqi);
  }

  /// 複数地点の現在気象を 1 リクエストで一括取得する (Comfort-Twin の
  /// 候補都市用)。Open-Meteo はカンマ区切りの latitude/longitude を受け、
  /// 地点数 ≥ 2 のとき配列で応答する。
  ///
  /// 戻り値は [coords] と同じ順序・同じ長さ。個別地点のパース失敗は
  /// null で埋めて続行する (MRI 候補から除外するだけで全体は止めない)。
  /// 全地点が失敗した場合のみ AppException を投げる。
  ///
  /// 空気質・hourly 気圧は取得しない (候補都市の MRI は §2.8 の
  /// 欠測フォールバックで十分。リクエストを最小に保つ)。
  Future<List<WeatherSnapshot?>> fetchCurrentBulk(
    List<({double latitude, double longitude})> coords,
  ) async {
    if (coords.isEmpty) return const [];

    final decoded = await _getJsonAny(
      Uri.https(_forecastHost, '/v1/forecast', {
        'latitude': coords.map((c) => c.latitude.toStringAsFixed(2)).join(','),
        'longitude':
            coords.map((c) => c.longitude.toStringAsFixed(2)).join(','),
        'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,'
            'pressure_msl,wind_speed_10m,uv_index,weather_code',
        'wind_speed_unit': 'ms',
        'timezone': 'auto',
      }),
    );

    // 1 地点のみ指定時はオブジェクト、複数指定時は配列で返る。
    final items = decoded is List ? decoded : <Object?>[decoded];
    final result = List<WeatherSnapshot?>.filled(coords.length, null);
    for (var i = 0; i < coords.length && i < items.length; i++) {
      final item = items[i];
      if (item is! Map<String, dynamic>) continue;
      try {
        result[i] = _parseSnapshot(
          item,
          coords[i].latitude,
          coords[i].longitude,
          null,
        );
      } on AppException {
        // 個別地点の欠測はスキップ (候補から外すだけ)。
      }
    }

    if (result.every((s) => s == null)) {
      throw const AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo bulk response had no parsable locations',
        ErrorType.parsing,
      );
    }
    return result;
  }

  /// 現在時刻を中心とした 24 時間分 (過去 6h 〜 未来 17h) の毎時
  /// スナップショットを取得する (Detail 画面の MRI 時系列用)。
  ///
  /// 空気質 (us_aqi) は取得失敗しても null のまま続行する。
  /// [now] はテスト用の基準時刻注入フック (既定: DateTime.now())。
  Future<List<WeatherSnapshot>> fetchHourly(
    double latitude,
    double longitude, {
    DateTime? now,
  }) async {
    final forecast = await _getJson(
      Uri.https(_forecastHost, '/v1/forecast', {
        'latitude': latitude.toStringAsFixed(2),
        'longitude': longitude.toStringAsFixed(2),
        'hourly': 'temperature_2m,apparent_temperature,relative_humidity_2m,'
            'pressure_msl,wind_speed_10m,uv_index,weather_code',
        'past_days': '1',
        'forecast_days': '2',
        'wind_speed_unit': 'ms',
        'timezone': 'auto',
      }),
    );

    Map<String, int> aqiByTime = const {};
    try {
      final air = await _getJson(
        Uri.https(_airQualityHost, '/v1/air-quality', {
          'latitude': latitude.toStringAsFixed(2),
          'longitude': longitude.toStringAsFixed(2),
          'hourly': 'us_aqi',
          'past_days': '1',
          'forecast_days': '2',
          'timezone': 'auto',
        }),
      );
      aqiByTime = _parseAqiByTime(air);
    } on AppException {
      aqiByTime = const {}; // 空気質は補助データ。欠測フォールバックに任せる。
    }

    return _parseHourly(forecast, latitude, longitude, aqiByTime, now);
  }

  Map<String, int> _parseAqiByTime(Map<String, dynamic> json) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    final times = (hourly?['time'] as List?)?.cast<String>();
    final values = hourly?['us_aqi'] as List?;
    if (times == null || values == null) return const {};
    final map = <String, int>{};
    for (var i = 0; i < times.length && i < values.length; i++) {
      final v = values[i] as num?;
      if (v != null) map[times[i]] = v.round();
    }
    return map;
  }

  List<WeatherSnapshot> _parseHourly(
    Map<String, dynamic> json,
    double latitude,
    double longitude,
    Map<String, int> aqiByTime,
    DateTime? now,
  ) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    final times = (hourly?['time'] as List?)?.cast<String>();
    if (hourly == null || times == null || times.isEmpty) {
      throw const AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo response missing hourly.time',
        ErrorType.parsing,
      );
    }

    List<double?> series(String key) => ((hourly[key] as List?) ?? const [])
        .map((v) => (v as num?)?.toDouble())
        .toList();

    final temps = series('temperature_2m');
    final apparents = series('apparent_temperature');
    final humidities = series('relative_humidity_2m');
    final pressures = series('pressure_msl');
    final winds = series('wind_speed_10m');
    final uvs = series('uv_index');
    final codes = series('weather_code');

    // 基準時刻 (時単位) のインデックスを探す。time 文字列は地点の壁時計なので、
    // 「今」も地点の壁時計に直してから比べる (海外の地点で窓がずれない)。
    final offset = _utcOffsetOf(json);
    final hourKey = _hourKeyAt(now ?? DateTime.now(), offset);
    var nowIndex = times.indexWhere((t) => t.startsWith(hourKey));
    if (nowIndex < 0) nowIndex = times.length ~/ 2; // 時刻不一致時の保険

    // 過去 6h 〜 未来 17h の 24 点窓 (端ではスライドして 24 点を維持)。
    var start = nowIndex - 6;
    if (start < 0) start = 0;
    var end = start + 23;
    if (end >= times.length) {
      end = times.length - 1;
      start = end - 23 < 0 ? 0 : end - 23;
    }

    final points = <WeatherSnapshot>[];
    for (var i = start; i <= end; i++) {
      final temperature = i < temps.length ? temps[i] : null;
      final timestamp = _instantOf(times[i], offset);
      // 気温は MRI の必須入力 (mri-spec.md §2.8)。欠ける時刻はスキップ。
      if (temperature == null || timestamp == null) continue;

      double? at<T>(List<double?> list) => i < list.length ? list[i] : null;
      final pressure = at(pressures);
      double? change6h;
      if (i >= 6 && pressure != null && pressures[i - 6] != null) {
        change6h = pressure - pressures[i - 6]!;
      }

      points.add(WeatherSnapshot(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        temperature: temperature,
        apparentTemperature: at(apparents),
        humidity: at(humidities),
        pressure: pressure,
        pressureChange6h: change6h,
        windSpeed: at(winds),
        uvIndex: at(uvs),
        aqi: aqiByTime[times[i]],
        // TODO(pollen): v1.0 は花粉データ未接続のスタブ (null → §2.8)。
        pollen: null,
        condition:
            _conditionFromWeatherCode(i < codes.length ? codes[i] : null),
        utcOffsetSeconds: offset?.inSeconds,
      ));
    }

    if (points.isEmpty) {
      throw const AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo hourly response has no usable points',
        ErrorType.parsing,
      );
    }
    return points;
  }

  WeatherSnapshot _parseSnapshot(
    Map<String, dynamic> json,
    double latitude,
    double longitude,
    int? aqi,
  ) {
    final current = json['current'] as Map<String, dynamic>?;
    final temperature = (current?['temperature_2m'] as num?)?.toDouble();
    if (current == null || temperature == null) {
      // 気温は MRI の必須入力 (mri-spec.md §2.8)。
      throw const AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo response missing current.temperature_2m',
        ErrorType.parsing,
      );
    }

    final pressure = (current['pressure_msl'] as num?)?.toDouble();
    final offset = _utcOffsetOf(json);
    // time は地点の壁時計。気圧の 6h 差は同じ壁時計の hourly.time と文字列の
    // まま突き合わせ、timestamp だけ絶対時刻に直す。
    final timeRaw = current['time'] as String?;
    final observedAt = (timeRaw == null ? null : _instantOf(timeRaw, offset)) ??
        DateTime.now();
    final observedHourKey = timeRaw != null &&
            timeRaw.length >= 13 &&
            DateTime.tryParse(timeRaw) != null
        ? timeRaw.substring(0, 13)
        : _hourKeyAt(DateTime.now(), offset);

    return WeatherSnapshot(
      timestamp: observedAt,
      latitude: latitude,
      longitude: longitude,
      temperature: temperature,
      apparentTemperature:
          (current['apparent_temperature'] as num?)?.toDouble(),
      humidity: (current['relative_humidity_2m'] as num?)?.toDouble(),
      pressure: pressure,
      pressureChange6h: _pressureChange6h(json, observedHourKey, pressure),
      windSpeed: (current['wind_speed_10m'] as num?)?.toDouble(),
      uvIndex: (current['uv_index'] as num?)?.toDouble(),
      aqi: aqi,
      // TODO(pollen): v1.0 は花粉データ未接続のスタブ (null → §2.8 で low 相当)。
      // 供給元 (Open-Meteo Pollen / Google Pollen API) 接続時に置き換える。
      pollen: null,
      solarRadiationWm2: (current['shortwave_radiation'] as num?)?.toDouble(),
      snowfallCm: (current['snowfall'] as num?)?.toDouble(),
      condition: _conditionFromWeatherCode(current['weather_code'] as num?),
      utcOffsetSeconds: offset?.inSeconds,
    );
  }

  /// 応答の `utc_offset_seconds` (timezone=auto で地点に当てたオフセット)。
  /// 無い・壊れている場合は null (従来どおり端末ローカルの壁時計として扱う)。
  static Duration? _utcOffsetOf(Map<String, dynamic> json) {
    final raw = json['utc_offset_seconds'];
    if (raw is! num) return null;
    final seconds = raw.toInt();
    // 実在するオフセットは −12h〜+14h。範囲外は壊れた値として捨てる。
    if (seconds.abs() > 14 * 3600) return null;
    return Duration(seconds: seconds);
  }

  /// time 文字列 (地点の壁時計。オフセットを含まない) を絶対時刻 (端末ローカル
  /// 表現) に直す。[offset] が無ければ従来どおり端末ローカルの壁時計として読む。
  ///
  /// 壁時計は UTC の年月日時として読む (端末のタイムゾーンの夏時間の境目で
  /// 時刻がずれないようにする) → オフセットを引く → 端末ローカルへ。
  static DateTime? _instantOf(String raw, Duration? offset) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || offset == null || parsed.isUtc) return parsed;
    final wall = DateTime.tryParse('${raw}Z');
    if (wall == null) return parsed;
    return wall.subtract(offset).toLocal();
  }

  /// [instant] (絶対時刻) の「時」を time 文字列と同じ形 (例: 2026-06-11T12) に
  /// する。[offset] があれば地点の壁時計、無ければ端末ローカルの時刻で。
  static String _hourKeyAt(DateTime instant, Duration? offset) {
    final wall = offset == null ? instant : instant.toUtc().add(offset);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wall.year.toString().padLeft(4, '0')}-${two(wall.month)}-'
        '${two(wall.day)}T${two(wall.hour)}';
  }

  /// hourly.pressure_msl から「現在 − 6 時間前」の気圧変化を求める
  /// (mri-spec.md §2.7)。揃わない場合は null (欠測フォールバック)。
  /// [hourKey] は観測時刻の「時」(地点の壁時計。例: 2026-06-11T12)。
  double? _pressureChange6h(
    Map<String, dynamic> json,
    String hourKey,
    double? currentPressure,
  ) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    final times = (hourly?['time'] as List?)?.cast<String>();
    final pressures = (hourly?['pressure_msl'] as List?)
        ?.map((v) => (v as num?)?.toDouble())
        .toList();
    if (times == null || pressures == null || currentPressure == null) {
      return null;
    }

    // 観測時刻の「時」で現在インデックスを探す。
    final nowIndex = times.indexWhere((t) => t.startsWith(hourKey));
    final pastIndex = nowIndex - 6;
    if (nowIndex < 0 || pastIndex < 0 || pastIndex >= pressures.length) {
      return null;
    }
    final past = pressures[pastIndex];
    if (past == null) return null;
    return currentPressure - past;
  }

  /// WMO weather code → アプリ内 condition 文字列。
  String _conditionFromWeatherCode(num? code) {
    if (code == null) return 'unknown';
    final c = code.toInt();
    if (c == 0) return 'sunny';
    if (c <= 3) return 'cloudy';
    if (c <= 48) return 'foggy';
    if (c <= 67) return 'rainy';
    if (c <= 77) return 'snowy';
    if (c <= 82) return 'rainy';
    if (c <= 86) return 'snowy';
    return 'stormy';
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final decoded = await _getJsonAny(uri);
    if (decoded is Map<String, dynamic>) return decoded;
    throw AppException(
      '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
      'Open-Meteo response was not a JSON object: ${decoded.runtimeType}',
      ErrorType.parsing,
    );
  }

  /// JSON 応答をオブジェクト/配列を問わずデコードして返す
  /// (一括取得は配列応答になるため)。
  Future<Object?> _getJsonAny(Uri uri) async {
    http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const AppException(
        '天気情報の取得に時間がかかっています。しばらく待ってお試しください。',
        'Open-Meteo request timed out',
        ErrorType.network,
      );
    } catch (e) {
      throw AppException(
        'インターネット接続を確認してください。',
        'Open-Meteo request failed: $e',
        ErrorType.network,
      );
    }
    if (res.statusCode != 200) {
      throw AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo HTTP ${res.statusCode} for ${uri.host}${uri.path}',
        ErrorType.network,
      );
    }
    try {
      return jsonDecode(res.body);
    } catch (e) {
      throw AppException(
        '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
        'Open-Meteo JSON decode failed: $e',
        ErrorType.parsing,
      );
    }
  }

  void dispose() => _http.close();
}
