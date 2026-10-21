// lib/data/wallpaper/wallpaper_bridge.dart
//
// Android のライブ壁紙 (MoodRingWallpaperService) へ現在地の MRI を渡す橋渡し。
//
// ネイティブ側 (MainActivity.kt) は MethodChannel
// `com.teciora.moodringweather/wallpaper` の `setMriState` を受けて
// SharedPreferences に保存し、壁紙を再描画する。v1.1 でネイティブ側だけが
// 実装され、Dart から一度も呼ばれていなかったため、壁紙の色が MRI に
// 追従していなかった (2026-09-28 発見。掲載文「MRI で色が変わるライブ壁紙」と
// 実装を一致させるための修正)。
//
// 引数 ([WallpaperState.toChannelArguments]):
//   - `mri`  : MRI 0–100
//   - `band` : 区分名 (MriBand.name: cool / comfortable / warm / hot / hotAlert)。
//              1.3.0 (13) から。壁紙の配色はこれで決まる (docs/design-wallpaper-palette.md)。
//              区分を決めるのは Dart の MriBand.fromValue (アプリのリングと同じ) で、
//              Kotlin は区分 → 配色の表だけを持つ。区分名の無い古い保存データの
//              ときだけ、Kotlin が同じ境界 (80 / 60 / 40 / 20) で区分を決める。
//
// 方針:
//   - 渡すのは**現在地**の MRI だけ (保存地点の表示に切り替えても壁紙は動かさない)。
//   - 同じ内容は送り直さない。失敗 (iOS・テスト・チャネル未登録) は握りつぶす —
//     壁紙の更新はおまけで、アプリ本体の動作を止めてはならない。
//   - 壁紙はアプリが MRI を計算したとき (起動・再取得・前景復帰) に更新される。
//     アプリを開いていない間のバックグラウンド更新は行わない。
//
// 壁紙の設定 ([LiveWallpaperSetupBridge]。1.3.0 (14)):
//   設定 › 一般 › ライブ壁紙の「ライブ壁紙を設定」から、壁紙のプレビュー画面を開き
//   (`openLiveWallpaperPicker`)、今の壁紙がこのライブ壁紙かを読む
//   (`isLiveWallpaperActive`)。Galaxy (One UI) の「壁紙とスタイル」は他社アプリの
//   ライブ壁紙を一覧に出さないため、アプリから開く (2026-10-01 実機で発見。
//   ネイティブ側は v1.1 から openLiveWallpaperPicker があったが、Dart から一度も
//   呼ばれていなかった)。色の受け渡し ([WallpaperBridge]) とは別の口にして、
//   テストでは片方だけ差し替えられるようにする。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/mri/mri_band.dart';

/// 壁紙が描く内容 (MethodChannel `setMriState` の引数)。
///
/// Kotlin の `WallpaperState` (android/.../wallpaper/WallpaperState.kt) と 1:1。
/// 項目を足すとき (気温の表示文字列・天気の種類・更新時刻など) は、ここに
/// フィールドを足して [toChannelArguments]・`==`・[hashCode] に含め、Kotlin の
/// `WallpaperState.fromChannelArguments` と `WallpaperStateStore` にも足す
/// (Kotlin は知らないキーを無視する)。内容が等しい間は [WallpaperMriSync] が
/// 送り直さない。
@immutable
class WallpaperState {
  /// [mri] は 0–100 に丸める。
  WallpaperState({required int mri}) : mri = mri.clamp(0, 100);

  /// MRI 0–100。
  final int mri;

  /// 壁紙の配色を決める区分。アプリのリング (`MoodRingIndex.band`) と同じ関数で
  /// 決める。OPTIMAL は区分ではない (快適のラベルだけの違い) ので、快適のまま。
  MriBand get band => MriBand.fromValue(mri);

  /// `setMriState` の引数。
  Map<String, Object> toChannelArguments() => <String, Object>{
        'mri': mri,
        'band': band.name,
      };

  @override
  bool operator ==(Object other) => other is WallpaperState && other.mri == mri;

  @override
  int get hashCode => mri.hashCode;

  @override
  String toString() => 'WallpaperState(mri: $mri, band: ${band.name})';
}

/// ライブ壁紙へ描く内容を渡す口。テストでは差し替える。
abstract class WallpaperBridge {
  /// 壁紙へ [state] を渡す (MethodChannel `setMriState`)。渡せたら true。
  /// 失敗しても例外は投げない。
  Future<bool> setMriState(WallpaperState state);

