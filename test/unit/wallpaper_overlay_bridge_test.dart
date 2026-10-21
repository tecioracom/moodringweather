// 重ね描きの受け渡し (lib/data/wallpaper/wallpaper_overlay_bridge.dart)。
//   - MethodChannel の名前・メソッド名・引数がネイティブ (MainActivity.kt・
//     WallpaperOverlay.kt の fromChannelArguments) と一致
//   - 配置の数値 (右 24dp・上 16dp・余白 8dp・3 時間・15 分) は Dart から渡す
//   - チャネル未登録・ネイティブのエラーでも例外にならない
//   - ライブ壁紙は Android だけ

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';

final _payload = WallpaperOverlayPayload(
  asOf: DateTime.utc(2026, 9, 30, 4, 15),
  freshPng: Uint8List.fromList([137, 80, 78, 71]),
  stalePng: Uint8List.fromList([137, 80, 78, 72]),
  pixelRatio: 2.75,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelWallpaperBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('色と同じチャネルの setWallpaperOverlay で、PNG 2 枚と配置の数値を渡す', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    expect(await MethodChannelWallpaperOverlayBridge().setOverlay(_payload),
        isTrue);
    expect(received?.method, 'setWallpaperOverlay');
    expect(received?.arguments, {
      'asOf': DateTime.utc(2026, 9, 30, 4, 15).millisecondsSinceEpoch,
      'fresh': Uint8List.fromList([137, 80, 78, 71]),
      'stale': Uint8List.fromList([137, 80, 78, 72]),
      'pixelRatio': 2.75,
      'paddingDp': 8.0,
      'rightDp': 24.0,
      'topGapDp': 16.0,
      'staleAfterMinutes': 180,
      'futureToleranceMinutes': 15,
    });
  });

  test('消すのは clearWallpaperOverlay (引数なし)', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    expect(await MethodChannelWallpaperOverlayBridge().clearOverlay(), isTrue);
    expect(received?.method, 'clearWallpaperOverlay');
    expect(received?.arguments, isNull);
  });

  test('ネイティブが false を返せば false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await MethodChannelWallpaperOverlayBridge().setOverlay(_payload),
        isFalse);
  });

  test('チャネル未登録・ネイティブのエラーでも例外にせず false', () async {
    final bridge = MethodChannelWallpaperOverlayBridge();
    expect(await bridge.setOverlay(_payload), isFalse);
    expect(await bridge.clearOverlay(), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await bridge.setOverlay(_payload), isFalse);
    expect(await bridge.clearOverlay(), isFalse);
  });

  test('iOS など (Noop) は何もしない', () async {
    const bridge = NoopWallpaperOverlayBridge();
    expect(await bridge.setOverlay(_payload), isFalse);
    expect(await bridge.clearOverlay(), isFalse);
  });

  test('ライブ壁紙は Android だけ (色・重ね描き・設定の区画で同じ判定)', () {
    expect(supportsLiveWallpaper(), isTrue); // flutter_test の既定は Android
    expect(defaultWallpaperOverlayBridge(),
        isA<MethodChannelWallpaperOverlayBridge>());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(supportsLiveWallpaper(), isFalse);
      expect(
          defaultWallpaperOverlayBridge(), isA<NoopWallpaperOverlayBridge>());
      expect(defaultWallpaperBridge(), isA<NoopWallpaperBridge>());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
