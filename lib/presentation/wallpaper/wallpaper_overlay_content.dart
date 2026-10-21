// lib/presentation/wallpaper/wallpaper_overlay_content.dart
//
// ライブ壁紙の重ね描きの中身と、送るか消すかの判定
// (docs/design-wallpaper-weather-overlay.md。2026-09-30 ユーザー決裁)。
//
//   1 行目: 天気グリフ + 気温 (「22°」)
//   2 行目: 区分名 · データの時刻 (「快適 · 11:30」。区分名はホームのリングの下と同じ語)
//   古い表示 (データの時刻から 3 時間超): 「9/30 10:30 更新」「アプリを開くと更新」
//
// 出さないとき: 設定でオフ・現在地が分からず既定地点 (東京) を使っている → 消す。
// データ待ち (現在地・天気・MRI の取得中や失敗) → 何もしない (前回の重ね描きが残り、
// 古さは壁紙側がデータの時刻で判断する)。

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:intl/intl.dart';

import '../../core/utils/temperature_unit.dart';
import '../../data/datasources/location_datasource.dart';
import '../../data/models/mood_ring_index.dart';
import '../../data/models/weather_snapshot.dart';
import '../../domain/mri/mri_band.dart';
import '../../l10n/app_localizations.dart';
import '../shared/band_label.dart';
import '../shared/quiet_glyphs.dart';
import '../theme/app_theme.dart';

/// 端末の文字の大きさへの追従の上限 (設計書 §3.5: アイコン列や時計にはみ出さない)。
const double kWallpaperOverlayMaxTextScale = 1.3;

/// 追従の下限 (Android の「小」0.85 まで)。
const double kWallpaperOverlayMinTextScale = 0.85;

/// 重ね描きの幅の上限 (画面の幅に対する比。左上の日付・時計ウィジェットと重ねない)。
const double kWallpaperOverlayMaxWidthFraction = 0.5;

/// 重ね描きの中身。等しい間は送り直さない (WallpaperOverlaySync)。
@immutable
class WallpaperOverlayContent {
  const WallpaperOverlayContent({
    required this.glyph,
    required this.temperature,
    required this.bandLabel,
    required this.time,
    required this.bandAndTime,
    required this.staleTitle,
    required this.staleHint,
    required this.asOf,
    required this.japanese,
    required this.textScale,
    required this.pixelRatio,
    required this.maxWidth,
  });

  /// 1 行目のグリフ。Heat は区分がとても暑いのときだけ (天気レールと同じ)。
  final QuietGlyph glyph;

  /// 1 行目の気温 (設定の °C / °F の整数 + 「°」)。
  final String temperature;

  /// 2 行目の区分名 (ホームのリングの下と同じ語。JA 以外は大文字)。
  final String bandLabel;

  /// 2 行目の時刻 (データの時刻。端末の 12 / 24 時間制。JA 以外は大文字)。
  final String time;

  /// 2 行目を 1 行で組むときの文 (「快適 · 11:30」)。幅に収まらなければ
  /// [bandLabel] と [time] の 2 行にする (「 · 」の位置で折り返す)。
  final String bandAndTime;

  /// 古い表示の 1 行目 (「9/30 10:30 更新」)。
  final String staleTitle;

  /// 古い表示の 2 行目 (「アプリを開くと更新」)。
  final String staleHint;

  /// データの時刻 (壁紙が新しい / 古いを選ぶ基準)。
  final DateTime asOf;

  /// JA の書体 (IBM Plex Sans JP) で組むか。それ以外は Inter / IBM Plex Mono。
  final bool japanese;

  /// 文字の倍率 (端末の設定。[kWallpaperOverlayMaxTextScale] まで)。
  final double textScale;

  /// 描く解像度 (端末の devicePixelRatio)。
  final double pixelRatio;

  /// 重ね描きの幅の上限 (dp。画面の幅の半分)。
  final double maxWidth;

  @override
  bool operator ==(Object other) =>
      other is WallpaperOverlayContent &&
      other.glyph == glyph &&
      other.temperature == temperature &&
      other.bandLabel == bandLabel &&
      other.time == time &&
      other.bandAndTime == bandAndTime &&
      other.staleTitle == staleTitle &&
      other.staleHint == staleHint &&
      other.asOf == asOf &&
      other.japanese == japanese &&
      other.textScale == textScale &&
      other.pixelRatio == pixelRatio &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(
        glyph,
        temperature,
        bandLabel,
        time,
        bandAndTime,
        staleTitle,
        staleHint,
        asOf,
        japanese,
        textScale,
        pixelRatio,
        maxWidth,
      );

  @override
  String toString() =>
      'WallpaperOverlayContent($glyph, $temperature, "$bandAndTime", '
      '"$staleTitle", asOf: $asOf)';
}

/// 重ね描きへの要求 (描いて渡す / 消す)。
@immutable
sealed class WallpaperOverlayRequest {
  const WallpaperOverlayRequest();
}

/// 重ね描きを描いて渡す。
final class ShowWallpaperOverlay extends WallpaperOverlayRequest {
  const ShowWallpaperOverlay(this.content);

  final WallpaperOverlayContent content;

  @override
  bool operator ==(Object other) =>
      other is ShowWallpaperOverlay && other.content == content;

