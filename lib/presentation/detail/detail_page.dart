// lib/presentation/detail/detail_page.dart
//
// 詳細 (24 時間) タブ (Figma v1.3 Detail — 24h Instrument 3:243 実測):
//   タイトル "24-hour" (Fraunces 28、字間 −0.28) → 本実装は既存 ARB detailTitle
//   Sparkline Card 350×210: MRI TREND + NOW 74 / capsule bar 12 本 / 右に軸ラベル (上限・下限)
//                           / 時刻ラベル (3 本おき、ロケール準拠の "15:00")
//   FACTORS ラベル → 既存 ARB detailMetricsTitle (大文字化)
//   タイル 2×3 (169×84): 気温 / 湿度 / UV / 空気質 / 風 / 気圧
//                         (docs/design-metric-units-proposal.md §2.1・§2.7)。気温は「22°」
//                         (単位は設定で決まるので付けない)、湿度・風・気圧は値の直後に単位、
//                         UV・空気質は段階語。組み方は shared/metric_tiles.dart
// 内容はボトムナビの上で終える。
//
// 解釈 (docs/v1.3-design-implementation-plan.md §5.4):
//   - バー 12 本は 2 時間刻み = 24 時間 (タイトルと整合。Figma の時刻 12/15/18/21 は例示)。
//     窓は「現在の 6 時間前」から。現在だけを起点にすると +22h までサンプリングする
//     一方でデータは +17h までしか無く、右端 3 本 (25%) が恒久的に空になっていた。
//     過去 6h は取得済み (気圧変化 6h の計算に必須) なのに 1 点も出していなかった。
//   - 軸ラベルは表示範囲の最大・最小を 10 刻みに丸めた値 (Figma の 80 / 30 は例示)。
//     スケールの算出は Home と共通 (MriBarScale)。時刻の書式も共通 (formatAxisHour)
//     — 片方だけ直すと 2 画面で書式が食い違う (docs/home-sparkline-decisions.md ②)。
//   - 副題 "COMFORT INDEX OVER TIME" は ARB に無いため保留。
//   - 花粉のタイルは出さない (2026-09-30 決定)。花粉データは未接続で、欠測でも
//     「少ない」(v1.0 のスタブ) を出していた。5 枚目は風 (ホームと同じ組み方)。
//   - UV・空気質は公式の区分の段階語だけを出す (statusGood 等の独自の状態語は使わない)。
//   - Figma の TEMP アイコンは UV と同じ太陽、PRESSURE は空気の流用 → そのまま踏襲
//     (1.3.1 で差し替え)。
// 地点タブ (案E' 段階 2 `507:2` / `507:111`): ホームで選んだ地点に追随する
// (display_weather_provider.dart)。タイトルの上に見出し行 (pin / bookmark + 地名 +
// 保存地点タグ) を置く。保存地点の時刻ラベルは現地時刻。取得中・失敗でも見出しは残す。
// 文字サイズは型スケール (theme/mrw_type.dart) の役割トークン経由。見出し 28・タイル値・
// 地名は display (固定)。案2 ではタイルの見出し (TEMPERATURE 等) を 2 行まで許容する。
// 厳守: 状態色は使わない (バーはニュートラル、§4.1)。文言は AppLocalizations 経由。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/temperature_unit.dart';
import '../../data/models/weather_snapshot.dart';
import '../../domain/mri/mri_timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/clock_provider.dart';
import '../../providers/display_weather_provider.dart';
import '../../providers/saved_place_weather_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/weather_provider.dart';
import '../places/place_header.dart';
import '../shared/app_background.dart';
import '../shared/chart_axes.dart';
import '../shared/data_attribution_line.dart';
import '../shared/glass_card.dart';
import '../shared/metric_tiles.dart';
import '../shared/mri_bar_scale.dart';
import '../shared/mri_line_chart.dart';
import '../shared/quiet_metric_tile.dart';
import '../shared/weather_rail.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// コンテンツ枠の左右マージン (Figma 3:243: 19/20px)。
const double _kEdgePadding = 20;

/// タイルの間隔。
const double _kGridGutter = 12;

