// 緊急プッシュ購読 (lib/data/push/push_subscription.dart) のユニット。計画 S8 / S11。
//   - 購読登録の冪等性 (同じトークン・座標で複数回呼んでも 1 回しか書かない)
//   - フィールドが firestore.rules の許可集合と一致し、opt-out / 課金系キーを含まない
//   - 座標の粗視化 (小数 1 桁)・フォールバック地点では登録しない
//   - Firebase 不在 (disabled) / ゲートウェイ失敗 / ストア失敗で例外が漏れない
//   - 権限拒否でもローカル通知経路 (EmergencyAlertController) は生き続ける

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/push/firebase_push_runtime.dart';
import 'package:mood_ring_weather/data/push/push_subscription.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway implements PushMessagingGateway {
  String? token = 'tok_1';
  bool throwOnGetToken = false;
  bool permissionGranted = true;
  int getTokenCalls = 0;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<Map<Object?, Object?>>.broadcast();

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    if (throwOnGetToken) throw StateError('no firebase');
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<Map<Object?, Object?>> get onForegroundData => foreground.stream;

  @override
  Future<bool> requestPermission() async => permissionGranted;
}

class _FakeStore implements PushSubscriptionStore {
  final writes = <(String uid, Map<String, Object> fields)>[];
  bool throwOnUpsert = false;

  @override
  Future<void> upsert(String uid, Map<String, Object> fields) async {
    if (throwOnUpsert) throw StateError('permission-denied');
    writes.add((uid, Map.of(fields)));
  }
}

class _FakeNotificationGateway implements NotificationGateway {
  final shown = <String>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    shown.add(body);
  }
}

