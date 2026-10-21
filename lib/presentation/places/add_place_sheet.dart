// lib/presentation/places/add_place_sheet.dart
//
// 「地点を追加」ボトムシート (案S′ 確定。Figma: docs/codex-figma_add-place-modal_revision.md
// §2〜§4 / docs/codex-figma_add-place-sheet_final.md。JA Dark `522:258` B0 / `522:2` B1 /
// `522:499` B1b / `522:851` B1c / `522:1114` B2 / `522:1365` B3 / `522:1612` B4 実測)。
//
//   上端はホームのタブ列の下 (背後の暗くしたヘッダとタブが覗く)。scrim = onyx-900 α.60。
//   シート地 = カード地 (surface)、上辺 1px、上の角丸 20。グラバー 36×4。
//   題「地点を追加」Bold 15 / 右に tertiary「閉じる」。フィールド 334×48 (surfaceLow、
//   フォーカス枠 = 主文字色 24%)、入力 Regular 15、× は中心 x=340 (ヒット 44)。
//   候補行 56 高: 地名 Regular 13 / 地域 Regular 11 textMid / 右端「+」(tertiary)。
//   保存済み: 地名 textMid・地域 textMono・右端「保存済み」(textMono)。区切り線は枠色。
//   出典行 (mono 10) は内容の直後。候補が多いと下端 24px をフェード。
//   キーボードの分だけ内容を持ち上げる (シート地はキーボードの裏まで続く)。
//
// 型スケール: 題・入力 = section、「閉じる」・地名・再試行 = body、地域・「保存済み」= meta、
// 案内文 = caption (段落)、検索中・出典 = tag。「+」「×」は記号 (固定)。
//
// 状態 (PlaceSearchState): B0 未入力 / B1 候補 / B2 検索中 / B3 0 件 / B4 通信エラー。
// IME 変換中は検索しない・入力の間引き 300ms (place_search_provider.dart)。
//
// 閉じ方: 「閉じる」/ 背後のタップ / 下スワイプ / Android の戻る (キーボード表示中は
// 1 回目でキーボードだけ閉じ、2 回目でシート)。背後のタップは自前の領域で受ける
// (ルートのバリアに任せると、戻るの制御 (PopScope) で外側タップまで止まるため)。
//
// 候補のタップで即追加し、結果 (AddPlaceOutcome) を返して閉じる。上限はタップ時に
// SavedPlacesController で判定し直す。状態色・MRI は出さない (候補の時点で天気は未取得)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/data_attribution.dart';
import '../../core/utils/external_url.dart';
import '../../data/models/place_candidate.dart';
import '../../domain/places/saved_place_rules.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/place_search_provider.dart';
import '../../providers/saved_places_provider.dart';
import '../shared/quiet_controls.dart';
import '../shared/quiet_progress.dart';
import '../theme/app_theme.dart';
import '../theme/mrw_tokens.dart';
import '../theme/mrw_type.dart';

/// scrim (Dark / Light 共通: onyx-900 α.60)。
const Color kAddPlaceScrim = Color(0x990D0E11);

/// シートの上端の既定位置 (セーフエリア上端から。ホーム以外から開くとき)。
const double kAddPlaceSheetDefaultTop = 88;

/// テスト用のキー。
const Key kAddPlaceFieldKey = ValueKey('add-place-field');
const Key kAddPlaceScrimKey = ValueKey('add-place-scrim');
const Key kAddPlaceCloseKey = ValueKey('add-place-close');
const Key kAddPlaceClearKey = ValueKey('add-place-clear');
const Key kAddPlaceRetryKey = ValueKey('add-place-retry');

/// シートを閉じたときの結果。null は何もせずに閉じた。
sealed class AddPlaceOutcome {
  const AddPlaceOutcome();
}

/// 候補を保存した (新規または更新)。
final class AddPlaceAdded extends AddPlaceOutcome {
  const AddPlaceAdded(this.result, this.name);

  final SavedPlaceAddResult result;

  /// 保存した表示名 (スナックバー用)。
  final String name;
}

