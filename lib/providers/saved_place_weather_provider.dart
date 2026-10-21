// lib/providers/saved_place_weather_provider.dart
//
// 保存地点ごとの天気 (Riverpod)。地点 ID → 現在の天気・時間別・MRI。
//
//   savedPlaceSnapshotProvider(id)     : 現在の天気 (AsyncValue<WeatherSnapshot>)
//   savedPlaceHourlyProvider(id)       : 24 時間の毎時の天気
//   savedPlaceMriProvider(id)          : MRI (個人補正 θ を掛ける)
//   savedPlaceMriTimelineProvider(id)  : 時間別 MRI (θ を掛ける)
//
// 出荷条件 (docs/ の地点タブ設計・PM 決定):
//   - G1 **副作用なし**。ここは天気を取って MRI を計算するだけで、緊急アラート
//     判定・push 購読・キャリブレーション学習・Comfort-Twin・ライブ壁紙には一切
//     つながない。それらは現在地専用の weatherSnapshotProvider / mriProvider
//     (weather_provider.dart / mri_provider.dart / main.dart) だけが呼ぶ。
//     本ファイルに emergency / push / wallpaper / calibration の学習 /
//     twinCandidates を足さないこと (test/unit/saved_place_weather_provider_test.dart
//     が参照を検査する)。
//   - G2 取得失敗時の直近成功分 (lastGood) は地点ごと (SavedPlaceWeatherRepository)。
//     現在地の WeatherRepository とは別インスタンスで、別地点のデータで代用しない。
//   - 取得経路と計算は現在地の単発取得と同じ (fetchCurrent / fetchHourly →
//     MriCalculator)。一括取得 (fetchCurrentBulk) は空気質・気圧差が既定値で
//     MRI が 3〜6 点ずれるため使わない。
//   - 取得した値は最初の取得から 10 分程度保持する (タブを行き来しても取り直さない)。
//     失敗は保持しない (戻ってきたら取り直す)。引っ張って更新するときは
//     ref.invalidate(savedPlaceSnapshotProvider(id)) / savedPlaceHourlyProvider(id)
//     (display_weather_provider.dart の refreshDisplayedWeather がまとめて行う)。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/models/mood_ring_index.dart';
import '../data/models/weather_snapshot.dart';
import '../data/repositories/saved_place_weather_repository.dart';
import '../domain/mri/mri_calculator.dart';
import '../domain/mri/mri_timeline.dart';
import 'calibration_provider.dart';
import 'clock_provider.dart';
import 'comfort_twin_provider.dart' show cityCatalogProvider;
import 'saved_places_provider.dart';
import 'weather_provider.dart' show weatherApiClientProvider;

/// 保存地点の天気を保持する時間 (最初の取得から)。
const Duration kSavedPlaceWeatherCacheDuration = Duration(minutes: 10);

/// 地点の座標 (値比較できる record。座標が変わったときだけ取り直す)。
typedef PlaceCoordinates = ({double latitude, double longitude});

/// 保存地点の天気の取得窓口 (地点ごとの lastGood を持つ。G2)。
final savedPlaceWeatherRepositoryProvider =
    Provider<SavedPlaceWeatherRepository>((ref) {
  final repository = SavedPlaceWeatherRepository(
    apiClient: ref.watch(weatherApiClientProvider),
  );
  // 削除した地点の天気・座標をメモリに残さない。
  ref.listen(
    savedPlacesProvider,
    (_, places) => repository.retainOnly([for (final p in places) p.id]),
  );
  return repository;
});

/// 保存地点の座標 (無い・保存されていなければ null)。名前の変更などでは
/// 変わらないので、天気の取り直しは座標が変わったときだけ起きる。
final savedPlaceCoordinatesProvider =
    Provider.autoDispose.family<PlaceCoordinates?, String>((ref, placeId) {
  final location = ref.watch(savedPlaceByIdProvider(placeId))?.location;
  if (location == null) return null;
  return (latitude: location.latitude, longitude: location.longitude);
});

