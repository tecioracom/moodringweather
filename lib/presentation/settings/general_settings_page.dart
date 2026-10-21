// lib/presentation/settings/general_settings_page.dart
//
// 設定 > 一般 (spec.md §4.4 / Figma v1.3 `Settings — General` 3:473・Light 24:555・
// JP 77:560 実測)。すべて即時反映 + SharedPreferences 永続化:
//   - 温度単位 °C/°F → temperatureUnitProvider (Home/Detail の表示に実反映)。
//     ja の切替は「℃ / ℉」(ARB。ja の書体の全角「°」で「° C」と割れるため)
//   - 風速の単位 m/s | km/h | mph → windSpeedUnitProvider (ホーム・詳細の風、
//     Twin の比較、緊急通知 (暴風) の本文。docs/design-metric-units-proposal.md §2.6)。
//     記号は訳さず、大文字にしない。温度の単位の直下 (言語の上)。温度・風速の切替は
//     記号ではなく読み方で読み上げる (unit*A11y。QA-24)
//   - 言語 → locale_controller (端末追従 + 4 言語)
//   - テーマ system/light/dark → themeModeProvider (MaterialApp.themeMode)
//   - ライブ壁紙 (Android だけ。テーマの下・デバッグの区画の上):
//       「ライブ壁紙を設定」(1.3.0 (14)) → 壁紙のプレビュー画面を開く
//       (liveWallpaperSetupBridgeProvider)。今のホーム画面の壁紙がこのライブ壁紙なら
//       右に「設定中」(liveWallpaperActiveProvider。画面を開いたときと前面に戻った
//       ときに読み直す)。設定中でも押せば開く (ロック画面にも設定し直す人のため)。
//       開けなければ手順をスナックバーで案内する。Galaxy (One UI) の「壁紙とスタイル」は
//       他社アプリのライブ壁紙を一覧に出さないため、アプリから開く (2026-10-01 実機で発見)
//       「壁紙に天気と気温を表示」(既定オン) → wallpaperWeatherProvider。オフで壁紙の
//       重ね描きを消す (色は区分のまま。docs/design-wallpaper-weather-overlay.md §6)
// 単位の初期値 (まだ選んでいない人) は端末の地域で決まる (settings_provider.dart)。
//
// 構成 (Figma): mono の区画ラベル (11 / 字間 0.88) + セグメント (外 48・角丸 16 /
// 選択ピル 32・角丸 12) / 言語は 1 行 1 カード (アイコン 20 + 見出し 15)。
//
// Figma にあって実装しない (理由):
//   - 「Color-safe mode」トグル (3:567): 対応する機能もロジックも存在しない。
//     偽のトグルを置かない (色覚配慮は §4.1「色だけで情報を伝えない」で担保済み)。
//   - 言語行の chevron (3:531 ほか): 遷移しない選択リストなので誤誘導になる。
//     選択中の行は Figma の「ON」バッジの代わりにチェックを出す (「ON」は
//     翻訳しない literal で ARB に置けないため)。
//
// 厳守: 状態色 (state/*) はこの画面に 0 個。文言はすべて AppLocalizations 経由。

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/temperature_unit.dart';
import '../../core/utils/wind_speed_unit.dart';
import '../../data/models/entitlement.dart';
import '../../domain/locale/locale_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/entitlement_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/wallpaper_provider.dart';
import '../locale/locale_controller.dart';
import '../shared/metric_tiles.dart'
    show temperatureUnitSpoken, windSpeedUnitSpoken;
import '../shared/quiet_controls.dart';
import '../shared/quiet_page.dart';
import '../shared/quiet_row_icons.dart';
import '../shared/quiet_snackbar.dart';
import '../theme/mrw_tokens.dart';

/// 言語ピッカーの 1 項目。`tag == null` は「端末の設定に従う」。
/// 各言語は **その言語自身の表記 (endonym)** で並べる — 中国語話者が英語表示中でも
/// 「简体中文」を見つけられるようにするため。
class _LangOption {
  const _LangOption(this.tag, this.endonym);
  final LocaleTag? tag;
  final String endonym;
}

