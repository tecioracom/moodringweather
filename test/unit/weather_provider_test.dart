// test/unit/weather_provider_test.dart
//
// weather_provider (位置 → 天気取得の Riverpod 配線) のユニット。
// これまで widget テスト経由の間接カバーのみだった provider 層エッジを
// 直接検証する (qa-test-report.md Sev3-9 の解消):
//   - 位置権限拒否/取得失敗 → 東京フォールバック (isFallback=true)
//   - 許可ダイアログを見切ったあとで遅れて許可が届いたら取り直す (QA-17)
//   - 取得失敗 + キャッシュあり → 直近成功分を返す (stale フォールバック)
//   - 取得失敗 + キャッシュなし → AppException 伝播
//   - 取得成功 → 緊急アラート判定が配線されている (WBGT 危険域で発火)
//   - 通知ゲートウェイ故障でも天気表示は止めない (best-effort)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/repositories/weather_repository.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _permissionDenied = AppException(
  '位置情報の利用を許可してください(設定 > プライバシー)。',
  'Location permission denied',
  ErrorType.permissionDenied,
);

const _networkError = AppException(
  '天気データを取得できませんでした。通信環境をご確認ください。',
  'HTTP 503',
  ErrorType.network,
);

class _FixedLocation extends LocationDataSource {
  const _FixedLocation(this.point);
  final GeoPoint point;

  @override
  Future<GeoPoint> getCurrentPosition({void Function()? onLateGrant}) async =>
      point;
}

class _ThrowingLocation extends LocationDataSource {
  const _ThrowingLocation(this.error);
  final AppException error;

  @override
  Future<GeoPoint> getCurrentPosition({void Function()? onLateGrant}) async =>
      throw error;
}

/// 1 回目は許可ダイアログへの回答を待ちきれずに見切った (拒否として扱う)。
/// 遅れて届く許可は、受け取った onLateGrant をテストが呼んで出す。
/// 2 回目以降は実座標を返す。
class _LateGrantLocation extends LocationDataSource {
  _LateGrantLocation();

  final onLateGrants = <void Function()>[];
  int calls = 0;

  @override
  Future<GeoPoint> getCurrentPosition({void Function()? onLateGrant}) async {
    calls++;
    if (onLateGrant != null) onLateGrants.add(onLateGrant);
    if (calls == 1) throw _permissionDenied;
    return const GeoPoint(43.06, 141.35);
  }
}

/// 実 HTTP を使わないフェイクリポジトリ。失敗・キャッシュ状態を注入できる。
class _FakeRepository extends WeatherRepository {
  _FakeRepository({
    this.current,
    this.error,
    this.cachedSnapshot,
    this.cachedHourly,
  });

  WeatherSnapshot? current;
  List<WeatherSnapshot>? hourly;
  AppException? error;
  WeatherSnapshot? cachedSnapshot;
  List<WeatherSnapshot>? cachedHourly;
  int fetchCount = 0;

  @override
  WeatherSnapshot? get lastGoodSnapshot => cachedSnapshot;

  @override
  List<WeatherSnapshot>? get lastGoodHourly => cachedHourly;

  @override
  Future<WeatherSnapshot> fetch(double latitude, double longitude) async {
    fetchCount++;
    final e = error;
    if (e != null) throw e;
    return current!;
  }

  @override
  Future<List<WeatherSnapshot>> fetchHourly(
    double latitude,
    double longitude,
  ) async {
    final e = error;
    if (e != null) throw e;
    return hourly!;
  }
}

class _ShownNotification {
  _ShownNotification(this.id, this.critical);
  final int id;
  final bool critical;
}

class _FakeGateway implements NotificationGateway {
  final shown = <_ShownNotification>[];
  bool failOnShow = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    if (failOnShow) throw StateError('plugin unavailable');
    shown.add(_ShownNotification(id, critical));
  }
}

WeatherSnapshot _snapshot({
  double temperature = 22,
  double? humidity = 50,
  double? solarRadiationWm2 = 0,
}) {
  return WeatherSnapshot(
    timestamp: DateTime(2026, 6, 11, 12),
    latitude: 35.681,
    longitude: 139.767,
    temperature: temperature,
    humidity: humidity,
    solarRadiationWm2: solarRadiationWm2,
  );
}

