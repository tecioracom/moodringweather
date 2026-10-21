// lib/providers/weather_provider.dart
//
// 位置 (COARSE) → 天気取得の配線 (Riverpod)。
// UI は weatherSnapshotProvider / cityNameProvider のみを参照する。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/datasources/city_name_datasource.dart';
import '../data/datasources/location_datasource.dart';
import '../data/datasources/weather_api_client.dart';
import '../data/models/weather_snapshot.dart';
import '../data/repositories/weather_repository.dart';
import 'emergency_alert_provider.dart';
import 'push_provider.dart';

final weatherApiClientProvider = Provider<WeatherApiClient>((ref) {
  final client = WeatherApiClient();
  ref.onDispose(client.dispose);
  return client;
});

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(apiClient: ref.watch(weatherApiClientProvider));
});

final locationDataSourceProvider =
    Provider<LocationDataSource>((ref) => const LocationDataSource());

final cityNameDataSourceProvider =
    Provider<CityNameDataSource>((ref) => const CityNameDataSource());

/// 現在地 (COARSE)。権限拒否・取得失敗時は東京の既定地点へフォールバックし、
/// アプリ自体は使用可能なまま保つ (isFallback=true で UI に通知)。
final currentLocationProvider = FutureProvider<GeoPoint>((ref) async {
  final source = ref.watch(locationDataSourceProvider);
  // この取得が最新のうちだけ取り直す (更新・破棄のあとに届いた許可では何もしない)。
  var latest = true;
  ref.onDispose(() => latest = false);
  try {
    return await source.getCurrentPosition(
      // 許可ダイアログへの回答を待ちきれずに既定地点で進めたあと、遅れて
      // 許可が届いたら現在地を取り直す (location_datasource.dart、QA-17)。
      onLateGrant: () {
        if (latest) ref.invalidateSelf();
      },
    );
  } on AppException {
    return LocationDataSource.fallback;
  }
});

/// 現在地の天気スナップショット。
/// 失敗時: 直近の取得成功分があればそれを返す (鮮度低下は UI バナーで通知)。
/// 無ければ AppException をそのまま伝播する。
final weatherSnapshotProvider = FutureProvider<WeatherSnapshot>((ref) async {
  final location = await ref.watch(currentLocationProvider.future);
  final repo = ref.watch(weatherRepositoryProvider);
  try {
    final snapshot = await repo.fetch(location.latitude, location.longitude);
    // 緊急アラート (熱中症/暴風/大雪) の判定・発火 (Sev1-1)。
    // best-effort: 通知配線の失敗で天気表示は決して止めない。
    try {
      await ref.read(emergencyAlertControllerProvider).onSnapshot(snapshot);
    } catch (_) {
      // 通知は付帯機能 (コントローラ内でも握るが、provider 解決失敗も含めて防御)。
    }
    // 緊急プッシュの購読登録 (計画 S8)。「自分の体感が表示された後」に登録する。
    // 既定地点 (位置情報なし) の間は登録しない。失敗は握る (Firebase 不在なら no-op)。
    try {
      await ref.read(pushSubscriptionCoordinatorProvider).onSnapshot(
            latitude: location.latitude,
            longitude: location.longitude,
            isFallbackLocation: location.isFallback,
          );
    } catch (_) {
      // 購読は付帯機能。天気表示を巻き込まない。
    }
    return snapshot;
  } on AppException {
    final cached = repo.lastGoodSnapshot;
    if (cached != null) return cached;
    rethrow;
  }
});

/// 現在時刻を中心とした 24 時間分の毎時スナップショット (Detail 画面用)。
/// 失敗時: 直近の取得成功分があればそれを返す。無ければ AppException を伝播。
final hourlyWeatherProvider =
    FutureProvider<List<WeatherSnapshot>>((ref) async {
  final location = await ref.watch(currentLocationProvider.future);
  final repo = ref.watch(weatherRepositoryProvider);
  try {
    return await repo.fetchHourly(location.latitude, location.longitude);
  } on AppException {
    final cached = repo.lastGoodHourly;
    if (cached != null) return cached;
    rethrow;
  }
});

/// 表示用の都市名。解決できない場合は null (UI 側で「現在地」を表示)。
final cityNameProvider = FutureProvider<String?>((ref) async {
  final location = await ref.watch(currentLocationProvider.future);
  return ref
      .watch(cityNameDataSourceProvider)
      .resolve(location.latitude, location.longitude);
});
