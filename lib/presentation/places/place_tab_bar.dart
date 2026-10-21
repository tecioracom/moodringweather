// lib/presentation/places/place_tab_bar.dart
//
// ホーム見出し直下の地点タブ「現在地 | 那覇 | 京都 … | +」(案E' 確定。
// Figma 段階 2: E1 `506:2` / E2 `506:152` / E3 `506:304` / E6b `506:919` /
// E7 `506:1027` 実測)。
//
//   - 下線タブ。選択 = Medium 13 / 行高 17 / 主文字色 + 下線 (ラベル幅 × 2px)、
//     非選択 = Regular 13 / 副文字色。ラベル間隔 24、先頭は x=20。
//   - 基線 (x 20〜370、1px、枠色) はスクロールしない。
//   - 「+」は列の末尾 (非固定)。Plus で上限なら textLo (押すと理由のスナックバー)。
//     保存 0 件のときは「＋ 地点を追加（実家・旅行先など）」(tertiary) を置く。
//     無料 (保存地点は Plus 限定) でも見た目は同じで、押すと paywall
//     (分岐は place_actions.dart の openAddPlace)。
//   - 右にはみ出すと横スクロール。端は 24px のフェード (スクロールできる側だけ)。
//   - 選択中のタブが見える位置へ自動でスクロールする (切替はタップのみ。スワイプ無し)。
//   - タップ領域は各タブ高さ 44 (Figma: y 93〜137)。ラベルの最大幅 104 (8 字) で省略。
//   - タブに MRI・帯ドット・commerce 紫を置かない (§4.1「タブは常にニュートラル」)。
// 文字倍率が大きいときは行の高さが伸びる (下線と基線はラベルの下に付いていく)。
// 型スケール: タブは placeTab (body。案2 は 14 で止める)、「＋ 地点を追加」は body。
// 「+」は記号 (固定)。ラベルの行送り・最大幅 (8 字)・下線の下の余白はトークンから導く。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/display_weather_provider.dart';
import '../../providers/place_selection_provider.dart';
import '../../providers/saved_places_provider.dart';
import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// 「+」のキー (テスト・導線の特定用)。
const Key kPlaceTabAddKey = ValueKey('place-tab-add');

class PlaceTabBar extends ConsumerStatefulWidget {
  const PlaceTabBar({super.key, required this.onAddPressed});

  /// 「+」/「＋ 地点を追加」を押したとき (上限の判定・シート・paywall は呼び出し側)。
  final VoidCallback onAddPressed;

  @override
  ConsumerState<PlaceTabBar> createState() => _PlaceTabBarState();
}

