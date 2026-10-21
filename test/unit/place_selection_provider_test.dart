// test/unit/place_selection_provider_test.dart
//
// 表示中の地点 (providers/place_selection_provider.dart) と表示用 provider
// (providers/display_weather_provider.dart)。出荷条件 G3:
//   - 起動時は現在地 (永続化しない)
//   - 通知をタップして開いたら現在地
//   - バックグラウンドに 30 分以上いたら現在地
//   - 表示中の保存地点が削除されたら現在地
// 表示用 provider は、選択が null なら現在地の provider をそのまま返し、
// 保存地点の取得中・失敗を現在地のデータで代用しない。

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mood_ring_weather/data/datasources/weather_api_client.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/push/firebase_push_runtime.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/display_weather_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/mri_provider.dart';
import 'package:mood_ring_weather/providers/notification_tap_provider.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/push_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nahaId = 'place-geo-1856035';
const _kyotoId = 'place-geo-1857910';

Map<String, dynamic> _placeRecord(
        String id, String label, double lat, double lon, int day) =>
    {
      'id': id,
      'type': 'place',
      'mri': null,
      'savedAt': '2026-09-0${day}T09:00:00.000',
      'label': label,
      'location': {'lat': lat, 'lon': lon},
      'addedAt': '2026-09-0${day}T09:00:00.000',
    };

/// 現在地のスナップショット (東京・快適)。
final _currentSnapshot = WeatherSnapshot(
  timestamp: DateTime(2026, 6, 11, 12),
  latitude: 35.68,
  longitude: 139.77,
  temperature: 22,
);

/// 保存地点の天気のフェイク。[gate] が完了するまで応答しない (取得中の再現)。
class _PlaceWeatherServer {
  Completer<void> gate = Completer<void>()..complete();
  bool fail = false;
  final requests = <Uri>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request.url);
    await gate.future;
    if (fail) return http.Response('down', 503);
    final isAir = request.url.host.startsWith('air-quality');
    if (isAir) {
      return http.Response(
        jsonEncode({
          'current': {'us_aqi': 30},
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'utc_offset_seconds': 32400,
        'current': {
          'time': '2026-06-11T12:00',
          'temperature_2m': 30.0,
          'relative_humidity_2m': 70,
        },
      }),
      200,
    );
  });
}

class _Env {
  _Env(this.container, this.server, this.pushOpened);

  final ProviderContainer container;
  final _PlaceWeatherServer server;
  final StreamController<void> pushOpened;

  static DateTime now = DateTime(2026, 9, 28, 9);

  static Future<_Env> create() async {
    now = DateTime(2026, 9, 28, 9);
    SharedPreferences.setMockInitialValues({
      kPrefKeyComfortRecords: jsonEncode([
        _placeRecord(_kyotoId, '京都', 35.02, 135.75, 2),
        _placeRecord(_nahaId, '那覇', 26.21, 127.68, 1),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final server = _PlaceWeatherServer();
    final pushOpened = StreamController<void>.broadcast();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cityCatalogProvider.overrideWith((ref) async => const []),
        clockProvider.overrideWithValue(() => now),
        weatherApiClientProvider.overrideWithValue(
          WeatherApiClient(httpClient: server.client),
        ),
        // 現在地の経路はここでは固定値 (保存地点で代用されないことを見る)
        weatherSnapshotProvider.overrideWith((ref) async => _currentSnapshot),
        hourlyWeatherProvider.overrideWith((ref) async => [_currentSnapshot]),
        cityNameProvider.overrideWith((ref) async => '東京'),
        pushRuntimeProvider.overrideWithValue(
          PushRuntime(available: false, notificationOpened: pushOpened.stream),
        ),
        // Plus (保存 5 件まで)
        isPlusProvider.overrideWithValue(true),
        savedLocationLimitProvider.overrideWithValue(5),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await pushOpened.close();
    });
    return _Env(container, server, pushOpened);
  }

  PlaceSelectionController get selection =>
      container.read(selectedPlaceIdProvider.notifier);

  String? get selected => container.read(selectedPlaceIdProvider);
}

void main() {
  group('G3 表示中の地点', () {
    test('起動時は現在地 (null)。選択は永続化しない', () async {
      final env = await _Env.create();
      expect(env.selected, isNull);
      expect(env.container.read(displayedPlaceIdProvider), isNull);

      env.selection.select(_nahaId);
      expect(env.selected, _nahaId);

      // 新しい起動 (= 新しいコンテナ) では現在地から始まる
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('select')), isEmpty);
      final next = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cityCatalogProvider.overrideWith((ref) async => const []),
      ]);
      addTearDown(next.dispose);
      expect(next.read(selectedPlaceIdProvider), isNull);
    });

