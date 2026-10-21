// lib/presentation/home/home_page.dart
//
// ホーム (spec.md §4.1 / Figma v1.3 Home — Comfortable Aurora 3:2・Light 24:6・
// Hot Coral 3:121 実測、地点タブ = 案E' 段階 2 `506:*` 実測)。
// 実データ配線: 表示中の地点 (現在地 or 保存地点) → display_weather_provider.dart。
//
// 構成 (上から。座標は Figma 390×844):
//   [保存地点を表示中] 現在地の緊急アラートのバナー (G4。閉じるボタン無し)
//   [鮮度切れ]        直近データを表示中の注記
//   ヘッダ  pin / bookmark + 地名 (Fraunces 18) + 「保存地点」タグ ・ 設定アイコン
//   地点タブ 「現在地 | 那覇 | 京都 … | +」(下線タブ。タップのみ。place_tab_bar.dart)
//   気温    64px SemiBold | 右: FEELS (mono 11) + 天気グリフ 20 + 概況 (Inter 15)
//           FEELS・概況は省略記号を使わず 2 行まで折り返す (FEELS は値の直前だけで
//           折る)。気温が右列と並ばない文字倍率 (2.0 の「°」落ち) では右列を下に回す
//   ラベル  MOOD RING INDEX (mono 11)
//   リング  176 (MoodRingWidget。弧 = 帯色、数値 + バンド名)
//   [保存地点を表示中] 現在地行「📍 現在地 ● 74 ›」(G4。タップで現在地へ)
//   Sparkline Card (3:73)  HOURLY MRI + 傾向語 / 折れ線 (毎時 13 点 = 過去 3h + 現在 +
//                          未来 9h) / 快適帯の参照バンド / 自動スケールの軸 /
//                          時刻ラベル (保存地点は現地時刻) / 天気レール (時刻ラベルと
//                          同じ間引きに従う)
//   タイル 2×2 (3:91〜3:110)  湿度 / 風 / UV / 空気質。値の直後に単位 (湿度 %、風は
//                          風速の単位の設定) / 段階語 (UV・空気質)。組み方は
//                          shared/metric_tiles.dart・quiet_metric_tile.dart
//   帰属表示「Weather data by Open-Meteo.com」(CC BY 4.0。リンク)
//
// 取得中 (E6a) / 取得失敗 (E6b) でもヘッダ・タブ・現在地行は消えない。数値は「—」、
// 体感は「体感 —」、リングは track だけ。失敗時は「再試行」(保存地点は「現在地に戻る」も)。
// 他の地点のデータで代用しない。
//
// Figma にあって実装しない (保留、docs/v1.3-design-implementation-plan.md §5.4):
//   「+2 VS YESTERDAY」(前日値のデータなし)、インサイト行 (生成ロジックなし)、
//   レールの天気略号 "CLR" (略号の語彙が ARB に無い → グリフ + 気温のみ)。
//
// 文字サイズは型スケール (theme/mrw_type.dart) の役割トークン経由。気温 64・リングの
// 数値 / 帯名・タイル値・地名は display (固定)。FEELS 列幅・リング上下の間隔は
// MrwType.layout (案1 / 案2 で変わる。現状は従来どおり)。
// 厳守: 状態色は弧・帯ドット・MRI 数値にのみ (§4.1)。天気グリフは Heat 以外ニュートラル (§4.4)。
// 文言はすべて AppLocalizations 経由 (ハードコード禁止)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/temperature_unit.dart';
import '../../core/utils/wind_speed_unit.dart';
import '../../data/models/saved_place.dart';
import '../../data/models/weather_snapshot.dart';
import '../../domain/mri/mri_band.dart';
import '../../domain/mri/mri_calculator.dart';
import '../../domain/mri/mri_timeline.dart';
import '../../domain/mri/mri_trend.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/clock_provider.dart';
import '../../providers/current_alert_provider.dart';
import '../../providers/display_weather_provider.dart';
import '../../providers/place_selection_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shell_provider.dart';
import '../places/current_location_cues.dart';
import '../places/place_actions.dart';
import '../places/place_header.dart';
import '../places/place_tab_bar.dart';
import '../settings/locations_page.dart';
import '../shared/app_background.dart';
import '../shared/band_label.dart';
import '../shared/chart_axes.dart';
import '../shared/data_attribution_line.dart';
import '../shared/glass_card.dart';
import '../shared/metric_tiles.dart';
import '../shared/mood_ring_widget.dart';
import '../shared/mri_bar_scale.dart';
import '../shared/mri_line_chart.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_glyphs.dart';
import '../shared/quiet_metric_tile.dart';
import '../shared/quiet_progress.dart';
import '../shared/weather_rail.dart';
import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// コンテンツ枠の左右マージン (Figma 3:2: 19/20px)。
const double _kEdgePadding = 20;