class _PlaceTabBarState extends ConsumerState<PlaceTabBar> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  static const String _currentKey = '\u0000current';

  bool _fadeStart = false;
  bool _fadeEnd = false;
  String? _revealed;
  bool _hasRevealed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateFades);
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateFades);
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String? placeId) =>
      _tabKeys.putIfAbsent(placeId ?? _currentKey, GlobalKey.new);

  void _updateFades() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (!p.hasContentDimensions) return;
    final start = p.pixels > p.minScrollExtent + 0.5;
    final end = p.pixels < p.maxScrollExtent - 0.5;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
  }

  /// 選択中のタブが見えるように、必要な分だけ横にスクロールする (端のフェードに
  /// かからない位置まで)。見えていれば動かさない (Figma: E4 / E6a は先頭のまま、
  /// 末尾のタブを選んだ E6b は終端)。ホームの縦スクロールは動かさない。
  void _revealSelected(String? placeId, {required bool animate}) {
    if (!mounted || !_scroll.hasClients) return;
    final box = _keyFor(placeId).currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final p = _scroll.position;
    // タブがフェードにかからずに見えるスクロール位置の範囲 [lo, hi]
    // (lo = 右端を右フェードの内側に、hi = 左端を左フェードの内側に合わせる位置)。
    const margin = 32.0; // フェード 24 + 余白
    final lo = viewport.getOffsetToReveal(box, 1).offset + margin;
    final hi = viewport.getOffsetToReveal(box, 0).offset - margin;
    final min = p.minScrollExtent;
    final max = p.maxScrollExtent;
    var target = p.pixels;
    if (target > hi) target = hi;
    if (target < lo) target = lo;
    target = target.clamp(min, max);
    // 端の近くなら端まで寄せる (末尾のタブなら「+」まで見せる。Figma E6b)。
    // 選択タブが見えなくなる側には寄せない。
    const snap = 80.0;
    bool keepsVisible(double offset) =>
        offset >= lo - 0.5 && offset <= hi + 0.5;
    if (max - target < snap && keepsVisible(max)) {
      target = max;
    } else if (target - min < snap && keepsVisible(min)) {
      target = min;
    }
    if ((target - p.pixels).abs() < 0.5) {
      _updateFades();
      return;
    }
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final ja = MrwFonts.isJa(Localizations.maybeLocaleOf(context));
    final scaler = MediaQuery.textScalerOf(context);

    final places = ref.watch(savedPlacesProvider);
    final selected = ref.watch(displayedPlaceIdProvider);
    final quota = ref.watch(savedPlaceQuotaProvider);

    // 選択が変わったら (初回を含む) レイアウト後に見える位置へ。
    if (!_hasRevealed || _revealed != selected) {
      final animate = _hasRevealed;
      _hasRevealed = true;
      _revealed = selected;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealSelected(selected, animate: animate),
      );
    }

    // 縦の寸法 (倍率 1.0: ラベル上端 6 / 下線 30〜32 / 基線 31 / 行 44)。
    // ラベルの行送り (現状 17)・最大幅 (現状 104 = 13px で 8 字)・下線の下 (現状 12)
    // は型スケールから (文字を大きくしても「8 字で省略」を保つ)。
    final tabType = type.placeTab;
    final labelHeight = scaler.scale(tabType.lineHeight(17));
    const labelTop = 6.0;
    final underlineTop = labelTop + labelHeight + 7;
    final rowHeight = math.max(
      44.0,
      underlineTop + 2 + type.layout.placeTabBottomGap,
    );
    final maxLabelWidth = scaler.scale(tabType.scaled(104));

    final regular = text.bodyMedium?.copyWith(
      fontSize: tabType.fontSize(13),
      height: tabType.height(17 / 13),
      color: tokens.textMid,
    );
    final medium = regular?.copyWith(
      fontWeight: FontWeight.w500,
      fontVariations: ja ? null : MrwFonts.interVariations(FontWeight.w500),
      color: tokens.textHi,
    );

    Widget tab({
      required String? placeId,
      required String label,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        selected: isSelected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          key: _keyFor(placeId),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: labelTop),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxLabelWidth),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isSelected ? medium : regular,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: isSelected ? tokens.textHi : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
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

    final selection = ref.read(selectedPlaceIdProvider.notifier);
    final atPlusLimit = quota.isPlus && !quota.canAddNew;
    final addColor = atPlusLimit ? tokens.textLo : tokens.actionTertiaryLabel;

    final Widget addItem = places.isEmpty
        // 保存 0 件: 「＋ 地点を追加（実家・旅行先など）」(tertiary)。
        ? Semantics(
            key: kPlaceTabAddKey,
            button: true,
            label: t.placeTabAddFirst,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onAddPressed,
              child: SizedBox(
                height: rowHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, labelTop, 12, 0),
                  child: Text(
                    t.placeTabAddFirst,
                    maxLines: 1,
                    style: text.titleSmall?.copyWith(
                      fontSize: type.body.fontSize(13),
                      height: type.body.height(17 / 13),
                      color: tokens.actionTertiaryLabel,
                    ),
                  ),
                ),
              ),
            ),
          )
        // 「+」: 最後のタブの右 +24、Regular 18。ヒット領域 44 × 行高。
        : Semantics(
            key: kPlaceTabAddKey,
            button: true,
            label: t.addPlaceTitle,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onAddPressed,
              child: SizedBox(
                width: 44,
                height: rowHeight,
                child: Padding(
                  padding: const EdgeInsets.only(top: labelTop - 2),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      '+',
                      style: text.bodyLarge?.copyWith(
                        fontSize: 18, // 型スケール対象外 (記号 +)
                        height: 20 / 18,
                        color: addColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tab(
          placeId: null,
          label: t.placeTabCurrent,
          isSelected: selected == null,
          onTap: selection.showCurrentLocation,
        ),
        for (final place in places)
          tab(
            placeId: place.id,
            label: place.name,
            isSelected: selected == place.id,
            onTap: () => selection.select(place.id),
          ),
        addItem,
      ],
    );

    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: [
          // 基線 (スクロールしない)。下線はこの上に重なる。
          Positioned(
            left: 20,
            right: 20,
            top: underlineTop + 1,
            height: 1,
            child: ColoredBox(color: tokens.border),
          ),
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _updateFades());
                return false;
              },
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  final fade = rect.width <= 0 ? 0.0 : 24 / rect.width;
                  const opaque = Color(0xFF000000);
                  const clear = Color(0x00000000);
                  return LinearGradient(
                    colors: [
                      _fadeStart ? clear : opaque,
                      opaque,
                      opaque,
                      _fadeEnd ? clear : opaque,
                    ],
                    stops: [0, fade, 1 - fade, 1],
                  ).createShader(rect);
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  // 先頭ラベルを x=20 に (タブ自身の左右 12 と合わせて)。
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: row,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
