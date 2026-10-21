// test/fixtures/geocoding_fixture_server.dart
//
// Open-Meteo Geocoding の実応答フィクスチャ (geocoding_fixtures.dart) を返す
// MockClient。実通信はしない。

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'geocoding_fixtures.dart';

/// 0 件の応答 (Open-Meteo は results キー自体を省く)。
const String kGeocodingEmptyBody = '{"generationtime_ms":0.1}';

class GeocodingFixtureServer {
  GeocodingFixtureServer({this.failNames = const {}});

  /// この名前の問い合わせは HTTP 500 を返す (通信エラーの再現)。
  final Set<String> failNames;

  /// 受けた問い合わせ (順に)。
  final List<Uri> requests = [];

  /// フィクスチャが無かった問い合わせ (テストで空であることを確かめる)。
  final List<String> missing = [];

  List<String> get requestedNames => [
        for (final uri in requests) uri.queryParameters['name'] ?? '',
      ];

  late final http.Client client = MockClient((request) async {
    requests.add(request.url);
    final name = request.url.queryParameters['name'] ?? '';
    final language = request.url.queryParameters['language'] ?? '';
    if (failNames.contains(name)) return http.Response('oops', 500);
    final body = kGeocodingFixtures[language]?[name];
    if (body == null) missing.add('$language/$name');
    return http.Response.bytes(
      utf8.encode(body ?? kGeocodingEmptyBody),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  });
}
