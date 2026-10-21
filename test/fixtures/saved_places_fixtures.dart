// test/fixtures/saved_places_fixtures.dart
//
// 保存地点の画面テスト (widget / golden) の共通データ。実通信なし。
//   - 保存地点の記録 (SharedPreferences の comfort_twin_records に入れる JSON)
//   - 地点ごとの天気 (savedPlaceSnapshotProvider / savedPlaceHourlyProvider の override)
//   - 地名検索の結果 (placeSearchControllerProvider の override)
//   - 課金状態 (isPlusProvider / savedLocationLimitProvider の override。途中で
//     購入・解約を再現する切り替え式もある)
// Figma 案E' の見本: 現在地 東京、保存地点 那覇 / 京都 / 札幌 / リスボン / レイキャビク。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/place_search_provider.dart';
import 'package:mood_ring_weather/providers/saved_place_weather_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unit_region_fixtures.dart';

/// 固定の「現在時刻」(golden_harness の kGoldenNow と同じ)。
final DateTime kPlacesNow = DateTime(2026, 7, 15, 12);

/// 見本の保存地点の UTC オフセット。テストを動かす端末のタイムゾーンと同じにして、
/// 時刻ラベル (現地時刻) が端末によって変わらないようにする。
final int kPlacesOffsetSeconds = kPlacesNow.timeZoneOffset.inSeconds;

const String kNahaId = 'place-geo-1856035';
const String kKyotoId = 'place-geo-1857910';
const String kSapporoId = 'place-geo-2128295';
const String kLisbonId = 'place-geo-2267057';
const String kReykjavikId = 'place-geo-3413829';

/// 見本の保存地点 (追加順)。名前は検索した言語で保存される。
class FixturePlace {
  const FixturePlace(this.id, this.ja, this.en, this.lat, this.lon);
  final String id;
  final String ja;
  final String en;
  final double lat;
  final double lon;

  String name(Locale locale) => locale.languageCode == 'ja' ? ja : en;
}

const List<FixturePlace> kFixturePlaces = [
  FixturePlace(kNahaId, '那覇', 'Naha', 26.21, 127.68),
  FixturePlace(kKyotoId, '京都', 'Kyoto', 35.02, 135.75),
  FixturePlace(kSapporoId, '札幌', 'Sapporo', 43.07, 141.35),
  FixturePlace(kLisbonId, 'リスボン', 'Lisbon', 38.73, -9.15),
  FixturePlace(kReykjavikId, 'レイキャビク', 'Reykjavik', 64.15, -21.94),
];

/// 保存地点の記録 JSON (先頭 [count] 件。追加順は配列順)。
String savedPlacesJson(
    {required int count, Locale locale = const Locale('ja')}) {
  final places = kFixturePlaces.take(count).toList();
  return jsonEncode([
    // 記録は新しい順に保存される → 逆順に並べる。
    for (var i = places.length - 1; i >= 0; i--)
      {
        'id': places[i].id,
        'type': 'place',
        'mri': null,
        'savedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
        'label': places[i].name(locale),
        'location': {'lat': places[i].lat, 'lon': places[i].lon},
        'addedAt': DateTime(2026, 7, 1 + i, 9).toIso8601String(),
      },
  ]);
}

/// 現在地 (東京・快適) のスナップショット。
WeatherSnapshot comfortableSnapshot(DateTime at) => WeatherSnapshot(
      timestamp: at,
      latitude: 35.68,
      longitude: 139.77,
      temperature: 22,
      apparentTemperature: 24,
      humidity: 58,
      pressure: 1013,
      pressureChange6h: 0,
      windSpeed: 3.2,
      uvIndex: 3,
      aqi: 42,
      condition: 'sunny',
    );

/// 現在地が危険な暑さ (WBGT 危険域 → 熱中症アラート)。
WeatherSnapshot dangerousHeatSnapshot(DateTime at) => WeatherSnapshot(
      timestamp: at,
      latitude: 35.68,
      longitude: 139.77,
      temperature: 36,
      apparentTemperature: 41,
      humidity: 60,
      pressure: 1008,
      pressureChange6h: 0,
      windSpeed: 1.5,
      uvIndex: 9,
      aqi: 60,
      solarRadiationWm2: 900,
      condition: 'sunny',
    );

/// 那覇 (Figma: 34° / 体感 39° / 湿度 68 / 風 2.1 / UV 9 / 空気質 91 → 暑い)。
WeatherSnapshot nahaSnapshot(DateTime at) => WeatherSnapshot(
      timestamp: at,
      latitude: 26.21,
      longitude: 127.68,
      temperature: 34,
      apparentTemperature: 39,
      humidity: 68,
      pressure: 1006,
      pressureChange6h: -1,
      windSpeed: 2.1,
      uvIndex: 9,
      aqi: 91,
      condition: 'sunny',
      utcOffsetSeconds: kPlacesOffsetSeconds,
    );

/// その他の保存地点 (快適寄り)。
WeatherSnapshot mildSnapshot(DateTime at, double lat, double lon) =>
    WeatherSnapshot(
      timestamp: at,
      latitude: lat,
      longitude: lon,
      temperature: 21,
      apparentTemperature: 21,
      humidity: 55,
      pressure: 1015,
      pressureChange6h: 0,
      windSpeed: 3,
      uvIndex: 4,
      aqi: 30,
      condition: 'cloudy',
      utcOffsetSeconds: kPlacesOffsetSeconds,
    );

List<WeatherSnapshot> hourlyAround(WeatherSnapshot Function(DateTime) at) => [
      for (var h = -6; h < 18; h++) at(kPlacesNow.add(Duration(hours: h))),
    ];

