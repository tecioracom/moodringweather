// lib/presentation/places/current_location_cues.dart
//
// 保存地点を表示中でも「現在地」を見失わないための 2 つの手がかり
// (保存地点の出荷条件 G4。Figma 案E' 段階 2: E4 `506:461` の現在地行、
// E5 `506:632` の緊急バナー実測)。どちらもタップで現在地の表示に戻る。
//
//   CurrentLocationRow   : リング直下「📍 現在地 ● 74 ›」(pin 14 / Regular 13 textMid /
//                          帯ドット 8 = state/* / 数値 Medium 13 主文字色 / › mono 色)。
//                          行全体 44 高のタップ領域。
//   CurrentAlertBanner   : 現在地が注意 / 危険のとき画面最上段に出すバナー (最小 44 高。
//                          地 = 浮いた面 + 1px 枠、角丸 14、グリフ 20 + 文言 + 「見る ›」)。
//                          閉じるボタンは無い (現在地の危険を消させない)。
//                          文言は行数を制限せず折り返す (高さ可変。QA-03: 2 行で省略すると
//                          文字倍率 2.0 の JA / ZH で文末のアラート種別「熱中症アラート」
//                          「中暑警示」が消えていた)。倍率 1.0 は省略が起きない長さなので
//                          見た目は変わらない (JA 1 行 = Figma E5、EN は案2 で 2 行。golden E5)。
//
// 文字は型スケールの body (現在地行・バナー本文・「見る ›」)。
// 状態色 (§4.1) は現在地行の帯ドットだけ。数値は無彩色。バナーの Heat グリフは
// §4.4 の例外で state/danger (他の種別はニュートラルなグリフ)。
// データは現在地だけから読む (mriProvider / currentTopEmergencyAlertProvider)。
// 通知の経路は呼ばない。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/safety/emergency_advisor.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/current_alert_provider.dart';
import '../../providers/mri_provider.dart';
import '../../providers/place_selection_provider.dart';
import '../../providers/weather_provider.dart';
import '../shared/quiet_glyphs.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// リング直下の「現在地 ● 74 ›」。保存地点を表示中だけ置く。
class CurrentLocationRow extends ConsumerWidget {
  const CurrentLocationRow({super.key});

  static const Key tapTargetKey = ValueKey('current-location-row');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final body = MrwType.of(context).body;
    final text = Theme.of(context).textTheme;
    final mri = ref.watch(mriProvider).valueOrNull;
    final label = text.bodyMedium?.copyWith(
      fontSize: body.fontSize(13),
      height: body.height(17 / 13),
      color: tokens.textMid,
    );

    return Semantics(
      button: true,
      label: t.placeCurrentRowLabel(mri == null ? '—' : '${mri.value}'),
      excludeSemantics: true,
      child: InkWell(
        key: tapTargetKey,
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            ref.read(selectedPlaceIdProvider.notifier).showCurrentLocation(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              const QuietIconMark(QuietIcon.pin, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  t.placeTabCurrent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label,
                ),
              ),
              const SizedBox(width: 8),
              if (mri != null) ...[
                Container(
                  key: const ValueKey('current-location-dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.stateColorForMri(mri.value),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                mri == null ? '—' : '${mri.value}',
                style: text.bodyMedium?.copyWith(
                  fontSize: body.fontSize(13),
                  height: body.height(17 / 13),
                  fontWeight: FontWeight.w500,
                  color: mri == null ? tokens.textLo : tokens.textHi,
                ),
              ),
              const SizedBox(width: 6),
              Text('›', style: label?.copyWith(color: tokens.textMono)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 現在地の緊急アラートのバナー。アラートが無ければ何も描かない。
class CurrentAlertBanner extends ConsumerWidget {
  const CurrentAlertBanner({super.key});

  static const Key bannerKey = ValueKey('current-alert-banner');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(currentTopEmergencyAlertProvider);
    if (alert == null) return const SizedBox.shrink();

    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final body = MrwType.of(context).body;
    final text = Theme.of(context).textTheme;
    final city = ref.watch(cityNameProvider).valueOrNull;
    final place =
        city == null ? t.homeAlertPlaceUnknown : t.homeAlertPlace(city);
    final message = switch (alert.kind) {
      EmergencyKind.heatStroke => t.homeAlertHeat(place),
      EmergencyKind.storm => t.homeAlertStorm(place),
      EmergencyKind.heavySnow => t.homeAlertSnow(place),
    };
    final glyph = switch (alert.kind) {
      EmergencyKind.heatStroke => QuietGlyph.heat,
      EmergencyKind.storm => QuietGlyph.storm,
      EmergencyKind.heavySnow => QuietGlyph.heavySnow,
    };

    return Semantics(
      button: true,
      liveRegion: true,
      label: '$message ${t.homeAlertView}',
      excludeSemantics: true,
      child: Material(
        key: bannerKey,
        color: tokens.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              ref.read(selectedPlaceIdProvider.notifier).showCurrentLocation(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  QuietGlyphIcon(glyph, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    // 省略しない: 安全の手がかり (種別) を文字倍率に関係なく読ませる。
                    // バナーはホームの ListView の中なので、高くなっても溢れない。
                    child: Text(
                      message,
                      style: text.bodyMedium?.copyWith(
                        fontSize: body.fontSize(13),
                        height: body.height(17 / 13),
                        color: tokens.textHi,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    t.homeAlertView,
                    style: text.titleSmall?.copyWith(
                      fontSize: body.fontSize(13),
                      height: body.height(17 / 13),
                      color: tokens.actionTertiaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
