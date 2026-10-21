// lib/presentation/wallpaper/wallpaper_overlay_painter.dart
//
// ライブ壁紙の重ね描きを組んで、PNG に描く (docs/design-wallpaper-weather-overlay.md
// §3・§4・§7)。Kotlin は受け取ったビットマップを右上に置くだけなので、見た目はすべて
// ここで決まる (golden: test/golden/wallpaper_overlay_golden_test.dart)。
//
// 座標は dp。基準点 = 重ね描きの右上 (画面の右端から 24dp、ステータスバーの下 16dp) を
// 原点に、左 (x < 0) と下 (y > 0) へ組む。ビットマップでは基準点を
// (幅 − 余白, 余白) に置く (余白 = kWallpaperOverlayPaddingDp。Kotlin も同じ式)。
//
//   新しい表示: 1 行目 = グリフ 28 + 間隔 6 + 気温 (数字書体 Medium 30、右寄せ)。
//               2 行目 = 区分名 · 時刻 (12。気温の数字の下端から 9 下が数字の上端)。
//               幅の上限 (画面の半分) を超えたら「 · 」の位置で区分名と時刻の 2 行に
//               し (行送り 16)、区分名だけでも超えるときは「—」の後ろでも折る
//               (ホームのリングと同じ位置。MoodRingWidget.splitLabel)。
//   古い表示:   1 行目「9/30 10:30 更新」(14)、2 行目「アプリを開くと更新」(12)。
//   文字倍率 (1.3 倍まで) で変わるのは文字・グリフ・字間・行送り。間隔は変えない。
//   色はすべてパール (MrwTokens.dark.textHi)。影・縁取りは付けない。

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../data/wallpaper/wallpaper_overlay_bridge.dart';
import '../shared/mood_ring_widget.dart' show MoodRingWidget;
import '../shared/quiet_glyphs.dart';
import '../shared/weather_rail.dart'
    show kFullWidthDegreeBlank, kFullWidthDegreeMinAdvance;
import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import 'wallpaper_overlay_content.dart';

/// 重ね描きのどちらの表示か。
enum WallpaperOverlayVariant { fresh, stale }

/// 重ね描きの色 (パール = textHi の Dark 値。地が区分ごとに違うので副文字色は使わない)。
final Color kWallpaperOverlayInk = MrwTokens.dark.textHi;

// ── 寸法 (dp。設計書 §3.1・§4) ─────────────────────────────────────────
const double _topPad = 4; // 基準点 → 1 行目の数字の上端
const double _temperatureSize = 30;
const double _glyphBox = 28;
const double _glyphGap = 6;
const double _line2Size = 12;
const double _line2Gap = 9; // 気温の数字の下端 → 2 行目の数字の上端
const double _line2Pitch = 16; // 2 行目を折り返したときの行送り
const double _line2LetterSpacing = 0.6; // JA 以外 (IBM Plex Mono・大文字)
const double _staleTitleSize = 14;
const double _staleHintSize = 12;
const double _staleGap = 10; // 古い表示の 1 行目の下端 → 2 行目の数字の上端

// ── 数字の高さ / em (同梱フォントの OS/2 sCapHeight。数字は大文字と同じ高さ) ──
const double _capInter = 1490 / 2048;
const double _capPlexSansJp = 733 / 1000;
const double _capPlexMono = 698 / 1000;

/// 重ね描きの組版 (dp。基準点 = 右上が原点)。使い終わったら [dispose] する。
class WallpaperOverlayLayout {
  WallpaperOverlayLayout._(this._texts, this._glyph, this.glyphRect);

  factory WallpaperOverlayLayout(
    WallpaperOverlayContent content,
    WallpaperOverlayVariant variant,
  ) =>
      switch (variant) {
        WallpaperOverlayVariant.fresh => _fresh(content),
        WallpaperOverlayVariant.stale => _stale(content),
      };

  final List<_PlacedText> _texts;
  final QuietGlyph? _glyph;

  /// グリフの枠 (新しい表示だけ)。
  final Rect? glyphRect;

  /// 並んだ文字と、その枠 (テスト・診断用)。
  List<({String text, Rect rect})> get lines => [
        for (final t in _texts) (text: t.text, rect: t.rect),
      ];

  /// 中身の外形 (文字の枠とグリフの枠を合わせたもの)。
  Rect get bounds {
    var rect = glyphRect;
    for (final t in _texts) {
      rect = rect == null ? t.rect : rect.expandToInclude(t.rect);
    }
    return rect ?? Rect.zero;
  }

  /// [anchor] (キャンバス上の基準点) に合わせて描く。
  void paint(Canvas canvas, Offset anchor) {
    final glyph = _glyph;
    final rect = glyphRect;
    if (glyph != null && rect != null) {
      paintQuietGlyph(canvas, glyph, rect.shift(anchor), kWallpaperOverlayInk);
    }
    for (final t in _texts) {
      t.painter.paint(canvas, anchor + t.offset);
    }
  }

