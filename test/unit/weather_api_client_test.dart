// test/unit/weather_api_client_test.dart
//
// Open-Meteo レスポンスのパース正常系 / 異常系 (programmer-agent.md §6.1-3)。
// http パッケージ同梱の MockClient でネットワークをスタブする。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/weather_api_client.dart';

/// 12:00 観測・6 時間前比 −4.0 hPa の典型レスポンス。
Map<String, dynamic> _forecastJson({double? temperature = 22.5}) {
  final times = List.generate(
    24,
    (i) => '2026-06-11T${i.toString().padLeft(2, '0')}:00',
  );
  final pressures =
      List.generate(24, (i) => i < 6 ? 1017.0 : 1017.0 - (i - 5) * 4.0 / 7);
  // index 12 (現在) − index 6 = -4.0 になるよう調整
  pressures[12] = 1013.0;
  pressures[6] = 1017.0;
  return {
    'current': {
      'time': '2026-06-11T12:00',
      if (temperature != null) 'temperature_2m': temperature,
      'apparent_temperature': 23.1,
      'relative_humidity_2m': 58,
      'pressure_msl': 1013.0,
      'wind_speed_10m': 2.4,
      'uv_index': 3.2,
      'weather_code': 0,
    },
    'hourly': {'time': times, 'pressure_msl': pressures},
  };
}

/// past_days=1 + forecast_days=2 相当の 72 時間 hourly レスポンス。
/// 6/11 12:00 を「現在」とした窓選択 (6/11 06:00〜6/12 05:00) を検証する。
Map<String, dynamic> _hourlyForecastJson() {
  final times = <String>[];
  for (var d = 10; d <= 12; d++) {
    for (var h = 0; h < 24; h++) {
      times.add('2026-06-$d'
          'T${h.toString().padLeft(2, '0')}:00');
    }
  }
  final n = times.length;
  return {
    'hourly': {
      'time': times,
      'temperature_2m': List.generate(n, (i) => 20.0 + (i % 24) * 0.5),
      'apparent_temperature': List.generate(n, (i) => 21.0 + (i % 24) * 0.5),
      'relative_humidity_2m': List.generate(n, (i) => 50.0 + (i % 10)),
      // 1 時間あたり −0.5 hPa 低下 → どの時刻でも Δp6h = −3.0。
      'pressure_msl': List.generate(n, (i) => 1020.0 - i * 0.5),
      'wind_speed_10m': List.generate(n, (i) => 2.0),
      'uv_index': List.generate(n, (i) => (i % 24) >= 6 ? 3.0 : 0.0),
      'weather_code': List.generate(n, (i) => 0),
    },
  };
}

Map<String, dynamic> _hourlyAirJson() {
  final times = <String>[];
  for (var d = 10; d <= 12; d++) {
    for (var h = 0; h < 24; h++) {
      times.add('2026-06-$d'
          'T${h.toString().padLeft(2, '0')}:00');
    }
  }
  return {
    'hourly': {
      'time': times,
      'us_aqi': List.generate(times.length, (i) => 40 + (i % 5)),
    },
  };
}

WeatherApiClient _client({
  Map<String, dynamic>? forecast,
  int forecastStatus = 200,
  bool airQualityFails = false,
  bool hourly = false,
}) {
  return WeatherApiClient(
    httpClient: MockClient((request) async {
      if (request.url.host.contains('air-quality')) {
        if (airQualityFails) return http.Response('oops', 500);
        return http.Response(
          jsonEncode(hourly
              ? _hourlyAirJson()
              : {
                  'current': {'us_aqi': 42},
                }),
          200,
        );
      }
      return http.Response(
        jsonEncode(
            forecast ?? (hourly ? _hourlyForecastJson() : _forecastJson())),
        forecastStatus,
      );
    }),
  );
}