const List<_LangOption> _langOptions = [
  _LangOption(null, ''), // ラベルは languageSystemDefault に差し替える
  _LangOption(LocaleTag('ja'), '日本語'),
  _LangOption(LocaleTag('en'), 'English'),
  _LangOption(LocaleTag('zh', 'Hans'), '简体中文'),
  _LangOption(LocaleTag('es'), 'Español'),
];

class GeneralSettingsPage extends ConsumerWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final unit = ref.watch(temperatureUnitProvider);
    final windUnit = ref.watch(windSpeedUnitProvider);
    final themeMode = ref.watch(themeModeProvider);

    return QuietPage(
      title: t.settingsTitle,
      headline: t.settingsGeneral,
      children: [
        QuietLabel(t.settingsTemperatureUnit),
        const SizedBox(height: 10),
        QuietSegmented<TemperatureUnit>(
          segments: [
            (TemperatureUnit.celsius, t.unitCelsius),
            (TemperatureUnit.fahrenheit, t.unitFahrenheit),
          ],
          selected: unit,
          onChanged: (v) =>
              ref.read(temperatureUnitProvider.notifier).select(v),
          // 記号ではなく読み方で読ませる (QA-24)。
          semanticsLabelOf: (v) => temperatureUnitSpoken(t, v),
        ),
        const SizedBox(height: 26),

        // === 風速の単位 (温度の単位の直下。記号は訳さず大文字にしない) ===
        QuietLabel(t.settingsWindSpeedUnit),
        const SizedBox(height: 10),
        QuietSegmented<WindSpeedUnit>(
          segments: [
            for (final u in WindSpeedUnit.values) (u, u.symbol),
          ],
          selected: windUnit,
          onChanged: (v) => ref.read(windSpeedUnitProvider.notifier).select(v),
          // 記号ではなく読み方で読ませる (「メートル毎秒」など。タイルと同じ語。QA-24)。
          semanticsLabelOf: (v) => windSpeedUnitSpoken(t, v),
        ),
        const SizedBox(height: 26),

        // === 言語 ===
        QuietLabel(t.languageSelectorLabel),
        const SizedBox(height: 10),
        const _LanguageRows(),
        const SizedBox(height: 26),

        // === テーマ ===
        QuietLabel(t.settingsTheme),
        const SizedBox(height: 10),
        QuietSegmented<ThemeMode>(
          segments: [
            (ThemeMode.system, t.themeSystem),
            (ThemeMode.light, t.themeLight),
            (ThemeMode.dark, t.themeDark),
          ],
          selected: themeMode,
          onChanged: (v) => ref.read(themeModeProvider.notifier).select(v),
        ),

        // === ライブ壁紙 (Android だけ。iOS にはライブ壁紙が無い) ===
        if (ref.watch(liveWallpaperSupportedProvider)) ...[
          const SizedBox(height: 26),
          QuietLabel(t.settingsLiveWallpaper),
          const SizedBox(height: 10),
          const _LiveWallpaperSetupRow(),
          const SizedBox(height: 8),
          const _WallpaperWeatherRow(),
        ],

        // === デバッグ: Plus 状態の上書き (kDebugMode 限定) ===
        // リリースビルドでは kDebugMode が false 定数になり丸ごと除去される。
        if (kDebugMode) ...[
          const SizedBox(height: 26),
          QuietLabel(t.debugPlusOverrideTitle),
          const SizedBox(height: 10),
          QuietSegmented<EntitlementTier>(
            segments: [
              (EntitlementTier.free, t.debugPlusOverrideOff),
              (EntitlementTier.plus, t.plusTierPlus),
              (EntitlementTier.pro, t.plusTierPro),
            ],
            selected: ref.watch(debugPlusTierProvider) ?? EntitlementTier.free,
            onChanged: (tier) => ref
                .read(debugPlusTierProvider.notifier)
                .select(tier == EntitlementTier.free ? null : tier),
          ),
        ],
      ],
    );
  }
}

