// test/unit/saved_place_weather_provider_test.dart
//
// 保存地点ごとの天気 (providers/saved_place_weather_provider.dart)。
//   - G1 副作用なし: 保存地点の取得で緊急判定・push 購読・学習・Comfort-Twin・
//     ライブ壁紙が呼ばれない (現在地の経路は従来どおり動く)
//   - G2 lastGood は地点ごと: 別地点・現在地のデータで代用しない
//   - 単発取得と同じ経路・同じ計算 (空気質・気圧差あり)、θ を掛ける
//   - 時差: utc_offset_seconds で海外地点の「今」と鮮度が正しい
//   - 取得した値は 10 分程度保持する
// Open-Meteo は MockClient で地点 (緯度) ごとに応答を返す。実通信なし。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/datasources/weather_api_client.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/push/push_subscription.dart';
import 'package:mood_ring_weather/data/repositories/weather_repository.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/domain/mri/mri_calculator.dart';
import 'package:mood_ring_weather/domain/mri/mri_timeline.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/display_weather_provider.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/mri_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/push_provider.dart';
import 'package:mood_ring_weather/providers/saved_place_weather_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Open-Meteo のフェイク ──────────────────────────────────────────

/// 地点の天気 (応答の元)。
class _Weather {
  const _Weather({
    required this.temperature,
    this.humidity = 50,
    this.radiation = 0,
    this.offsetSeconds = 32400,
    this.localNow = '2026-06-11T12:00',
  });

  final double temperature;
  final double humidity;
  final double radiation;

  /// 空気質 (US AQI)。全地点共通。
  int get aqi => 42;

  /// utc_offset_seconds (null なら応答に含めない)。
  final int? offsetSeconds;

  /// 地点の壁時計の「今」(current.time)。
  final String localNow;
}

class _WeatherServer {
  _WeatherServer(this.byLatitude);

  /// 緯度 (小数 2 桁の文字列) → 天気。
  final Map<String, _Weather> byLatitude;

  /// この緯度の問い合わせは HTTP 503 にする。
  final Set<String> failing = {};

  final List<Uri> requests = [];

  int forecastCurrentCount(String latitude) => requests
      .where((u) =>
          u.host == 'api.open-meteo.com' &&
          u.queryParameters['latitude'] == latitude &&
          u.queryParameters.containsKey('current'))
      .length;

  late final http.Client client = MockClient((request) async {
    final url = request.url;
    requests.add(url);
    final lat = url.queryParameters['latitude']!;
    final weather = byLatitude[lat];
    if (failing.contains(lat) || weather == null) {
      return http.Response('unavailable', 503);
    }
    final isCurrent = url.queryParameters.containsKey('current');
    final isAir = url.host.startsWith('air-quality');
    final Map<String, dynamic> body;
    if (isAir) {
      body = isCurrent
          ? {
              'current': {'us_aqi': weather.aqi},
            }
          : {
              'hourly': {
                'time': _hourlyTimes,
                'us_aqi': [for (final _ in _hourlyTimes) weather.aqi],
              },
            };
    } else {
      body = isCurrent ? _currentJson(weather) : _hourlyJson(weather);
    }
    return http.Response(jsonEncode(body), 200);
  });
}

/// 6/10〜6/12 の 72 時間 (地点の壁時計)。
final List<String> _hourlyTimes = [
  for (var d = 10; d <= 12; d++)
    for (var h = 0; h < 24; h++)
      '2026-06-${d}T${h.toString().padLeft(2, '0')}:00',
];

