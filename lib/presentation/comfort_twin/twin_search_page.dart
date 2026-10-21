// lib/presentation/comfort_twin/twin_search_page.dart
//
// Comfort-Twin 検索画面 (Figma v1.3 `Twin — Search` 5:133・Light 24:947・
// JP 77:894 実測)。
//
// 構成 (Figma):
//   パネル   「TARGET MRI」mono + 値 Fraunces 64 (**無彩色**) + 帯名 mono +
//            「今日の体感を使う」の副ボタン + スライダー (すべてニュートラル)
//   セクション「記録から」
//   行       ラベル + 「MRI nn」(mono 10・**帯色**) + chevron
//   主 CTA   世界中から探す
//
// **状態色 (§4.1)**: 記録行の「MRI nn」テキストのみ (規則 1 の ③)。
// 大きなターゲット値は Figma でも pearl (無彩色) — まだ「どこかの実測値」では
// なく入力値だからである。件数が上限 6 を超えるときは数値を主文字色に戻し、
// 行頭の帯ドットだけに縮小する (規則 2)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/comfort_record.dart';
import '../../domain/mri/mri_band.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/comfort_twin_provider.dart';
import '../../providers/mri_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';
import 'twin_map_page.dart';

/// 行の間隔。
const double _kRowGap = 10;

/// §4.1 規則 2 の上限。
const int _kMaxStateColoredRows = 6;

class TwinSearchPage extends ConsumerStatefulWidget {
  const TwinSearchPage({super.key});

  @override
  ConsumerState<TwinSearchPage> createState() => _TwinSearchPageState();
}

class _TwinSearchPageState extends ConsumerState<TwinSearchPage> {
  /// null = 未操作 (現在の自分の MRI で初期化)。
  double? _target;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final myMri = ref.watch(mriProvider).valueOrNull;
    // 記録の MRI をターゲットに使う。地名検索で追加した保存地点は保存時の
    // MRI を持たない (天気を取る前に保存する) ので、ここには出さない。
    final records = [
      for (final r in ref.watch(comfortRecordsProvider))
        if (r.mri != null) r,
    ];
    final target = _target ?? (myMri?.value ?? 64).toDouble();
    final targetValue = target.round();
    final useDots = records.length > _kMaxStateColoredRows;

    return QuietPage(
      title: t.settingsTitle,
      headline: t.twinTitle,
      intro: t.twinIntro,
      children: [
        // === ターゲット MRI (数値は無彩色。スライダーもニュートラル) ===
        QuietPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QuietLabel(t.twinTargetLabel,
                  small: true, color: tokens.textMono),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  QuietDisplayNumber('$targetValue', size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: QuietLabel(
                      _bandLabel(t, targetValue),
                      small: true,
                      color: tokens.inkMid,
                    ),
                  ),
                ],
              ),
              QuietSlider(
                value: target,
                min: 0,
                max: 100,
                divisions: 100,
                label: '$targetValue',
                semanticFormatterCallback: (v) => '${t.mriAbbrev} ${v.round()}',
                onChanged: (v) => setState(() => _target = v),
              ),
              if (myMri != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: QuietSecondaryButton(
                    expand: false,
                    label: '${t.twinCurrentFeel} · ${myMri.value}',
                    onPressed: () =>
                        setState(() => _target = myMri.value.toDouble()),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 26),

        // === 記録から選ぶ ===
        QuietSectionTitle(t.twinRecordsTitle),
        const SizedBox(height: 10),
        if (records.isEmpty)
          QuietBodyCard(text: t.twinNoRecords)
        else
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const SizedBox(height: _kRowGap),
            _RecordRow(
              record: records[i],
              useDot: useDots,
              onTap: () => setState(() => _target = records[i].mri!.toDouble()),
            ),
          ],
        const SizedBox(height: 10),
        QuietTertiaryButton(
          label: t.twinSaveToday,
          onPressed: myMri == null
              ? null
              : () async {
                  await ref
                      .read(comfortRecordsProvider.notifier)
                      .saveDayFeel(myMri.value);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.twinTodaySaved)),
                  );
                },
        ),
        const SizedBox(height: 16),

        // === 世界中から探す (主 CTA は 1 画面 1 つ) ===
        QuietPrimaryButton(
          label: t.twinFindWorldwide,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TwinMapPage(targetMri: targetValue),
            ),
          ),
        ),
      ],
    );
  }

  /// 帯名 (Figma 5:141 の「comfortable」。色は持たせない)。
  String _bandLabel(AppLocalizations t, int mri) {
    switch (MriBand.fromValue(mri)) {
      case MriBand.cool:
        return t.bandCool;
      case MriBand.comfortable:
        return t.bandComfortable;
      case MriBand.warm:
        return t.bandWarm;
      case MriBand.hot:
        return t.bandHot;
      case MriBand.hotAlert:
        return t.bandHotHydrate;
    }
  }
}

/// 記録の 1 行 (Figma 5:148)。MRI 値だけが帯色。
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.useDot,
    required this.onTap,
  });

  /// MRI を持つ記録だけを渡す (呼び出し側で絞り込み済み)。
  final ComfortRecord record;
  final bool useDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final tag = MrwType.of(context).tag;
    final band = tokens.stateColorForMri(record.mri ?? 0);

    return QuietListRow(
      title: _label(context, t),
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
          Text(
            '${t.mriAbbrev} ${record.mri ?? '—'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: tag.fontSize(10),
                  letterSpacing: 0,
                  fontWeight: FontWeight.w400,
                  height: tag.height(13 / 10),
                  color: useDot ? tokens.textHi : band,
                ),
          ),
        ],
      ),
      chevron: true,
      onTap: onTap,
    );
  }

  /// place は保存時の都市名、day は日付を整形表示。
  String _label(BuildContext context, AppLocalizations t) {
    if (record.type == ComfortRecordType.place) {
      final emoji = record.emoji == null ? '' : '${record.emoji} ';
      return '$emoji${record.label ?? t.currentLocation}'.trim();
    }
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.MMMd(locale).format(record.savedAt);
  }
}