  void dispose() {
    for (final t in _texts) {
      t.painter.dispose();
    }
  }

  static WallpaperOverlayLayout _fresh(WallpaperOverlayContent c) {
    final s = c.textScale;
    final ja = c.japanese;

    // 1 行目: 気温 (右寄せ) とグリフ。
    final temperatureStyle = _numeralStyle(ja, _temperatureSize * s);
    final temperature = _layout(c.temperature, temperatureStyle);
    final cap = (ja ? _capPlexSansJp : _capInter) * _temperatureSize * s;
    final baseline = _topPad + cap;
    // JA の全角「°」は右の空きの分だけ右へずらし、見た目の右端を 2 行目とそろえる
    // (天気レールと同じ扱い)。
    final blank =
        _degreeBlank(c.temperature, temperatureStyle, _temperatureSize * s);
    final texts = <_PlacedText>[
      _PlacedText(
        c.temperature,
        temperature,
        Offset(
          blank - temperature.width,
          baseline - _firstBaseline(temperature),
        ),
      ),
    ];
    final glyphSize = _glyphBox * s;
    final glyphRect = Rect.fromLTWH(
      blank - temperature.width - _glyphGap - glyphSize,
      baseline - cap / 2 - glyphSize / 2,
      glyphSize,
      glyphSize,
    );

    // 2 行目: 区分名 · 時刻 (右寄せ)。
    final style = _labelStyle(ja, _line2Size * s);
    final spacing = ja ? 0.0 : _line2LetterSpacing * s;
    final cap2 = (ja ? _capPlexSansJp : _capPlexMono) * _line2Size * s;
    var lineBaseline = baseline + _line2Gap + cap2;
    for (final line in _line2(c, style)) {
      final painter = _layout(line, style, maxWidth: c.maxWidth);
      final top = lineBaseline - _firstBaseline(painter);
      // 字間は最後の字の後ろにも付くので、その分だけ右へ出して字面の右端をそろえる。
      texts.add(
          _PlacedText(line, painter, Offset(spacing - painter.width, top)));
      lineBaseline = top + _lastBaseline(painter) + _line2Pitch * s;
    }
    return WallpaperOverlayLayout._(texts, c.glyph, glyphRect);
  }

  static WallpaperOverlayLayout _stale(WallpaperOverlayContent c) {
    final s = c.textScale;
    final ja = c.japanese;
    final capRatio = ja ? _capPlexSansJp : _capInter;
    final titleStyle = _bodyStyle(ja, _staleTitleSize * s);
    final hintStyle = _bodyStyle(ja, _staleHintSize * s);

    final title = _layout(c.staleTitle, titleStyle, maxWidth: c.maxWidth);
    final titleTop =
        _topPad + capRatio * _staleTitleSize * s - _firstBaseline(title);
    final hint = _layout(c.staleHint, hintStyle, maxWidth: c.maxWidth);
    final hintTop = titleTop +
        _lastBaseline(title) +
        _staleGap +
        capRatio * _staleHintSize * s -
        _firstBaseline(hint);
    return WallpaperOverlayLayout._(
      [
        _PlacedText(c.staleTitle, title, Offset(-title.width, titleTop)),
        _PlacedText(c.staleHint, hint, Offset(-hint.width, hintTop)),
      ],
      null,
      null,
    );
  }

  /// 2 行目の行分け。1 行で幅に収まればそのまま、収まらなければ「 · 」の位置で
  /// 区分名と時刻に分け、区分名だけでも収まらなければ「—」の後ろでも分ける。
  static List<String> _line2(WallpaperOverlayContent c, TextStyle style) {
    double width(String text) {
      final painter = _layout(text, style);
      final w = painter.width;
      painter.dispose();
      return w;
    }

    if (width(c.bandAndTime) <= c.maxWidth) return [c.bandAndTime];
    if (width(c.bandLabel) <= c.maxWidth) return [c.bandLabel, c.time];
    final split = MoodRingWidget.splitLabel(c.bandLabel);
    if (split == null) return [c.bandLabel, c.time];
    return [split.$1, split.$2, c.time];
  }
}

class _PlacedText {
  _PlacedText(this.text, this.painter, this.offset);

  final String text;
  final TextPainter painter;

  /// 基準点からの左上の位置。
  final Offset offset;

  Rect get rect => offset & painter.size;
}

TextPainter _layout(String text, TextStyle style, {double? maxWidth}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      // 折り返したときも、いちばん長い行の幅を painter の幅にする (右端をそろえる)。
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxWidth ?? double.infinity);

double _firstBaseline(TextPainter painter) =>
    painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);

double _lastBaseline(TextPainter painter) {
  final metrics = painter.computeLineMetrics();
  return metrics.isEmpty ? _firstBaseline(painter) : metrics.last.baseline;
}