Map<String, dynamic> _currentJson(_Weather w) {
  final day = w.localNow.substring(0, 10);
  final hour = int.parse(w.localNow.substring(11, 13));
  final times = [
    for (var h = 0; h < 24; h++) '${day}T${h.toString().padLeft(2, '0')}:00',
  ];
  // 1 時間に −0.5 hPa → 6 時間で −3.0 hPa。
  final pressures = [for (var h = 0; h < 24; h++) 1016.0 - h * 0.5];
  return {
    if (w.offsetSeconds != null) 'utc_offset_seconds': w.offsetSeconds,
    'current': {
      'time': w.localNow,
      'temperature_2m': w.temperature,
      'apparent_temperature': w.temperature + 1,
      'relative_humidity_2m': w.humidity,
      'pressure_msl': pressures[hour],
      'wind_speed_10m': 2.0,
      'uv_index': 5.0,
      'weather_code': 0,
      'shortwave_radiation': w.radiation,
      'snowfall': 0.0,
    },
    'hourly': {'time': times, 'pressure_msl': pressures},
  };
}

Map<String, dynamic> _hourlyJson(_Weather w) {
  final n = _hourlyTimes.length;
  return {
    if (w.offsetSeconds != null) 'utc_offset_seconds': w.offsetSeconds,
    'hourly': {
      'time': _hourlyTimes,
      'temperature_2m': [
        for (var i = 0; i < n; i++) w.temperature + (i % 24) * 0.1
      ],
      'apparent_temperature': [
        for (var i = 0; i < n; i++) w.temperature + 1 + (i % 24) * 0.1,
      ],
      'relative_humidity_2m': [for (var i = 0; i < n; i++) w.humidity],
      'pressure_msl': [for (var i = 0; i < n; i++) 1020.0 - i * 0.5],
      'wind_speed_10m': [for (var i = 0; i < n; i++) 2.0],
      'uv_index': [for (var i = 0; i < n; i++) 3.0],
      'weather_code': [for (var i = 0; i < n; i++) 0],
    },
  };
}

// ─── 副作用の観測用フェイク ─────────────────────────────────────────

class _FakeGateway implements NotificationGateway {
  final shown = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    shown.add(id);
  }
}

class _SpyPushCoordinator extends PushSubscriptionCoordinator {
  _SpyPushCoordinator() : super.disabled();

  final calls = <({double lat, double lon})>[];

  @override
  Future<void> onSnapshot({
    required double latitude,
    required double longitude,
    bool isFallbackLocation = false,
  }) async {
    calls.add((lat: latitude, lon: longitude));
  }
}

class _FakeWallpaperBridge implements WallpaperBridge {
  final sent = <int>[];

  @override
  Future<bool> setMriState(WallpaperState state) async {
    sent.add(state.mri);
    return true;
  }

  @override
  Future<bool> clearMriState() async => true;
}

class _FixedLocation extends LocationDataSource {
  const _FixedLocation(this.point);
  final GeoPoint point;

  @override
  Future<GeoPoint> getCurrentPosition({void Function()? onLateGrant}) async =>
      point;
}

// ─── 共通の組み立て ─────────────────────────────────────────────────

const _nahaId = 'place-geo-1856035';
const _lisbonId = 'place-geo-2267057';
const _homeId = 'place-geo-1';

/// 現在地 (東京付近・快適)。
const _currentLocation = GeoPoint(35.68, 139.77);
const _comfortable = _Weather(temperature: 22);

/// 那覇 (危険な暑さ: 36°C / RH 60% / 日射 900 → WBGT 危険域)。
const _dangerousHeat = _Weather(temperature: 36, humidity: 60, radiation: 900);

/// リスボン (UTC+1。壁時計 12:00 = 11:00Z)。
const _lisbonWeather = _Weather(
  temperature: 24,
  offsetSeconds: 3600,
  localNow: '2026-06-11T12:00',
);

Map<String, dynamic> _placeRecord(
  String id,
  String label,
  double lat,
  double lon, {
  String? timezone,
  int day = 1,
}) =>
    {
      'id': id,
      'type': 'place',
      'mri': null,
      'savedAt': '2026-09-0${day}T09:00:00.000',
      'label': label,
      'location': {
        'lat': lat,
        'lon': lon,
        if (timezone != null) 'timezone': timezone,
      },
      'addedAt': '2026-09-0${day}T09:00:00.000',
    };

class _Env {
  _Env._(this.container, this.prefs, this.server, this.gateway, this.push,
      this.wallpaper);

