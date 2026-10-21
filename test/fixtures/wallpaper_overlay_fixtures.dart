// test/fixtures/wallpaper_overlay_fixtures.dart
//
// ライブ壁紙の重ね描きのテスト用部品。
//   - 区分ごとの見本の天気 (designer のモック overlay_metrics.json と同じ天気・気温)
//   - 中身 (WallpaperOverlayContent) の組み立て
//   - golden 用の壁紙の地: Kotlin の MoodRingWallpaperService と同じ形 (縦の 3 色の
//     グラデーション + 中心 (0.5w, 0.35h)・半径 max(w, h) × 0.5 の光) を Dart で描く。
//     配色は WallpaperPalette.kt の表 (docs/design-wallpaper-palette.md §0) の写し。

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/models/mood_ring_index.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_sync.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';

/// データの時刻 (2026-09-30 13:15。端末ローカル)。
final DateTime kOverlayAsOf = DateTime(2026, 9, 30, 13, 15);

/// 区分ごとの見本 (MRI, 天気, 気温 °C)。推定最適 64 のとき 70 は「快適」、64 は「最適」。
/// 涼しい区分は体感温度 (見本は体感 = 気温) で「涼しい / 寒い / とても寒い — 防寒を」に
/// 分かれる (band_label.dart)。
const Map<String, (int, String, double)> kOverlaySamples = {
  'cool': (85, 'sunny', 10),
  'cold': (92, 'cloudy', 0),
  'veryCold': (100, 'cloudy', -20),
  'optimal': (64, 'partly', 22),
  'comfortable': (70, 'partly', 22),
  'warm': (50, 'cloudy', 27),
  'hot': (30, 'sunny', 33),
  'hotAlert': (10, 'sunny', 37),
};

WeatherSnapshot overlaySnapshot({
  double temperature = 22,
  String condition = 'partly',
  DateTime? timestamp,
}) =>
    WeatherSnapshot(
      timestamp: timestamp ?? kOverlayAsOf,
      latitude: 35.68,
      longitude: 139.77,
      temperature: temperature,
      condition: condition,
    );

MoodRingIndex overlayMri(int value, {DateTime? at}) => MoodRingIndex(
      value: value,
      band: MriBand.fromValue(value),
      factorContributions: const {},
      calculatedAt: at ?? kOverlayAsOf,
    );

/// 見本 [sample] (kOverlaySamples のキー) の中身。
WallpaperOverlayContent overlayContentFor(
  String sample, {
  Locale locale = const Locale('ja'),
  bool? use24HourClock,
  double textScale = 1,
  double pixelRatio = 3,
  double screenWidth = 360,
  TemperatureUnit unit = TemperatureUnit.celsius,
  int optimalMri = 64,
}) {
  final (mri, condition, temperature) = kOverlaySamples[sample]!;
  return wallpaperOverlayContent(
    snapshot: overlaySnapshot(temperature: temperature, condition: condition),
    mri: overlayMri(mri),
    optimalMri: optimalMri,
    unit: unit,
    l10n: lookupAppLocalizations(locale),
    locale: locale,
    // EN は 12 時間制 (端末の既定)、ほかは 24 時間制。
    use24HourClock: use24HourClock ?? locale.languageCode != 'en',
    textScale: textScale,
    pixelRatio: pixelRatio,
    screenWidth: screenWidth,
  );
}

/// 区分 → 地の 3 色と光の中心 (WallpaperPalette.kt の表)。
const Map<MriBand, (Color, Color, Color, Color)> kWallpaperPalettes = {
  MriBand.cool: (
    Color(0xFF1C3855),
    Color(0xFF132437),
    Color(0xFF0D141B),
    Color(0x6658A0EE),
  ),
  MriBand.comfortable: (
    Color(0xFF174734),
    Color(0xFF122E22),
    Color(0xFF0F1914),
    Color(0x6646C795),
  ),
  MriBand.warm: (
    Color(0xFF553D18),
    Color(0xFF382912),
    Color(0xFF1E1810),
    Color(0x66EBAE4A),
  ),
  MriBand.hot: (
    Color(0xFF56291D),
    Color(0xFF381B14),
    Color(0xFF1C110E),
    Color(0x66F0795A),
  ),
  MriBand.hotAlert: (
    Color(0xFF762115),
    Color(0xFF57180F),
    Color(0xFF3A130C),
    Color(0xB3E5533D),
  ),
};

/// 壁紙の地 (画面の高さ [screenHeight] の上から [size].height ぶんを描く)。
class WallpaperBackdropPainter extends CustomPainter {
  WallpaperBackdropPainter(this.band, {this.screenHeight = 800});

  final MriBand band;
  final double screenHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final (top, middle, bottom, glow) = kWallpaperPalettes[band]!;
    final w = size.width;
    final h = screenHeight;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, middle, bottom],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    final radius = (w > h ? w : h) * 0.5;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(
          Rect.fromCircle(center: Offset(w * 0.5, h * 0.35), radius: radius),
        ),
    );
  }

  @override
  bool shouldRepaint(WallpaperBackdropPainter old) =>
      old.band != band || old.screenHeight != screenHeight;
}

/// 描画せずに要求を記録する重ね描きの同期役 (アプリ全体を組むテスト用。本物の
/// ビットマップ化とチャネル呼び出しをしない)。[providerOverride] を ProviderScope に渡す。
class RecordingWallpaperOverlay implements WallpaperOverlayBridge {
  RecordingWallpaperOverlay() {
    sync = WallpaperOverlaySync(
      this,
      render: (content) async {
        contents.add(content);
        return WallpaperOverlayPayload(
          asOf: content.asOf,
          freshPng: Uint8List(1),
          stalePng: Uint8List(1),
          pixelRatio: content.pixelRatio,
        );
      },
    );
  }

  late final WallpaperOverlaySync sync;

  /// 描いて渡した中身 (順に)。
  final contents = <WallpaperOverlayContent>[];

  /// 壁紙へ届いた呼び出し ('set' / 'clear')。
  final calls = <String>[];

  Override get providerOverride =>
      wallpaperOverlaySyncProvider.overrideWithValue(sync);

  @override
  Future<bool> setOverlay(WallpaperOverlayPayload payload) async {
    calls.add('set');
    return true;
  }

  @override
  Future<bool> clearOverlay() async {
    calls.add('clear');
    return true;
  }
}
