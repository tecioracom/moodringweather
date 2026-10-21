// ライブ壁紙への MRI 連携 (lib/data/wallpaper/wallpaper_bridge.dart)。
//   - 値が変わったときだけ送る / 失敗は握りつぶして次回また送る
//   - MethodChannel の名前・メソッド名・引数 (mri と区分名) がネイティブ
//     (MainActivity.kt・WallpaperState.kt) と一致
//   - 区分はアプリのリングと同じ MriBand.fromValue。境界の表は Kotlin の
//     WallpaperBandTest (android/app/src/test) と同じ
//   - チャネル未登録 (iOS・テスト) でも例外にならない
//   - 壁紙の設定 (LiveWallpaperSetupBridge。1.3.0 (14)): プレビュー画面を開く
//     openLiveWallpaperPicker と、今の壁紙がこのライブ壁紙かの isLiveWallpaperActive。
//     失敗・iOS は false

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';

class _FakeBridge implements WallpaperBridge {
  _FakeBridge({this.succeed = true});
  bool succeed;
  final sent = <WallpaperState>[];
  int cleared = 0;

  /// 次の setMriState の返事を待たせる (送信中に消す場面の再現)。
  Completer<void>? hold;

  @override
  Future<bool> setMriState(WallpaperState state) async {
    sent.add(state);
    final gate = hold;
    if (gate != null) await gate.future;
    return succeed;
  }

  @override
  Future<bool> clearMriState() async {
    cleared++;
    return succeed;
  }
}