    test('保存されていない地点は選べない (現在地のまま)', () async {
      final env = await _Env.create();
      env.selection.select('place-geo-404');
      expect(env.selected, isNull);
    });

    test('現在地に戻す操作', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);
      env.selection.showCurrentLocation();
      expect(env.selected, isNull);
      expect(env.selection.isShowingCurrentLocation, isTrue);
    });

    test('通知 (ローカル通知) をタップして開いたら現在地', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);

      env.container.read(notificationTapSignalProvider).notifyTapped();
      await pumpEventQueue();

      expect(env.selected, isNull);
    });

    test('OS が表示した FCM 通知から開いたら現在地', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);

      env.pushOpened.add(null);
      await pumpEventQueue();

      expect(env.selected, isNull);
    });

    test('バックグラウンド 30 分以上で現在地、30 分未満はそのまま', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);

      env.selection.onAppLifecycleChanged(AppLifecycleState.inactive);
      env.selection.onAppLifecycleChanged(AppLifecycleState.hidden);
      _Env.now = _Env.now.add(const Duration(minutes: 29, seconds: 59));
      env.selection.onAppLifecycleChanged(AppLifecycleState.paused);
      env.selection.onAppLifecycleChanged(AppLifecycleState.resumed);
      expect(env.selected, _nahaId);

      env.selection.onAppLifecycleChanged(AppLifecycleState.hidden);
      env.selection.onAppLifecycleChanged(AppLifecycleState.paused);
      _Env.now = _Env.now.add(const Duration(minutes: 30));
      env.selection.onAppLifecycleChanged(AppLifecycleState.hidden);
      env.selection.onAppLifecycleChanged(AppLifecycleState.inactive);
      env.selection.onAppLifecycleChanged(AppLifecycleState.resumed);
      expect(env.selected, isNull);
    });

    test('inactive (通知センター・着信) だけでは時間を数えない', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);
      env.selection.onAppLifecycleChanged(AppLifecycleState.inactive);
      _Env.now = _Env.now.add(const Duration(hours: 2));
      env.selection.onAppLifecycleChanged(AppLifecycleState.resumed);
      expect(env.selected, _nahaId);
    });

    test('表示中の保存地点を削除したら現在地', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);

      await env.container.read(savedPlacesControllerProvider).remove(_nahaId);
      env.container.read(savedPlacesProvider);
      await pumpEventQueue();

      expect(env.selected, isNull);
      expect(env.container.read(displayedPlaceIdProvider), isNull);
    });

    test('追加した直後の地点をすぐ選べ、元に戻すと現在地に戻る', () async {
      final env = await _Env.create();
      final c = env.container;
      expect(c.read(selectedPlaceIdProvider), isNull); // UI と同じく先に作る
      final places = c.read(savedPlacesControllerProvider);

      final result = await places.add(const PlaceCandidate(
        geocodingId: 1863967,
        name: '福岡',
        sourceName: '福岡市',
        latitude: 33.6,
        longitude: 130.42,
      ));
      // 保存地点の一覧の更新 (非同期の通知) を待たずに選べる
      env.selection.select(result.placeId);
      expect(env.selected, 'place-geo-1863967');
      expect(c.read(displayedPlaceIdProvider), 'place-geo-1863967');

      await places.undo(result);
      c.read(savedPlacesProvider);
      await pumpEventQueue();
      expect(env.selected, isNull);
    });

    test('別の地点を削除しても表示は変えない', () async {
      final env = await _Env.create();
      env.selection.select(_nahaId);

      await env.container.read(savedPlacesControllerProvider).remove(_kyotoId);
      env.container.read(savedPlacesProvider);
      await pumpEventQueue();

      expect(env.selected, _nahaId);
    });
  });

  group('表示用 provider', () {
    test('現在地: 既存の現在地 provider の値をそのまま返す', () async {
      final env = await _Env.create();
      final c = env.container;
      await c.read(weatherSnapshotProvider.future);
      await c.read(hourlyWeatherProvider.future);

      expect(c.read(displayWeatherSnapshotProvider).requireValue,
          same(_currentSnapshot));
      expect(c.read(displayMriProvider).requireValue.value,
          c.read(mriProvider).requireValue.value);
      expect(c.read(displayHourlyWeatherProvider).requireValue.single,
          same(_currentSnapshot));
      expect(c.read(displayMriTimelineProvider).requireValue, hasLength(1));
      await c.read(cityNameProvider.future);
      expect(c.read(displayPlaceNameProvider).requireValue, '東京');
      expect(c.read(displayedSavedPlaceProvider), isNull);
      expect(env.server.requests, isEmpty); // 保存地点の取得は起きない
    });

    test('保存地点: その地点の天気・MRI・地名を返す', () async {
      final env = await _Env.create();
      final c = env.container;
      env.selection.select(_nahaId);

      final sub = c.listen(displayWeatherSnapshotProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final snapshot = c.read(displayWeatherSnapshotProvider).requireValue;
      expect(snapshot.temperature, 30);
      expect(snapshot.latitude, 26.21);
      final MoodRingIndex mri = c.read(displayMriProvider).requireValue;
      expect(mri.band, isA<MriBand>());
      expect(c.read(displayPlaceNameProvider).requireValue, '那覇');
      expect(c.read(displayedSavedPlaceProvider)!.id, _nahaId);
    });

    test('保存地点の取得中・失敗は現在地のデータで代用しない', () async {
      final env = await _Env.create();
      final c = env.container;
      await c.read(weatherSnapshotProvider.future);
      env.server.gate = Completer<void>();
      env.selection.select(_nahaId);

      final sub = c.listen(displayWeatherSnapshotProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(c.read(displayWeatherSnapshotProvider).isLoading, isTrue);
      expect(c.read(displayWeatherSnapshotProvider).valueOrNull, isNull);
      expect(c.read(displayMriProvider).valueOrNull, isNull);

      env.server.fail = true;
      env.server.gate.complete();
      await pumpEventQueue();
      expect(c.read(displayWeatherSnapshotProvider).hasError, isTrue);
      expect(c.read(displayWeatherSnapshotProvider).valueOrNull, isNull);
      // 現在地の値はそのまま (別の経路)
      expect(
          c.read(weatherSnapshotProvider).requireValue, same(_currentSnapshot));
    });

    test('表示中の地点が削除されたら表示用 provider も現在地に戻る', () async {
      final env = await _Env.create();
      final c = env.container;
      await c.read(weatherSnapshotProvider.future);
      env.selection.select(_nahaId);
      final sub = c.listen(displayWeatherSnapshotProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(
          c.read(displayWeatherSnapshotProvider).requireValue.temperature, 30);

      await c.read(savedPlacesControllerProvider).remove(_nahaId);
      await pumpEventQueue();

      expect(c.read(displayWeatherSnapshotProvider).requireValue,
          same(_currentSnapshot));
    });
  });
}