/// タイルの間隔 (Figma: 169 + 12 + 169 = 350)。
const double _kGridGutter = 12;

/// Sparkline の刻みと本数 (docs/home-sparkline-decisions.md ③)。
/// 9 本 × 1.5 時間 = 12 時間 = 過去 3 時間 + 現在 + 未来 9 時間。
/// 現在は左端ではなく index 2 — Figma の「現在 = 中央寄り」設計 (3:73 の 4 本目が
/// α0.72) と整合し、直前の推移も見える。ラベルとレールは 2 本おき (= 3 時間)。
const int _kSparkCount = 9;
const Duration _kSparkStep = Duration(minutes: 90);
const int _kSparkNowIndex = 2;
const int _kSparkLabelEvery = 2;
const double _kSparkGap = 8;
const double _kSparkBarHeight = 36;

/// 折れ線の頂点は毎時 (docs/home-sparkline-line-consult.md)。9 スロット × 1.5h の窓に
/// 13 点、現在はスロット 2 = 頂点 3。1.5h 標本だと奇数時のピークが鈍るので毎時にする。
const Duration _kSparkVertexStep = Duration(hours: 1);
const int _kSparkVertexCount = 13;
const int _kSparkNowVertex = 3;
const double _kSparkVerticesPerSlot = 1.5;

Widget _edge(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kEdgePadding),
      child: child,
    );

TextStyle? _monoLabelStyle(BuildContext context) {
  final tokens = MrwTokens.of(context);
  final label = MrwType.of(context).label;
  return Theme.of(context).textTheme.labelMedium?.copyWith(
        fontSize: label.fontSize(11),
        letterSpacing: label.letterSpacing(0.88),
        color: tokens.textLo,
        height: label.height(14 / 11),
      );
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 地点タブ列 (ボトムシートの上端をこの下に合わせる)。
  final GlobalKey _tabsKey = GlobalKey();

  double? _sheetTop() {
    final box = _tabsKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset(0, box.size.height)).dy;
  }

  void _openLocations() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LocationsPage()),
    );
  }

  Future<void> _onAddPressed() => openAddPlace(
        context,
        ref,
        origin: AddPlaceOrigin.home,
        sheetTop: _sheetTop(),
        onManage: _openLocations,
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final place = ref.watch(displayedSavedPlaceProvider);
    final weather = ref.watch(displayWeatherSnapshotProvider);
    final snapshot = weather.valueOrNull;
    final now = ref.watch(clockProvider)();
    final isStale = snapshot != null &&
        now.difference(snapshot.timestamp) > const Duration(hours: 2);

    final Widget body;
    if (snapshot != null) {
      body = _WeatherBody(snapshot: snapshot, place: place);
    } else if (weather.hasError) {
      body = _PlaceholderBody(place: place, error: weather.error);
    } else {
      body = _PlaceholderBody(place: place);
    }

    return AppBackground(
      // タブ本体は Scaffold を持たない。行の InkWell 用に透明な Material を敷く。
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => refreshDisplayedWeather(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                12,
                0,
                // 内容はナビの上で終える (Figma: タイル下端 735 / ナビ上端 755 = 20)。
                MediaQuery.of(context).padding.bottom + 20,
              ),
              children: [
                // 保存地点を表示中でも、現在地の緊急アラートは最上段に (G4)。
                if (place != null) const _CurrentAlertSlot(),
                if (isStale)
                  _edge(
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StaleBanner(message: t.errorWeatherFetch),
                    ),
                  ),

                // === ヘッダ: pin / bookmark + 地名 (+ 保存地点タグ) / 設定 ===
                _edge(
                  PlaceHeaderRow(
                    trailing: IconButton(
                      onPressed: () =>
                          ref.read(mainShellTabProvider.notifier).state = 2,
                      tooltip: t.tabSettings,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      icon: const QuietIconMark(QuietIcon.settings, size: 22),
                    ),
                  ),
                ),

                // === 地点タブ ===
                PlaceTabBar(key: _tabsKey, onAddPressed: _onAddPressed),

                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 現在地の緊急アラートのバナー (アラートが無ければ余白も置かない)。
class _CurrentAlertSlot extends ConsumerWidget {
  const _CurrentAlertSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentTopEmergencyAlertProvider) == null) {
      return const SizedBox.shrink();
    }
    return _edge(
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: CurrentAlertBanner(),
      ),
    );
  }
}

