// lib/presentation/shared/weather_rail.dart
//
// 時間別 MRI の時刻ラベルの下に並べる「天気レール」(天気グリフ + 気温)。
// ホームの時間別 MRI と、詳細の MRI TREND で共用する。
//
// - 文字の天気名 (「晴れ」など) は出さない。グリフと気温だけ (2026-09-29 ユーザー指示)。
// - 気温の書体は Inter / Plex Sans JP Medium (読み値) のまま、サイズだけ型スケールの
//   axis を借りる (時刻軸の Plex Mono にはしない)。
// - Heat グリフは、その時刻の MRI 帯が hotAlert のときだけ (§4.4 の例外)。
// - 項目は時刻ラベルと同じ間引きに従う。項目の幅 ([weatherRailCompanion]) を時刻
//   ラベル (TimeAxisLabels.companion) に渡し、項目どうしが接しない間引き・置き方を
//   選ばせる (QA-10)。

import 'package:flutter/material.dart';

import '../../core/utils/temperature_unit.dart';
import '../../domain/mri/mri_band.dart';
import '../../domain/mri/mri_timeline.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'chart_axes.dart';
import 'quiet_glyphs.dart';

/// レール項目のグリフの大きさ (Figma 9.5)。
const double kWeatherRailGlyphSize = 9.5;

/// グリフと気温の間隔 (Figma 3)。
const double kWeatherRailGlyphGap = 3;

/// 送り幅がこれ (em) 以上の「°」は全角とみなす ([weatherRailCompanion])。
const double kFullWidthDegreeMinAdvance = 0.8;

/// 全角の「°」の右端の空き (送り幅に対する比)。実測 57.6% より少し控えめ。
const double kFullWidthDegreeBlank = 0.55;

/// 天気レールの気温の文字スタイル。
TextStyle? weatherRailTextStyle(BuildContext context) {
  final tokens = MrwTokens.of(context);
  final type = MrwType.of(context);
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: type.axis.fontSize(8.5),
        fontWeight: FontWeight.w500,
        height: type.axis.height(11 / 8.5),
        color: tokens.textMid.withValues(alpha: 0.82),
      );
}

/// 天気レールの行の高さ (= 行送り)。文字倍率に追従させる (固定だと拡大時に切れる)。
double weatherRailHeight(BuildContext context) {
  final line = MrwType.of(context).axis.lineHeight(11);
  return MediaQuery.textScalerOf(context)
      .scale(line)
      .clamp(line, line * 2)
      .toDouble();
}

/// レールに出すデータ点 (スロット番号 → その時刻 [slots] に最も近い点)。
/// データが無いスロットは含めない。
Map<int, MriTimelinePoint> weatherRailPoints(
  List<MriTimelinePoint> points,
  Map<int, DateTime> slots,
) =>
    {
      for (final MapEntry(key: i, value: at) in slots.entries)
        if (MriTimeline.nearest(points, at) case final p?) i: p,
    };

/// レールの項目 (長さ [slotCount]。データの無いスロットは null)。
List<Widget?> weatherRailItems(
  Map<int, MriTimelinePoint> points, {
  required int slotCount,
  required TemperatureUnit unit,
  TextStyle? style,
}) =>
    [
      for (var i = 0; i < slotCount; i++)
        if (points[i] case final p?)
          WeatherRailItem(point: p, unit: unit, style: style)
        else
          null,
    ];

/// レールの項目の中身の幅 (グリフ + 間隔 + 気温。文字倍率込み)。時刻ラベルに渡し、
/// 項目どうしが接しない間引き・置き方を選ばせる (TimeAxisLabels.companion)。
/// [span] は BarSlotRow.span と同じ値。
///
/// 気温の末尾の「°」は、JA の書体 (IBM Plex Sans JP) では全角 (送り 1.00em) で、
/// 字面は左の 0.06〜0.43em だけ・右の 0.58em (送り幅の 57.6%) は空き (2026-09-29
/// 実測)。EN / ES / ZH の書体 (Inter) の「°」は送り 0.46em で、右の空きは 0.07em。
/// 送り幅が 0.8em 以上の「°」は、送り幅の 55% (実測より少し控えめ) を右端の空き
/// ([AxisCompanionRow.trailingBlanks]) として間隔の判定から除く (見た目では離れて
/// いるのに置き方を変えたり間引いたりしない)。
AxisCompanionRow weatherRailCompanion(
  BuildContext context,
  Map<int, MriTimelinePoint> points, {
  required int span,
  required TemperatureUnit unit,
  TextStyle? style,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final locale = Localizations.maybeLocaleOf(context);
  double advance(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final em = scaler.scale(style?.fontSize ?? 14);
  final degree = advance('°');
  final degreeBlank = degree >= em * kFullWidthDegreeMinAdvance
      ? degree * kFullWidthDegreeBlank
      : 0.0;
  final widths = <int, double>{};
  final blanks = <int, double>{};
  for (final MapEntry(key: i, value: p) in points.entries) {
    final text = unit.formatDegrees(p.snapshot.temperature);
    widths[i] = kWeatherRailGlyphSize + kWeatherRailGlyphGap + advance(text);
    if (degreeBlank > 0 && text.endsWith('°')) blanks[i] = degreeBlank;
  }
  return AxisCompanionRow(
    span: span,
    widths: widths,
    trailingBlanks: blanks,
  );
}

/// レールの 1 項目: グリフ 9.5 + 気温。
class WeatherRailItem extends StatelessWidget {
  const WeatherRailItem({
    super.key,
    required this.point,
    required this.unit,
    this.style,
  });

  final MriTimelinePoint point;
  final TemperatureUnit unit;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        QuietGlyphIcon(
          glyphForCondition(
            point.snapshot.condition,
            heat: point.mri.band == MriBand.hotAlert,
          ),
          size: kWeatherRailGlyphSize,
          opacity: 0.65,
        ),
        const SizedBox(width: kWeatherRailGlyphGap),
        Flexible(
          // 気温と同じ理由で 1 行のまま (JA の全角「°」の空きは枠からはみ出して
          // よい。折り返すと「22」だけになる)。
          child: Text(
            unit.formatDegrees(point.snapshot.temperature),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: style,
          ),
        ),
      ],
    );
  }
}
