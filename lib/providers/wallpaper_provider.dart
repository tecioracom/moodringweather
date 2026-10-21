// lib/providers/wallpaper_provider.dart
//
// ライブ壁紙への連携 (Android)。
//   - 色 (MRI の区分): lib/data/wallpaper/wallpaper_bridge.dart。MoodRingApp の
//     initState で mriProvider (現在地) を listenManual し、値が確定するたびに
//     wallpaperMriSyncProvider.onMri() を呼ぶ。
//   - 重ね描き (天気・気温・区分名 · 時刻): lib/presentation/wallpaper/。
//     MaterialApp.builder の WallpaperOverlayHost が要求を作り、
//     wallpaperOverlaySyncProvider へ渡す。
//   - 「データを削除」: wallpaperDataEraserProvider が色と重ね描きの保存を消す。
//   - 壁紙の設定 (1.3.0 (14)): 設定 › 一般 › ライブ壁紙「ライブ壁紙を設定」が
//     liveWallpaperSetupBridgeProvider で壁紙のプレビュー画面を開き、
//     liveWallpaperActiveProvider で「設定中」を出す。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wallpaper/wallpaper_bridge.dart';
import '../data/wallpaper/wallpaper_overlay_bridge.dart';
import '../presentation/wallpaper/wallpaper_overlay_sync.dart';

/// ライブ壁紙のあるプラットフォームか (Android だけ)。設定 › 一般の「ライブ壁紙」の
/// 区画と、重ね描きのホストが見る。テストでは override する。
final liveWallpaperSupportedProvider =
    Provider<bool>((ref) => supportsLiveWallpaper());

/// 壁紙への橋渡し。テストでは override する。
final wallpaperBridgeProvider =
    Provider<WallpaperBridge>((ref) => defaultWallpaperBridge());

/// 壁紙の設定 (プレビュー画面を開く・今の壁紙がこのライブ壁紙か)。テストでは override する。
final liveWallpaperSetupBridgeProvider = Provider<LiveWallpaperSetupBridge>(
  (ref) => defaultLiveWallpaperSetupBridge(),
);

/// 今のホーム画面の壁紙がこのアプリのライブ壁紙か (設定 › 一般の「設定中」)。
///
/// autoDispose なので、設定 › 一般を開くたびに読み直す。アプリが前面に戻ったとき
/// (壁紙のプレビュー画面から戻ってきたとき) は、行が invalidate して読み直す。
/// 読み直している間は前の値のまま (valueOrNull)。Android 以外・失敗は false。
final liveWallpaperActiveProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  if (!ref.watch(liveWallpaperSupportedProvider)) return false;
  try {
    return await ref.watch(liveWallpaperSetupBridgeProvider).isActive();
  } catch (_) {
    return false;
  }
});

/// 同じ値を送り直さないための状態を持つ同期役 (アプリ全体で 1 つ)。
final wallpaperMriSyncProvider = Provider<WallpaperMriSync>(
  (ref) => WallpaperMriSync(ref.watch(wallpaperBridgeProvider)),
);

/// 重ね描きの橋渡し (色とは別のメソッド。失敗しても色の更新は止めない)。
final wallpaperOverlayBridgeProvider = Provider<WallpaperOverlayBridge>(
  (ref) => defaultWallpaperOverlayBridge(),
);

/// 重ね描きの同期役 (アプリ全体で 1 つ)。テストでは描画を差し替えて override する。
final wallpaperOverlaySyncProvider = Provider<WallpaperOverlaySync>(
  (ref) => WallpaperOverlaySync(ref.watch(wallpaperOverlayBridgeProvider)),
);

/// 「データを削除」でライブ壁紙側の保存を消す関数 (DataDeletionService.eraseWallpaper)。
/// 色の状態 (MRI・区分) と重ね描き (PNG・設定) の両方を消し、壁紙は既定 (快適の配色・
/// 重ね描きなし) に戻る。次に現在地の MRI・天気が確定したら、前と同じ内容でも送り直す
/// (通常どおり描き直す)。Android 以外は何もしない。どちらかを消せなければ例外。
final wallpaperDataEraserProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    if (!ref.read(liveWallpaperSupportedProvider)) return;
    final color = await ref.read(wallpaperMriSyncProvider).clear();
    final overlay = await ref.read(wallpaperOverlaySyncProvider).clear();
    if (!color || !overlay) {
      throw StateError(
        'live wallpaper data not cleared (color: $color, overlay: $overlay)',
      );
    }
  };
});