const AppException kPlaceNetworkError = AppException(
  '天気情報を取得できませんでした。しばらく待ってから再試行してください。',
  'test: network down',
  ErrorType.network,
);

/// 地点ごとの天気の振る舞い。
enum PlaceWeatherMode { data, loading, error }

/// 保存地点の天気の override。[modes] に無い地点はデータを返す。
List<Override> savedPlaceWeatherOverrides({
  Map<String, PlaceWeatherMode> modes = const {},
}) {
  WeatherSnapshot snapshotFor(String id, DateTime at) {
    if (id == kNahaId) return nahaSnapshot(at);
    final place = kFixturePlaces.firstWhere(
      (p) => p.id == id,
      orElse: () => kFixturePlaces.first,
    );
    return mildSnapshot(at, place.lat, place.lon);
  }

  Future<T> behave<T>(String id, T Function() value) {
    switch (modes[id] ?? PlaceWeatherMode.data) {
      case PlaceWeatherMode.data:
        return Future.value(value());
      case PlaceWeatherMode.loading:
        return Completer<T>().future; // 取得中のまま
      case PlaceWeatherMode.error:
        return Future.error(kPlaceNetworkError);
    }
  }

  return [
    savedPlaceSnapshotProvider.overrideWith(
      (ref, id) => behave(id, () => snapshotFor(id, kPlacesNow)),
    ),
    savedPlaceHourlyProvider.overrideWith(
      (ref, id) => behave(
        id,
        () => hourlyAround((at) => snapshotFor(id, at)),
      ),
    ),
  ];
}

/// 地点管理 (A1〜A5) の見本の現在値 MRI (Figma: 65 / 62 / 60 / 71 / 84)。
const Map<String, int> kFixtureRowMri = {
  kNahaId: 65,
  kKyotoId: 62,
  kSapporoId: 60,
  kLisbonId: 71,
  kReykjavikId: 84,
};

/// 地点管理の MRI を固定する override (現在値の取得を置き換える)。
Override savedPlaceMriOverride({Map<String, int> values = kFixtureRowMri}) =>
    savedPlaceMriProvider.overrideWith((ref, id) {
      final v = values[id];
      if (v == null) return const AsyncLoading();
      return AsyncData(MoodRingIndex(
        value: v,
        band: MriBand.fromValue(v),
        factorContributions: const {},
        calculatedAt: kPlacesNow,
      ));
    });

/// 課金状態の override (true = Plus 5 / false = 無料 0。保存地点は Plus 限定)。
List<Override> entitlementOverrides({required bool plus}) => [
      isPlusProvider.overrideWithValue(plus),
      savedLocationLimitProvider.overrideWithValue(
        plus ? kPlusSavedLocationLimit : kFreeSavedLocationLimit,
      ),
    ];

/// 途中で購入・解約を再現する課金状態の override。[plus] の値 (true = Plus) を
/// 変えると isPlusProvider と savedLocationLimitProvider が追従する。
List<Override> switchableEntitlementOverrides(StateProvider<bool> plus) => [
      isPlusProvider.overrideWith((ref) => ref.watch(plus)),
      savedLocationLimitProvider.overrideWith(
        (ref) =>
            ref.watch(plus) ? kPlusSavedLocationLimit : kFreeSavedLocationLimit,
      ),
    ];

/// 地名検索の結果を固定する (クエリ → 候補 / 例外)。間引きは 0。
Override placeSearchOverride(
  Map<String, Object> results, {
  List<String>? calls,
}) =>
    placeSearchControllerProvider.overrideWith(
      (ref) => PlaceSearchController(
        debounce: Duration.zero,
        search: (query, {abortTrigger}) async {
          calls?.add(query);
          final r = results[query];
          if (r is List<PlaceCandidate>) return r;
          if (r is Exception) throw r;
          return const [];
        },
      ),
    );

/// 候補 (Figma B1: 京都 / 京都府・日本、B1c: 那覇 / 沖縄県・日本)。
PlaceCandidate fixtureCandidate(FixturePlace p, Locale locale,
        {String? admin1}) =>
    PlaceCandidate(
      geocodingId: int.parse(p.id.substring('place-geo-'.length)),
      name: p.name(locale),
      sourceName: p.name(locale),
      latitude: p.lat,
      longitude: p.lon,
      featureCode: 'PPLA',
      admin1: admin1,
      country: locale.languageCode == 'ja' ? '日本' : 'Japan',
      countryCode: 'JP',
      timezone: 'Asia/Tokyo',
      population: 1000000,
    );

/// 画面テストの共通 override (prefs・時計・現在地・カタログ)。
Future<List<Override>> placesBaseOverrides({
  int savedCount = 0,
  Locale locale = const Locale('ja'),
  WeatherSnapshot Function(DateTime)? current,
  String city = '東京',
}) async {
  SharedPreferences.setMockInitialValues({
    if (savedCount > 0)
      kPrefKeyComfortRecords:
          savedPlacesJson(count: savedCount, locale: locale),
  });
  final prefs = await SharedPreferences.getInstance();
  final currentAt = current ?? comfortableSnapshot;
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kPlacesNow),
    cityCatalogProvider.overrideWith((ref) async => const <City>[]),
    weatherSnapshotProvider.overrideWith((ref) async => currentAt(kPlacesNow)),
    hourlyWeatherProvider.overrideWith((ref) async => hourlyAround(currentAt)),
    cityNameProvider.overrideWith((ref) async => city),
    // 単位の初期値は日本の端末 (°C・m/s) に固定する。
    unitRegionOverride(),
  ];
}