/// Sparkline: 12 本 × 2 時間 = 24 時間 (過去 6h + 現在 + 未来 16h)。
/// 時刻ラベルは 3 本おき (6 時間)。現在は既定で index 3 だが、データが
/// 足りない時間帯 (早朝は当日 00:00 始まり) では窓ごと前に寄せるため実測で決める。
const int _kBarCount = 12;
const Duration _kBarStep = Duration(hours: 2);

/// 折れ線の頂点は毎時。12 スロット × 2h の窓に 23 点、現在の頂点 = スロット × 2。
const Duration _kBarVertexStep = Duration(hours: 1);
const int _kBarVertexCount = (_kBarCount - 1) * 2 + 1;
const double _kBarVerticesPerSlot = 2;
const int _kLabelEvery = 3;
const int _kBarNowIndexDefault = 3;
const double _kBarGap = 10;
const double _kBarHeight = 112;

class DetailPage extends ConsumerWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(displayMriTimelineProvider);

    return AppBackground(
      // タブ本体は Scaffold を持たない。帰属表示の InkWell 用に透明な Material を敷く。
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: timeline.when(
            data: (points) => _DetailBody(points: points),
            loading: () => const _DetailStatus(child: _Loading()),
            error: (error, _) => _DetailStatus(child: _ErrorBody(error: error)),
          ),
        ),
      ),
    );
  }
}

/// 表示中の地点の時間別を取り直す (引っ張って更新・再試行)。失敗は投げない。
Future<void> _refreshHourly(WidgetRef ref) async {
  final placeId = ref.read(displayedPlaceIdProvider);
  try {
    if (placeId == null) {
      ref.invalidate(hourlyWeatherProvider);
      await ref.read(hourlyWeatherProvider.future);
    } else {
      ref.invalidate(savedPlaceHourlyProvider(placeId));
      await ref.read(savedPlaceHourlyProvider(placeId).future);
    }
  } catch (_) {
    // 失敗は画面の AsyncError として出る。
  }
}

/// 取得中・失敗の画面。見出し行 (地点) は残す。
class _DetailStatus extends StatelessWidget {
  const _DetailStatus({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(_kEdgePadding, 14, _kEdgePadding, 0),
          child: PlaceHeaderRow(),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _Loading extends ConsumerWidget {
  const _Loading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final place = ref.watch(displayedSavedPlaceProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            place == null ? t.loadingWeather : t.placeLoading(place.name),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: MrwType.of(context).body.fontSize(13)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  const _ErrorBody({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final place = ref.watch(displayedSavedPlaceProvider);
    final message = place == null
        ? t.errorWeatherLoadFailed
        : t.placeLoadFailed(place.name);
    debugPrint(error is AppException
        ? (error as AppException).developerMessage
        : '$error');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kEdgePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _refreshHourly(ref),
              child: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.points});
  final List<MriTimelinePoint> points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final label = MrwType.of(context).label;
    final text = Theme.of(context).textTheme;
    final place = ref.watch(displayedSavedPlaceProvider);
    final clockNow = ref.watch(clockProvider)();
    final nowIndex = MriTimeline.indexNearest(points, reference: clockNow);
    final now = nowIndex >= 0 ? points[nowIndex] : null;
    final isStale = now != null &&
        clockNow.difference(now.timestamp).abs() > const Duration(hours: 2);

    final labelStyle = text.labelMedium?.copyWith(
      fontSize: label.fontSize(11),
      letterSpacing: label.letterSpacing(0.88),
      color: tokens.textLo,
      height: label.height(14 / 11),
    );

    return RefreshIndicator(
      onRefresh: () => _refreshHourly(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          _kEdgePadding,
          12,
          _kEdgePadding,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        children: [
          if (isStale)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StaleBanner(message: t.errorWeatherFetch),
            ),

          // === 見出し行 (Figma 507:2 / 507:111: y=58、pin / bookmark + 地名) ===
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: PlaceHeaderRow(),
          ),
          const SizedBox(height: 9),

          // === タイトル (Figma 3:285: Fraunces 28 / 字間 −0.28) ===
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              t.detailTitle,
              style: text.headlineMedium?.copyWith(
                fontSize: 28, // 型スケール対象外 (display: 見出し)
                letterSpacing: -0.28,
                height: 34 / 28,
                color: tokens.textHi,
              ),
            ),
          ),

          // === Sparkline Card (3:287) ===
          _TrendCard(
            points: points,
            now: now,
            anchor: now?.timestamp ?? clockNow,
            unit: ref.watch(temperatureUnitProvider),
            labelStyle: labelStyle,
            // 保存地点の時刻は現地時刻で見せる (現在地は端末の時刻のまま)。
            labelOffsetSeconds:
                place == null ? null : now?.snapshot.utcOffsetSeconds,
          ),
          const SizedBox(height: 22),

          // === FACTORS (3:312) + タイル 2×3 ===
          Text(t.detailMetricsTitle.toUpperCase(), style: labelStyle),
          const SizedBox(height: 10),
          if (now != null) _FactorTiles(snapshot: now.snapshot),
          const SizedBox(height: 8),
          const WeatherDataAttribution(),
        ],
      ),
    );
  }
}