  final ProviderContainer container;
  final SharedPreferences prefs;
  final _WeatherServer server;
  final _FakeGateway gateway;
  final _SpyPushCoordinator push;
  final _FakeWallpaperBridge wallpaper;

  static Future<_Env> create({
    List<Map<String, dynamic>>? places,
    List<City> catalog = const [],
    DateTime Function()? clock,
    GeoPoint currentLocation = _currentLocation,
  }) async {
    SharedPreferences.setMockInitialValues({
      kPrefKeyComfortRecords: jsonEncode(places ??
          [
            _placeRecord(_nahaId, '那覇', 26.21, 127.68, timezone: 'Asia/Tokyo'),
            _placeRecord(_lisbonId, 'リスボン', 38.72, -9.15,
                timezone: 'Europe/Lisbon', day: 2),
          ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final server = _WeatherServer({
      '35.68': _comfortable,
      '26.21': _dangerousHeat,
      '38.72': _lisbonWeather,
    });
    final gateway = _FakeGateway();
    final push = _SpyPushCoordinator();
    final wallpaper = _FakeWallpaperBridge();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cityCatalogProvider.overrideWith((ref) async => catalog),
        weatherApiClientProvider.overrideWithValue(
          WeatherApiClient(httpClient: server.client),
        ),
        locationDataSourceProvider
            .overrideWithValue(_FixedLocation(currentLocation)),
        notificationGatewayProvider.overrideWithValue(gateway),
        pushSubscriptionCoordinatorProvider.overrideWithValue(push),
        wallpaperBridgeProvider.overrideWithValue(wallpaper),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    return _Env._(container, prefs, server, gateway, push, wallpaper);
  }

  /// main.dart と同じ配線: 現在地の MRI が確定するたびにライブ壁紙へ送る。
  void wireWallpaperLikeMain() {
    container.listen(
      mriProvider,
      (_, next) => container
          .read(wallpaperMriSyncProvider)
          .onMri(next.valueOrNull?.value),
      fireImmediately: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('G1 副作用なし', () {
    test('対照: 同じ危険な暑さが「現在地」なら緊急通知と push 購読が走る', () async {
      // 現在地を那覇にした現在地経路 (保存地点の経路と比べるための対照)
      final env = await _Env.create(
        currentLocation: const GeoPoint(26.21, 127.68),
      );
      final c = env.container;
      addTearDown(c.dispose);

      await c.read(weatherSnapshotProvider.future);

      expect(env.gateway.shown, [1001]); // 熱中症の固定 ID
      expect(env.push.calls, hasLength(1));
    });

    test('保存地点の取得は緊急判定・push 購読・学習・Comfort-Twin・壁紙を呼ばない', () async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);
      env.wireWallpaperLikeMain();

      // 現在地 (快適) を表示 → 現在地の経路は従来どおり動く
      final current = await c.read(weatherSnapshotProvider.future);
      await pumpEventQueue();
      final currentMri = c.read(mriProvider).requireValue.value;
      expect(env.gateway.shown, isEmpty);
      expect(env.push.calls, hasLength(1));
      expect(env.wallpaper.sent, [currentMri]);

      // 那覇 (危険な暑さ) を表示して取得する
      c.read(selectedPlaceIdProvider.notifier).select(_nahaId);
      final naha = await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      await c.read(savedPlaceHourlyProvider(_nahaId).future);
      final displayed = c.read(displayMriProvider).requireValue;
      c.read(displayMriTimelineProvider);
      await pumpEventQueue();

      expect(naha.temperature, 36);
      expect(displayed.value, isNot(currentMri));
      // 緊急通知は出ない (現在地経路なら 1001 が出る天気)
      expect(env.gateway.shown, isEmpty);
      // push 購読は現在地の 1 回だけ (保存地点の座標を送らない)
      expect(env.push.calls, hasLength(1));
      expect(env.push.calls.single.lat, _currentLocation.latitude);
      // ライブ壁紙は現在地の MRI のまま
      expect(env.wallpaper.sent, [currentMri]);
      expect(c.read(mriProvider).requireValue.value, currentMri);
      // キャリブレーションは学習していない
      expect(c.read(personalProfileProvider).feedbackCount, 0);
      expect(env.prefs.getString(kPrefKeyPersonalProfile), isNull);
      // Comfort-Twin (一括取得) は作られていない
      expect(c.exists(twinCandidatesProvider), isFalse);
      expect(
        env.server.requests
            .any((u) => (u.queryParameters['latitude'] ?? '').contains(',')),
        isFalse,
      );
      // 現在地の lastGood は現在地のまま (G2)
      expect(
        c.read(weatherRepositoryProvider).lastGoodSnapshot!.temperature,
        current.temperature,
      );
    });

    test('保存地点の provider は副作用のある provider を参照しない (静的検査)', () {
      final forbidden = [
        'emergencyAlertControllerProvider',
        'notificationGatewayProvider',
        'pushSubscriptionCoordinatorProvider',
        'pushRuntimeProvider',
        'wallpaperMriSyncProvider',
        'wallpaperBridgeProvider',
        'twinCandidatesProvider',
        'weatherSnapshotProvider',
        'hourlyWeatherProvider',
        'weatherRepositoryProvider',
        'currentLocationProvider',
        'submitFeedback',
        'adjustManually',
      ];
      for (final path in [
        'lib/providers/saved_place_weather_provider.dart',
        'lib/data/repositories/saved_place_weather_repository.dart',
      ]) {
        final code = _withoutComments(File(path).readAsStringSync());
        for (final name in forbidden) {
          expect(code.contains(name), isFalse, reason: '$path が $name を参照');
        }
        expect(RegExp(r'\bmriProvider\b').hasMatch(code), isFalse,
            reason: '$path が現在地の mriProvider を参照');
        for (final import in [
          'emergency_alert_provider.dart',
          'push_provider.dart',
          'wallpaper_provider.dart',
          'mri_provider.dart',
          'privacy_provider.dart',
        ]) {
          expect(code.contains(import), isFalse,
              reason: '$path が $import を import');
        }
      }
      // weather_provider.dart からは HTTP クライアントだけを使う
      final provider = File('lib/providers/saved_place_weather_provider.dart')
          .readAsStringSync();
      expect(
        provider,
        contains(
            "import 'weather_provider.dart' show weatherApiClientProvider;"),
      );
    });
  });

  group('G2 lastGood は地点ごと', () {
    test('失敗時はその地点の直近成功分を返し、別地点・現在地のデータで代用しない', () async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);

      final first = await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      expect(first.temperature, 36);

      env.server.failing.addAll({'26.21', '38.72'});
      c.invalidate(savedPlaceSnapshotProvider(_nahaId));
      final fallback = await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      expect(fallback.temperature, 36); // 那覇の直近成功分

      // リスボンは一度も取れていない → 那覇の値で代用せずエラー
      await expectLater(
        c.read(savedPlaceSnapshotProvider(_lisbonId).future),
        throwsA(isA<AppException>()),
      );

      // 現在地は保存地点の取得の影響を受けない (lastGood は空のまま)
      expect(c.read(weatherRepositoryProvider).lastGoodSnapshot, isNull);
      env.server.failing.add('35.68');
      await expectLater(
        c.read(weatherSnapshotProvider.future),
        throwsA(isA<AppException>()),
      );
    });

    test('時間別も地点ごとに直近成功分を返す', () async {
      final env = await _Env.create(
        clock: () => DateTime.utc(2026, 6, 11, 3, 20),
      );
      final c = env.container;
      addTearDown(c.dispose);

      final hourly = await c.read(savedPlaceHourlyProvider(_nahaId).future);
      env.server.failing.add('26.21');
      c.invalidate(savedPlaceHourlyProvider(_nahaId));
      final fallback = await c.read(savedPlaceHourlyProvider(_nahaId).future);
      expect(fallback.length, hourly.length);
      expect(fallback.first.timestamp, hourly.first.timestamp);
    });

    test('削除した地点のキャッシュは捨てる', () async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);

      await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      await c.read(savedPlaceSnapshotProvider(_lisbonId).future);
      final repository = c.read(savedPlaceWeatherRepositoryProvider);
      expect(repository.cachedPlaceIds, {_nahaId, _lisbonId});

      await c.read(savedPlacesControllerProvider).remove(_nahaId);
      c.read(savedPlacesProvider);
      await pumpEventQueue();
      expect(repository.cachedPlaceIds, {_lisbonId});
    });
  });

