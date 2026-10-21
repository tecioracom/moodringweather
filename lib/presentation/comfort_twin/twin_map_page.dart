// lib/presentation/comfort_twin/twin_map_page.dart
//
// Comfort-Twin 結果 / マップ画面 (Figma v1.3 `Twin — Map` 5:167・Light 24:981・
// JP 77:928 実測)。
//
// 構成 (Figma):
//   見出し  「最も近い一致」+ リード文
//   マップ  パネル (角丸 22) に格子とドット。**線もドットもニュートラル**
//   行      都市名 + 「nn% · MRI nn」(mono 10・**帯色**。語は付けず、読み上げは
//           「nn% 一致 · MRI nn」) + chevron
//
// **状態色 (§4.2 C3 / §4.1)**: 各行の「一致率 · MRI nn」だけが帯色
// (規則 1 の ③ MRI 数値)。見出し・リード文・chevron・地図の線とドットは
// すべてニュートラル。件数が上限 6 を超えるときは数値を主文字色に戻し、
// 行頭の帯ドットだけに縮小する (規則 2)。
//
// 候補都市の気象は twinCandidatesProvider (テストでは override) 経由。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/temperature_unit.dart';
import '../../domain/comfort_twin/twin_matcher.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/comfort_twin_provider.dart';
import '../../providers/settings_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'twin_compare_page.dart';
import 'twin_world_map.dart';

/// 結果リストの行間 (Figma: 471 → 529 = 58 − 52)。
const double _kRowGap = 10;

/// §4.1 規則 2 の上限。これを超えたら数値の着色をやめ、帯ドットだけにする。
const int _kMaxStateColoredRows = 6;

class TwinMapPage extends ConsumerWidget {
  const TwinMapPage({super.key, required this.targetMri});

  /// 検索画面で選んだ体感ターゲット (MRI 0–100)。
  final int targetMri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final candidates = ref.watch(twinCandidatesProvider);

    return candidates.when(
      loading: () => QuietPage(
        title: t.twinTitle,
        headline: t.twinMapTitle,
        intro: t.twinLoadingCities,
        children: const [Center(child: CircularProgressIndicator())],
      ),
      error: (error, _) => _ErrorPage(error: error),
      data: (list) {
        final matches = TwinMatcher.rank(targetMri, list);
        final useDots = matches.length > _kMaxStateColoredRows;
        return QuietPage(
          title: t.twinTitle,
          headline: t.twinResultsFor(targetMri),
          children: [
            QuietPanel(
              padding: const EdgeInsets.all(12),
              child: TwinWorldMap(matches: matches),
            ),
            const SizedBox(height: 26),
            for (var i = 0; i < matches.length; i++) ...[
              if (i > 0) const SizedBox(height: _kRowGap),
              _MatchRow(match: matches[i], useDot: useDots),
            ],
          ],
        );
      },
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
      title: t.twinTitle,
      headline: t.twinMapTitle,
      intro: t.errorWeatherLoadFailed,
      children: [
        QuietPrimaryButton(
          label: t.retry,
          onPressed: () => ref.invalidate(twinCandidatesProvider),
        ),
      ],
    );
  }
}

/// 類似都市の 1 行 (Figma 5:180)。MRI 値だけが帯色。
class _MatchRow extends ConsumerWidget {
  const _MatchRow({required this.match, required this.useDot});

  final TwinMatch match;

  /// true なら数値を無彩色にし、行頭に帯ドットを出す (§4.1 規則 2)。
  final bool useDot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final unit = ref.watch(temperatureUnitProvider);
    final band = tokens.stateColorForMri(match.mri.value);
    final similarity = match.similarity.round();

    return QuietListRow(
      title: '${match.city.emoji} ${match.city.name}',
      subtitle: '${match.city.country} · '
          '${unit.formatDegrees(match.snapshot.temperature)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: band, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            // 見た目は「nn% · MRI nn」(語なし)。読み上げは語つきの文言にする。
            child: Semantics(
              label: '${t.twinSimilarityA11y(similarity)} · '
                  '${t.mriAbbrev} ${match.mri.value}',
              excludeSemantics: true,
              child: Text(
                // 「MRI」と数値の間は NBSP (数値だけが次の行へ行かないように)。
                // 省略記号は使わず 2 行まで (×1.3 までは 1 行に収まる)。
                '${t.twinSimilarity(similarity)} · '
                '${t.mriAbbrev}\u00A0${match.mri.value}',
                maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: tag.fontSize(10),
                      letterSpacing: 0,
                      fontWeight: FontWeight.w400,
                      height: tag.height(13 / 10),
                      color: useDot ? tokens.textHi : band,
                    ),
              ),
            ),
          ),
        ],
      ),
      chevron: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TwinComparePage(other: match.candidate),
        ),
      ),
    );
  }
}
