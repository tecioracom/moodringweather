// test/golden/wallpaper_overlay_golden_test.dart
//
// ライブ壁紙の重ね描きの golden (docs/design-wallpaper-weather-overlay.md、2026-09-30 決裁)。
// Kotlin に渡すのと同じビットマップ (rasterizeWallpaperOverlay、解像度 2) を、画面の
// 右上 240dp の切り抜き (360dp 幅の端末) に、Kotlin と同じ位置 (右端から 24dp、
// ステータスバー 24dp の下 16dp) で置いて撮る。地は区分の「地・上」の色 (平ら。
// グラデーションと光は Kotlin 側で、JVM のテストで確かめる)。ビットマップの外形が
// 小さすぎて字形やグリフが欠けると、ここで分かる。
//
// 1 枚に 13 コマ (JA / EN の 2 枚):
//   涼しい・寒い・とても寒い・快適・最適・やや暑い・暑い・とても暑い (新しい表示)、
//   古い表示 (3 時間超)、既定地点 (重ね描きを出さない)、快適 ×1.3、とても暑い ×1.3・
//   とても寒い ×1.3 (長い区分名の折り返し)
//
// 実行:   flutter test test/golden/wallpaper_overlay_golden_test.dart
// 更新:   flutter test test/golden/wallpaper_overlay_golden_test.dart --update-goldens

@Tags(['golden'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_painter.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';
import 'golden_harness.dart';

const double _ratio = 2;
const double _screenWidth = 360;
const Size _panel = Size(240, 150);
const double _statusBar = 24;
const double _captionHeight = 16;
const double _gap = 12;
const Color _sheet = Color(0xFF0D0E11);

class _Panel {
  _Panel(this.caption, this.band, this.image);

  final String caption;
  final MriBand band;
  final ui.Image? image;
}

class _PanelPainter extends CustomPainter {
  _PanelPainter(this.panel);

  final _Panel panel;

  @override
  void paint(Canvas canvas, Size size) {
    final (top, _, _, _) = kWallpaperPalettes[panel.band]!;
    canvas.drawRect(Offset.zero & size, Paint()..color = top);
    final image = panel.image;
    if (image == null) return;
    // Kotlin (WallpaperOverlaySpec.place) と同じ: 基準点 = ビットマップの (幅 − 余白, 余白)
    // を、画面の (右端 − 24dp, ステータスバーの下端 + 16dp) に合わせる。
    const pad = kWallpaperOverlayPaddingDp;
    final width = image.width / _ratio;
    final height = image.height / _ratio;
    final anchor = Offset(
      size.width - kWallpaperOverlayRightDp,
      _statusBar + kWallpaperOverlayTopGapDp,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(anchor.dx - (width - pad), anchor.dy - pad, width, height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PanelPainter old) => old.panel != panel;
}

class _Sheet extends StatelessWidget {
  const _Sheet(this.panels);

  final List<_Panel> panels;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _sheet,
      child: Padding(
        padding: const EdgeInsets.all(_gap),
        child: Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final panel in panels)
              SizedBox(
                width: _panel.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _captionHeight,
                      child: Text(
                        panel.caption,
                        style: const TextStyle(
                          fontFamily: 'IBMPlexSansJP',
                          fontSize: 10,
                          color: Color(0xFFAEB2BA),
                        ),
                      ),
                    ),
                    CustomPaint(
                      size: _panel,
                      painter: _PanelPainter(panel),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  const cases = <(String sample, String caption, double scale, bool stale)>[
    ('cool', '涼しい 85 (体感 10°) · 新しい', 1.0, false),
    ('cold', '寒い 92 (体感 0°) · 新しい', 1.0, false),
    ('veryCold', 'とても寒い 100 (体感 −20°) · 新しい', 1.0, false),
    ('comfortable', '快適 70 · 新しい', 1.0, false),
    ('optimal', '最適 64 (推定最適 64) · 新しい', 1.0, false),
    ('warm', 'やや暑い 50 · 新しい', 1.0, false),
    ('hot', '暑い 30 · 新しい', 1.0, false),
    ('hotAlert', 'とても暑い 10 · 新しい', 1.0, false),
    ('comfortable', '快適 · 古い表示 (3 時間超)', 1.0, true),
    ('comfortable', '快適 · 既定地点 (出さない)', 1.0, false),
    ('comfortable', '快適 · 文字 ×1.3', 1.3, false),
    ('hotAlert', 'とても暑い · 文字 ×1.3', 1.3, false),
    ('veryCold', 'とても寒い · 文字 ×1.3', 1.3, false),
  ];

  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('重ね描き (${locale.languageCode})', (tester) async {
      final sheetSize = Size(
        _gap * 3 + _panel.width * 2,
        _gap +
            (cases.length / 2).ceil() * (_captionHeight + _panel.height + _gap),
      );
      tester.view.physicalSize = sheetSize * _ratio;
      tester.view.devicePixelRatio = _ratio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final panels = <_Panel>[];
      for (final (sample, caption, scale, stale) in cases) {
        final (mri, condition, temperature) = kOverlaySamples[sample]!;
        final fallback = caption.contains('既定地点');
        // 送る / 消すの判定は本番と同じ関数 (既定地点は消す = 何も描かない)。
        final request = wallpaperOverlayRequest(
          enabled: true,
          location: fallback
              ? LocationDataSource.fallback
              : const GeoPoint(35.68, 139.77),
          snapshot:
              overlaySnapshot(temperature: temperature, condition: condition),
          mri: overlayMri(mri),
          optimalMri: 64,
          unit: TemperatureUnit.celsius,
          l10n: lookupAppLocalizations(locale),
          locale: locale,
          use24HourClock: locale.languageCode != 'en',
          textScale: scale,
          pixelRatio: _ratio,
          screenWidth: _screenWidth,
        );
        ui.Image? image;
        if (request is ShowWallpaperOverlay) {
          image = await tester.runAsync(
            () => rasterizeWallpaperOverlay(
              request.content,
              stale
                  ? WallpaperOverlayVariant.stale
                  : WallpaperOverlayVariant.fresh,
            ),
          );
        } else {
          expect(fallback, isTrue);
          expect(request, isA<ClearWallpaperOverlay>());
        }
        panels.add(_Panel(caption, MriBand.fromValue(mri), image));
      }

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: sheetSize, child: _Sheet(panels)),
          ),
        ),
      );
      await expectLater(
        find.byType(_Sheet),
        matchesGoldenFile(
            'goldens/wallpaper_overlay_${locale.languageCode}.png'),
      );
      for (final panel in panels) {
        panel.image?.dispose();
      }
    });
  }
}