/// 保存済みの候補を選んだ (その地点を表示する)。
final class AddPlaceShowExisting extends AddPlaceOutcome {
  const AddPlaceShowExisting(this.placeId);

  final String placeId;
}

/// タップ時の再判定で無料だった (シートを開いている間に解約など。保存地点は
/// Plus 限定なので Plus 導線へ)。
final class AddPlaceNeedsPlus extends AddPlaceOutcome {
  const AddPlaceNeedsPlus();
}

/// タップ時の再判定で Plus の上限だった (理由を表示)。
final class AddPlaceLimitReached extends AddPlaceOutcome {
  const AddPlaceLimitReached();
}

/// シートを開く。[top] はシート上端の画面 y (ホームはタブ列の下端)。
Future<AddPlaceOutcome?> showAddPlaceSheet(
  BuildContext context, {
  double? top,
}) {
  final media = MediaQuery.of(context);
  final minTop = media.padding.top + 24;
  final maxTop = media.size.height * 0.5;
  final sheetTop = (top ?? media.padding.top + kAddPlaceSheetDefaultTop)
      .clamp(minTop, maxTop < minTop ? minTop : maxTop)
      .toDouble();
  return showModalBottomSheet<AddPlaceOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    // 外側のタップはシート側の透明な領域で受ける (上の注記)。
    isDismissible: false,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: kAddPlaceScrim,
    builder: (_) => AddPlaceSheet(top: sheetTop),
  );
}

class AddPlaceSheet extends ConsumerStatefulWidget {
  const AddPlaceSheet({super.key, required this.top});

  /// シート上端の画面 y。
  final double top;

