// test/unit/geocoding_api_client_test.dart
//
// Open-Meteo Geocoding クライアント (data/datasources/geocoding_api_client.dart)。
// MockClient で実通信なし。0 件と通信エラーを区別して返すことを確かめる。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/geocoding_api_client.dart';

import '../fixtures/geocoding_fixtures.dart';

http.Response _utf8(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// abortTrigger に従う最小のクライアント (IOClient と同じ振る舞いを再現)。
class _AbortAwareClient extends http.BaseClient {
  _AbortAwareClient(this.response);

  final Completer<http.StreamedResponse> response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    final aborted = Completer<http.StreamedResponse>();
    trigger?.whenComplete(() {
      if (!aborted.isCompleted) {
        aborted.completeError(http.RequestAbortedException(request.url));
      }
    });
    return Future.any([response.future, aborted.future]);
  }
}

void main() {
  group('GeocodingApiClient.search', () {
    test('名前・件数 10・言語・format=json で問い合わせる', () async {
      Uri? seen;
      final client = GeocodingApiClient(
        httpClient: MockClient((request) async {
          seen = request.url;
          return _utf8(kGeocodingFixtures['ja']!['京都市']!);
        }),
      );

      await client.search('京都市', language: 'ja');

      expect(seen!.host, 'geocoding-api.open-meteo.com');
      expect(seen!.path, '/v1/search');
      expect(seen!.queryParameters, {
        'name': '京都市',
        'count': '10',
        'language': 'ja',
        'format': 'json',
      });
    });

    test('実応答 (京都市) を読む。日本語は UTF-8 で読む', () async {
      final client = GeocodingApiClient(
        httpClient: MockClient(
          (_) async => _utf8(kGeocodingFixtures['ja']!['京都市']!),
        ),
      );

      final hits = await client.search('京都市', language: 'ja');

      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.id, 1857910);
      expect(hit.name, '京都市');
      expect(hit.latitude, closeTo(35.02107, 1e-9));
      expect(hit.longitude, closeTo(135.75385, 1e-9));
      expect(hit.featureCode, 'PPLA');
      expect(hit.countryCode, 'JP');
      expect(hit.country, '日本');
      expect(hit.admin1, '京都府');
      expect(hit.admin2, '京都市');
      expect(hit.admin3, '上京区');
      expect(hit.timezone, 'Asia/Tokyo');
      expect(hit.population, 1463723);
    });

    test('0 件 (results キーが無い実応答「京都」) は空リスト。エラーにしない', () async {
      final client = GeocodingApiClient(
        httpClient: MockClient(
          (_) async => _utf8(kGeocodingFixtures['ja']!['京都']!),
        ),
      );
      expect(await client.search('京都', language: 'ja'), isEmpty);
    });

    test('id・名前・座標が欠ける項目だけ捨てる', () async {
      final client = GeocodingApiClient(
        httpClient: MockClient((_) async => _utf8(jsonEncode({
              'results': [
                {'id': 1, 'name': 'A', 'latitude': 1.0, 'longitude': 2.0},
                {'id': 2, 'name': 'B'}, // 座標なし
                {'name': 'C', 'latitude': 1.0, 'longitude': 2.0}, // id なし
                {'id': 4, 'name': ' ', 'latitude': 1.0, 'longitude': 2.0},
                {'id': 5, 'name': 'E', 'latitude': 91.0, 'longitude': 2.0},
              ],
            }))),
      );
      final hits = await client.search('A', language: 'en');
      expect(hits.map((h) => h.id), [1]);
    });

    test('HTTP エラーは AppException(network) (0 件とは区別する)', () async {
      final client = GeocodingApiClient(
        httpClient: MockClient((_) async => http.Response('oops', 500)),
      );
      await expectLater(
        client.search('京都', language: 'ja'),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.network)
            .having((e) => e.userMessage, 'userMessage', contains('地名'))),
      );
    });

    test('通信失敗は AppException(network)', () async {
      final client = GeocodingApiClient(
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(
        client.search('京都', language: 'ja'),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.network)),
      );
    });

    test('壊れた JSON・results が配列でない応答は AppException(parsing)', () async {
      for (final body in ['{not json', '[]', '{"results": {"id": 1}}']) {
        final client = GeocodingApiClient(
          httpClient: MockClient((_) async => _utf8(body)),
        );
        await expectLater(
          client.search('京都', language: 'ja'),
          throwsA(isA<AppException>()
              .having((e) => e.type, 'type', ErrorType.parsing)),
          reason: body,
        );
      }
    });

    test('abortTrigger の完了で PlaceSearchCancelledException (通信を打ち切る)', () async {
      final pending = Completer<http.StreamedResponse>();
      final client = GeocodingApiClient(
        httpClient: _AbortAwareClient(pending),
      );
      final abort = Completer<void>();

      final future =
          client.search('京都', language: 'ja', abortTrigger: abort.future);
      abort.complete();

      await expectLater(future, throwsA(isA<PlaceSearchCancelledException>()));
    });
  });
}
