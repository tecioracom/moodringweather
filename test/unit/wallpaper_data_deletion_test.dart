// 「データを削除」でライブ壁紙側の保存を消す配線 (1.3.0 (13))。
// privacy_provider の dataDeletionServiceProvider → wallpaperDataEraserProvider。
//   - 色の状態 (clearMriState) と重ね描き (clearWallpaperOverlay) の両方を消す
//   - 消したあと、アプリが現在地の MRI・天気で描き直すと、前と同じ内容でも送る
//   - iOS (ライブ壁紙なし) では何も呼ばない
//   - どちらかを消せなければ部分失敗 (もう片方も消しに行く)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/providers/privacy_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';

class _ColorBridge implements WallpaperBridge {
  bool succeed = true;
  final calls = <String>[];

  @override
  Future<bool> setMriState(WallpaperState state) async {
    calls.add('set ${state.mri}');
    return true;
  }

  @override
  Future<bool> clearMriState() async {
    calls.add('clear');
    return succeed;
  }
}

class _Env {
  _Env(this.container, this.color, this.overlay);

  final ProviderContainer container;
  final _ColorBridge color;
  final RecordingWallpaperOverlay overlay;

  Future<void> drawCurrent() async {
    await container.read(wallpaperMriSyncProvider).onMri(30);
    await overlay.sync.update(ShowWallpaperOverlay(overlayContentFor('hot')));
  }
}

Future<_Env> _env({bool supported = true}) async {
  SharedPreferences.setMockInitialValues({'k': 'v'});
  final prefs = await SharedPreferences.getInstance();
  final color = _ColorBridge();
  final overlay = RecordingWallpaperOverlay();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      liveWallpaperSupportedProvider.overrideWithValue(supported),
      wallpaperBridgeProvider.overrideWithValue(color),
      overlay.providerOverride,
    ],
  );
  addTearDown(container.dispose);
  return _Env(container, color, overlay);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDateFormatting);

  test('削除すると、壁紙の色の状態と重ね描きの両方を消す', () async {
    final env = await _env();
    await env.drawCurrent();
    final outcome =
        await env.container.read(dataDeletionServiceProvider).deleteAll();
    expect(env.color.calls, ['set 30', 'clear']);
    expect(env.overlay.calls, ['set', 'clear']);
    expect(outcome.wallpaperCleared, isTrue);
    expect(outcome.isComplete, isTrue);
  });

  test('消したあと、アプリが描き直すと前と同じ内容でも送る (通常どおり描き直す)', () async {
    final env = await _env();
    await env.drawCurrent();
    await env.container.read(dataDeletionServiceProvider).deleteAll();
    await env.drawCurrent();
    expect(env.color.calls, ['set 30', 'clear', 'set 30']);
    expect(env.overlay.calls, ['set', 'clear', 'set']);
  });

  test('iOS (ライブ壁紙なし) では何も呼ばず、完了扱い', () async {
    final env = await _env(supported: false);
    final outcome =
        await env.container.read(dataDeletionServiceProvider).deleteAll();
    expect(env.color.calls, isEmpty);
    expect(env.overlay.calls, isEmpty);
    expect(outcome.isComplete, isTrue);
  });

  test('色の状態を消せなければ部分失敗。重ね描きは消しに行く', () async {
    final env = await _env();
    env.color.succeed = false;
    final outcome =
        await env.container.read(dataDeletionServiceProvider).deleteAll();
    expect(env.overlay.calls, ['clear']);
    expect(outcome.wallpaperCleared, isFalse);
    expect(outcome.isComplete, isFalse);
  });
}
