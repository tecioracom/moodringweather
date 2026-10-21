// 重ね描きの組版と描画 (lib/presentation/wallpaper/wallpaper_overlay_painter.dart)。
// 同梱フォントを読み込んで、実際の文字幅で確かめる (docs/design-wallpaper-weather-overlay.md
// §3・§4)。
//   - 右端そろえ (気温と 2 行目。JA の全角「°」は空きの分だけ右へ)、グリフは気温の左 6dp
//   - 2 行目は 1 行で収まらなければ「 · 」で折り返す (区分名 / 時刻)。区分名だけでも
//     収まらなければ「—」の後ろでも折る。どの行も幅の上限 (画面の半分) に収まる
//   - 文字倍率は 1.3 倍で止まる
//   - ビットマップの大きさと、基準点 (幅 − 余白, 余白) の約束

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_painter.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';
import '../golden/golden_harness.dart';

const _locales = [
  Locale('ja'),
  Locale('en'),
  Locale('es'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];

List<String> _texts(WallpaperOverlayLayout layout) =>
    layout.lines.map((l) => l.text).toList();

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await initializeDateFormatting();
  });

  WallpaperOverlayLayout fresh(WallpaperOverlayContent c) =>
      WallpaperOverlayLayout(c, WallpaperOverlayVariant.fresh);

  testWidgets('新しい表示: 1 行目は気温とグリフ、2 行目は右端をそろえる', (tester) async {
    final layout = fresh(overlayContentFor('comfortable'));
    addTearDown(layout.dispose);
    final [temperature, line2] = layout.lines;
    expect(temperature.text, '22°');
    expect(line2.text, '快適 · 13:15');
    // 2 行目の右端が基準点 (右上) にそろう
    expect(line2.rect.right, moreOrLessEquals(0, epsilon: 0.01));
    // JA の全角「°」は右の空きの分だけ右へ出る
    expect(temperature.rect.right, greaterThan(10));
    // グリフ (28dp) は気温の左 6dp
    final glyph = layout.glyphRect!;
    expect(glyph.width, 28);
    expect(glyph.right, moreOrLessEquals(temperature.rect.left - 6));
    // グリフは気温の数字の高さの中央 (上端は基準点より下)
    expect(glyph.top, greaterThanOrEqualTo(0));
    // 2 行目は 1 行目の下
    expect(line2.rect.top, greaterThan(temperature.rect.top));
  });

  testWidgets('EN は字間の分だけ右へ出して、字面の右端をそろえる', (tester) async {
    final layout =
        fresh(overlayContentFor('comfortable', locale: const Locale('en')));
    addTearDown(layout.dispose);
    final [temperature, line2] = layout.lines;
    expect(line2.text, 'COMFORTABLE · 1:15\u202FPM');
    expect(line2.rect.right, moreOrLessEquals(0.6, epsilon: 0.01));
    // Inter の「°」は半角なので、気温の右端も基準点
    expect(temperature.rect.right, moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets('長い区分名は「 · 」の位置で折り返す (区分名 / 時刻)', (tester) async {
    final en = fresh(overlayContentFor('hotAlert', locale: const Locale('en')));
    addTearDown(en.dispose);
    expect(_texts(en), ['37°', 'VERY HOT — HYDRATE', '1:15\u202FPM']);
    final [_, band, time] = en.lines;
    expect(band.rect.right, moreOrLessEquals(time.rect.right));
    // 行送り 16
    expect(time.rect.top - band.rect.top, moreOrLessEquals(16, epsilon: 0.5));

    // JA: 412dp なら 1 行 (360dp・倍率 1.0 は幅の上限ちょうど 179.98 / 180 なので、
    // ここでは見ず golden で見る)。360dp・倍率 1.3 では「 · 」で折り返す。
    final ja = fresh(overlayContentFor('hotAlert', screenWidth: 412));
    addTearDown(ja.dispose);
    expect(_texts(ja), ['37°', 'とても暑い — 水分補給を · 13:15']);
    final ja13 = fresh(overlayContentFor('hotAlert', textScale: 1.3));
    addTearDown(ja13.dispose);
    expect(_texts(ja13), ['37°', 'とても暑い — 水分補給を', '13:15']);
  });

  testWidgets('区分名だけでも収まらなければ「—」の後ろでも折る (ホームのリングと同じ位置)', (tester) async {
    final layout = fresh(
      overlayContentFor('hotAlert', locale: const Locale('en'), textScale: 1.3),
    );
    addTearDown(layout.dispose);
    expect(_texts(layout), ['37°', 'VERY HOT —', 'HYDRATE', '1:15\u202FPM']);
    // 412dp なら区分名は 1 行
    final wide = fresh(overlayContentFor(
      'hotAlert',
      locale: const Locale('en'),
      textScale: 1.3,
      screenWidth: 412,
    ));
    addTearDown(wide.dispose);
    expect(_texts(wide), ['37°', 'VERY HOT — HYDRATE', '1:15\u202FPM']);
  });

  testWidgets('4 言語 × 全区分 × 倍率 1.0 / 1.3 × 360 / 412dp で、幅の上限 (画面の半分) に収まる',
      (tester) async {
    for (final locale in _locales) {
      for (final sample in kOverlaySamples.keys) {
        for (final scale in [1.0, 1.3]) {
          for (final width in [360.0, 412.0]) {
            final content = overlayContentFor(
              sample,
              locale: locale,
              textScale: scale,
              screenWidth: width,
            );
            for (final variant in WallpaperOverlayVariant.values) {
              final layout = WallpaperOverlayLayout(content, variant);
              final tag = '$locale $sample ×$scale ${width}dp ${variant.name}';
              expect(-layout.bounds.left, lessThanOrEqualTo(width / 2 + 0.5),
                  reason: tag);
              for (final line in layout.lines) {
                expect(line.rect.width, lessThanOrEqualTo(width / 2 + 0.7),
                    reason: '$tag 「${line.text}」');
              }
              layout.dispose();
            }
          }
        }
      }
    }
  });

  testWidgets('文字倍率は 1.3 倍で止まる (グリフ 28 → 36.4)', (tester) async {
    final layout = fresh(overlayContentFor('comfortable', textScale: 2));
    addTearDown(layout.dispose);
    expect(layout.glyphRect!.width, moreOrLessEquals(28 * 1.3));
  });

  testWidgets('古い表示: 「9/30 13:15 更新」と「アプリを開くと更新」を右寄せで 2 行', (tester) async {
    final layout = WallpaperOverlayLayout(
      overlayContentFor('comfortable'),
      WallpaperOverlayVariant.stale,
    );
    addTearDown(layout.dispose);
    expect(_texts(layout), ['9/30 13:15 更新', 'アプリを開くと更新']);
    expect(layout.glyphRect, isNull);
    final [title, hint] = layout.lines;
    expect(title.rect.right, moreOrLessEquals(0, epsilon: 0.01));
    expect(hint.rect.right, moreOrLessEquals(0, epsilon: 0.01));
    expect(hint.rect.top, greaterThan(title.rect.top));
  });

  testWidgets('ビットマップの大きさと PNG (基準点は (幅 − 余白, 余白))', (tester) async {
    final content = overlayContentFor('comfortable', pixelRatio: 2.75);
    final layout = fresh(content);
    final size = wallpaperOverlayBitmapSize(layout, 2.75);
    final left = -layout.bounds.left;
    final down = layout.bounds.bottom;
    layout.dispose();
    const pad = kWallpaperOverlayPaddingDp;
    expect(size.width, ((left + 2 * pad) * 2.75).ceil());
    expect(size.height, ((down + 2 * pad) * 2.75).ceil());

    final payload =
        (await tester.runAsync(() => renderWallpaperOverlayPayload(content)))!;
    expect(payload.asOf, content.asOf);
    expect(payload.pixelRatio, 2.75);
    final decoded = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(payload.freshPng);
      final frame = await codec.getNextFrame();
      return frame.image;
    }))!;
    expect(decoded.width, size.width);
    expect(decoded.height, size.height);
    decoded.dispose();
    expect(payload.stalePng.take(4), [137, 80, 78, 71]); // PNG
  });
}
