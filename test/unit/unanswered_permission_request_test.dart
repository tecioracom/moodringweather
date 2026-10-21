// 回答の来ない権限の要求の見切り (unanswered_permission_request.dart、QA-17)。
//
// 回帰: geolocator の要求が取り消されると (結果の配列が空) 応答が無く、権限の
// 要求のキューが永久に空かなかった。以後の位置情報・通知の要求 (FCM 前景の
// 緊急アラートの表示前段を含む) がすべて止まり、引っ張って更新しても戻らな
// かった (docs/qa-report-saved-places-2026-09-29.md §S.6)。
//
// 実時間では何秒も待たない:
//   - 見切りの時間の判断は testWidgets の fake time で進める (既定の 4 秒のまま)。
//   - キュー (permission_request_queue.dart) を通すものは通常の test で、見切り
//     までの時間を短く注入する。キューはアイソレートで共有されるため、
//     testWidgets の fake zone の中では使わない (終わった fake zone に後続の
//     処理が積まれ、以後のキューが進まなくなる)。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/core/permissions/permission_request_queue.dart';
import 'package:mood_ring_weather/core/permissions/unanswered_permission_request.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';

/// 見切りの対象の要求 (回答はテストが出す) と、アプリの状態。
class _Request {
  _Request({this.state = AppLifecycleState.resumed});

  /// アプリの状態 (見切りの判断に使う)。
  AppLifecycleState? state;

  /// 許可ダイアログへの回答。
  final answer = Completer<String>();

  /// check (今の許可状態) の呼び出し回数と、返す値。
  int checks = 0;
  String current = 'denied';

  /// onLateAnswer に届いた回答。
  final lateAnswers = <String>[];

  String? result;
  Object? error;
  bool get settled => result != null || error != null;

  Future<String> start({
    Future<String> Function()? request,
    Future<String> Function()? check,
    Duration giveUpAfter = kPermissionGiveUpAfter,
  }) {
    final future = requestPermissionOrGiveUp<String>(
      request: request ?? () => answer.future,
      check: check ??
          () async {
            checks++;
            return current;
          },
      onLateAnswer: lateAnswers.add,
      giveUpAfter: giveUpAfter,
      lifecycleState: () => state,
    );
    unawaited(future.then<void>(
      (value) => result = value,
      onError: (Object e) => error = e,
    ));
    return future;
  }
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

const _tick = Duration(milliseconds: 250);

/// 通常の test で見切りまで待つ時間 (状態を見る間隔 1 回で見切る)。
const _short = Duration(milliseconds: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('requestPermissionOrGiveUp (fake time)', () {
    testWidgets('ダイアログが出ている (inactive) 間は待ち、回答をそのまま返す。check は呼ばない',
        (tester) async {
      final r = _Request();
      unawaited(r.start());
      // 要求の直後に許可ダイアログが前面へ出る。
      await tester.pump(const Duration(milliseconds: 500));
      r.state = AppLifecycleState.inactive;
      // 回答まで 1 分考えても見切らない。
      await tester.pump(const Duration(minutes: 1));
      expect(r.settled, isFalse);
      expect(r.checks, 0);

      r.answer.complete('whileInUse');
      r.state = AppLifecycleState.resumed;
      await tester.pump();
      expect(r.result, 'whileInUse');
      expect(r.checks, 0);

      // 回答のあとは見張らない (前面に 10 秒いても check しない)。
      await tester.pump(const Duration(seconds: 10));
      expect(r.checks, 0);
      expect(r.lateAnswers, isEmpty);
    });

    testWidgets('取り消し (resumed のまま回答なし): 4 秒で見切り、check の結果を返す', (tester) async {
      final r = _Request();
      unawaited(r.start());

      await tester.pump(kPermissionGiveUpAfter - _tick);
      expect(r.settled, isFalse);
      expect(r.checks, 0);

      await tester.pump(_tick);
      expect(r.result, 'denied');
      expect(r.checks, 1);
    });

    testWidgets('裏に回っている間 (paused / hidden / inactive) は見切らず、前面に戻ってから数え直す',
        (tester) async {
      final r = _Request(state: AppLifecycleState.paused);
      unawaited(r.start());
      await tester.pump(const Duration(minutes: 10));
      expect(r.settled, isFalse);

      // 前面に 3 秒 → 一瞬 hidden → また前面 3 秒 → 一瞬 inactive。続けて前面に
      // いた時間を数え直すので、合わせて 4 秒を超えても見切らない。
      r.state = AppLifecycleState.resumed;
      await tester.pump(const Duration(seconds: 3));
      r.state = AppLifecycleState.hidden;
      await tester.pump(_tick);
      r.state = AppLifecycleState.resumed;
      await tester.pump(const Duration(seconds: 3));
      r.state = AppLifecycleState.inactive;
      await tester.pump(_tick);
      r.state = AppLifecycleState.resumed;
      await tester.pump(kPermissionGiveUpAfter - _tick);
      expect(r.settled, isFalse);
      expect(r.checks, 0);

      await tester.pump(_tick);
      expect(r.result, 'denied');
      expect(r.checks, 1);
    });

    testWidgets('見切ったあとに遅れて許可が届いたら、onLateAnswer を 1 回呼ぶ', (tester) async {
      final r = _Request();
      unawaited(r.start());
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.result, 'denied');

      // 見切りが早すぎた (ダイアログは遅れて出ていた) → 許可が後から届く。
      r.answer.complete('whileInUse');
      await tester.pump();
      expect(r.lateAnswers, ['whileInUse']);
      expect(r.result, 'denied', reason: '返した結果は変えない');
      expect(r.checks, 1);
    });

    testWidgets('遅れて届いた回答が見切りの結果と同じなら、onLateAnswer は呼ばない', (tester) async {
      final r = _Request();
      unawaited(r.start());
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.result, 'denied');

      r.answer.complete('denied');
      await tester.pump();
      expect(r.lateAnswers, isEmpty);
    });

    testWidgets('見切りの確認中に回答が届いたら、回答を返す', (tester) async {
      final r = _Request();
      final checking = Completer<String>();
      unawaited(r.start(check: () => checking.future));
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.settled, isFalse);

      r.answer.complete('whileInUse');
      await tester.pump();
      expect(r.result, 'whileInUse');

      checking.complete('denied');
      await tester.pump();
      expect(r.result, 'whileInUse');
      expect(r.lateAnswers, isEmpty);
    });

