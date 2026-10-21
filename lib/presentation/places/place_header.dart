// lib/presentation/places/place_header.dart
//
// ホーム / 詳細の見出し行 (Figma 案E' 段階 2: E4 `506:461`、Detail Place Header
// `507:2` / `507:111` 実測)。
//   現在地   : pin 18 + 地名 (逆ジオコーディング。無ければ「現在地」)
//   保存地点 : bookmark 18 + 保存した表示名 + タグ「保存地点」(地名の右 +8、高さ 18)
// 地名は Fraunces 18 / 行高 24 (JA は Plex Sans JP)。タグは Regular 10 textMid。
// 型スケール: 地名は display (固定)、タグは tag。
// 状態色は使わない (§4.1)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/display_weather_provider.dart';
import '../shared/quiet_glyphs.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 表示中の地点の見出し。[trailing] はホームの設定アイコン (詳細では無し)。
class PlaceHeaderRow extends ConsumerWidget {
  const PlaceHeaderRow({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final text = Theme.of(context).textTheme;
    final place = ref.watch(displayedSavedPlaceProvider);
    final name =
        ref.watch(displayPlaceNameProvider).valueOrNull ?? t.currentLocation;

    return Row(
      children: [
        if (place == null)
          const QuietIconMark(QuietIcon.pin, size: 18)
        else
          const PlaceBookmarkIcon(size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(
                    fontSize: 18, // 型スケール対象外 (display: 地名)
                    height: 24 / 18,
                    color: tokens.textHi,
                  ),
                ),
              ),
              if (place != null) ...[
                const SizedBox(width: 8),
                const SavedPlaceTag(),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 保存地点の印 (Figma 案B4 / 案E' の bookmark: Material の bookmark_border と
/// 同じ形)。色は pin と同じ (Dark 副文字色 / Light #6B7480)。
class PlaceBookmarkIcon extends StatelessWidget {
  const PlaceBookmarkIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Icon(
      Icons.bookmark_border,
      size: size,
      color: isDark ? tokens.textMid : tokens.textMono,
    );
  }
}

/// タグ「保存地点」(Figma: バッジ地 = pearl 16% / Light ink 10%、高さ 18、
/// 文字 Regular 10 textMid)。
class SavedPlaceTag extends StatelessWidget {
  const SavedPlaceTag({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.textHi.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t.placeSavedTag,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: tag.fontSize(10),
              height: tag.height(13 / 10),
              color: tokens.textMid,
            ),
      ),
    );
  }
}
