// lib/providers/display_weather_provider.dart
//
// ホーム / 詳細の UI が使う「表示用」provider (地点タブで選んだ地点の天気)。
//
//   選択が null (現在地) → 既存の現在地 provider をそのまま返す
//                          (weatherSnapshotProvider / hourlyWeatherProvider /
//                           mriProvider / mriTimelineProvider / cityNameProvider)
//   保存地点             → 地点ごとの provider (saved_place_weather_provider.dart)
//
// 取得中・失敗は**その地点の** AsyncLoading / AsyncError をそのまま返し、
// 別地点 (現在地) のデータで代用しない。
//
// 表示用に分けるだけで、現在地の経路 (緊急アラート・push 購読・壁紙・
// キャリブレーション・Comfort-Twin) は選択に関係なく現在地のまま。
// UI 側の差し替え (weatherSnapshotProvider → displayWeatherSnapshotProvider 等) は
// Figma 確定後の後続タスクで行う。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/mood_ring_index.dart';
import '../data/models/saved_place.dart';
import '../data/models/weather_snapshot.dart';
import '../domain/mri/mri_timeline.dart';
import 'mri_provider.dart';
import 'place_selection_provider.dart';
import 'saved_place_weather_provider.dart';
import 'saved_places_provider.dart';
import 'weather_provider.dart';

/// 表示中の保存地点 ID (null = 現在地)。選択が保存地点に無ければ null。
final displayedPlaceIdProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedPlaceIdProvider);
  if (selected == null) return null;
  return ref.watch(savedPlaceByIdProvider(selected)) == null ? null : selected;
});

/// 表示中の保存地点 (null = 現在地)。ヘッダの地名・「保存地点」タグ用。
final displayedSavedPlaceProvider = Provider<SavedPlace?>((ref) {
  final placeId = ref.watch(displayedPlaceIdProvider);
  return placeId == null ? null : ref.watch(savedPlaceByIdProvider(placeId));
});

/// 表示中の地点の現在の天気。
final displayWeatherSnapshotProvider =
    Provider<AsyncValue<WeatherSnapshot>>((ref) {
  final placeId = ref.watch(displayedPlaceIdProvider);
  if (placeId == null) return ref.watch(weatherSnapshotProvider);
  return ref.watch(savedPlaceSnapshotProvider(placeId));
});

/// 表示中の地点の 24 時間の毎時の天気。
final displayHourlyWeatherProvider =
    Provider<AsyncValue<List<WeatherSnapshot>>>((ref) {
  final placeId = ref.watch(displayedPlaceIdProvider);
  if (placeId == null) return ref.watch(hourlyWeatherProvider);
  return ref.watch(savedPlaceHourlyProvider(placeId));
});

/// 表示中の地点の MRI (個人補正 θ 込み)。
final displayMriProvider = Provider<AsyncValue<MoodRingIndex>>((ref) {
  final placeId = ref.watch(displayedPlaceIdProvider);
  if (placeId == null) return ref.watch(mriProvider);
  return ref.watch(savedPlaceMriProvider(placeId));
});

/// 表示中の地点の時間別 MRI (個人補正 θ 込み)。
final displayMriTimelineProvider =
    Provider<AsyncValue<List<MriTimelinePoint>>>((ref) {
  final placeId = ref.watch(displayedPlaceIdProvider);
  if (placeId == null) return ref.watch(mriTimelineProvider);
  return ref.watch(savedPlaceMriTimelineProvider(placeId));
});

/// 表示中の地点名。現在地は逆ジオコーディングの都市名 (解決できなければ
/// null → UI で「現在地」)。保存地点は保存した表示名。
final displayPlaceNameProvider = Provider<AsyncValue<String?>>((ref) {
  final place = ref.watch(displayedSavedPlaceProvider);
  if (place == null) return ref.watch(cityNameProvider);
  return AsyncData(place.name);
});

/// 表示中の地点の天気を取り直す (引っ張って更新・再試行)。
///
/// 現在地は従来のホームと同じく位置から取り直す。保存地点はその地点の
/// 現在・時間別を取り直す (取得できなければその地点の直近成功分に戻る)。
/// 失敗は投げない (状態は各 provider の AsyncError で表示する)。
Future<void> refreshDisplayedWeather(WidgetRef ref) async {
  final placeId = ref.read(displayedPlaceIdProvider);
  try {
    if (placeId == null) {
      ref.invalidate(currentLocationProvider);
      ref.invalidate(weatherSnapshotProvider);
      await ref.read(weatherSnapshotProvider.future);
    } else {
      ref.invalidate(savedPlaceSnapshotProvider(placeId));
      ref.invalidate(savedPlaceHourlyProvider(placeId));
      await ref.read(savedPlaceSnapshotProvider(placeId).future);
    }
  } catch (_) {
    // 失敗は各 provider の AsyncError として画面に出る。
  }
}
