// lib/presentation/wallpaper/wallpaper_overlay_sync.dart
//
// 重ね描きの要求 (描いて渡す / 消す) を壁紙へ流す。同じ要求は送り直さない
// (中身 = 区分名・気温・グリフ・データの時刻・単位・言語・12/24 時間制・倍率・
// 解像度のどれかが変われば送る。設計書 §7.2)。
//
// - 描画 (ビットマップ化と PNG) は非同期。途中で新しい要求が来たら、終わってから
//   最新の要求だけを処理する (古い要求を後から送って上書きしない)。
// - 失敗 (チャネル未登録・Kotlin の保存失敗・描画の失敗) は握りつぶし、次の要求で
//   また送る。壁紙の重ね描きは付帯機能で、アプリ本体と壁紙の色を止めてはならない。
// - 「データを削除」では clear() で消す。次の要求は前と同じ内容でも送り直す。

import 'package:flutter/foundation.dart';

import '../../data/wallpaper/wallpaper_overlay_bridge.dart';
import 'wallpaper_overlay_content.dart';
import 'wallpaper_overlay_painter.dart';

/// 中身をビットマップ 2 枚に描いて受け渡しの内容にする関数 (テストでは差し替える)。
typedef WallpaperOverlayRenderer = Future<WallpaperOverlayPayload> Function(
  WallpaperOverlayContent content,
);

class WallpaperOverlaySync {
  WallpaperOverlaySync(this._bridge, {WallpaperOverlayRenderer? render})
      : _render = render ?? renderWallpaperOverlayPayload;

  final WallpaperOverlayBridge _bridge;
  final WallpaperOverlayRenderer _render;

  WallpaperOverlayRequest? _applied;
  WallpaperOverlayRequest? _wanted;
  bool _running = false;

  /// [clear] のたびに増える番号。消している間に描き終わった古い要求は送らない。
  int _generation = 0;

  /// 直近に壁紙へ届いた要求 (テスト・診断用)。
  WallpaperOverlayRequest? get lastApplied => _applied;

  /// 最新の要求を渡す。null (データ待ち) は何もしない。
  Future<void> update(WallpaperOverlayRequest? request) async {
    if (request == null) return;
    _wanted = request;
    if (_running) return; // 処理中の分が終わったら最新の要求を処理する
    _running = true;
    try {
      while (true) {
        final target = _wanted;
        if (target == null || target == _applied) break;
        final generation = _generation;
        final ok = await _apply(target, generation);
        if (generation != _generation) continue; // 途中で消した。最新の要求を見直す
        if (ok) {
          _applied = target;
        } else if (_wanted == target) {
          break; // 失敗。次に要求が来たときにまた送る
        }
      }
    } finally {
      _running = false;
    }
  }

  /// 重ね描きを消す (「データを削除」)。PNG と設定が消え、壁紙は色だけになる。
  /// 描いている途中の要求は送らず、次の要求は前と同じ内容でも送り直す
  /// (アプリが現在地の天気で描き直したとき、通常どおり出る)。消せたら true。
  Future<bool> clear() async {
    _generation++;
    _applied = null;
    _wanted = null;
    try {
      return await _bridge.clearOverlay();
    } catch (e) {
      debugPrint('wallpaper overlay: $e');
      return false;
    }
  }

  Future<bool> _apply(WallpaperOverlayRequest request, int generation) async {
    try {
      switch (request) {
        case ShowWallpaperOverlay(:final content):
          final payload = await _render(content);
          // 描いている間に消した (データ削除) なら、古い内容は送らない。
          if (generation != _generation) return false;
          return await _bridge.setOverlay(payload);
        case ClearWallpaperOverlay():
          return await _bridge.clearOverlay();
      }
    } catch (e) {
      debugPrint('wallpaper overlay: $e');
      return false;
    }
  }
}