class _WeatherBody extends ConsumerWidget {
  const _WeatherBody({required this.snapshot, required this.place});
  final WeatherSnapshot snapshot;

  /// 表示中の保存地点 (null = 現在地)。
  final SavedPlace? place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(personalProfileProvider);
    final mri = ref.watch(displayMriProvider).valueOrNull ??
        MriCalculator.calculate(snapshot, profile: profile);
    final unit = ref.watch(temperatureUnitProvider);
    final windUnit = ref.watch(windSpeedUnitProvider);
    final tiles = MetricTiles(t);
    final now = ref.watch(clockProvider)();
    final points = ref.watch(displayMriTimelineProvider).valueOrNull ??
        const <MriTimelinePoint>[];
    final heat = mri.band == MriBand.hotAlert;
    final labelStyle = _monoLabelStyle(context);

    final feels = snapshot.apparentTemperature == null
        ? null
        : '${unit.fromCelsius(snapshot.apparentTemperature!).round()}';
    final conditionStyle = text.bodyLarge?.copyWith(
      fontSize: type.section.fontSize(15),
      height: type.section.height(20 / 15),
      color: tokens.textMid,
    );

    return _edge(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === 気温 64px | FEELS + 天気グリフ + 概況 ===
          _TemperatureRow(
            temperature: unit.formatDegrees(snapshot.temperature),
            style: MrwFonts.numeral(
              context,
              size: 64,
              weight: FontWeight.w600,
              height: 70 / 64,
              color: tokens.textHi,
            ),
            side: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feels != null)
                  Text(
                    feelsLine(t.feelsLike(feels).toUpperCase(), feels),
                    // 省略記号は使わない (値の直前で 2 行目へ)。
                    maxLines: 2,
                    style: _feelsStyle(context),
                  ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      // グリフは 1 行目の中央 (2 行に折れても 1 行目に揃える)。
                      padding: EdgeInsets.only(
                        top: _glyphTopInLine(context, conditionStyle, 20),
                      ),
                      child: QuietGlyphIcon(
                        glyphForCondition(snapshot.condition, heat: heat),
                        size: 20,
                        opacity: 0.86,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _conditionLabel(t, snapshot.condition),
                        // 省略記号は使わず 2 行まで (es の長い概況)。
                        maxLines: 2,
                        style: conditionStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // === MOOD RING INDEX + リング ===
          Text(t.mriFullName.toUpperCase(), style: labelStyle),
          SizedBox(height: type.layout.homeLabelToRingGap),
          Center(
            child: MoodRingWidget(
              mri: mri,
              size: 176,
              label: mriBandLabel(
                t,
                mri,
                optimalMri: profile.estimatedOptimalMri,
                apparentTemperature:
                    snapshot.apparentTemperature ?? snapshot.temperature,
              ),
            ),
          ),
          ..._afterRing(place, type.layout.homeRingBottomGap),

          // === Sparkline Card ===
          _SparklineCard(
            points: points,
            nowMri: mri.value,
            now: now,
            unit: unit,
            labelStyle: labelStyle,
            // 保存地点の時刻は現地時刻で見せる (現在地は端末の時刻のまま)。
            labelOffsetSeconds:
                place == null ? null : snapshot.utcOffsetSeconds,
          ),
          const SizedBox(height: _kGridGutter),

          // === 2×2 タイル: 湿度 / 風 / UV / 空気質 (同じ行の 2 枚は高さを揃える) ===
          QuietMetricTileRow(
            gap: _kGridGutter,
            left: tiles.humidity(snapshot.humidity),
            right: tiles.wind(snapshot.windSpeed, windUnit),
          ),
          const SizedBox(height: _kGridGutter),
          QuietMetricTileRow(
            gap: _kGridGutter,
            left: tiles.uv(snapshot.uvIndex),
            right: tiles.air(snapshot.aqi),
          ),
          const SizedBox(height: 8),
          const WeatherDataAttribution(),
        ],
      ),
    );
  }

  /// WeatherSnapshot.condition ('sunny' 等) → l10n 済み概況ラベル。
  static String _conditionLabel(AppLocalizations t, String condition) {
    switch (condition) {
      case 'sunny':
        return t.conditionSunny;
      case 'cloudy':
        return t.conditionCloudy;
      case 'foggy':
        return t.conditionFoggy;
      case 'rainy':
        return t.conditionRainy;
      case 'snowy':
        return t.conditionSnowy;
      case 'stormy':
        return t.conditionStormy;
      default:
        return t.conditionUnknown;
    }
  }
}

