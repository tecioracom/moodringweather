// lib/presentation/shared/data_attribution_line.dart
//
// 気象データの帰属表示 (Open-Meteo の CC BY 4.0。docs/open-meteo-commercial-terms.md §3:
// 「データを表示する場所の近くに open-meteo.com へのリンクを置く」)。
// ホーム・詳細の天気データの下に置く 1 行。mono 10 / textMono、タップで外部ブラウザ。
// 型スケールは tag (出典行)。
// ライセンス名・加工の旨・GeoNames の帰属は About (aboutDataCredit) にまとめる。

import 'package:flutter/material.dart';

import '../../core/constants/data_attribution.dart';
import '../../core/utils/external_url.dart';
import '../../l10n/app_localizations.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

class WeatherDataAttribution extends StatelessWidget {
  const WeatherDataAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => openExternalUrl(PlaceSearchAttribution.searchProviderUrl),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t.weatherDataAttribution,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: tag.fontSize(10),
                    letterSpacing: tag.letterSpacing(0.4),
                    fontWeight: FontWeight.w400,
                    height: tag.height(13 / 10),
                    color: tokens.textMono,
                    decoration: TextDecoration.underline,
                    decorationColor: tokens.textMono.withValues(alpha: 0.5),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
