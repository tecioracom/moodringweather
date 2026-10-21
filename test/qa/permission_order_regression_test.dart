// test/qa/permission_order_regression_test.dart
//
// 初回起動の許可ダイアログの不具合 (QA-16、Sev1) の修正を守る回帰テスト。
// qa のテスト案 (docs/qa-16_permission-dialog_evidence/
// proposed_permission_order_test.dart.txt、175b185 で 4 件合格) を取り込んだもの
// (QA-19、docs/qa-report-saved-places-2026-09-29.md §S.6)。
//
// 1. main.dart: 起動時の通知の初期化は、現在地の取得 (許可ダイアログへの回答を
//    含む) が終わるまで始まらない。取得が失敗しても初期化は行う。
// 2. LocationDataSource: キューで待っている間に別の要求で許可が決まれば、
//    二重に requestPermission しない。
// 3. (QA-17) 先の位置情報の要求に回答が来なくても (要求の取り消し)、見切って
//    通知の初期化 (= 緊急アラートの表示前段) と位置情報の取り直しが進む。
//    qa の案では「止まる」ことを確かめる特性テストだった。QA-17 の修正
//    (unanswered_permission_request.dart) に合わせて「止まらない」形に書き換えた。
//
// キュー (permission_request_queue.dart) はアイソレートで共有されるため、
// キューを通るテスト (2・3) は testWidgets の fake zone の外 (通常の test) で行う。
// 許可ダイアログが出ている間はアプリの状態を inactive にする (見切りは前面に
// いる時間だけを数える)。実時間の速さに結果が左右されないようにするため。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/main.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';
import '../fixtures/saved_places_fixtures.dart';
import '../golden/golden_harness.dart';

class _RecordingGateway implements NotificationGateway {
  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {}
}

class _FakeWallpaper implements WallpaperBridge {
  @override
  Future<bool> setMriState(WallpaperState state) async => true;

  @override
  Future<bool> clearMriState() async => true;
}

class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  int requestCalls = 0;
  final pending = <Completer<LocationPermission>>[];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requestCalls++;
    final c = Completer<LocationPermission>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async =>
      Position(
        latitude: 34.7,
        longitude: 135.5,
        timestamp: DateTime(2026, 9, 29),
        accuracy: 1000,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

/// アプリの状態 (許可ダイアログが出ている間は inactive、取り消されたら resumed)。
void _setLifecycle(AppLifecycleState state) =>
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);

Future<_RecordingGateway> _pumpApp(
  WidgetTester tester,
  Future<GeoPoint> Function() location,
) async {
  useGoldenViewport(tester);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = _RecordingGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => kPlacesNow),
        cityCatalogProvider.overrideWith((ref) async => const <City>[]),
        currentLocationProvider.overrideWith((ref) => location()),
        weatherSnapshotProvider.overrideWith(
          (ref) async => comfortableSnapshot(kPlacesNow),
        ),
        hourlyWeatherProvider.overrideWith(
          (ref) async => hourlyAround(comfortableSnapshot),
        ),
        cityNameProvider.overrideWith((ref) async => 'Tokyo'),
        ...entitlementOverrides(plus: false),
        notificationGatewayProvider.overrideWithValue(gateway),
        wallpaperBridgeProvider.overrideWithValue(_FakeWallpaper()),
        RecordingWallpaperOverlay().providerOverride,
      ],
      child: const MoodRingApp(),
    ),
  );
  return gateway;
}