/// MRI TREND カード: capsule bar 12 本 (2 時間刻み) + 右の軸ラベル + 時刻ラベル。
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.points,
    required this.now,
    required this.anchor,
    required this.unit,
    required this.labelStyle,
    this.labelOffsetSeconds,
  });

  final List<MriTimelinePoint> points;
  final MriTimelinePoint? now;

  /// 天気レールの気温の単位 (設定 › 一般)。
  final TemperatureUnit unit;

  /// 「現在」に最も近いデータ点の時刻。窓の起点はここから 6 時間戻す。
  final DateTime anchor;
  final TextStyle? labelStyle;

  /// 時刻ラベルを出す地点の UTC オフセット秒 (保存地点)。null は端末の時刻。
  final int? labelOffsetSeconds;

  /// 窓の起点と、そこから見た「現在」の位置を決める。
  /// 既定は現在の 6 時間前を起点にするが、窓がデータの範囲から食み出す場合は
  /// 範囲内へ寄せる (早朝は過去が、深夜は未来が足りない)。こうすると
  /// どの時刻でも空のバーが出ない。
  (DateTime, int) _window() {
    final span = _kBarStep * (_kBarCount - 1);
    var origin = anchor.subtract(_kBarStep * _kBarNowIndexDefault);
    if (points.isNotEmpty) {
      final first = points.first.timestamp;
      final last = points.last.timestamp;
      if (origin.add(span).isAfter(last)) origin = last.subtract(span);
      if (origin.isBefore(first)) origin = first;
    }
    final index = (anchor.difference(origin).inMinutes / _kBarStep.inMinutes)
        .round()
        .clamp(0, _kBarCount - 1);
    return (origin, index);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;

    final (origin, nowIndex) = _window();
    final samples = MriTimeline.sample(
      points,
      start: origin,
      step: _kBarVertexStep,
      count: _kBarVertexCount,
    );
    // 軸ラベル: 表示範囲の最小・最大を 10 刻みに丸める (最低でも 20 の幅を確保)。
    final scale = MriBarScale.forSamples(samples);

    // 軸ラベルは JA でも Plex Mono (Figma JP の実測。chart_axes.dart 参照)。
    final monoSmall = axisLabelStyle(context, color: tokens.textMono);

    // 軸ラベル 2 行が入らない文字スケールではバー列を高くする。
    final axisMin = MriValueAxis.minChartHeight(context, monoSmall);
    final barHeight = axisMin > _kBarHeight ? axisMin : _kBarHeight;

    // 天気レール (グリフ + 気温。2026-09-29 ユーザー指示でホームと同じものを追加)。
    // 点は時刻ラベルのあるスロットだけ (現在を基準に 3 本おき)。
    final railStyle = weatherRailTextStyle(context);
    final railPoints = weatherRailPoints(points, {
      for (var i = 0; i < _kBarCount; i++)
        if ((i - nowIndex) % _kLabelEvery == 0) i: origin.add(_kBarStep * i),
    });

    // 時刻ラベル。衝突すると現在を起点に間引かれるので、天気レールも同じ間引きに
    // 従わせる (ホームと同じ)。レールの項目幅も渡し、項目どうしが接するときは
    // 置き方を変えるか 1 段多く間引く (QA-10)。
    final timeLabels = TimeAxisLabels(
      labels: [
        for (var i = 0; i < _kBarCount; i++)
          // 現在を基準に 3 本おき。現在に必ずラベルが乗る。
          (i - nowIndex) % _kLabelEvery == 0
              ? formatAxisHour(
                  context,
                  axisLocalTime(
                    origin.add(_kBarStep * i),
                    labelOffsetSeconds,
                  ),
                )
              : null,
      ],
      gap: _kBarGap,
      style: monoSmall,
      anchorIndex: nowIndex,
      anchorStyle: axisLabelStyle(
        context,
        color: tokens.textMid,
        weight: FontWeight.w600,
      ),
      companion: weatherRailCompanion(
        context,
        railPoints,
        span: _kLabelEvery,
        unit: unit,
        style: railStyle,
      ),
    );

    return QuietCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(17, 13, 17, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.detailMriTrend.toUpperCase(), style: labelStyle),
              ),
              if (now != null)
                Text(
                  '${t.detailNow.toUpperCase()} ${now!.mri.value}',
                  style: text.labelMedium?.copyWith(
                    fontSize: type.status.fontSize(10),
                    letterSpacing: type.status.letterSpacing(0.7),
                    color: tokens.textMono,
                    height: type.status.height(12 / 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MriLineChart(
                        values: samples,
                        nowIndex: nowIndex * 2,
                        slotCount: _kBarCount,
                        verticesPerSlot: _kBarVerticesPerSlot,
                        scale: scale,
                        height: barHeight,
                        gap: _kBarGap,
                        bandMin: kComfortBandMin,
                        bandMax: kComfortBandMax,
                      ),
                      const SizedBox(height: 6),
                      timeLabels,
                      const SizedBox(height: 3),
                      BarSlotRow(
                        gap: _kBarGap,
                        height: weatherRailHeight(context),
                        span: _kLabelEvery,
                        follow: timeLabels,
                        children: weatherRailItems(
                          railPoints,
                          slotCount: _kBarCount,
                          unit: unit,
                          style: railStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: MriValueAxis.widthFor(context),
                height: barHeight,
                child: MriValueAxis(
                  scale: scale,
                  style: axisLabelStyle(
                    context,
                    color: tokens.textLo.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
          // パーソナル補正適用済みの小ラベル (mri-spec.md §6.4)。
          if (now != null && now!.mri.isPersonalized)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: tokens.textLo),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.calibrationAppliedNote,
                      style: text.bodySmall?.copyWith(
                        fontSize: type.meta.fontSize(11),
                        height: type.meta.height(null, paragraph: true),
                        color: tokens.textLo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 6 タイル (気温・湿度・UV・空気質・風・気圧)。同じ行の 2 枚は高さを揃える
/// (Figma 3:313〜3:350。花粉は 2026-09-30 に風へ差し替え)。
class _FactorTiles extends ConsumerWidget {
  const _FactorTiles({required this.snapshot});
  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = MetricTiles(
      AppLocalizations.of(context),
      height: 84,
      labelMaxLines: MrwType.of(context).layout.detailTileLabelMaxLines,
    );
    final rows = [
      (
        tiles.temperature(
          snapshot.temperature,
          ref.watch(temperatureUnitProvider),
        ),
        tiles.humidity(snapshot.humidity),
      ),
      (tiles.uv(snapshot.uvIndex), tiles.air(snapshot.aqi)),
      (
        tiles.wind(snapshot.windSpeed, ref.watch(windSpeedUnitProvider)),
        tiles.pressure(snapshot.pressure),
      ),
    ];

    return Column(
      children: [
        for (final (i, (left, right)) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: _kGridGutter),
          QuietMetricTileRow(gap: _kGridGutter, left: left, right: right),
        ],
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return QuietCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: MrwType.of(context).caption.fontSize(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
