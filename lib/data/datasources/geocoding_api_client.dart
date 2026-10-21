// lib/data/datasources/geocoding_api_client.dart
//
// Open-Meteo Geocoding API クライアント (地名 → 緯度経度。キー不要)。
//   GET https://geocoding-api.open-meteo.com/v1/search
//       ?name=京都市&count=10&language=ja&format=json
//
// 1 回の呼び出しは「その名前をそのまま 1 回引く」だけ。表記の補正 (京都 →
// 京都市) や並べ替えは domain/places/place_search_rules.dart と
// data/repositories/place_search_repository.dart が組み立てる。
//
// 応答:
//   - 0 件のとき Open-Meteo は `results` キー自体を省く ({"generationtime_ms": …})
//     → 空リストを返す (通信エラーと区別する)
//   - 通信失敗・タイムアウト・HTTP エラー → AppException(network)
//   - JSON が壊れている → AppException(parsing)
//   - [abortTrigger] の完了で取り消されたら PlaceSearchCancelledException
//
// TODO(workers): 商用プラン移行時は Cloudflare Workers 経由
// (customer-geocoding-api.open-meteo.com + apikey) に切り替える
// (docs/open-meteo-commercial-terms.md §4)。キーはクライアントに置かない。
// 帰属表示の定数は core/constants/data_attribution.dart。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../models/place_candidate.dart';

/// 検索が取り消された (新しい入力に置き換わった・画面を閉じた)。
/// 利用者に見せるエラーではないので AppException にしない。
class PlaceSearchCancelledException implements Exception {
  const PlaceSearchCancelledException();

  @override
  String toString() => 'PlaceSearchCancelledException';
}

class GeocodingApiClient {
  GeocodingApiClient({
    http.Client? httpClient,
    this.host = defaultHost,
  }) : _http = httpClient ?? http.Client();

  static const String defaultHost = 'geocoding-api.open-meteo.com';
  static const String searchPath = '/v1/search';
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _http;

  /// 接続先 (商用キー経由の Workers へ切り替えるときに差し替える)。
  final String host;

  /// [name] を 1 回検索する。[language] は小文字の ISO 639-1 (ja / en / zh / es)。
  Future<List<GeocodingHit>> search(
    String name, {
    required String language,
    int count = 10,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.https(host, searchPath, {
      'name': name,
      'count': '$count',
      'language': language,
      'format': 'json',
    });

    final http.Response res;
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abortTrigger,
      );
      final streamed = await _http.send(request).timeout(_timeout);
      res = await http.Response.fromStream(streamed).timeout(_timeout);
    } on http.RequestAbortedException {
      throw const PlaceSearchCancelledException();
    } on TimeoutException {
      throw const AppException(
        '地名の検索に時間がかかっています。しばらく待ってからお試しください。',
        'Open-Meteo Geocoding request timed out',
        ErrorType.network,
      );
    } catch (e) {
      throw AppException(
        'インターネット接続を確認してください。',
        'Open-Meteo Geocoding request failed: $e',
        ErrorType.network,
      );
    }

    if (res.statusCode != 200) {
      throw AppException(
        '地名を検索できませんでした。通信を確認してもう一度お試しください。',
        'Open-Meteo Geocoding HTTP ${res.statusCode}',
        ErrorType.network,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      throw AppException(
        '地名を検索できませんでした。しばらく待ってからお試しください。',
        'Open-Meteo Geocoding JSON decode failed: $e',
        ErrorType.parsing,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppException(
        '地名を検索できませんでした。しばらく待ってからお試しください。',
        'Open-Meteo Geocoding response was not an object: '
            '${decoded.runtimeType}',
        ErrorType.parsing,
      );
    }

    final results = decoded['results'];
    if (results == null) return const []; // 0 件 (results キーごと省かれる)
    if (results is! List) {
      throw AppException(
        '地名を検索できませんでした。しばらく待ってからお試しください。',
        'Open-Meteo Geocoding results was not a list: ${results.runtimeType}',
        ErrorType.parsing,
      );
    }
    return [
      for (final item in results)
        if (GeocodingHit.tryParse(item) case final hit?) hit,
    ];
  }

  void dispose() => _http.close();
}