PushSubscriptionCoordinator _coordinator(
  _FakeGateway gateway,
  _FakeStore store, {
  Locale locale = const Locale('ja'),
  List<Map<Object?, Object?>>? pushed,
}) {
  return PushSubscriptionCoordinator(
    gateway: gateway,
    store: store,
    uid: 'uid_1',
    platform: 'android',
    localeOf: () => locale,
    onPushData: (data) async => pushed?.add(data),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildPushSubscriptionFields / roundCoarse', () {
    test('キー集合が firestore.rules の許可集合と一致し、座標は小数 1 桁', () {
      final f = buildPushSubscriptionFields(
        fcmToken: 't',
        platform: 'ios',
        locale:
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        latitude: 35.6812,
        longitude: 139.7671,
      );
      expect(f.keys.toSet(), kPushSubscriptionClientKeys);
      expect(f['lat'], 35.7);
      expect(f['lon'], 139.8);
      expect(f['locale'], 'zh-Hans');
      expect(f['platform'], 'ios');
    });

    test('opt-out / 課金 / 静音系のキーを一切含まない (spec §12.2.1)', () {
      final f = buildPushSubscriptionFields(
        fcmToken: 't',
        platform: 'android',
        locale: const Locale('en'),
        latitude: 0,
        longitude: 0,
      );
      for (final k in f.keys) {
        expect(
          k.toLowerCase(),
          isNot(anyOf(contains('opt'), contains('enabled'), contains('plus'),
              contains('tier'), contains('quiet'), contains('limit'))),
        );
      }
    });

    test('roundCoarse: 負の座標も 1 桁', () {
      expect(roundCoarse(-33.8688), -33.9);
      expect(roundCoarse(151.2093), 151.2);
    });
  });

  group('PushSubscriptionCoordinator.onSnapshot (冪等性)', () {
    test('同じトークン・座標で 3 回呼んでも書き込みは 1 回・1 ドキュメント', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final c = _coordinator(g, s);
      for (var i = 0; i < 3; i++) {
        await c.onSnapshot(latitude: 35.6812, longitude: 139.7671);
      }
      expect(s.writes, hasLength(1));
      expect(s.writes.single.$1, 'uid_1');
      expect(s.writes.single.$2, {
        'fcmToken': 'tok_1',
        'platform': 'android',
        'locale': 'ja',
        'lat': 35.7,
        'lon': 139.8,
      });
    });

    test('同じ 10km セル内の移動では書かず、セルを跨いだら書き直す', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final c = _coordinator(g, s);
      await c.onSnapshot(latitude: 35.6812, longitude: 139.7671);
      await c.onSnapshot(latitude: 35.6900, longitude: 139.7600); // 同セル
      expect(s.writes, hasLength(1));
      await c.onSnapshot(latitude: 35.9, longitude: 139.7671); // 別セル
      expect(s.writes, hasLength(2));
      expect(s.writes.last.$2['lat'], 35.9);
    });

    test('フォールバック地点 (位置情報なし) では登録しない', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final c = _coordinator(g, s);
      await c.onSnapshot(
          latitude: 35.681, longitude: 139.767, isFallbackLocation: true);
      expect(s.writes, isEmpty);
      expect(g.getTokenCalls, 0);
    });

    test('トークンが取れない (null / 空) 間は書かない', () async {
      final g = _FakeGateway()..token = null;
      final s = _FakeStore();
      final c = _coordinator(g, s);
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      g.token = '';
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      expect(s.writes, isEmpty);
    });

    test('言語を切り替えたら再登録する (locale はサーバーの本文言語選択に使う)', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      var locale = const Locale('ja');
      final c = PushSubscriptionCoordinator(
        gateway: g,
        store: s,
        uid: 'uid_1',
        platform: 'ios',
        localeOf: () => locale,
        onPushData: (_) async {},
      );
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      locale = const Locale('en');
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      expect(s.writes.map((w) => w.$2['locale']), ['ja', 'en']);
    });
  });

  group('PushSubscriptionCoordinator.start (トークン更新 / 前景受信)', () {
    test('onTokenRefresh で新トークンなら再 upsert、同じトークンなら書かない', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final c = _coordinator(g, s)..start();
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      g.refresh.add('tok_2');
      await Future<void>.delayed(Duration.zero);
      g.refresh.add('tok_2');
      await Future<void>.delayed(Duration.zero);
      expect(s.writes.map((w) => w.$2['fcmToken']), ['tok_1', 'tok_2']);
      await c.dispose();
    });

    test('座標未取得の間はトークン更新でも書かない (無関係な地点を登録しない)', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final c = _coordinator(g, s)..start();
      g.refresh.add('tok_2');
      await Future<void>.delayed(Duration.zero);
      expect(s.writes, isEmpty);
      await c.dispose();
    });

    test('前景受信の data は onPushData に渡る。start は 2 回呼んでも二重購読しない', () async {
      final g = _FakeGateway();
      final s = _FakeStore();
      final pushed = <Map<Object?, Object?>>[];
      final c = _coordinator(g, s, pushed: pushed)
        ..start()
        ..start();
      g.foreground.add({'type': 'emergency', 'kind': 'heat_stroke'});
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      await c.dispose();
    });
  });

  group('graceful degradation (例外を漏らさない)', () {
    test('disabled: すべて no-op で例外なし', () async {
      final c = PushSubscriptionCoordinator.disabled();
      expect(c.enabled, isFalse);
      c.start();
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      expect(await c.requestPermission(), isFalse);
      expect(c.lastRegistered, isNull);
      await c.dispose();
    });

    test('getToken が例外でも onSnapshot は例外を漏らさない', () async {
      final g = _FakeGateway()..throwOnGetToken = true;
      final s = _FakeStore();
      final c = _coordinator(g, s);
      await expectLater(
          c.onSnapshot(latitude: 35.7, longitude: 139.8), completes);
      expect(s.writes, isEmpty);
    });

    test('Firestore 書き込み拒否 (S1/S6 未反映相当) でも例外を漏らさず、次回再試行する', () async {
      final g = _FakeGateway();
      final s = _FakeStore()..throwOnUpsert = true;
      final c = _coordinator(g, s);
      await expectLater(
          c.onSnapshot(latitude: 35.7, longitude: 139.8), completes);
      expect(c.lastRegistered, isNull);
      s.throwOnUpsert = false;
      await c.onSnapshot(latitude: 35.7, longitude: 139.8);
      expect(s.writes, hasLength(1));
    });

    test('Firebase 不在の環境で initPushRuntime は disabled を返し例外を投げない', () async {
      // flutter_test には Firebase のプラットフォーム実装が無い =
      // 構成ファイル無し / Anonymous Auth 無効と同じ「初期化失敗」経路を通る。
      final runtime = await initPushRuntime();
      expect(runtime.available, isFalse);
      expect(runtime.uid, isNull);
    });

    test('pushPlatformName: iOS / Android 以外は null (登録対象外)', () {
      expect(pushPlatformName(TargetPlatform.iOS), 'ios');
      expect(pushPlatformName(TargetPlatform.android), 'android');
      expect(pushPlatformName(TargetPlatform.macOS), isNull);
      expect(pushPlatformName(TargetPlatform.linux), isNull);
    });
  });

  group('ローカル通知経路は push の状態に依存しない', () {
    test('権限拒否 (requestPermission=false) + push 無効でも現在値の緊急通知は出る', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notif = _FakeNotificationGateway();
      final controller = EmergencyAlertController(
        gateway: notif,
        prefs: prefs,
        localeOf: () => const Locale('ja'),
      );
      final g = _FakeGateway()..permissionGranted = false;
      final push = _coordinator(g, _FakeStore());
      expect(await push.requestPermission(), isFalse);

      await controller.onSnapshot(WeatherSnapshot(
        timestamp: DateTime(2026, 7, 15, 12),
        latitude: 35.66,
        longitude: 139.75,
        temperature: 38,
        humidity: 70,
        windSpeed: 25,
      ));
      expect(notif.shown, isNotEmpty);
      // 免責文の併記 (spec §12.10.4) も不変
      expect(notif.shown.first, contains('独自推定'));
    });
  });
}