/// FEELS 行の文言。折り返しは値の直前だけにする: ラベルの語間の空白を NBSP (U+00A0)
/// にし、値の前の空白だけを通常の空白で残す。[line] は大文字化済みの 1 行、[value] は
/// そこへ差し込んだ値 (「24」「—」)。値がラベルの後ろに無い並びはそのまま返す。
String feelsLine(String line, String value) {
  final at = line.lastIndexOf(value);
  if (at <= 0) return line;
  final head = line.substring(0, at);
  final label = head.trimRight();
  return '${label.replaceAll(' ', '\u00A0')}${head.substring(label.length)}'
      '${line.substring(at)}';
}

/// [style] の 1 行の中央に高さ [box] の要素を置くときの上端 (文字倍率込み)。
double _glyphTopInLine(BuildContext context, TextStyle? style, double box) {
  final size = style?.fontSize ?? 15;
  final line =
      MediaQuery.textScalerOf(context).scale(size) * (style?.height ?? 20 / 15);
  return ((line - box) / 2).clamp(0.0, double.infinity);
}

/// 気温 (64) | 右列 (FEELS + 概況)。右列は Figma どおり気温の右 (幅は型スケールの
/// FEELS 列、上 14)。気温の実幅 + 16 + 右列の幅が枠を超える (文字倍率 2.0 で「°」が
/// 落ちる) ときだけ、右列を気温の下へ回す。
///
/// 実幅は字面で測る: JA の数字書体 (Plex Sans JP) は「°」が全角 (1em) で、字面の右に
/// 0.5em ほどの空きがある。送り幅のままだと ×1.3 で 188 > 184 となり、並べて収まる
/// 表示まで下へ回ってしまうので、「°」は欧文 (Inter) の「°」の幅で数える
/// (JA ×1.0 の「22°」: 送り 144.6 / 字面 約 111 / この計算 109.9)。
class _TemperatureRow extends StatelessWidget {
  const _TemperatureRow({
    required this.temperature,
    required this.style,
    required this.side,
  });

  final String temperature;
  final TextStyle style;

  /// FEELS + 概況の列 (上の余白は含めない)。
  final Widget side;

  /// 気温と右列の間に最低これだけ空ける。
  static const double _minGap = 16;

  /// 右列を下へ回したときの気温との間。
  static const double _stackedGap = 4;