/// 全角の「°」(送り 0.8em 以上) の右の空き。JA の書体 (IBM Plex Sans JP) だけ。
double _degreeBlank(String text, TextStyle style, double fontSize) {
  if (!text.endsWith('°')) return 0;
  final painter = _layout('°', style);
  final advance = painter.width;
  painter.dispose();
  return advance >= fontSize * kFullWidthDegreeMinAdvance
      ? advance * kFullWidthDegreeBlank
      : 0;
}

/// 気温: 数字書体 Medium (EN Inter / JA IBM Plex Sans JP。MrwFonts.numeral と同じ)。
TextStyle _numeralStyle(bool ja, double size) => ja
    ? TextStyle(
        fontFamily: MrwFonts.plexSansJp,
        fontFamilyFallback: const [MrwFonts.inter],
        fontWeight: FontWeight.w500,
        fontSize: size,
        color: kWallpaperOverlayInk,
      )
    : TextStyle(
        fontFamily: MrwFonts.inter,
        fontFamilyFallback: const [MrwFonts.plexSansJp],
        fontVariations: MrwFonts.interVariations(FontWeight.w500),
        fontWeight: FontWeight.w500,
        fontSize: size,
        color: kWallpaperOverlayInk,
      );

/// 2 行目: アプリの状態ラベルと同じ (EN IBM Plex Mono Medium・字間 0.6 / JA IBM Plex
/// Sans JP Medium)。大文字化は中身の側 (wallpaperOverlayContent) で済ませてある。
TextStyle _labelStyle(bool ja, double size) => TextStyle(
      fontFamily: ja ? MrwFonts.plexSansJp : MrwFonts.plexMono,
      fontFamilyFallback:
          ja ? const [MrwFonts.plexMono] : const [MrwFonts.plexSansJp],
      fontWeight: FontWeight.w500,
      fontSize: size,
      letterSpacing: ja ? null : size / _line2Size * _line2LetterSpacing,
      color: kWallpaperOverlayInk,
    );

/// 古い表示: 本文 Regular (EN Inter / JA IBM Plex Sans JP)。
TextStyle _bodyStyle(bool ja, double size) => ja
    ? TextStyle(
        fontFamily: MrwFonts.plexSansJp,
        fontFamilyFallback: const [MrwFonts.inter],
        fontWeight: FontWeight.w400,
        fontSize: size,
        color: kWallpaperOverlayInk,
      )
    : TextStyle(
        fontFamily: MrwFonts.inter,
        fontFamilyFallback: const [MrwFonts.plexSansJp],
        fontVariations: MrwFonts.interVariations(FontWeight.w400),
        fontWeight: FontWeight.w400,
        fontSize: size,
        color: kWallpaperOverlayInk,
      );

/// ビットマップの大きさ (画素)。基準点は (幅 − 余白, 余白) に来る。
({int width, int height}) wallpaperOverlayBitmapSize(
  WallpaperOverlayLayout layout,
  double pixelRatio,
) {
  const pad = kWallpaperOverlayPaddingDp;
  final bounds = layout.bounds;
  final left = math.max(0.0, -bounds.left);
  final down = math.max(0.0, bounds.bottom);
  return (
    width: ((left + 2 * pad) * pixelRatio).ceil(),
    height: ((down + 2 * pad) * pixelRatio).ceil(),
  );
}

/// 重ね描きの 1 枚をビットマップに描く (端末の解像度)。
Future<ui.Image> rasterizeWallpaperOverlay(
  WallpaperOverlayContent content,
  WallpaperOverlayVariant variant,
) async {
  final layout = WallpaperOverlayLayout(content, variant);
  try {
    final ratio = content.pixelRatio;
    final size = wallpaperOverlayBitmapSize(layout, ratio);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    layout.paint(
      canvas,
      Offset(
        size.width / ratio - kWallpaperOverlayPaddingDp,
        kWallpaperOverlayPaddingDp,
      ),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size.width, size.height);
    } finally {
      picture.dispose();
    }
  } finally {
    layout.dispose();
  }
}

/// 新しい表示と古い表示の 2 枚を PNG にして、受け渡しの内容にする。
Future<WallpaperOverlayPayload> renderWallpaperOverlayPayload(
  WallpaperOverlayContent content,
) async {
  final fresh =
      await rasterizeWallpaperOverlay(content, WallpaperOverlayVariant.fresh);
  try {
    final stale =
        await rasterizeWallpaperOverlay(content, WallpaperOverlayVariant.stale);
    try {
      return WallpaperOverlayPayload(
        asOf: content.asOf,
        freshPng: await _encodePng(fresh),
        stalePng: await _encodePng(stale),
        pixelRatio: content.pixelRatio,
      );
    } finally {
      stale.dispose();
    }
  } finally {
    fresh.dispose();
  }
}

Future<Uint8List> _encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('wallpaper overlay: PNG encoding failed');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
