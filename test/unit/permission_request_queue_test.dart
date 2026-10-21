// 実行時権限の要求を 1 つずつ順に行う (permission_request_queue.dart)。
//
// 回帰: 初回起動で通知の許可ダイアログと位置情報の許可の要求が重なり、
// Android が位置情報の要求を取り消す → geolocator が応答せず、位置情報の
// ダイアログが出ないまま現在地の取得が止まっていた (2026-09-29 実機)。
// キューを通らない要求はまた取り消しを起こすため、lib/ の権限の要求が
// すべてキューを通ることも静的に確かめる (QA-17)。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/permissions/permission_request_queue.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runPermissionRequest', () {
    test('先の要求が終わるまで次の要求を始めない', () async {
      final location = Completer<String>();
      final started = <String>[];
      final first = runPermissionRequest(() {
        started.add('location');
        return location.future;
      });
      final second = runPermissionRequest(() async {
        started.add('notification');
        return 'notification';
      });

      await pumpEventQueue();
      expect(started, ['location']);

      location.complete('location');
      expect(await first, 'location');
      expect(await second, 'notification');
      expect(started, ['location', 'notification']);
    });

    test('失敗した要求は呼び出し元へ返し、後続の要求は止めない', () async {
      final failed = runPermissionRequest<void>(
        () async => throw PlatformException(code: 'x'),
      );
      final thrown = runPermissionRequest<void>(() => throw StateError('x'));
      final next = runPermissionRequest(() async => 1);

      await expectLater(failed, throwsA(isA<PlatformException>()));
      await expectLater(thrown, throwsStateError);
      expect(await next, 1);
    });
  });

  group('LocalNotificationGateway (Android)', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    late List<String> calls;

    int permissionRequests() =>
        calls.where((m) => m == 'requestNotificationsPermission').length;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('起動時と緊急アラートが同時に初期化しても、通知の許可は 1 回だけ求める', () async {
      final gateway =
          LocalNotificationGateway(plugin: FlutterLocalNotificationsPlugin());

      await Future.wait([gateway.initialize(), gateway.initialize()]);
      expect(permissionRequests(), 1);

      await gateway.initialize();
      expect(permissionRequests(), 1);
    });

    test('位置情報の許可ダイアログへの回答を待ってから、通知の許可を求める', () async {
      final location = Completer<void>();
      final pendingLocation = runPermissionRequest<void>(() => location.future);
      final gateway =
          LocalNotificationGateway(plugin: FlutterLocalNotificationsPlugin());

      final init = gateway.initialize();
      await pumpEventQueue();
      // プラグインの初期化 (通知タップの受け口) は待たない。
      expect(calls, contains('initialize'));
      expect(permissionRequests(), 0);

      location.complete();
      await pendingLocation;
      await init;
      expect(permissionRequests(), 1);
    });

    test('初期化に失敗したら、次の呼び出しでやり直す', () async {
      var failNext = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'initialize' && failNext) {
          failNext = false;
          throw PlatformException(code: 'boom');
        }
        return true;
      });
      final gateway =
          LocalNotificationGateway(plugin: FlutterLocalNotificationsPlugin());

      await expectLater(
          gateway.initialize(), throwsA(isA<PlatformException>()));
      await gateway.initialize();
      expect(calls.where((m) => m == 'initialize'), hasLength(2));
      expect(permissionRequests(), 1);
    });
  });

  group('権限の要求は必ずキューを通す (静的検査)', () {
    test('lib/ で権限ダイアログを出す API を呼ぶのは、runPermissionRequest を通すファイルだけ', () {
      // 権限ダイアログを出すプラグインの API (呼び出しと、関数としての受け渡し)。
      final api = RegExp(
        r'Geolocator\s*\.\s*requestPermission\b'
        r'|[.?]\s*(requestPermissions?|requestNotificationsPermission'
        r'|requestExactAlarmsPermission|requestFullScreenIntentPermission)'
        r'\s*\(',
      );
      // runPermissionRequest を通して呼ぶファイル。
      const queued = {
        'lib/data/datasources/location_datasource.dart',
        'lib/data/services/notification_service.dart',
        'lib/data/push/firebase_push_runtime.dart',
      };
      // 自前の抽象 (PushMessagingGateway.requestPermission) を呼ぶだけのファイル。
      // 実装 (firebase_push_runtime.dart) がキューを通す。
      const viaGateway = {'lib/data/push/push_subscription.dart'};

      final callers = {
        for (final file
            in Directory('lib').listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.dart') &&
              api.hasMatch(_withoutComments(file.readAsStringSync())))
            file.path,
      };
      expect(callers, containsAll(queued));
      expect(
        callers.difference({...queued, ...viaGateway}),
        isEmpty,
        reason: '権限の要求は runPermissionRequest (permission_request_queue.dart) '
            'を通す。通したら queued に足す',
      );
      for (final path in queued) {
        expect(
          _withoutComments(File(path).readAsStringSync()),
          contains('runPermissionRequest'),
          reason: path,
        );
      }
    });
  });
}

String _withoutComments(String source) => source.split('\n').map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    }).join('\n');
