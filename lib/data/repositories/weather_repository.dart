// lib/data/repositories/weather_repository.dart
//
// 天気データの取得窓口 (data 層)。UI / domain は本リポジトリ経由でのみ
// 気象データへアクセスする (agents.md の 3 層分離)。

import '../datasources/weather_api_client.dart';
import '../models/weather_snapshot.dart';

class WeatherRepository {
  WeatherRepository({WeatherApiClient? apiClient})
      : _api = apiClient ?? WeatherApiClient();

  final WeatherApiClient _api;

  WeatherSnapshot? _lastGood;
  List<WeatherSnapshot>? _lastGoodHourly;

  /// 直近に取得成功したスナップショット (取得失敗時の UI フォールバック用)。
  WeatherSnapshot? get lastGoodSnapshot => _lastGood;

  /// 直近に取得成功した 24 時間時系列 (取得失敗時の UI フォールバック用)。
  List<WeatherSnapshot>? get lastGoodHourly => _lastGoodHourly;

  /// 現在地の天気を取得する。失敗時は AppException (日本語 userMessage) を投げる。
  Future<WeatherSnapshot> fetch(double latitude, double longitude) async {
    final snapshot = await _api.fetchCurrent(latitude, longitude);
    _lastGood = snapshot;
    return snapshot;
  }

  /// 現在時刻を中心とした 24 時間分の毎時スナップショットを取得する
  /// (Detail 画面用)。失敗時は AppException を投げる。
  Future<List<WeatherSnapshot>> fetchHourly(
    double latitude,
    double longitude,
  ) async {
    final points = await _api.fetchHourly(latitude, longitude);
    _lastGoodHourly = points;
    return points;
  }
}