/// 区分の境目 (下端を含む) と、区分名。Kotlin の WallpaperBandTest と同じ表。
const _boundaries = <int, String>{
  0: 'hotAlert',
  19: 'hotAlert',
  20: 'hot',
  39: 'hot',
  40: 'warm',
  59: 'warm',
  60: 'comfortable',
  64: 'comfortable',
  79: 'comfortable',
  80: 'cool',
  100: 'cool',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WallpaperState', () {
    test('区分名は Kotlin の WallpaperBand の key と同じ 5 つ', () {
      // 名前を変えると Kotlin が区分名を読めず、値から決める (古いデータ扱い) に
      // なる。変えるときは WallpaperBand.kt も直す。
      expect(
        MriBand.values.map((b) => b.name),
        ['cool', 'comfortable', 'warm', 'hot', 'hotAlert'],
      );
    });

    test('区分はアプリのリングと同じ境界 (80 / 60 / 40 / 20、下端を含む)', () {
      for (final entry in _boundaries.entries) {
        final state = WallpaperState(mri: entry.key);
        expect(state.band.name, entry.value, reason: 'mri=${entry.key}');
        expect(state.band, MriBand.fromValue(entry.key));
      }
    });

    test('引数は MRI と区分名', () {
      expect(
        WallpaperState(mri: 74).toChannelArguments(),
        {'mri': 74, 'band': 'comfortable'},
      );
    });

    test('範囲外の値は 0–100 に丸めてから区分を決める', () {
      expect(
        WallpaperState(mri: 130).toChannelArguments(),
        {'mri': 100, 'band': 'cool'},
      );
      expect(
        WallpaperState(mri: -5).toChannelArguments(),
        {'mri': 0, 'band': 'hotAlert'},
      );
    });

    test('同じ値なら等しい (送り直しの判定に使う)', () {
      expect(WallpaperState(mri: 74), WallpaperState(mri: 74));
      expect(
          WallpaperState(mri: 74).hashCode, WallpaperState(mri: 74).hashCode);
      expect(WallpaperState(mri: 74), isNot(WallpaperState(mri: 75)));
    });
  });

  group('WallpaperMriSync', () {
    test('値が変わったときだけ送る', () async {
      final bridge = _FakeBridge();
      final sync = WallpaperMriSync(bridge);
      await sync.onMri(74);
      await sync.onMri(74);
      await sync.onMri(null);
      await sync.onMri(38);
      expect(bridge.sent.map((s) => s.mri), [74, 38]);
      expect(sync.lastSent, WallpaperState(mri: 38));
    });

    test('区分名も一緒に送る', () async {
      final bridge = _FakeBridge();
      final sync = WallpaperMriSync(bridge);
      await sync.onMri(74);
      await sync.onMri(38);
      expect(
        bridge.sent.map((s) => s.toChannelArguments()),
        [
          {'mri': 74, 'band': 'comfortable'},
          {'mri': 38, 'band': 'hot'},
        ],
      );
    });

    test('同じ区分の中でも値が変われば送る (Kotlin は mri も保存する)', () async {
      final bridge = _FakeBridge();
      final sync = WallpaperMriSync(bridge);
      await sync.onMri(74);
      await sync.onMri(70);
      expect(bridge.sent.map((s) => s.mri), [74, 70]);
      expect(bridge.sent.map((s) => s.band), everyElement(MriBand.comfortable));
    });

    test('データ削除で消すと、次は前と同じ値でも送り直す (通常どおり描き直す)', () async {
      final bridge = _FakeBridge();
      final sync = WallpaperMriSync(bridge);
      await sync.onMri(74);
      expect(await sync.clear(), isTrue);
      expect(bridge.cleared, 1);
      expect(sync.lastSent, isNull);
      await sync.onMri(74);
      expect(bridge.sent.map((s) => s.mri), [74, 74]);
      expect(sync.lastSent, WallpaperState(mri: 74));
    });

    test('送っている途中で消したら、その送信は送れたことにしない', () async {
      final bridge = _FakeBridge()..hold = Completer<void>();
      final sync = WallpaperMriSync(bridge);
      final sending = sync.onMri(30);
      await sync.clear();
      bridge.hold!.complete();
      await sending;
      // ネイティブは「送信 → 消去」の順に処理して既定に戻っている。同じ値もまた送る。
      expect(sync.lastSent, isNull);
      bridge.hold = null;
      await sync.onMri(30);
      expect(bridge.sent.map((s) => s.mri), [30, 30]);
    });

    test('送れなかった値は次回また送る', () async {
      final bridge = _FakeBridge(succeed: false);
      final sync = WallpaperMriSync(bridge);
      await sync.onMri(60);
      expect(sync.lastSent, isNull);
      bridge.succeed = true;
      await sync.onMri(60);
      expect(bridge.sent.map((s) => s.mri), [60, 60]);
      expect(sync.lastSent, WallpaperState(mri: 60));
    });
  });

  group('MethodChannelWallpaperBridge', () {
    const channel = MethodChannel(MethodChannelWallpaperBridge.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('ネイティブと同じチャネル名・メソッド名・引数で送る', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });
      final state = WallpaperState(mri: 74);
      final ok = await MethodChannelWallpaperBridge().setMriState(state);
      expect(ok, isTrue);
      expect(MethodChannelWallpaperBridge.channelName,
          'com.teciora.moodringweather/wallpaper');
      expect(received?.method, 'setMriState');
      expect(received?.arguments, {'mri': 74, 'band': 'comfortable'});
    });

    test('区分の境目の値は、それぞれの区分名で送る', () async {
      final received = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        received.add(call.arguments);
        return true;
      });
      final bridge = MethodChannelWallpaperBridge();
      for (final mri in _boundaries.keys) {
        await bridge.setMriState(WallpaperState(mri: mri));
      }
      expect(received, [
        for (final entry in _boundaries.entries)
          {'mri': entry.key, 'band': entry.value},
      ]);
    });

    test('範囲外の値は 0–100 に丸める', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });
      await MethodChannelWallpaperBridge()
          .setMriState(WallpaperState(mri: 130));
      expect(received?.arguments, {'mri': 100, 'band': 'cool'});
    });

    test('色の状態を消すのは clearMriState (引数なし)', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });
      expect(await MethodChannelWallpaperBridge().clearMriState(), isTrue);
      expect(received?.method, 'clearMriState');
      expect(received?.arguments, isNull);
    });

    test('チャネル未登録でも例外にせず false', () async {
      expect(
        await MethodChannelWallpaperBridge()
            .setMriState(WallpaperState(mri: 50)),
        isFalse,
      );
      expect(await MethodChannelWallpaperBridge().clearMriState(), isFalse);
    });

    test('ネイティブ側のエラーでも例外にせず false', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      expect(
        await MethodChannelWallpaperBridge()
            .setMriState(WallpaperState(mri: 50)),
        isFalse,
      );
    });
  });

  group('壁紙の設定 (LiveWallpaperSetupBridge)', () {
    const channel = MethodChannel(MethodChannelWallpaperBridge.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('プレビュー画面を開くのは openLiveWallpaperPicker (引数なし)', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });
      expect(await MethodChannelWallpaperBridge().openPicker(), isTrue);
      expect(received?.method, 'openLiveWallpaperPicker');
      expect(received?.arguments, isNull);
    });

    test('ネイティブがプレビューも一覧も開けなければ false', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await MethodChannelWallpaperBridge().openPicker(), isFalse);
    });

    test('設定中かは isLiveWallpaperActive (引数なし) の返事', () async {
      final received = <MethodCall>[];
      var active = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received.add(call);
        return active;
      });
      final bridge = MethodChannelWallpaperBridge();
      expect(await bridge.isActive(), isTrue);
      active = false;
      expect(await bridge.isActive(), isFalse);
      expect(received.map((c) => c.method),
          ['isLiveWallpaperActive', 'isLiveWallpaperActive']);
      expect(received.map((c) => c.arguments), [null, null]);
    });

    test('チャネル未登録・ネイティブのエラー・返事なしは false', () async {
      final bridge = MethodChannelWallpaperBridge();
      expect(await bridge.openPicker(), isFalse);
      expect(await bridge.isActive(), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      expect(await bridge.openPicker(), isFalse);
      expect(await bridge.isActive(), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await bridge.openPicker(), isFalse);
      expect(await bridge.isActive(), isFalse);
    });

    test('既定の実装は Android が MethodChannel、iOS は何もしない', () {
      expect(defaultLiveWallpaperSetupBridge(),
          isA<MethodChannelWallpaperBridge>());
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(defaultLiveWallpaperSetupBridge(), isA<NoopWallpaperBridge>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('iOS など (NoopWallpaperBridge) は何もしない', () async {
    expect(
      await const NoopWallpaperBridge().setMriState(WallpaperState(mri: 50)),
      isFalse,
    );
    expect(await const NoopWallpaperBridge().clearMriState(), isFalse);
    expect(await const NoopWallpaperBridge().openPicker(), isFalse);
    expect(await const NoopWallpaperBridge().isActive(), isFalse);
  });
}