  @override
  int get hashCode => content.hashCode;

  @override
  String toString() => 'ShowWallpaperOverlay($content)';
}

/// 重ね描きを消す理由 (テスト・診断用。送る内容は同じ)。
enum WallpaperOverlayClearReason { disabled, fallbackLocation }

/// 重ね描きを消す (壁紙は区分の色だけ)。
final class ClearWallpaperOverlay extends WallpaperOverlayRequest {
  const ClearWallpaperOverlay(this.reason);

  final WallpaperOverlayClearReason reason;

  /// 消す要求どうしは理由によらず同じ (続けて送らない)。
  @override
  bool operator ==(Object other) => other is ClearWallpaperOverlay;

  @override
  int get hashCode => (ClearWallpaperOverlay).hashCode;

  @override
  String toString() => 'ClearWallpaperOverlay(${reason.name})';
}

/// 重ね描きを送るか消すかを決める。null はデータ待ち (何もしない)。
///
/// [location] は現在地 (取得中は null)、[snapshot] / [mri] は現在地の天気と MRI
/// (無ければ null)。保存地点を表示していても壁紙は現在地のまま (色と同じ)。
/// [optimalMri] はホームと同じ推定最適 MRI (区分名の「最適」の判定)。
/// [textScale] は端末の文字の倍率、[screenWidth] は画面の幅 (dp)。
WallpaperOverlayRequest? wallpaperOverlayRequest({
  required bool enabled,
  required GeoPoint? location,
  required WeatherSnapshot? snapshot,
  required MoodRingIndex? mri,
  required int optimalMri,
  required TemperatureUnit unit,
  required AppLocalizations l10n,
  required Locale locale,
  required bool use24HourClock,
  required double textScale,
  required double pixelRatio,
  required double screenWidth,
}) {
  if (!enabled) {
    return const ClearWallpaperOverlay(WallpaperOverlayClearReason.disabled);
  }
  if (location == null) return null;
  if (location.isFallback) {
    // 東京の天気を自分の場所の天気のように見せない。
    return const ClearWallpaperOverlay(
      WallpaperOverlayClearReason.fallbackLocation,
    );
  }
  if (snapshot == null || mri == null) return null;
  return ShowWallpaperOverlay(
    wallpaperOverlayContent(
      snapshot: snapshot,
      mri: mri,
      optimalMri: optimalMri,
      unit: unit,
      l10n: l10n,
      locale: locale,
      use24HourClock: use24HourClock,
      textScale: textScale,
      pixelRatio: pixelRatio,
      screenWidth: screenWidth,
    ),
  );
}

/// 重ね描きの中身を組み立てる (文言・書式はアプリと同じ関数・ARB)。
WallpaperOverlayContent wallpaperOverlayContent({
  required WeatherSnapshot snapshot,
  required MoodRingIndex mri,
  required int optimalMri,
  required TemperatureUnit unit,
  required AppLocalizations l10n,
  required Locale locale,
  required bool use24HourClock,
  required double textScale,
  required double pixelRatio,
  required double screenWidth,
}) {
  final japanese = MrwFonts.isJa(locale);
  final localeName = locale.toString();
  final asOf = snapshot.timestamp;
  final at = asOf.toLocal();
  final clock =
      use24HourClock ? DateFormat.Hm(localeName) : DateFormat.jm(localeName);
  final time = clock.format(at);

  // 2 行目: EN などはアプリの状態ラベルと同じく大文字 (JA はそのまま)。
  String label(String s) => japanese ? s : s.toUpperCase();
  final band = label(mriBandLabel(
    l10n,
    mri,
    optimalMri: optimalMri,
    apparentTemperature: snapshot.apparentTemperature ?? snapshot.temperature,
  ));
  final shownTime = label(time);

  // 古い表示の日付: 数字の月/日 (JA・ZH「9/30」) か月の略称 (EN「Sep 30」・ES「30 sept」)。
  // 日付・時刻の中の空白は改行しない空白にし、折り返すなら文言の語の間か、日付と
  // 時刻の間にする。
  final numericDate = japanese || locale.languageCode == 'zh';
  final date =
      (numericDate ? DateFormat.Md(localeName) : DateFormat.MMMd(localeName))
          .format(at);
  String keepTogether(String s) => s.replaceAll(' ', '\u00A0');

  return WallpaperOverlayContent(
    glyph: glyphForCondition(
      snapshot.condition,
      heat: mri.band == MriBand.hotAlert,
    ),
    temperature: unit.formatDegrees(snapshot.temperature),
    bandLabel: band,
    time: shownTime,
    bandAndTime: l10n.wallpaperBandAtTime(band, shownTime),
    staleTitle: l10n.updatedAt(
      l10n.wallpaperDateTime(keepTogether(date), keepTogether(time)),
    ),
    staleHint: l10n.wallpaperOpenToRefresh,
    asOf: asOf,
    japanese: japanese,
    textScale: textScale.clamp(
      kWallpaperOverlayMinTextScale,
      kWallpaperOverlayMaxTextScale,
    ),
    pixelRatio: pixelRatio,
    maxWidth: screenWidth * kWallpaperOverlayMaxWidthFraction,
  );
}
