// lib/data/repositories/saved_place_weather_repository.dart
//
// 保存地点の天気の取得窓口 (data 層)。
//
// 厳守 (保存地点の出荷条件):
//   - G1: 天気を取るだけ。緊急アラート判定・push 購読・キャリブレーション学習・
//     Comfort-Twin・ライブ壁紙には一切つながない (それらは現在地専用の
//     weather_provider.dart の weatherSnapshotProvider 経路だけが呼ぶ)。
//   - G2: 取得失敗時の直近成功分 (lastGood) は**地点ごと**に持つ。現在地の
//     WeatherRepository (lastGoodSnapshot) とは別のインスタンスで、互いに
//     混ざらない (別地点のデータで代用しない)。
//   - 取得経路と MRI の入力は現在地の単発取得 (WeatherApiClient.fetchCurrent /
//     fetchHourly) と同じ。Comfort-Twin の一括取得 (fetchCurrentBulk) は空気質・
//     気圧差を既定値にしていて MRI が 3〜6 点ずれるため使わない。
//
// キャッシュはメモリのみ (端末にも保存しない)。削除した地点の分は retainOnly で捨てる。

import '../datasources/weather_api_client.dart';
import '../models/weather_snapshot.dart';

class _PlaceWeatherCache {
  _PlaceWeatherCache(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
  WeatherSnapshot? current;
  List<WeatherSnapshot>? hourly;
}

class SavedPlaceWeatherRepository {
  SavedPlaceWeatherRepository({required WeatherApiClient apiClient})
      : _api = apiClient;

  final WeatherApiClient _api;
  final Map<String, _PlaceWeatherCache> _cache = {};

  /// 地点 [placeId] ([latitude], [longitude]) の現在の天気。
  /// 失敗時は AppException (日本語 userMessage) を投げる。
  Future<WeatherSnapshot> fetchCurrent(
    String placeId, {
    required double latitude,
    required double longitude,
  }) async {
    final snapshot = await _api.fetchCurrent(latitude, longitude);
    _entry(placeId, latitude, longitude).current = snapshot;
    return snapshot;
  }

  /// 地点 [placeId] の 24 時間分 (過去 6h〜未来 17h) の毎時の天気。
  /// [now] はテスト用の基準時刻。失敗時は AppException を投げる。
  Future<List<WeatherSnapshot>> fetchHourly(
    String placeId, {
    required double latitude,
    required double longitude,
    DateTime? now,
  }) async {
    final points = await _api.fetchHourly(latitude, longitude, now: now);
    _entry(placeId, latitude, longitude).hourly = points;
    return points;
  }

  /// 地点 [placeId] で直近に取得できた現在の天気 (座標が変わっていれば null)。
  WeatherSnapshot? lastGoodSnapshot(
    String placeId, {
    required double latitude,
    required double longitude,
  }) =>
      _lookup(placeId, latitude, longitude)?.current;

  /// 地点 [placeId] で直近に取得できた時間別の天気 (座標が変わっていれば null)。
  List<WeatherSnapshot>? lastGoodHourly(
    String placeId, {
    required double latitude,
    required double longitude,
  }) =>
      _lookup(placeId, latitude, longitude)?.hourly;

  /// [placeIds] 以外の地点のキャッシュを捨てる (保存地点の削除時)。
  void retainOnly(Iterable<String> placeIds) {
    final keep = placeIds.toSet();
    _cache.removeWhere((id, _) => !keep.contains(id));
  }

  /// すべて捨てる (データ削除時)。
  void clear() => _cache.clear();

  /// キャッシュを持っている地点 (テスト・デバッグ用)。
  Set<String> get cachedPlaceIds => _cache.keys.toSet();

  _PlaceWeatherCache _entry(String placeId, double lat, double lon) {
    final existing = _lookup(placeId, lat, lon);
    if (existing != null) return existing;
    return _cache[placeId] = _PlaceWeatherCache(lat, lon);
  }

  _PlaceWeatherCache? _lookup(String placeId, double lat, double lon) {
    final entry = _cache[placeId];
    if (entry == null) return null;
    // 同じ id で座標が変わった (再保存で地点が変わった) 古い値は使わない。
    if (entry.latitude != lat || entry.longitude != lon) return null;
    return entry;
  }
}