/// 「ライブ壁紙を設定」の行 (1.3.0 (14))。押すと壁紙のプレビュー画面を開く。
///
/// 今のホーム画面の壁紙がこのライブ壁紙なら、説明を「ロック画面への設定もここから」に
/// 変え、見出しの右 (シェブロンの左) に「設定中」のバッジを出す (文字が大きくて
/// 1 行に収まらなければ見出しの下)。設定中でも押せば開く。読み直すのは、画面を
/// 開いたとき (liveWallpaperActiveProvider は autoDispose) と、アプリが前面に戻った
/// とき (壁紙のプレビュー画面から戻ってきたとき)。開けなかったら (プレビューも一覧も
/// 無い端末) 手順をスナックバーで案内する。読み上げは行を 1 つにまとめる。
class _LiveWallpaperSetupRow extends ConsumerStatefulWidget {
  const _LiveWallpaperSetupRow();

  @override
  ConsumerState<_LiveWallpaperSetupRow> createState() =>
      _LiveWallpaperSetupRowState();
}

class _LiveWallpaperSetupRowState
    extends ConsumerState<_LiveWallpaperSetupRow> {
  late final AppLifecycleListener _lifecycle;

  /// 開いている途中か (連打でプレビュー画面を 2 回開かない)。
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(liveWallpaperActiveProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final opened =
          await ref.read(liveWallpaperSetupBridgeProvider).openPicker();
      if (opened || !mounted) return;
      showQuietSnackBar(
        context,
        message: AppLocalizations.of(context).settingsLiveWallpaperOpenFailed,
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final active = ref.watch(liveWallpaperActiveProvider).valueOrNull ?? false;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: QuietListRow(
          title: t.settingsLiveWallpaperSet,
          subtitle: active
              ? t.settingsLiveWallpaperSetActiveHint
              : t.settingsLiveWallpaperSetHint,
          emphasizeTitle: true,
          // 「設定中」は見出しの横 (1 行に収まれば右端、収まらなければ見出しの下)。
          // 右要素 (trailing) にすると 360dp・倍率 1.3 以上で説明・見出しの幅が
          // 足りず、見出しが語の途中で折れ、説明が省略される。
          titleBadge: active ? QuietBadge(t.settingsLiveWallpaperActive) : null,
          chevron: true,
          onTap: _open,
        ),
      ),
    );
  }
}

/// 「壁紙に天気と気温を表示」のトグル行 (設計書 §6。Figma では Color-safe mode の行を
/// 作り替えたもの)。スイッチでも行のどこを押しても切り替わる。読み上げは行を 1 つに
/// まとめる (「壁紙に天気と気温を表示、ライブ壁紙の右上に表示します、スイッチ、オン」)。
class _WallpaperWeatherRow extends ConsumerWidget {
  const _WallpaperWeatherRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final enabled = ref.watch(wallpaperWeatherProvider);
    final controller = ref.read(wallpaperWeatherProvider.notifier);
    return MergeSemantics(
      child: QuietListRow(
        title: t.settingsWallpaperWeather,
        subtitle: t.settingsWallpaperWeatherHint,
        emphasizeTitle: true,
        onTap: () => controller.select(!enabled),
        trailing: QuietSwitch(value: enabled, onChanged: controller.select),
      ),
    );
  }
}

/// 言語の選択リスト (Figma 3:523〜3:559)。選択中の行にチェックを出す。
class _LanguageRows extends ConsumerWidget {
  const _LanguageRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final controller = ref.read(localeControllerProvider.notifier);
    final current = controller.isFollowingSystem
        ? null
        : _tagOf(ref.watch(localeControllerProvider));

    return Column(
      children: [
        for (var i = 0; i < _langOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final o = _langOptions[i];
              final selected = o.tag == current;
              return Semantics(
                selected: selected,
                child: QuietListRow(
                  icon: QuietRowIcon.globe,
                  title: o.tag == null ? t.languageSystemDefault : o.endonym,
                  emphasizeTitle: true,
                  trailing: selected
                      ? Icon(Icons.check, size: 18, color: tokens.textHi)
                      : null,
                  onTap: () => controller.select(o.tag),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  /// 解決済み Locale を対応表のタグへ逆引き (表示中の言語を示すため)。
  LocaleTag? _tagOf(Locale locale) {
    for (final tag in kSupportedLocales) {
      if (tag.languageCode == locale.languageCode &&
          (tag.scriptCode == locale.scriptCode || tag.scriptCode == null)) {
        return tag;
      }
    }
    return null;
  }
}