  group('単発取得と同じ経路・同じ計算', () {
    test('同じ座標なら現在地の単発取得と同じスナップショット・MRI (空気質・気圧差あり)', () async {
      final env = await _Env.create(places: [
        _placeRecord(_homeId, '自宅', 35.68, 139.77),
      ]);
      final c = env.container;
      addTearDown(c.dispose);

      final saved = await c.read(savedPlaceSnapshotProvider(_homeId).future);
      final single = await WeatherRepository(
        apiClient: WeatherApiClient(httpClient: env.server.client),
      ).fetch(35.68, 139.77);

      // 一括取得 (Comfort-Twin) と違い、空気質と 6 時間気圧差が入っている
      expect(saved.aqi, 42);
      expect(saved.pressureChange6h, closeTo(-3.0, 1e-9));
      expect(saved.toJson(), single.toJson());
      expect(
        c.read(savedPlaceMriProvider(_homeId)).requireValue.value,
        MriCalculator.calculate(single).value,
      );
    });

    test('個人補正 θ を掛ける (学習済みプロファイルを反映)', () async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);

      await c.read(personalProfileProvider.notifier).adjustManually(
            (p) => p.copyWith(deltaT: -2.0, lambdaHeat: 1.4, betaHumid: 0.3),
          );
      final profile = c.read(personalProfileProvider);
      final snapshot = await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      final mri = c.read(savedPlaceMriProvider(_nahaId)).requireValue;

      expect(
          mri.value, MriCalculator.calculate(snapshot, profile: profile).value);
      expect(mri.isPersonalized, isTrue);

      final timeline =
          await c.read(savedPlaceHourlyProvider(_nahaId).future).then(
                (list) => MriTimeline.fromSnapshots(list, profile: profile),
              );
      expect(
        c.read(savedPlaceMriTimelineProvider(_nahaId)).requireValue.map(
              (p) => p.mri.value,
            ),
        timeline.map((p) => p.mri.value),
      );
    });