  /// 壁紙の色の状態 (MRI・区分) を消し、既定 (MRI 64 = 快適の配色) に戻す
  /// (MethodChannel `clearMriState`。設定 › プライバシーの「データを削除」)。
  /// 消せたら true。失敗しても例外は投げない。
  Future<bool> clearMriState();
}

/// アプリからライブ壁紙を設定する口 (設定 › 一般 › ライブ壁紙「ライブ壁紙を設定」)。
/// テストでは差し替える。
abstract class LiveWallpaperSetupBridge {
  /// 壁紙のプレビュー画面を開く (MethodChannel `openLiveWallpaperPicker`)。
  /// Kotlin が ① この壁紙のプレビュー → ② ライブ壁紙の一覧 の順に試す。
  /// どちらも開けなかったら false (呼び出し側が手順を案内する)。例外は投げない。
  Future<bool> openPicker();

  /// 今のホーム画面の壁紙がこのアプリのライブ壁紙か (MethodChannel
  /// `isLiveWallpaperActive`)。読めない・失敗は false。例外は投げない。
  Future<bool> isActive();
}

/// 何もしない実装 (iOS など、ライブ壁紙が無いプラットフォーム用)。
class NoopWallpaperBridge implements WallpaperBridge, LiveWallpaperSetupBridge {
  const NoopWallpaperBridge();

  @override
  Future<bool> setMriState(WallpaperState state) async => false;

  @override
  Future<bool> clearMriState() async => false;

  @override
  Future<bool> openPicker() async => false;

  @override
  Future<bool> isActive() async => false;
}

/// MethodChannel 経由の実装 (Android)。
class MethodChannelWallpaperBridge
    implements WallpaperBridge, LiveWallpaperSetupBridge {
  MethodChannelWallpaperBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// MainActivity.kt の `channelName` と必ず一致させる。
  static const String channelName = 'com.teciora.moodringweather/wallpaper';

  final MethodChannel _channel;

  @override
  Future<bool> setMriState(WallpaperState state) =>
      _invoke('setMriState', state.toChannelArguments());

  @override
  Future<bool> clearMriState() => _invoke('clearMriState', null);

  @override
  Future<bool> openPicker() => _invoke('openLiveWallpaperPicker', null);

  @override
  Future<bool> isActive() => _invoke('isLiveWallpaperActive', null);

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

/// ライブ壁紙のあるプラットフォームか (Android だけ。iOS には無い)。
/// 壁紙の色・重ね描きの受け渡しと、設定 › 一般の「ライブ壁紙」の区画で共用する。
bool supportsLiveWallpaper() => defaultTargetPlatform == TargetPlatform.android;

// 既定の実装。色の受け渡しと壁紙の設定は同じクラス (同じ MethodChannel) で、口だけ
// 分ける。条件式 (a ? b : c) だと型が両方の口の共通の上位 (Object) になるので if で返す。

/// プラットフォームに応じた既定の実装。
WallpaperBridge defaultWallpaperBridge() {
  if (supportsLiveWallpaper()) return MethodChannelWallpaperBridge();
  return const NoopWallpaperBridge();
}

/// 壁紙の設定の既定の実装 (Android は MethodChannel、iOS などは何もしない)。
LiveWallpaperSetupBridge defaultLiveWallpaperSetupBridge() {
  if (supportsLiveWallpaper()) return MethodChannelWallpaperBridge();
  return const NoopWallpaperBridge();
}

/// 現在地の MRI を壁紙へ流す。同じ内容の連続送信を省く。
class WallpaperMriSync {
  WallpaperMriSync(this._bridge);

  final WallpaperBridge _bridge;
  WallpaperState? _lastSent;

  /// [clear] のたびに増える番号。消している間に届いた古い送信の結果を捨てる。
  int _generation = 0;

  /// 直近に送れた内容 (テスト・診断用)。
  WallpaperState? get lastSent => _lastSent;

  /// MRI が確定したら呼ぶ。値 (0–100 に丸めた MRI) が変わったときだけ送る。
  /// 区分は値の関数なので、値が変われば区分名も一緒に送り直される。
  Future<void> onMri(int? mri) async {
    if (mri == null) return;
    final state = WallpaperState(mri: mri);
    if (state == _lastSent) return;
    final generation = _generation;
    final ok = await _bridge.setMriState(state);
    if (ok && generation == _generation) _lastSent = state;
  }

  /// 壁紙の色の状態を消す (「データを削除」)。壁紙は既定 (快適の配色) に戻る。
  /// 次に MRI が確定したら、前と同じ値でも送り直す (通常どおり描き直す)。
  /// 消せたら true。
  Future<bool> clear() {
    _generation++;
    _lastSent = null;
    return _bridge.clearMriState();
  }
}