void main() {
  group('WeatherApiClient.fetchCurrent', () {
    test('正常系: 全フィールドをパースする', () async {
      final s = await _client().fetchCurrent(35.66, 139.70);
      expect(s.temperature, 22.5);
      expect(s.apparentTemperature, 23.1);
      expect(s.humidity, 58);
      expect(s.pressure, 1013.0);
      expect(s.pressureChange6h, closeTo(-4.0, 0.001));
      expect(s.windSpeed, 2.4);
      expect(s.uvIndex, 3.2);
      expect(s.aqi, 42);
      expect(s.pollen, isNull); // v1.0 はスタブ (mri-spec.md §2.8 で low 相当)
      expect(s.condition, 'sunny');
      expect(s.latitude, 35.66);
      expect(s.longitude, 139.70);
    });

    test('空気質 API 失敗時も天気本体は返す (aqi=null)', () async {
      final s =
          await _client(airQualityFails: true).fetchCurrent(35.66, 139.70);
      expect(s.aqi, isNull);
      expect(s.temperature, 22.5);
    });

    test('気温欠測は AppException(parsing) — MRI 必須入力', () async {
      expect(
        () => _client(forecast: _forecastJson(temperature: null))
            .fetchCurrent(35.66, 139.70),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.parsing)
            .having((e) => e.userMessage, 'userMessage', contains('天気情報'))),
      );
    });

    test('HTTP エラーは AppException(network) で日本語メッセージ', () async {
      expect(
        () => _client(forecastStatus: 502).fetchCurrent(35.66, 139.70),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.network)),
      );
    });
  });

  group('WeatherApiClient.fetchHourly', () {
    final now = DateTime(2026, 6, 11, 12, 20);

    test('現在−6h〜+17h の 24 点窓を全フィールド込みでパースする', () async {
      final points =
          await _client(hourly: true).fetchHourly(35.66, 139.70, now: now);

      expect(points, hasLength(24));
      // 窓: 6/11 06:00 〜 6/12 05:00
      expect(points.first.timestamp, DateTime(2026, 6, 11, 6));
      expect(points.last.timestamp, DateTime(2026, 6, 12, 5));

      final nowPoint =
          points.firstWhere((p) => p.timestamp == DateTime(2026, 6, 11, 12));
      expect(nowPoint.temperature, 26.0); // 20 + 12×0.5
      expect(nowPoint.apparentTemperature, 27.0);
      expect(nowPoint.humidity, isNotNull);
      expect(nowPoint.pressureChange6h, closeTo(-3.0, 0.001));
      expect(nowPoint.windSpeed, 2.0);
      expect(nowPoint.uvIndex, 3.0);
      expect(nowPoint.aqi, isNotNull);
      expect(nowPoint.condition, 'sunny');
      // 全点で Δp6h が計算できている (i ≥ 6 を満たす窓)。
      expect(points.every((p) => p.pressureChange6h != null), isTrue);
    });

    test('空気質 API 失敗時も時系列は返す (aqi=null)', () async {
      final points = await _client(hourly: true, airQualityFails: true)
          .fetchHourly(35.66, 139.70, now: now);
      expect(points, hasLength(24));
      expect(points.every((p) => p.aqi == null), isTrue);
    });

    test('hourly 欠落は AppException(parsing)', () async {
      expect(
        () => _client(hourly: true, forecast: {'hourly': null})
            .fetchHourly(35.66, 139.70, now: now),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.parsing)
            .having((e) => e.userMessage, 'userMessage', contains('天気情報'))),
      );
    });

    test('HTTP エラーは AppException(network)', () async {
      expect(
        () => _client(hourly: true, forecastStatus: 502)
            .fetchHourly(35.66, 139.70, now: now),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.network)),
      );
    });
  });

  group('時差 (utc_offset_seconds)', () {
    // timezone=auto の time 文字列は地点の壁時計。utc_offset_seconds で絶対時刻に
    // 直す (端末のタイムゾーンに依らず同じ瞬間になる)。無い応答は従来どおり。

    test('fetchCurrent: 壁時計 + オフセット → 絶対時刻。気圧差は壁時計で突き合わせ', () async {
      final json = _forecastJson()
        ..['utc_offset_seconds'] = -25200; // PDT (UTC−7)
      final s = await _client(forecast: json).fetchCurrent(37.77, -122.42);

      // 2026-06-11T12:00 (UTC−7) = 2026-06-11T19:00Z
      expect(
          s.timestamp.isAtSameMomentAs(DateTime.utc(2026, 6, 11, 19)), isTrue);
      expect(s.utcOffsetSeconds, -25200);
      expect(s.placeLocalTime.hour, 12);
      expect(s.pressureChange6h, closeTo(-4.0, 0.001));
    });

    test('fetchCurrent: オフセットが無い応答は従来どおり端末ローカルの壁時計', () async {
      final s = await _client().fetchCurrent(35.66, 139.70);
      expect(s.timestamp, DateTime(2026, 6, 11, 12));
      expect(s.utcOffsetSeconds, isNull);
      expect(s.placeLocalTime, s.timestamp);
    });

    test('fetchHourly: 「今」を地点の壁時計に直して窓を決める', () async {
      final json = _hourlyForecastJson()
        ..['utc_offset_seconds'] = 3600; // UTC+1
      // 今 = 11:20Z = 地点の 12:20 → 窓は地点の 6/11 06:00 〜 6/12 05:00
      final points = await _client(hourly: true, forecast: json).fetchHourly(
        38.72,
        -9.14,
        now: DateTime.utc(2026, 6, 11, 11, 20),
      );

      expect(points, hasLength(24));
      expect(
        points.first.timestamp.isAtSameMomentAs(DateTime.utc(2026, 6, 11, 5)),
        isTrue,
      );
      expect(points.first.placeLocalTime.hour, 6);
      expect(points.first.utcOffsetSeconds, 3600);
      // 空気質は同じ壁時計の時刻で対応付く
      expect(points.every((p) => p.aqi != null), isTrue);
    });

    test('fetchHourly: 端末と時差のある地点でも窓がずれない (オフセットが無いと端末基準)', () async {
      final base = _hourlyForecastJson();
      final withOffset = Map<String, dynamic>.of(base)
        ..['utc_offset_seconds'] = 32400; // UTC+9
      final now = DateTime.utc(2026, 6, 11, 3, 20); // 地点 (UTC+9) の 12:20

      final points = await _client(hourly: true, forecast: withOffset)
          .fetchHourly(35.0, 135.0, now: now);
      // 窓の先頭は地点の 6/11 06:00 = 6/10 21:00Z
      expect(
        points.first.timestamp.isAtSameMomentAs(DateTime.utc(2026, 6, 10, 21)),
        isTrue,
      );
      // 「今」に最も近い点は地点の 12:00 (= 03:00Z)。鮮度 2 時間の判定も正しい
      final nearest = points.reduce((a, b) =>
          (a.timestamp.difference(now)).abs() <
                  (b.timestamp.difference(now)).abs()
              ? a
              : b);
      expect(nearest.placeLocalTime.hour, 12);
      expect(now.difference(nearest.timestamp), const Duration(minutes: 20));
    });

    test('範囲外のオフセットは壊れた値として使わない', () async {
      final json = _forecastJson()..['utc_offset_seconds'] = 999999;
      final s = await _client(forecast: json).fetchCurrent(35.66, 139.70);
      expect(s.utcOffsetSeconds, isNull);
      expect(s.timestamp, DateTime(2026, 6, 11, 12));
    });
  });

  group('WeatherApiClient.fetchCurrentBulk', () {
    /// 一括取得 (Comfort-Twin)。複数地点指定時の配列応答をスタブする。
    WeatherApiClient bulkClient(Object body, {int status = 200}) {
      return WeatherApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.open-meteo.com');
          return http.Response(jsonEncode(body), status);
        }),
      );
    }

    Map<String, dynamic> item(double temperature) => {
          'current': {
            'time': '2026-06-11T12:00',
            'temperature_2m': temperature,
            'apparent_temperature': temperature + 0.5,
            'relative_humidity_2m': 55,
            'pressure_msl': 1012.0,
            'wind_speed_10m': 2.0,
            'uv_index': 3.0,
            'weather_code': 0,
          },
        };

    test('配列応答を入力順のまま WeatherSnapshot に対応付ける', () async {
      final client = bulkClient([item(22.0), item(30.0)]);
      final result = await client.fetchCurrentBulk(const [
        (latitude: 35.68, longitude: 139.69),
        (latitude: 25.20, longitude: 55.27),
      ]);

      expect(result, hasLength(2));
      expect(result[0]!.temperature, 22.0);
      expect(result[0]!.latitude, 35.68);
      expect(result[1]!.temperature, 30.0);
      expect(result[1]!.longitude, 55.27);
      // 一括取得は hourly を要求しないため Δp6h は欠測 (§2.8 フォールバック)。
      expect(result[0]!.pressureChange6h, isNull);
    });

    test('一部地点の気温欠測は null 埋めで続行する', () async {
      final client = bulkClient([item(18.0), <String, dynamic>{}, item(28.0)]);
      final result = await client.fetchCurrentBulk(const [
        (latitude: 51.51, longitude: -0.13),
        (latitude: 0.0, longitude: 0.0),
        (latitude: -33.87, longitude: 151.21),
      ]);

      expect(result, hasLength(3));
      expect(result[0], isNotNull);
      expect(result[1], isNull);
      expect(result[2], isNotNull);
    });

    test('1 地点のみ指定時のオブジェクト応答も受理する', () async {
      final client = bulkClient(item(22.0));
      final result = await client.fetchCurrentBulk(const [
        (latitude: 35.68, longitude: 139.69),
      ]);
      expect(result, hasLength(1));
      expect(result[0]!.temperature, 22.0);
    });

    test('空の座標リスト → 空 (リクエストしない)', () async {
      final client = WeatherApiClient(
        httpClient: MockClient((_) async => fail('リクエスト不要のはず')),
      );
      expect(await client.fetchCurrentBulk(const []), isEmpty);
    });

    test('全地点パース不能は AppException(parsing)', () async {
      final client = bulkClient([<String, dynamic>{}, <String, dynamic>{}]);
      expect(
        () => client.fetchCurrentBulk(const [
          (latitude: 1.0, longitude: 1.0),
          (latitude: 2.0, longitude: 2.0),
        ]),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.parsing)
            .having((e) => e.userMessage, 'userMessage', contains('天気情報'))),
      );
    });

    test('HTTP エラーは AppException(network)', () async {
      final client = bulkClient([item(22.0)], status: 502);
      expect(
        () => client.fetchCurrentBulk(const [
          (latitude: 1.0, longitude: 1.0),
          (latitude: 2.0, longitude: 2.0),
        ]),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.network)),
      );
    });
  });
}