    testWidgets('request の例外は、見切る前ならそのまま返す (check は呼ばない)', (tester) async {
      final failure =
          PlatformException(code: 'PERMISSION_DEFINITIONS_NOT_FOUND');
      final r = _Request();
      unawaited(r.start(request: () async => throw failure));
      await tester.pump();
      expect(r.error, same(failure));
      expect(r.checks, 0);

      // 見張りも止まる。
      await tester.pump(const Duration(seconds: 10));
      expect(r.checks, 0);
    });

    testWidgets('request が同期で投げても、例外として返す', (tester) async {
      final r = _Request();
      unawaited(r.start(request: () => throw StateError('sync')));
      await tester.pump();
      expect(r.error, isStateError);
      await tester.pump(const Duration(seconds: 10));
      expect(r.checks, 0);
    });

    testWidgets('見切ったあとの例外は捨てる (未処理のエラーにしない)', (tester) async {
      final r = _Request();
      unawaited(r.start());
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.result, 'denied');

      r.answer.completeError(PlatformException(code: 'late'));
      await tester.pump();
      expect(r.lateAnswers, isEmpty);
      expect(r.error, isNull);
    });

    testWidgets('check の例外は、見切りの結果としてそのまま返す', (tester) async {
      final r = _Request();
      unawaited(r.start(check: () async => throw StateError('check')));
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.error, isStateError);
    });

    testWidgets('アプリの状態が分からない (null) ときは前面として数える', (tester) async {
      final r = _Request(state: null);
      unawaited(r.start());
      await tester.pump(kPermissionGiveUpAfter);
      expect(r.result, 'denied');
    });
  });

  group('キュー (permission_request_queue.dart)', () {
    test('取り消されてアプリが前面に戻ると、見切ってキューの枠が空き、後続の要求が始まる', () async {
      // ダイアログが出ている (inactive)。
      final r = _Request(state: AppLifecycleState.inactive);
      final first = runPermissionRequest(() => r.start(giveUpAfter: _short));
      final started = <String>[];
      final next = runPermissionRequest(() async {
        started.add('notification');
        return 'notification';
      });

      // 見切りの時間 (1 ms) の何倍待っても、ダイアログが出ている間は進まない。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(started, isEmpty);
      expect(r.checks, 0);

      // 要求が取り消された (回答は来ない) まま、アプリが前面に戻る。
      r.state = AppLifecycleState.resumed;
      expect(await first, 'denied');
      expect(await next, 'notification');
      expect(started, ['notification']);
    });

    test('ダイアログへの回答が届けば、その回答で後続の要求が始まる', () async {
      final r = _Request(state: AppLifecycleState.inactive);
      final first = runPermissionRequest(() => r.start(giveUpAfter: _short));
      var nextStarted = false;
      final next = runPermissionRequest(() async => nextStarted = true);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(nextStarted, isFalse);

      r.answer.complete('whileInUse');
      r.state = AppLifecycleState.resumed;
      expect(await first, 'whileInUse');
      await next;
      expect(nextStarted, isTrue);
      expect(r.checks, 0);
    });
  });

  group('LocationDataSource: 回答の来ない位置情報の要求', () {
    late GeolocatorPlatform original;
    late _FakeGeolocator geolocator;

    setUp(() {
      original = GeolocatorPlatform.instance;
      geolocator = _FakeGeolocator();
      GeolocatorPlatform.instance = geolocator;
    });

    tearDown(() => GeolocatorPlatform.instance = original);

    const ds = LocationDataSource(permissionGiveUpAfter: _short);

    test('見切ったら拒否として扱い、遅れて許可が届いたら onLateGrant を 1 回呼ぶ', () async {
      var lateGrants = 0;
      final position = ds.getCurrentPosition(onLateGrant: () => lateGrants++);
      await expectLater(
        position,
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.permissionDenied)),
      );
      expect(geolocator.requestCalls, 1);
      expect(lateGrants, 0);

      geolocator.permission = LocationPermission.whileInUse;
      geolocator.pending.single.complete(LocationPermission.whileInUse);
      await pumpEventQueue();
      expect(lateGrants, 1);
    });

    test('遅れて届いたのが拒否なら、onLateGrant は呼ばない', () async {
      var lateGrants = 0;
      await expectLater(
        ds.getCurrentPosition(onLateGrant: () => lateGrants++),
        throwsA(isA<AppException>()),
      );

      geolocator.permission = LocationPermission.deniedForever;
      geolocator.pending.single.complete(LocationPermission.deniedForever);
      await pumpEventQueue();
      expect(lateGrants, 0);
    });
  });
}