  @override
  Widget build(BuildContext context) {
    final sideWidth = MrwType.of(context).layout.feelsColumnWidth;
    // 1 行で組み、枠からはみ出す分も描く。JA の全角「°」は右半分が空きなので、
    // 枠 (360dp で 170) に送り幅が収まらないと「°」だけが見えない 2 行目へ
    // 折れて消えていた (Sev2)。字面が収まるかは下の判定 (_visibleWidth) で見る。
    final value = Text(
      temperature,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: style,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _visibleWidth(context);
        if (width + _minGap + sideWidth <= constraints.maxWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: value),
              SizedBox(
                width: sideWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: side,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [value, const SizedBox(height: _stackedGap), side],
        );
      },
    );
  }

  /// 気温の字面の幅 (文字倍率込み)。「°」は欧文の「°」の幅で数える (上の注記)。
  double _visibleWidth(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle s) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final advance = measure(temperature, style);
    if (!temperature.contains('°') || style.fontFamily == MrwFonts.inter) {
      return advance;
    }
    final latin = style.copyWith(
      fontFamily: MrwFonts.inter,
      fontFamilyFallback: const [],
      fontVariations: MrwFonts.interVariations(
        style.fontWeight ?? FontWeight.w600,
      ),
    );
    final count = '°'.allMatches(temperature).length;
    return advance - count * (measure('°', style) - measure('°', latin));
  }
}

/// FEELS (型スケールは label。現状の字間 0.55・Regular のまま、案1 / 案2 は label の字間)。
TextStyle? _feelsStyle(BuildContext context) {
  final label = MrwType.of(context).label;
  return Theme.of(context).textTheme.labelMedium?.copyWith(
        fontSize: label.fontSize(11),
        letterSpacing: label.letterSpacing(0.55),
        fontWeight: FontWeight.w400,
        color: MrwTokens.of(context).textMono,
        height: label.height(14 / 11),
      );
}

/// リング直下: 保存地点を表示中は現在地行 (G4)、現在地なら余白 [ringBottomGap]
/// (現状 28。型スケール案2 は 20)。
List<Widget> _afterRing(SavedPlace? place, double ringBottomGap) =>
    place == null
        ? [SizedBox(height: ringBottomGap)]
        : const [
            SizedBox(height: 8),
            CurrentLocationRow(),
            SizedBox(height: 8),
          ];

/// 取得中 (Figma E6a) / 取得失敗 (E6b) の本体。値はすべて「—」(textLo)、
/// リングは track だけ。[error] が非 null なら失敗 (再試行 + 保存地点は「現在地に戻る」)。
class _PlaceholderBody extends ConsumerWidget {
  const _PlaceholderBody({required this.place, this.error});

  final SavedPlace? place;
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final labelStyle = _monoLabelStyle(context);
    final failed = error != null;
    if (failed) {
      final e = error;
      debugPrint(e is AppException ? e.developerMessage : '$e');
    }
    final name = place?.name;
    // 値は無い (null) ので「—」(textLo)。単位・段階語は出さない。
    final tiles = MetricTiles(t);