  @override
  ConsumerState<AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends ConsumerState<AddPlaceSheet> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _list = ScrollController();
  bool _busy = false;
  bool _fadeBottom = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    _list.addListener(_updateFade);
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _list.removeListener(_updateFade);
    _text.dispose();
    _focus.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // 文字の変更だけでなく変換の確定 (composing の解除) でも呼ばれる。
    ref.read(placeSearchControllerProvider.notifier).onQueryChanged(
          _text.text,
          isComposing: isImeComposing(_text.value),
        );
    setState(() {}); // × の表示
  }

  void _onFocusChanged() => setState(() {});

  void _updateFade() {
    if (!_list.hasClients) return;
    final p = _list.position;
    final fade = p.hasContentDimensions && p.pixels < p.maxScrollExtent - 0.5;
    if (fade != _fadeBottom) setState(() => _fadeBottom = fade);
  }

  void _close() => Navigator.of(context).pop();

  void _finish(AddPlaceOutcome outcome) => Navigator.of(context).pop(outcome);

  void _clear() {
    _text.clear();
    ref.read(placeSearchControllerProvider.notifier).clear();
    _focus.requestFocus();
  }

  Future<void> _select(PlaceCandidate candidate) async {
    if (_busy) return;
    final controller = ref.read(savedPlacesControllerProvider);
    if (controller.isSaved(candidate)) {
      _finish(AddPlaceShowExisting(candidate.placeId));
      return;
    }
    setState(() => _busy = true);
    final result = await controller.add(candidate);
    if (!mounted) return;
    switch (result.check) {
      case SavedPlaceAddCheck.allowed:
      case SavedPlaceAddCheck.alreadySaved:
        _finish(AddPlaceAdded(result, candidate.name));
      case SavedPlaceAddCheck.needsPlus:
        _finish(const AddPlaceNeedsPlus());
      case SavedPlaceAddCheck.limitReached:
        _finish(const AddPlaceLimitReached());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // キーボードが出ている間の「戻る」はキーボードだけを閉じる。
    final keyboardShown = keyboard > 0 && _focus.hasFocus;
    final search = ref.watch(placeSearchControllerProvider);

    return PopScope(
      canPop: !keyboardShown,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focus.unfocus();
      },
      child: SizedBox(
        height: media.size.height,
        child: Column(
          children: [
            // 背後 (暗くしたホーム) のタップで閉じる。
            Semantics(
              button: true,
              label: t.addPlaceClose,
              excludeSemantics: true,
              child: GestureDetector(
                key: kAddPlaceScrimKey,
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: SizedBox(width: double.infinity, height: widget.top),
              ),
            ),
            Expanded(
              child: CustomPaint(
                foregroundPainter: _SheetTopEdgePainter(color: tokens.border),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: ColoredBox(
                    color: tokens.surface,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboard),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: tokens.textHi.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          _header(t, tokens, text),
                          _field(t, tokens, text),
                          const SizedBox(height: 16),
                          Expanded(child: _results(t, tokens, text, search)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations t, MrwTokens tokens, TextTheme text) {
    final ja = MrwFonts.isJa(Localizations.maybeLocaleOf(context));
    final type = MrwType.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 44, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  t.addPlaceTitle,
                  // Figma: 題は Bold 15/19 (EN Inter Bold / JA Plex Sans JP
                  // Bold)。テーマの title は EN が SemiBold なので上書きする。
                  style: text.titleMedium?.copyWith(
                    fontSize: type.section.fontSize(15),
                    height: type.section.height(19 / 15),
                    fontWeight: FontWeight.w700,
                    fontVariations:
                        ja ? null : MrwFonts.interVariations(FontWeight.w700),
                    color: tokens.textHi,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              child: InkWell(
                key: kAddPlaceCloseKey,
                onTap: _close,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: 44, minWidth: 44),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Text(
                      t.addPlaceClose,
                      style: text.titleSmall?.copyWith(
                        fontSize: type.body.fontSize(13),
                        height: type.body.height(17 / 13),
                        color: tokens.actionTertiaryLabel,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(AppLocalizations t, MrwTokens tokens, TextTheme text) {
    final focused = _focus.hasFocus;
    final section = MrwType.of(context).section;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: tokens.surfaceLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                focused ? tokens.textHi.withValues(alpha: 0.24) : tokens.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Semantics(
                  label: t.addPlaceFieldLabel,
                  child: TextField(
                    key: kAddPlaceFieldKey,
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => ref
                        .read(placeSearchControllerProvider.notifier)
                        .submit(),
                    style: text.bodyLarge?.copyWith(
                      fontSize: section.fontSize(15),
                      height: section.height(20 / 15),
                      color: tokens.textHi,
                    ),
                    cursorColor: tokens.textHi,
                    cursorWidth: 1,
                    cursorHeight: section.scaled(18).roundToDouble(),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
            if (_text.text.isNotEmpty)
              Semantics(
                button: true,
                label: t.addPlaceClear,
                excludeSemantics: true,
                child: InkResponse(
                  key: kAddPlaceClearKey,
                  onTap: _clear,
                  radius: 22,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Text(
                        '×',
                        style: text.bodyLarge?.copyWith(
                          fontSize: 16, // 型スケール対象外 (記号 ×)
                          height: 20 / 16,
                          color: tokens.textMono,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _results(
    AppLocalizations t,
    MrwTokens tokens,
    TextTheme text,
    PlaceSearchState search,
  ) {
    final type = MrwType.of(context);
    final body = text.bodyMedium?.copyWith(
      fontSize: type.caption.fontSize(12),
      height: type.caption.height(17 / 12, paragraph: true),
      color: tokens.textMid,
    );
    final meta = text.labelSmall?.copyWith(
      fontSize: type.tag.fontSize(10),
      height: type.tag.height(13 / 10),
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: tokens.textMono,
    );
    Widget inset(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16), child: child);

    final attribution = inset(
      Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          link: true,
          child: GestureDetector(
            onTap: () =>
                openExternalUrl(PlaceSearchAttribution.geocodingApiUrl),
            child: Text(
              t.addPlaceAttribution(
                PlaceSearchAttribution.searchProviderName,
                PlaceSearchAttribution.placeDataName,
              ),
              style: meta,
            ),
          ),
        ),
      ),
    );

    final List<Widget> children;
    switch (search) {
      case PlaceSearchIdle():
        children = [inset(Text(t.addPlaceGuide, style: body))];
      case PlaceSearchLoading():
        children = [
          inset(Text(t.addPlaceSearching, style: meta)),
          const SizedBox(height: 8),
          const QuietIndeterminateTrack(),
        ];
      case PlaceSearchNoResults():
        children = [inset(Text(t.addPlaceNoResults, style: body))];
      case PlaceSearchFailure():
        children = [
          inset(Text(t.addPlaceError, style: body)),
          const SizedBox(height: 16),
          _RetryButton(
            label: t.retry,
            onPressed: () =>
                ref.read(placeSearchControllerProvider.notifier).retry(),
          ),
        ];
      case PlaceSearchResults(:final candidates):
        children = [
          for (var i = 0; i < candidates.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: tokens.border),
            _CandidateRow(
              candidate: candidates[i],
              onTap: _busy ? null : () => _select(candidates[i]),
            ),
          ],
        ];
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final fade = rect.height <= 0 ? 0.0 : 24 / rect.height;
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF000000),
              const Color(0xFF000000),
              _fadeBottom ? const Color(0x00000000) : const Color(0xFF000000),
            ],
            stops: [0, 1 - fade, 1],
          ).createShader(rect);
        },
        child: ListView(
          controller: _list,
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          children: [
            ...children,
            const SizedBox(height: 14),
            attribution,
          ],
        ),
      ),
    );
  }
}

/// 候補 1 行 (Figma: 56 高、地名 (16,+10) / 地域 (16,+29) / 右端「+」または「保存済み」)。
class _CandidateRow extends ConsumerWidget {
  const _CandidateRow({required this.candidate, required this.onTap});

  final PlaceCandidate candidate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = MrwTokens.of(context);
    final type = MrwType.of(context);
    final text = Theme.of(context).textTheme;
    final saved = ref.watch(isSavedPlaceProvider(candidate.placeId));
    final region = candidate.regionParts.join(t.placeRegionSeparator);

    return Semantics(
      button: true,
      label: [
        candidate.name,
        if (region.isNotEmpty) region,
        saved ? t.addPlaceSaved : t.addPlaceTitle,
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontSize: type.body.fontSize(13),
                          height: type.body.height(17 / 13),
                          color: saved ? tokens.textMid : tokens.textHi,
                        ),
                      ),
                      if (region.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          region,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            fontSize: type.meta.fontSize(11),
                            height: type.meta.height(16 / 11),
                            color: saved ? tokens.textMono : tokens.textMid,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (saved)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    t.addPlaceSaved,
                    style: text.bodySmall?.copyWith(
                      fontSize: type.meta.fontSize(11),
                      height: type.meta.height(16 / 11),
                      color: tokens.textMono,
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Text(
                      '+',
                      style: text.bodyLarge?.copyWith(
                        fontSize: 18, // 型スケール対象外 (記号 +)
                        height: 20 / 18,
                        color: tokens.actionTertiaryLabel,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// B4 の再試行 (Figma: 334×46、角丸 23、地 = 浮いた面 + 1px 枠、ラベル Bold 13 主文字色)。
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = MrwTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: kAddPlaceRetryKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: tokens.surfaceHigh,
          foregroundColor: tokens.textHi,
          minimumSize: const Size.fromHeight(46),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
            side: BorderSide(color: tokens.border),
          ),
          textStyle: quietButtonTextStyle(context),
        ),
        child: Text(label),
      ),
    );
  }
}

/// シートの上辺 1px (角丸 20 に沿う)。側辺・下辺には線を引かない。
class _SheetTopEdgePainter extends CustomPainter {
  const _SheetTopEdgePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 20.0;
    final path = Path()
      ..moveTo(0.5, r)
      ..arcToPoint(const Offset(r, 0.5), radius: const Radius.circular(r - 0.5))
      ..lineTo(size.width - r, 0.5)
      ..arcToPoint(
        Offset(size.width - 0.5, r),
        radius: const Radius.circular(r - 0.5),
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SheetTopEdgePainter old) => old.color != color;
}
