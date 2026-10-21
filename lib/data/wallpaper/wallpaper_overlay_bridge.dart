// lib/data/wallpaper/wallpaper_overlay_bridge.dart
//
// ライブ壁紙の重ね描き (天気グリフ・気温・区分名 · 時刻) のビットマップを Android へ
// 渡す口 (docs/design-wallpaper-weather-overlay.md §7。2026-09-30 決裁)。
//
// 壁紙の色 (区分) の受け渡し (wallpaper_bridge.dart の setMriState) とは別のメソッド
// にする。重ね描きで失敗しても、色の更新は止めない。
//
// MethodChannel `com.teciora.moodringweather/wallpaper` (MainActivity.kt):
//   setWallpaperOverlay({asOf, fresh, stale, pixelRatio, paddingDp, rightDp, topGapDp,
//                        staleAfterMinutes, futureToleranceMinutes}) -> Boolean
//   clearWallpaperOverlay() -> Boolean
// Kotlin は 2 枚の PNG と数値を保存し、表示のたびに経過時間で 2 枚のどちらを描くか
// 決めて右上に置く (wallpaper/WallpaperOverlay*.kt)。配置の数値は Dart のここで持つ。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wallpaper_bridge.dart';

/// 画面の右端から重ね描きの右端まで (dp)。
const double kWallpaperOverlayRightDp = 24;

/// ステータスバーの下端から重ね描きの上端まで (dp)。
const double kWallpaperOverlayTopGapDp = 16;

/// ビットマップの基準点の周りの余白 (dp)。基準点 (重ね描きの右上) はビットマップの
/// (幅 − 余白, 余白) にある。余白は字形のはみ出し (JA の全角「°」の空きなど) の逃げ。
const double kWallpaperOverlayPaddingDp = 8;

/// データの時刻からこれを超えたら古い表示に切り替える (設計書 §2)。
const Duration kWallpaperOverlayStaleAfter = Duration(hours: 3);

/// データの時刻が端末の時計よりこれ以上先なら古い表示にする (時計が戻ったとき)。
const Duration kWallpaperOverlayFutureTolerance = Duration(minutes: 15);

/// 重ね描きの受け渡し内容 (`setWallpaperOverlay` の引数)。
@immutable
class WallpaperOverlayPayload {
  const WallpaperOverlayPayload({
    required this.asOf,
    required this.freshPng,
    required this.stalePng,
    required this.pixelRatio,
    this.paddingDp = kWallpaperOverlayPaddingDp,
    this.rightDp = kWallpaperOverlayRightDp,
    this.topGapDp = kWallpaperOverlayTopGapDp,
    this.staleAfter = kWallpaperOverlayStaleAfter,
    this.futureTolerance = kWallpaperOverlayFutureTolerance,
  });

  /// データの時刻 (WeatherSnapshot.timestamp)。新しい / 古いの基準。
  final DateTime asOf;

  /// 新しい表示 (グリフ + 気温、区分名 · 時刻) の PNG。
  final Uint8List freshPng;

  /// 古い表示 (「9/30 10:30 更新」「アプリを開くと更新」) の PNG。
  final Uint8List stalePng;

  /// PNG を描いた解像度 (1dp あたりの画素数。端末の devicePixelRatio)。
  final double pixelRatio;

  final double paddingDp;
  final double rightDp;
  final double topGapDp;
  final Duration staleAfter;
  final Duration futureTolerance;

  Map<String, Object> toChannelArguments() => <String, Object>{
        'asOf': asOf.millisecondsSinceEpoch,
        'fresh': freshPng,
        'stale': stalePng,
        'pixelRatio': pixelRatio,
        'paddingDp': paddingDp,
        'rightDp': rightDp,
        'topGapDp': topGapDp,
        'staleAfterMinutes': staleAfter.inMinutes,
        'futureToleranceMinutes': futureTolerance.inMinutes,
      };
}

/// ライブ壁紙へ重ね描きを渡す・消す口。テストでは差し替える。
abstract class WallpaperOverlayBridge {
  /// 重ね描きを渡す。渡せたら true。失敗しても例外は投げない。
  Future<bool> setOverlay(WallpaperOverlayPayload payload);

  /// 重ね描きを消す (設定でオフ・既定地点)。消せたら true。例外は投げない。
  Future<bool> clearOverlay();
}

/// 何もしない実装 (iOS など、ライブ壁紙が無いプラットフォーム用)。
class NoopWallpaperOverlayBridge implements WallpaperOverlayBridge {
  const NoopWallpaperOverlayBridge();

  @override
  Future<bool> setOverlay(WallpaperOverlayPayload payload) async => false;

  @override
  Future<bool> clearOverlay() async => false;
}

/// MethodChannel 経由の実装 (Android)。チャネルは壁紙の色と同じ。
class MethodChannelWallpaperOverlayBridge implements WallpaperOverlayBridge {
  MethodChannelWallpaperOverlayBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(MethodChannelWallpaperBridge.channelName);

  final MethodChannel _channel;

  @override
  Future<bool> setOverlay(WallpaperOverlayPayload payload) =>
      _invoke('setWallpaperOverlay', payload.toChannelArguments());

  @override
  Future<bool> clearOverlay() => _invoke('clearWallpaperOverlay', null);

  Future<bool> _invoke(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// プラットフォームに応じた既定の実装。
WallpaperOverlayBridge defaultWallpaperOverlayBridge() =>
    supportsLiveWallpaper()
        ? MethodChannelWallpaperOverlayBridge()
        : const NoopWallpaperOverlayBridge();
