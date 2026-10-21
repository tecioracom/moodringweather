// データ削除 (決裁 D3) の司令塔。サーバー側は best-effort、端末内は必ず消す。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/privacy/data_deletion.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEraser implements RemoteDataEraser {
  _FakeEraser(
      {this.failPush = false,
      this.failEntitlement = false,
      this.failAuth = false});
  final bool failPush;
  final bool failEntitlement;
  final bool failAuth;
  final calls = <String>[];

  @override
  Future<void> deletePushSubscription(String uid) async {
    calls.add('push:$uid');
    if (failPush) throw StateError('push');
  }

  @override
  Future<void> deleteEntitlement(String uid) async {
    calls.add('entitlement:$uid');
    if (failEntitlement) throw StateError('entitlement');
  }

  @override
  Future<void> deleteFcmToken() async => calls.add('token');

  @override
  Future<void> deleteAuthUser() async {
    calls.add('auth');
    if (failAuth) throw StateError('auth');
  }
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({'k': 'v', 'debug_plus_tier': 'plus'});
  return SharedPreferences.getInstance();
}

void main() {
  test('全部成功: サーバー 3 件 → 端末内クリア → 匿名アカウント削除の順', () async {
    final prefs = await _prefs();
    final eraser = _FakeEraser();
    final out =
        await DataDeletionService(prefs: prefs, uid: 'u1', remote: eraser)
            .deleteAll();
    expect(out.isComplete, isTrue);
    expect(out.localCleared, isTrue);
    expect(prefs.getKeys(), isEmpty);
    expect(eraser.calls, ['push:u1', 'entitlement:u1', 'token', 'auth']);
    // 匿名アカウントの削除は最後 (以後 Firestore の所有者判定が通らないため)。
    expect(eraser.calls.last, 'auth');
  });

  test('サーバー側が失敗しても端末内は消え、部分失敗として返す', () async {
    final prefs = await _prefs();
    final eraser = _FakeEraser(failEntitlement: true);
    // 購読記録の失敗も同様に部分失敗 (isComplete = false) になる。
    expect(
      (await DataDeletionService(
        prefs: await _prefs(),
        uid: 'u2',
        remote: _FakeEraser(failPush: true),
      ).deleteAll())
          .isComplete,
      isFalse,
    );
    final out =
        await DataDeletionService(prefs: prefs, uid: 'u1', remote: eraser)
            .deleteAll();
    expect(out.localCleared, isTrue);
    expect(prefs.getKeys(), isEmpty);
    expect(out.pushSubscriptionDeleted, isTrue);
    expect(out.entitlementDeleted, isFalse);
    expect(out.isComplete, isFalse);
    // 失敗しても後続 (トークン・アカウント) は試みる。
    expect(eraser.calls, contains('token'));
    expect(eraser.calls, contains('auth'));
  });

  test('uid が無い (Firebase 無効) なら端末内だけ消して完了扱い', () async {
    final prefs = await _prefs();
    final out = await DataDeletionService(prefs: prefs).deleteAll();
    expect(out.remoteAttempted, isFalse);
    expect(out.localCleared, isTrue);
    expect(out.isComplete, isTrue);
    expect(prefs.getKeys(), isEmpty);
  });

  test('匿名アカウントの削除失敗は完了判定に影響しない', () async {
    final prefs = await _prefs();
    final eraser = _FakeEraser(failAuth: true);
    final out =
        await DataDeletionService(prefs: prefs, uid: 'u1', remote: eraser)
            .deleteAll();
    expect(out.authUserDeleted, isFalse);
    expect(out.isComplete, isTrue);
  });

  group('ライブ壁紙の保存 (1.3.0 (13))', () {
    test('端末内の設定と一緒に壁紙の保存も消す', () async {
      final prefs = await _prefs();
      final order = <String>[];
      final out = await DataDeletionService(
        prefs: prefs,
        uid: 'u1',
        remote: _FakeEraser(),
        eraseWallpaper: () async {
          // 端末内の設定を消したあとに呼ばれる
          order.add('wallpaper (prefs: ${prefs.getKeys().length})');
        },
      ).deleteAll();
      expect(order, ['wallpaper (prefs: 0)']);
      expect(out.wallpaperCleared, isTrue);
      expect(out.isComplete, isTrue);
    });

    test('壁紙の保存を消せなければ部分失敗 (端末内の設定とサーバー側は消える)', () async {
      final prefs = await _prefs();
      final eraser = _FakeEraser();
      final out = await DataDeletionService(
        prefs: prefs,
        uid: 'u1',
        remote: eraser,
        eraseWallpaper: () async => throw StateError('wallpaper'),
      ).deleteAll();
      expect(out.wallpaperCleared, isFalse);
      expect(out.localCleared, isTrue);
      expect(out.isComplete, isFalse);
      expect(prefs.getKeys(), isEmpty);
      expect(eraser.calls, ['push:u1', 'entitlement:u1', 'token', 'auth']);
    });

    test('消し方が無い (壁紙の無い端末・古い呼び出し) なら完了扱い', () async {
      final out = await DataDeletionService(prefs: await _prefs()).deleteAll();
      expect(out.wallpaperCleared, isTrue);
      expect(out.isComplete, isTrue);
    });
  });
}