    test('旧 Comfort-Twin 記録は同梱カタログの座標で取得する', () async {
      final env = await _Env.create(
        places: [
          {
            'id': 'place-naha',
            'type': 'place',
            'mri': 40,
            'savedAt': '2026-06-01T10:00:00.000',
            'label': 'Naha',
          },
        ],
        catalog: const [
          City(
            id: 'naha',
            name: 'Naha',
            country: 'Japan',
            latitude: 26.21,
            longitude: 127.68,
            emoji: '🇯🇵',
          ),
        ],
      );
      final c = env.container;
      addTearDown(c.dispose);

      final snapshot =
          await c.read(savedPlaceSnapshotProvider('place-naha').future);
      expect(snapshot.temperature, 36);
      expect(
        env.server.requests.first.queryParameters['latitude'],
        '26.21',
      );
    });

    test('保存されていない地点・座標の無い地点はエラー (現在地で代用しない)', () async {
      final env = await _Env.create(places: [
        {
          'id': 'place-atlantis',
          'type': 'place',
          'mri': 50,
          'savedAt': '2026-06-01T10:00:00.000',
          'label': 'Atlantis',
        },
      ]);
      final c = env.container;
      addTearDown(c.dispose);

      await expectLater(
        c.read(savedPlaceSnapshotProvider('place-geo-999').future),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.unknown)),
      );
      await expectLater(
        c.read(savedPlaceSnapshotProvider('place-atlantis').future),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.location)),
      );
      expect(env.server.requests, isEmpty);
    });
  });

  group('時差 (utc_offset_seconds)', () {
    test('海外の地点: 現地の壁時計を絶対時刻に直し、鮮度判定が正しい', () async {
      // 端末のタイムゾーンに関係なく、今 = 2026-06-11 11:20Z (リスボン 12:20)。
      final now = DateTime.utc(2026, 6, 11, 11, 20);
      final env = await _Env.create(clock: () => now);
      final c = env.container;
      addTearDown(c.dispose);

      final s = await c.read(savedPlaceSnapshotProvider(_lisbonId).future);

      expect(
          s.timestamp.isAtSameMomentAs(DateTime.utc(2026, 6, 11, 11)), isTrue);
      expect(s.utcOffsetSeconds, 3600);
      expect(s.placeLocalTime.hour, 12); // 現地 12:00
      // 取得から 20 分: 2 時間の鮮度しきい値を超えない (旧実装は時差ぶんずれていた)
      expect(now.difference(s.timestamp), const Duration(minutes: 20));
    });

    test('海外の地点: 時間別の窓と「今」の位置を現地時刻で決める', () async {
      final now = DateTime.utc(2026, 6, 11, 11, 20); // リスボン 12:20
      final env = await _Env.create(clock: () => now);
      final c = env.container;
      addTearDown(c.dispose);

      final hourly = await c.read(savedPlaceHourlyProvider(_lisbonId).future);
      final timeline =
          c.read(savedPlaceMriTimelineProvider(_lisbonId)).requireValue;

      expect(hourly, hasLength(24));
      // 窓: 現地 6/11 06:00 (= 05:00Z) 〜 6/12 05:00
      expect(
          hourly.first.timestamp.isAtSameMomentAs(DateTime.utc(2026, 6, 11, 5)),
          isTrue);
      expect(hourly.first.placeLocalTime.hour, 6);
      // 「今」に最も近い点 = 現地 12:00 (= 11:00Z)。端末のタイムゾーンに依らない。
      final nowIndex = MriTimeline.indexNearest(timeline, reference: now);
      expect(timeline[nowIndex].snapshot.placeLocalTime.hour, 12);
      expect(
        timeline[nowIndex]
            .timestamp
            .isAtSameMomentAs(DateTime.utc(2026, 6, 11, 11)),
        isTrue,
      );
    });
  });

  group('保持 (10 分程度)', () {
    testWidgets('最初の取得から 10 分は取り直さず、過ぎたら破棄して取り直す', (tester) async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);

      final sub = c.listen(savedPlaceSnapshotProvider(_nahaId), (_, __) {});
      await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      expect(env.server.forecastCurrentCount('26.21'), 1);
      sub.close(); // 別の地点のタブへ切り替えた

      await tester.pump(const Duration(minutes: 5));
      expect(c.exists(savedPlaceSnapshotProvider(_nahaId)), isTrue);
      await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      expect(env.server.forecastCurrentCount('26.21'), 1); // 取り直していない

      await tester.pump(const Duration(minutes: 6)); // 最初の取得から 11 分
      expect(c.exists(savedPlaceSnapshotProvider(_nahaId)), isFalse);
      await c.read(savedPlaceSnapshotProvider(_nahaId).future);
      expect(env.server.forecastCurrentCount('26.21'), 2);

      c.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('失敗は保持しない (戻ってきたら取り直す)', (tester) async {
      final env = await _Env.create();
      final c = env.container;
      addTearDown(c.dispose);
      env.server.failing.add('26.21');

      final sub = c.listen(savedPlaceSnapshotProvider(_nahaId), (_, __) {});
      await expectLater(
        c.read(savedPlaceSnapshotProvider(_nahaId).future),
        throwsA(isA<AppException>()),
      );
      sub.close();
      // Riverpod は破棄を 0 秒タイマーで行う (擬似時間を少し進める)
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.exists(savedPlaceSnapshotProvider(_nahaId)), isFalse);

      c.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

/// 行コメント (// …) を除いたソース (コメント中の説明文を検査対象にしない)。
String _withoutComments(String source) => source.split('\n').map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    }).join('\n');