/// 保存地点 [placeId] の現在の天気。
/// 失敗時: その地点の直近成功分があれば返す (鮮度は timestamp で UI が判断)。
/// 無ければ AppException。
final savedPlaceSnapshotProvider = FutureProvider.autoDispose
    .family<WeatherSnapshot, String>((ref, placeId) async {
  final link = _keepFor(ref, kSavedPlaceWeatherCacheDuration);
  final repository = ref.watch(savedPlaceWeatherRepositoryProvider);
  try {
    final c = await _requireCoordinates(ref, placeId);
    try {
      return await repository.fetchCurrent(
        placeId,
        latitude: c.latitude,
        longitude: c.longitude,
      );
    } on AppException {
      final cached = repository.lastGoodSnapshot(
        placeId,
        latitude: c.latitude,
        longitude: c.longitude,
      );
      if (cached != null) return cached;
      rethrow;
    }
  } catch (_) {
    link.close(); // 失敗は保持しない
    rethrow;
  }
});

/// 保存地点 [placeId] の 24 時間分の毎時の天気 (過去 6h〜未来 17h。
/// 「今」は地点の現地時刻で決める)。失敗時の扱いは savedPlaceSnapshotProvider と同じ。
final savedPlaceHourlyProvider = FutureProvider.autoDispose
    .family<List<WeatherSnapshot>, String>((ref, placeId) async {
  final link = _keepFor(ref, kSavedPlaceWeatherCacheDuration);
  final repository = ref.watch(savedPlaceWeatherRepositoryProvider);
  // 窓の「今」(clockProvider。テストは固定時刻)。地点の現地時刻への換算は
  // WeatherApiClient が utc_offset_seconds で行う。
  final now = ref.read(clockProvider)();
  try {
    final c = await _requireCoordinates(ref, placeId);
    try {
      return await repository.fetchHourly(
        placeId,
        latitude: c.latitude,
        longitude: c.longitude,
        now: now,
      );
    } on AppException {
      final cached = repository.lastGoodHourly(
        placeId,
        latitude: c.latitude,
        longitude: c.longitude,
      );
      if (cached != null) return cached;
      rethrow;
    }
  } catch (_) {
    link.close();
    rethrow;
  }
});

/// 保存地点 [placeId] の MRI (学習済みの個人補正 θ を掛ける。mri-spec.md §6)。
final savedPlaceMriProvider = Provider.autoDispose
    .family<AsyncValue<MoodRingIndex>, String>((ref, placeId) {
  final profile = ref.watch(personalProfileProvider);
  final snapshot = ref.watch(savedPlaceSnapshotProvider(placeId));
  return snapshot.whenData(
    (s) => MriCalculator.calculate(s, profile: profile),
  );
});

/// 保存地点 [placeId] の時間別 MRI (θ を掛ける)。
final savedPlaceMriTimelineProvider = Provider.autoDispose
    .family<AsyncValue<List<MriTimelinePoint>>, String>((ref, placeId) {
  final profile = ref.watch(personalProfileProvider);
  final hourly = ref.watch(savedPlaceHourlyProvider(placeId));
  return hourly.whenData(
    (list) => MriTimeline.fromSnapshots(list, profile: profile),
  );
});

/// 最初の取得から [duration] は購読者がいなくても保持する (autoDispose 用)。
/// 購読され続けている間は保持され、[duration] を過ぎてから購読者が離れると
/// すぐ破棄される (次に表示するときは取り直す = 古い値を使い回さない)。
KeepAliveLink _keepFor(Ref<Object?> ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
  return link;
}

/// 保存地点 [placeId] の座標。座標が無ければ AppException。
///
/// 旧 Comfort-Twin 記録で同梱カタログがまだ読み込まれていないときは、読み込みを
/// 待ってカタログから補う。`ref` は最初の await より前にだけ使う (待っている間に
/// 依存 = 座標が変わると Riverpod は ref の利用を禁じるため)。
Future<PlaceCoordinates> _requireCoordinates(
  Ref<Object?> ref,
  String placeId,
) async {
  final coordinates = ref.watch(savedPlaceCoordinatesProvider(placeId));
  if (coordinates != null) return coordinates;
  final place = ref.read(savedPlaceByIdProvider(placeId));
  if (place == null) {
    throw AppException(
      'この地点は保存されていません。',
      'Saved place $placeId not found',
      ErrorType.unknown,
    );
  }
  final cityId = place.catalogCityId;
  if (cityId != null) {
    final catalogFuture = ref.read(cityCatalogProvider.future);
    try {
      for (final city in await catalogFuture) {
        if (city.id == cityId) {
          return (latitude: city.latitude, longitude: city.longitude);
        }
      }
    } catch (_) {
      // カタログが読めなければ座標なしとして下で失敗させる。
    }
  }
  throw AppException(
    'この地点の位置が分からないため、天気を表示できません。地点を追加し直してください。',
    'Saved place $placeId has no coordinates',
    ErrorType.location,
  );
}