Future<ProviderContainer> _container({
  LocationDataSource location = const _FixedLocation(GeoPoint(35.0, 139.0)),
  WeatherRepository? repository,
  NotificationGateway? gateway,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      locationDataSourceProvider.overrideWithValue(location),
      if (repository != null)
        weatherRepositoryProvider.overrideWithValue(repository),
      if (gateway != null)
        notificationGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('currentLocationProvider', () {
    test('取得成功: 実座標を返し isFallback=false', () async {
      final c = await _container(
        location: const _FixedLocation(GeoPoint(43.06, 141.35)),
      );
      final point = await c.read(currentLocationProvider.future);
      expect(point.latitude, 43.06);
      expect(point.longitude, 141.35);
      expect(point.isFallback, isFalse);
    });

    test('権限拒否: 東京の既定地点へフォールバック (isFallback=true)', () async {
      final c = await _container(
        location: const _ThrowingLocation(_permissionDenied),
      );
      final point = await c.read(currentLocationProvider.future);
      expect(point.isFallback, isTrue);
      expect(point.latitude, LocationDataSource.fallback.latitude);
      expect(point.longitude, LocationDataSource.fallback.longitude);
    });

    test('許可ダイアログを見切ったあとで遅れて許可が届いたら、現在地を取り直す (QA-17)', () async {
      final location = _LateGrantLocation();
      final c = await _container(location: location);
      expect((await c.read(currentLocationProvider.future)).isFallback, isTrue);

      location.onLateGrants.single();
      final point = await c.read(currentLocationProvider.future);
      expect(point.isFallback, isFalse);
      expect(point.latitude, 43.06);
      expect(location.calls, 2);
    });

    test('取り直したあとに古い取得の許可が届いても、もう一度は取り直さない', () async {
      final location = _LateGrantLocation();
      final c = await _container(location: location);
      await c.read(currentLocationProvider.future);

      // 引っ張って更新などで先に取り直した。
      c.invalidate(currentLocationProvider);
      expect(
          (await c.read(currentLocationProvider.future)).isFallback, isFalse);
      expect(location.calls, 2);

      location.onLateGrants.first();
      await c.read(currentLocationProvider.future);
      expect(location.calls, 2);
    });
  });

  group('weatherSnapshotProvider', () {
    test('取得成功: スナップショットを返す', () async {
      final repo = _FakeRepository(current: _snapshot());
      final c = await _container(repository: repo, gateway: _FakeGateway());
      final snapshot = await c.read(weatherSnapshotProvider.future);
      expect(snapshot.temperature, 22);
      expect(repo.fetchCount, 1);
    });

    test('取得失敗 + キャッシュあり: 直近成功分を返す', () async {
      final cached = _snapshot(temperature: 19);
      final repo =
          _FakeRepository(error: _networkError, cachedSnapshot: cached);
      final c = await _container(repository: repo, gateway: _FakeGateway());
      final snapshot = await c.read(weatherSnapshotProvider.future);
      expect(snapshot.temperature, 19);
    });

    test('取得失敗 + キャッシュなし: AppException を伝播する', () async {
      final repo = _FakeRepository(error: _networkError);
      final c = await _container(repository: repo, gateway: _FakeGateway());
      await expectLater(
        c.read(weatherSnapshotProvider.future),
        throwsA(isA<AppException>().having(
          (e) => e.type,
          'type',
          ErrorType.network,
        )),
      );
    });

    test('権限拒否でも東京フォールバック経由で天気が取得できる', () async {
      final repo = _FakeRepository(current: _snapshot());
      final c = await _container(
        location: const _ThrowingLocation(_permissionDenied),
        repository: repo,
        gateway: _FakeGateway(),
      );
      final snapshot = await c.read(weatherSnapshotProvider.future);
      expect(snapshot.temperature, 22);
      expect(repo.fetchCount, 1);
    });

    test('WBGT 危険域のスナップショットで緊急通知が発火する (配線確認)', () async {
      // 36°C / RH60% / SR900 → WBGT ≈ 38.2 (mri-spec §8.3) ≥ 33 = danger。
      final repo = _FakeRepository(
        current:
            _snapshot(temperature: 36, humidity: 60, solarRadiationWm2: 900),
      );
      final gateway = _FakeGateway();
      final c = await _container(repository: repo, gateway: gateway);
      await c.read(weatherSnapshotProvider.future);
      expect(gateway.shown, hasLength(1));
      expect(gateway.shown.single.id, 1001); // 熱中症の固定 ID
      expect(gateway.shown.single.critical, isTrue); // danger = Time-Sensitive
    });

    test('快適域では緊急通知は発火しない', () async {
      final gateway = _FakeGateway();
      final c = await _container(
        repository: _FakeRepository(current: _snapshot()),
        gateway: gateway,
      );
      await c.read(weatherSnapshotProvider.future);
      expect(gateway.shown, isEmpty);
    });

    test('通知ゲートウェイ故障でも天気表示は止めない (best-effort)', () async {
      final gateway = _FakeGateway()..failOnShow = true;
      final c = await _container(
        repository: _FakeRepository(
          current:
              _snapshot(temperature: 36, humidity: 60, solarRadiationWm2: 900),
        ),
        gateway: gateway,
      );
      final snapshot = await c.read(weatherSnapshotProvider.future);
      expect(snapshot.temperature, 36);
    });
  });

  group('hourlyWeatherProvider', () {
    test('取得失敗 + キャッシュあり: 直近成功分を返す', () async {
      final cachedHourly = [_snapshot(temperature: 18)];
      final repo =
          _FakeRepository(error: _networkError, cachedHourly: cachedHourly);
      final c = await _container(repository: repo, gateway: _FakeGateway());
      final points = await c.read(hourlyWeatherProvider.future);
      expect(points, hasLength(1));
      expect(points.single.temperature, 18);
    });

    test('取得失敗 + キャッシュなし: AppException を伝播する', () async {
      final repo = _FakeRepository(error: _networkError);
      final c = await _container(repository: repo, gateway: _FakeGateway());
      await expectLater(
        c.read(hourlyWeatherProvider.future),
        throwsA(isA<AppException>()),
      );
    });
  });
}
