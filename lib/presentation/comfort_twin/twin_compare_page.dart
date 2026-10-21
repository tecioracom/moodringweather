// lib/presentation/comfort_twin/twin_compare_page.dart
//
// Comfort-Twin 比較画面 (Figma v1.3 `Twin — Compare` 5:213・Light 24:1026・
// JP 77:973 実測)。
//
// 構成 (Figma):
//   リングカード ×2  156×170 角丸 22: リング 100 (弧 + head dot 10) +
//                    数値 Fraunces 44 (**帯色**) + 都市名 mono 10 + 気温 mono 12
//   「差の要因」    2×2 タイル 158×78 角丸 18: mono ラベル (単位つき) +
//                    値 Inter SemiBold 17 + 右上にニュートラルのドット
//   パネル          「一致度」mono + 割合 Fraunces 28
//   主 CTA          この場所を保存 (action/primary)
//
// **状態色 (§4.1)**: 弧 2 + head dot 2 + 数値 2 = **6 個**。上限ちょうど
// (codex-fixes_v1.3_ruling-item9.md の「Compare は各 6」と一致)。
// 差の要因タイルのドットはニュートラル、単位ラベル・値も無彩色。
//
// Figma との差異 (意図的):
//   - 見出しは「Tokyo vs Vancouver」ではなく既存 ARB の twinCompareTitle。
//     「vs」の語順・訳が 4 言語で確定していないため (都市名はリング内に出る)。
//   - 差の要因は Figma の 4 指標 (湿度 / 風 / UV / 気圧) をそのまま採用。
//     欠測時は「—」を出す (勝手に 0 とみなさない)。
//   - 風の見出しと差は風速の単位の設定に従う (「風 (m/s)」「Wind (mph)」。差は
//     m/s は小数 1 桁、km/h・mph は整数。docs/design-metric-units-proposal.md §2.6)。
//     見出しの記号は途中で折らない (WindSpeedUnit.nonBreakingSymbol。QA-20)。
//
// 月別平均の比較は v1.1 以降 (データ追加取得が必要なため本サイクルでは省略)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/temperature_unit.dart';
import '../../core/utils/wind_speed_unit.dart';
import '../../data/models/mood_ring_index.dart';
import '../../data/models/weather_snapshot.dart';
import '../../domain/comfort_twin/twin_matcher.dart';
import '../../domain/mri/mri_calculator.dart';
import '../../domain/places/saved_place_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/entitlement_provider.dart';
import '../../providers/mri_provider.dart';
import '../../providers/saved_places_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/weather_provider.dart';
import '../paywall/paywall_page.dart';
import '../shared/glass_card.dart';
import '../shared/mood_ring_widget.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// タイルの間隔 (Figma: 27 + 158 + 18 + 158 = 361)。
const double _kTileGap = 18;

class TwinComparePage extends ConsumerWidget {
  const TwinComparePage({super.key, required this.other});

  /// 比較対象の都市 (マップ画面で選択)。
  final CityComfort other;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final myWeather = ref.watch(weatherSnapshotProvider);

    return myWeather.when(
      loading: () => QuietPage(
        title: t.twinMapTitle,
        headline: t.twinCompareTitle,
        children: const [Center(child: CircularProgressIndicator())],
      ),
      error: (error, _) => _ErrorPage(error: error),
      data: (mine) => _CompareBody(mine: mine, other: other),
    );
  }
}

class _ErrorPage extends ConsumerWidget {
  const _ErrorPage({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    debugPrint(error is AppException
        ? (error as AppException).developerMessage
        : '$error');
    return QuietPage(
      title: t.twinMapTitle,
      headline: t.twinCompareTitle,
      intro: t.errorWeatherLoadFailed,
      children: [
        QuietPrimaryButton(
          label: t.retry,
          onPressed: () => ref.invalidate(weatherSnapshotProvider),
        ),
      ],
    );
  }
}

class _CompareBody extends ConsumerWidget {
  const _CompareBody({required this.mine, required this.other});

  final WeatherSnapshot mine;
  final CityComfort other;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(personalProfileProvider);
    final myMri = ref.watch(mriProvider).valueOrNull ??
        MriCalculator.calculate(mine, profile: profile);
    final myCity = ref.watch(cityNameProvider).valueOrNull ?? t.twinMyPlace;
    // リング内のラベルと差のタイルは幅が狭いので、絵文字は付けない
    // (絵文字は一覧・地図の行が担う)。
    final otherCity = other.city.name;
    final unit = ref.watch(temperatureUnitProvider);
    final windUnit = ref.watch(windSpeedUnitProvider);
    double? wind(double? metersPerSecond) => metersPerSecond == null
        ? null
        : windUnit.fromMetersPerSecond(metersPerSecond);
    final match = TwinMatcher.similarity(myMri.value, other.mri.value);

