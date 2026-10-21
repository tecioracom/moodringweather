// 重ね描きの同期役 (lib/presentation/wallpaper/wallpaper_overlay_sync.dart)。
//   - 同じ要求は送り直さない / 変われば送る / 消す要求は理由によらず 1 回
//   - 失敗 (送れない・描けない) は握りつぶし、次の要求でまた送る
//   - 描いている間に来た要求は、終わってから最新のものだけを処理する

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_sync.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';

class _RecordingBridge implements WallpaperOverlayBridge {
  final calls = <String>[];
  bool succeed = true;

  @override
  Future<bool> setOverlay(WallpaperOverlayPayload payload) async {
    calls.add('set ${payload.asOf.millisecondsSinceEpoch} ${payload.freshPng}');
    return succeed;
  }

  @override
  Future<bool> clearOverlay() async {
    calls.add('clear');
    return succeed;
  }
}

/// 中身ごとに区別できる受け渡し内容を返す (描画はしない)。
Future<WallpaperOverlayPayload> _fakeRender(WallpaperOverlayContent c) async =>
    WallpaperOverlayPayload(
      asOf: c.asOf,
      freshPng: Uint8List.fromList(c.bandAndTime.codeUnits.take(4).toList()),
      stalePng: Uint8List.fromList(const [1]),
      pixelRatio: c.pixelRatio,
    );

ShowWallpaperOverlay _show(String sample) =>
    ShowWallpaperOverlay(overlayContentFor(sample));

const _clear = ClearWallpaperOverlay(WallpaperOverlayClearReason.disabled);

void main() {
  setUpAll(initializeDateFormatting);

  test('同じ要求は送り直さない。変われば送る', () async {
    final bridge = _RecordingBridge();
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_show('comfortable'));
    await sync.update(_show('comfortable'));
    await sync.update(null); // データ待ちは何もしない
    await sync.update(_show('hot'));
    expect(bridge.calls, hasLength(2));
    expect(sync.lastApplied, _show('hot'));
  });

  test('消す要求は理由によらず 1 回。描いて渡したあとは消し、また描く', () async {
    final bridge = _RecordingBridge();
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_show('comfortable'));
    await sync.update(_clear);
    await sync.update(
      const ClearWallpaperOverlay(WallpaperOverlayClearReason.fallbackLocation),
    );
    await sync.update(_show('comfortable'));
    expect(
        bridge.calls.map((c) => c.split(' ').first), ['set', 'clear', 'set']);
  });

  test('起動直後に設定がオフなら、まず消す (前回の重ね描きを残さない)', () async {
    final bridge = _RecordingBridge();
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_clear);
    expect(bridge.calls, ['clear']);
  });

  test('送れなかった要求は次にまた送る', () async {
    final bridge = _RecordingBridge()..succeed = false;
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_show('comfortable'));
    expect(sync.lastApplied, isNull);
    bridge.succeed = true;
    await sync.update(_show('comfortable'));
    expect(bridge.calls, hasLength(2));
    expect(sync.lastApplied, _show('comfortable'));
  });

  test('描けなかったときも例外にせず、次にまた描く', () async {
    final bridge = _RecordingBridge();
    var fail = true;
    final sync = WallpaperOverlaySync(
      bridge,
      render: (c) async {
        if (fail) throw StateError('boom');
        return _fakeRender(c);
      },
    );
    await sync.update(_show('comfortable'));
    expect(bridge.calls, isEmpty);
    fail = false;
    await sync.update(_show('comfortable'));
    expect(bridge.calls, hasLength(1));
  });

  test('描いている間に来た要求は、終わってから最新のものだけを処理する', () async {
    final bridge = _RecordingBridge();
    final gate = Completer<void>();
    var renders = 0;
    final sync = WallpaperOverlaySync(
      bridge,
      render: (c) async {
        renders++;
        if (renders == 1) await gate.future;
        return _fakeRender(c);
      },
    );
    final first = sync.update(_show('cool'));
    await sync.update(_show('warm')); // 処理中なので待たずに戻る
    await sync.update(_clear); // 最新
    gate.complete();
    await first;
    expect(bridge.calls.map((c) => c.split(' ').first), ['set', 'clear']);
    expect(sync.lastApplied, _clear);
  });

  test('受け渡しの内容はデータの時刻と解像度を持つ (実際の描画は painter のテスト)', () async {
    final bridge = _RecordingBridge();
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_show('comfortable'));
    expect(bridge.calls.single,
        startsWith('set ${kOverlayAsOf.millisecondsSinceEpoch} '));
  });

  test('ロケールが違えば送り直す (文言と書体が変わる)', () async {
    final bridge = _RecordingBridge();
    final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
    await sync.update(_show('comfortable'));
    await sync.update(ShowWallpaperOverlay(
      overlayContentFor('comfortable', locale: const Locale('en')),
    ));
    expect(bridge.calls, hasLength(2));
  });

  group('データ削除 (clear)', () {
    test('消したあとは、前と同じ内容でも描き直して送る', () async {
      final bridge = _RecordingBridge();
      final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
      await sync.update(_show('comfortable'));
      expect(await sync.clear(), isTrue);
      expect(sync.lastApplied, isNull);
      await sync.update(_show('comfortable'));
      expect(
          bridge.calls.map((c) => c.split(' ').first), ['set', 'clear', 'set']);
    });

    test('設定でオフ (消した状態) でも、データ削除では必ず消しに行く', () async {
      final bridge = _RecordingBridge();
      final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
      await sync.update(_clear);
      await sync.clear();
      expect(bridge.calls, ['clear', 'clear']);
      // 次のオフの要求も送る (前に届いた要求を覚えていない)
      await sync.update(_clear);
      expect(bridge.calls, ['clear', 'clear', 'clear']);
    });

    test('描いている途中で消したら、その内容は送らない', () async {
      final bridge = _RecordingBridge();
      final gate = Completer<void>();
      var renders = 0;
      final sync = WallpaperOverlaySync(
        bridge,
        render: (c) async {
          renders++;
          if (renders == 1) await gate.future;
          return _fakeRender(c);
        },
      );
      final drawing = sync.update(_show('hot'));
      await sync.clear();
      gate.complete();
      await drawing;
      expect(bridge.calls, ['clear']);
      expect(sync.lastApplied, isNull);
      // 次の要求 (アプリが描き直したとき) は通常どおり送る
      await sync.update(_show('hot'));
      expect(bridge.calls.map((c) => c.split(' ').first), ['clear', 'set']);
    });

    test('消せなければ false (例外にしない)', () async {
      final bridge = _RecordingBridge()..succeed = false;
      final sync = WallpaperOverlaySync(bridge, render: _fakeRender);
      expect(await sync.clear(), isFalse);
    });
  });
}