    return _edge(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === 気温「—」| 体感 — / 概況 — ===
          _TemperatureRow(
            temperature: '—',
            style: MrwFonts.numeral(
              context,
              size: 64,
              weight: FontWeight.w600,
              height: 70 / 64,
              color: tokens.textLo,
            ),
            side: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feelsLine(t.feelsLikeUnknown.toUpperCase(), '—'),
                  maxLines: 2,
                  style: _feelsStyle(context),
                ),
                const SizedBox(height: 4),
                Text(
                  '—',
                  style: text.bodyLarge?.copyWith(
                    fontSize: type.section.fontSize(15),
                    height: type.section.height(20 / 15),
                    color: tokens.textLo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(t.mriFullName.toUpperCase(), style: labelStyle),
          SizedBox(height: type.layout.homeLabelToRingGap),
          const Center(child: MoodRingPlaceholder(size: 176)),
          ..._afterRing(place, type.layout.homeRingBottomGap),

          if (!failed)
            // === 取得中: 時間別MRI の枠に「○○の天気を取得しています…」+ 進捗 ===
            QuietCard(
              borderRadius: 20,
              padding: const EdgeInsets.fromLTRB(17, 13, 17, 33),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.homeHourlyMri, style: labelStyle),
                  const SizedBox(height: 29),
                  Text(
                    name == null ? t.loadingWeather : t.placeLoading(name),
                    style: text.bodySmall?.copyWith(
                      fontSize: type.meta.fontSize(11),
                      height: type.meta.height(14 / 11),
                      color: tokens.textMono,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const QuietIndeterminateTrack(),
                ],
              ),
            )
          else ...[
            // === 取得失敗: 本文カード + 再試行 (+ 現在地に戻る) ===
            QuietCard(
              borderRadius: 20,
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
              child: Text(
                name == null
                    ? t.errorWeatherLoadFailed
                    : t.placeLoadFailed(name),
                style: text.bodyMedium?.copyWith(
                  fontSize: type.caption.fontSize(12),
                  height: type.caption.height(17 / 12, paragraph: true),
                  color: tokens.textMid,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (name == null)
              QuietSecondaryButton(
                label: t.retry,
                onPressed: () => refreshDisplayedWeather(ref),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: QuietSecondaryButton(
                      label: t.retry,
                      onPressed: () => refreshDisplayedWeather(ref),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: QuietTertiaryButton(
                      label: t.placeBackToCurrent,
                      onPressed: () => ref
                          .read(selectedPlaceIdProvider.notifier)
                          .showCurrentLocation(),
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: _kGridGutter),

          // === タイル: 値は「—」(textLo)、単位・段階語は出さない ===
          QuietMetricTileRow(
            gap: _kGridGutter,
            left: tiles.humidity(null),
            right: tiles.wind(null, WindSpeedUnit.metersPerSecond),
          ),
          const SizedBox(height: _kGridGutter),
          QuietMetricTileRow(
            gap: _kGridGutter,
            left: tiles.uv(null),
            right: tiles.air(null),
          ),
        ],
      ),
    );
  }
}

/// Sparkline Card (Figma 3:73): HOURLY MRI + 傾向語 / capsule bar 9 本 / 軸 /
/// 時刻 / 天気レール。縦は MriBarScale の自動スケール (固定 0–100 では MRI 1 点が
/// 0.24px しか動かず、傾向語と見た目が食い違う)。
class _SparklineCard extends StatelessWidget {
  const _SparklineCard({
    required this.points,
    required this.nowMri,
    required this.now,
    required this.unit,
    required this.labelStyle,
    this.labelOffsetSeconds,
  });

  final List<MriTimelinePoint> points;
  final int nowMri;
  final DateTime now;
  final TemperatureUnit unit;
  final TextStyle? labelStyle;

  /// 時刻ラベルを出す地点の UTC オフセット秒 (保存地点)。null は端末の時刻。
  final int? labelOffsetSeconds;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;

    // 「今」に最も近いデータ点をハイライト位置に据え、そこから 2 本 (= 3 時間)
    // 戻したところを起点にする。時刻ラベルはデータ点に揃う。
    final anchor = MriTimeline.nearest(points, now)?.timestamp ?? now;
    final origin = anchor.subtract(_kSparkStep * _kSparkNowIndex);
    final samples = MriTimeline.sample(
      points,
      start: origin,
      step: _kSparkVertexStep,
      count: _kSparkVertexCount,
    );
    // 傾向語は「これから」だけで決める。窓に過去が入ったので、現在より後ろだけを
    // 渡す (過去の値を混ぜると傾向が事実と逆になる)。毎時の点で判定するので
    // 1.5h 標本では取りこぼした短い谷も拾う。
    final future = [
      for (final v in samples.skip(_kSparkNowVertex + 1))
        if (v != null) v.round(),
    ];
    final scale = MriBarScale.forSamples(samples);
    final trend = MriTrendClassifier.classify(now: nowMri, future: future);
    final trendLabel = switch (trend) {
      MriTrend.stable => t.trendStable,
      MriTrend.riskRises => t.trendRiskRises,
      MriTrend.easing => t.trendEasing,
    };
    // 軸ラベルは JA でも Plex Mono (Figma JP の実測。chart_axes.dart 参照)。
    final hourStyle = axisLabelStyle(context, color: tokens.textMono);
    // 天気レール (グリフ + 気温。天気名の文字は出さない)。詳細と共用。
    final railStyle = weatherRailTextStyle(context);

    // 現在のラベルだけウェイトを上げる。現在が左端でなくなったので、
    // バーの α 差 (0.42 / 0.72) だけに頼らず「どれが今か」を示す。
    final nowHourStyle = axisLabelStyle(
      context,
      color: tokens.textMid,
      weight: FontWeight.w600,
    );
    final axisStyle = axisLabelStyle(
      context,
      color: tokens.textLo.withValues(alpha: 0.72),
    );
    final railHeight = weatherRailHeight(context);
    // 天気レールの点 (時刻ラベルのあるスロットだけ。現在を基準に 2 本おき)。
    final railPoints = weatherRailPoints(points, {
      for (var i = 0; i < _kSparkCount; i++)
        if ((i - _kSparkNowIndex) % _kSparkLabelEvery == 0)
          i: origin.add(_kSparkStep * i),
    });
    // 軸ラベル 2 行が入らない文字スケールではバー列を高くする。
    final axisMin = MriValueAxis.minChartHeight(context, hourStyle);
    final barHeight = axisMin > _kSparkBarHeight ? axisMin : _kSparkBarHeight;
    // 時刻ラベル。衝突すると現在を起点に間引かれるので、天気レールも同じ間引きに
    // 従わせる (ラベルが 2 本に減ってもレールが 5 個残り、右端が詰まるのを防ぐ)。
    // レールの項目幅も渡し、項目どうしが接するときは置き方を変えるか 1 段多く
    // 間引く (QA-10)。
    final timeLabels = TimeAxisLabels(
      labels: [
        for (var i = 0; i < _kSparkCount; i++)
          // 現在を基準に 2 本おき。現在に必ずラベルが乗る。
          (i - _kSparkNowIndex) % _kSparkLabelEvery == 0
              ? formatAxisHour(
                  context,
                  axisLocalTime(
                    origin.add(_kSparkStep * i),
                    labelOffsetSeconds,
                  ),
                )
              : null,
      ],
      gap: _kSparkGap,
      style: hourStyle,
      anchorIndex: _kSparkNowIndex,
      anchorStyle: nowHourStyle,
      companion: weatherRailCompanion(
        context,
        railPoints,
        span: _kSparkLabelEvery,
        unit: unit,
        style: railStyle,
      ),
    );

    return QuietCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(17, 13, 17, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.homeHourlyMri, style: labelStyle)),
              Text(
                trendLabel,
                style: text.labelMedium?.copyWith(
                  fontSize: type.status.fontSize(10),
                  letterSpacing: type.status.letterSpacing(0.7),
                  color: tokens.textMono,
                  height: type.status.height(12 / 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                        nowIndex: _kSparkNowVertex,
                        slotCount: _kSparkCount,
                        verticesPerSlot: _kSparkVerticesPerSlot,
                        scale: scale,
                        height: barHeight,
                        gap: _kSparkGap,
                        // 快適帯 (60–79) の参照バンド。無彩色なので §4.1 の
                        // 状態色の算定には入らない (決定 ④「代替A」)。
                        bandMin: kComfortBandMin,
                        bandMax: kComfortBandMax,
                      ),
                      const SizedBox(height: 5),
                      timeLabels,
                      const SizedBox(height: 3),
                      BarSlotRow(
                        gap: _kSparkGap,
                        height: railHeight,
                        span: _kSparkLabelEvery,
                        follow: timeLabels,
                        children: weatherRailItems(
                          railPoints,
                          slotCount: _kSparkCount,
                          unit: unit,
                          style: railStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 自動スケールの上限 / 下限。拡大率を示すため必ず一緒に出す。
              SizedBox(
                width: MriValueAxis.widthFor(context),
                height: barHeight,
                child: MriValueAxis(scale: scale, style: axisStyle),
              ),
            ],
          ),
        ],
      ),
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