    return QuietPage(
      title: t.twinMapTitle,
      headline: t.twinCompareTitle,
      children: [
        // === リングカード ×2 (状態色: 弧 2 + dot 2 + 数値 2 = 6) ===
        _Pair(
          left: _RingCard(
            mri: myMri,
            city: myCity,
            temperature: unit.formatDegrees(mine.temperature),
          ),
          right: _RingCard(
            mri: other.mri,
            city: otherCity,
            temperature: unit.formatDegrees(other.snapshot.temperature),
          ),
        ),
        const SizedBox(height: 26),

        // === 差の要因 (2×2、すべてニュートラル) ===
        QuietSectionTitle(t.twinDiffTitle),
        const SizedBox(height: 10),
        _Pair(
          left: _DiffTile(
            label: '${t.statHumidity} (%)',
            value: _diffLabel(
              t,
              myCity: myCity,
              otherCity: otherCity,
              mine: mine.humidity,
              other: other.snapshot.humidity,
              digits: 0,
            ),
          ),
          right: _DiffTile(
            // 記号の途中 (「km/」「h」) で折らない (QA-20)。折るなら語と「(」の間。
            label: '${t.statWind} (${windUnit.nonBreakingSymbol})',
            value: _diffLabel(
              t,
              myCity: myCity,
              otherCity: otherCity,
              mine: wind(mine.windSpeed),
              other: wind(other.snapshot.windSpeed),
              digits: windUnit.fractionDigits,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Pair(
          left: _DiffTile(
            label: t.statUv,
            value: _diffLabel(
              t,
              myCity: myCity,
              otherCity: otherCity,
              mine: mine.uvIndex,
              other: other.snapshot.uvIndex,
              digits: 0,
            ),
          ),
          right: _DiffTile(
            label: '${t.statPressure} (hPa)',
            value: _diffLabel(
              t,
              myCity: myCity,
              otherCity: otherCity,
              mine: mine.pressure,
              other: other.snapshot.pressure,
              digits: 0,
            ),
          ),
        ),
        const SizedBox(height: 26),

        // === 一致度 ===
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuietLabel(
                t.twinMatchQualityLabel,
                small: true,
                color: MrwTokens.of(context).textMono,
              ),
              const SizedBox(height: 6),
              QuietDisplayNumber('${match.round()}%', size: 28),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === この場所を保存 (オンデバイス) ===
        QuietPrimaryButton(
          label: t.twinSavePlace,
          onPressed: () => _save(context, ref),
        ),
      ],
    );
  }

  /// 「どちらがどれだけ多いか」。Figma 5:240 の「Tokyo +18」形式。
  /// 欠測は「—」、差が表示桁で 0 になるときは twinDiffSame。
  String _diffLabel(
    AppLocalizations t, {
    required String myCity,
    required String otherCity,
    required double? mine,
    required double? other,
    required int digits,
  }) {
    if (mine == null || other == null) return '—';
    final delta = other - mine;
    final shown = delta.abs().toStringAsFixed(digits);
    if (double.parse(shown) == 0) return t.twinDiffSame;
    final winner = delta > 0 ? otherCity : myCity;
    return '$winner +$shown';
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    // 多地点ゲート (spec §12.11.5 / docs/pricing-decision.md) は地名検索の追加と
    // 同じ SavedPlacesController で判定する: 保存地点は Plus 限定 (無料 0 /
    // Plus 5)。無料は needsPlus → Paywall (「上限 N 件」は出さない)。上限は
    // **新規追加**だけを止め (grandfathering)、同一地点の再保存は更新扱いで
    // 常に許可。limitReached (理由のスナックバー) は Plus の 5 件だけ。
    final check = await ref
        .read(savedPlacesControllerProvider)
        .saveCatalogCity(other.city, other.mri.value);
    if (!context.mounted) return;
    switch (check) {
      case SavedPlaceAddCheck.needsPlus:
        await showPaywall(context);
      case SavedPlaceAddCheck.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.locationsLimitReached(ref.read(savedLocationLimitProvider)),
            ),
          ),
        );
      case SavedPlaceAddCheck.allowed:
      case SavedPlaceAddCheck.alreadySaved:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.twinPlaceSaved)),
        );
    }
  }
}

/// 横に 2 枚並べて高さを揃える (Figma の 156×170 / 158×78 の 2 列)。
/// ListView の中では高さが無限なので、stretch だけでは組めず IntrinsicHeight が要る。
class _Pair extends StatelessWidget {
  const _Pair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: _kTileGap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// リングカード (Figma 5:223)。数値は帯色 = MRI 値そのもの (§4.1 規則 1 の ③)。
class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.mri,
    required this.city,
    required this.temperature,
  });

  final MoodRingIndex mri;
  final String city;
  final String temperature;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final caption = MrwType.of(context).caption;
    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: MoodRingWidget(
              mri: mri,
              size: 100,
              // Figma 5:227 / 5:226: 100px のリングに 44px の数値と 10px の dot。
              valueFontSize: 44,
              labelFontSize: 10,
              dotRadius: 5,
              colorValue: true,
              label: city,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            temperature,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: caption.fontSize(12),
                  letterSpacing: 0,
                  height: caption.height(16 / 12),
                  color: tokens.inkMid,
                ),
          ),
        ],
      ),
    );
  }
}

/// 差の要因タイル (Figma 5:238)。ラベル・値・ドットはすべてニュートラル。
class _DiffTile extends StatelessWidget {
  const _DiffTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final text = Theme.of(context).textTheme;
    return QuietCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.labelSmall?.copyWith(
                    fontSize: tag.fontSize(10),
                    letterSpacing: 0,
                    fontWeight: FontWeight.w400,
                    height: tag.height(13 / 10),
                    color: tokens.textMono,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.inkMid,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              fontSize: 17, // 型スケール対象外 (display: タイル値)
              height: 22 / 17,
              color: tokens.textHi,
            ),
          ),
        ],
      ),
    );
  }
}