void main() {
  group('QA-16 main.dart の順序', () {
    testWidgets('現在地の取得が終わるまで通知の初期化を始めない', (tester) async {
      final location = Completer<GeoPoint>();
      final gateway = await _pumpApp(tester, () => location.future);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(gateway.initializeCalls, 0);

      location.complete(const GeoPoint(35.68, 139.77));
      await tester.pump();
      await tester.pump();
      expect(gateway.initializeCalls, 1);
    });

    testWidgets('現在地の取得が失敗しても通知の初期化は行う', (tester) async {
      final location = Completer<GeoPoint>();
      final gateway = await _pumpApp(tester, () => location.future);
      await tester.pump(const Duration(seconds: 1));
      expect(gateway.initializeCalls, 0);

      location.completeError(StateError('boom'));
      await tester.pump();
      await tester.pump();
      expect(gateway.initializeCalls, 1);
    });
  });

  group('QA-16 LocationDataSource', () {
    late GeolocatorPlatform original;
    setUp(() => original = GeolocatorPlatform.instance);
    tearDown(() {
      GeolocatorPlatform.instance = original;
      _setLifecycle(AppLifecycleState.resumed);
    });

    test('待っている間に許可が決まれば、二重に聞かない', () async {
      final fake = _FakeGeolocator();
      GeolocatorPlatform.instance = fake;
      const ds = LocationDataSource();

      // a の許可ダイアログが出ている。
      _setLifecycle(AppLifecycleState.inactive);
      final a = ds.getCurrentPosition();
      await pumpEventQueue();
      expect(fake.requestCalls, 1);

      final b = ds.getCurrentPosition();
      await pumpEventQueue();
      expect(fake.requestCalls, 1, reason: 'b waits in the queue');

      fake.permission = LocationPermission.whileInUse;
      fake.pending.single.complete(LocationPermission.whileInUse);
      expect((await a).isFallback, isFalse);
      expect((await b).isFallback, isFalse);
      expect(fake.requestCalls, 1);
    });
  });

  group('QA-17 先の要求に回答が来ない場合 (見切り)', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    late List<String> calls;
    late GeolocatorPlatform original;
    late _FakeGeolocator fake;

    int notificationRequests() =>
        calls.where((m) => m == 'requestNotificationsPermission').length;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      original = GeolocatorPlatform.instance;
      fake = _FakeGeolocator();
      GeolocatorPlatform.instance = fake;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      GeolocatorPlatform.instance = original;
      _setLifecycle(AppLifecycleState.resumed);
    });

    test('位置情報の要求に回答が来なくても、見切って通知の初期化 (= 緊急アラートの表示前段) と位置情報の取り直しが進む', () async {
      // 見切りまでの時間だけ短くする (既定は前面で 4 秒。実時間では待たない)。
      const ds = LocationDataSource(
        permissionGiveUpAfter: Duration(milliseconds: 1),
      );

      // 位置情報の許可ダイアログが出ている (アプリは inactive)。
      // 見切ったら拒否として扱う (provider は既定地点で表示する)。
      _setLifecycle(AppLifecycleState.inactive);
      final first = expectLater(
        ds.getCurrentPosition(),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.permissionDenied)),
      );
      await pumpEventQueue();
      expect(fake.requestCalls, 1);

      final gateway = LocalNotificationGateway(
        plugin: FlutterLocalNotificationsPlugin(),
      );
      final init = gateway.initialize();
      // 見切りの時間の何倍待っても、ダイアログが出ている間は通知の許可を重ねない。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(notificationRequests(), 0);

      // 要求が取り消され (geolocator_android は応答しない)、アプリが前面に戻る。
      // 修正前はここで止まった (キューが永久に空かない)。
      _setLifecycle(AppLifecycleState.resumed);
      await init.timeout(const Duration(seconds: 10));
      await first;
      expect(notificationRequests(), 1);

      // 引っ張って更新などで取り直すと、位置情報のダイアログがもう一度出て
      // (修正前は出なかった)、その回答で進む。
      final again = ds.getCurrentPosition();
      await pumpEventQueue();
      expect(fake.requestCalls, 2, reason: '2 回目のダイアログが出る');

      fake.permission = LocationPermission.whileInUse;
      fake.pending.last.complete(LocationPermission.whileInUse);
      expect((await again).isFallback, isFalse);
    });
  });
}
