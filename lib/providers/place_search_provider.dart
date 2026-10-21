// lib/providers/place_search_provider.dart
//
// 「地点を追加」の地名検索 (Riverpod)。Figma 修正版 (docs/codex-figma_add-place-
// modal_revision.md) の状態 B0〜B4 に対応する PlaceSearchState を出す。
//
//   B0 未入力        → PlaceSearchIdle
//   B1 候補あり      → PlaceSearchResults
//   B2 検索中        → PlaceSearchLoading
//   B3 0 件          → PlaceSearchNoResults (isKanaOnly なら「漢字かローマ字で」)
//   B4 通信エラー    → PlaceSearchFailure (retry() で再試行)
//
// UI の使い方:
//   final search = ref.watch(placeSearchControllerProvider);           // 状態
//   final ctrl = ref.read(placeSearchControllerProvider.notifier);
//   TextField(onChanged: (_) => ctrl.onQueryChanged(
//       controller.text, isComposing: isImeComposing(controller.value)));
//   onSubmitted → ctrl.submit() / × → ctrl.clear() / 再試行 → ctrl.retry()
//
// - 入力の間引き 300ms。IME の変換中 (未確定文字がある間) は検索しない
// - 新しい入力・clear・cancel・シートを閉じる (autoDispose) で進行中の検索を
//   取り消す (古い結果で表示を上書きしない。通信も打ち切る)
// - 候補の保存済み判定・追加は saved_places_provider.dart
//   (isSavedPlaceProvider(candidate.placeId) / SavedPlacesController.add)
// - 出典の固有名・URL は core/constants/data_attribution.dart

import 'dart:async';

import 'package:flutter/services.dart' show TextEditingValue;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/datasources/geocoding_api_client.dart';
import '../data/models/place_candidate.dart';
import '../data/repositories/place_search_repository.dart';
import '../domain/places/place_search_rules.dart';
import '../presentation/locale/locale_controller.dart';

/// 入力の間引き (最後の入力からこの時間だけ待って検索する)。
const Duration kPlaceSearchDebounce = Duration(milliseconds: 300);

final geocodingApiClientProvider = Provider<GeocodingApiClient>((ref) {
  final client = GeocodingApiClient();
  ref.onDispose(client.dispose);
  return client;
});

final placeSearchRepositoryProvider = Provider<PlaceSearchRepository>((ref) {
  return PlaceSearchRepository(client: ref.watch(geocodingApiClientProvider));
});

/// IME の変換中 (未確定の文字がある) か。変換中は検索しない。
bool isImeComposing(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;

/// 地名検索の状態。[query] は正規化した入力。
sealed class PlaceSearchState {
  const PlaceSearchState(this.query);

  final String query;
}

/// 未入力・検索するには短すぎる入力 (B0)。
final class PlaceSearchIdle extends PlaceSearchState {
  const PlaceSearchIdle([super.query = '']);
}

/// 検索中 (B2)。
final class PlaceSearchLoading extends PlaceSearchState {
  const PlaceSearchLoading(super.query);
}

/// 候補あり (B1)。人口の多い順・最大 10 件。
final class PlaceSearchResults extends PlaceSearchState {
  const PlaceSearchResults(super.query, this.candidates);

  final List<PlaceCandidate> candidates;
}

/// 見つからなかった (B3)。通信は成功している。
final class PlaceSearchNoResults extends PlaceSearchState {
  const PlaceSearchNoResults(super.query, {required this.isKanaOnly});

  /// ひらがな・カタカナだけの入力 (補正しても 0 件のまま)。UI は
  /// 「漢字かローマ字で試してください」と案内する。
  final bool isKanaOnly;
}

/// 検索できなかった (B4。通信エラー・タイムアウトなど)。0 件とは別。
final class PlaceSearchFailure extends PlaceSearchState {
  const PlaceSearchFailure(super.query, this.error);

  /// userMessage は日本語 (UI は ARB の文言を出し、これはログ用に使う)。
  final AppException error;
}

/// 検索の実体 (テストでは差し替える)。
typedef PlaceSearchFunction = Future<List<PlaceCandidate>> Function(
  String query, {
  Future<void>? abortTrigger,
});

class PlaceSearchController extends StateNotifier<PlaceSearchState> {
  PlaceSearchController({
    required PlaceSearchFunction search,
    this.debounce = kPlaceSearchDebounce,
  })  : _search = search,
        super(const PlaceSearchIdle());

  final PlaceSearchFunction _search;

  /// 入力の間引き。
  final Duration debounce;

  Timer? _debounceTimer;
  Completer<void>? _abort;
  int _generation = 0;
  String _query = '';

  /// 入力が変わったとき (TextField.onChanged)。[isComposing] (IME の変換中) の
  /// 間は検索せず、待っている検索も取りやめる (確定後の呼び出しで検索する)。
  void onQueryChanged(String text, {bool isComposing = false}) {
    if (isComposing) {
      _cancelDebounce();
      return;
    }
    final query = normalizePlaceQuery(text);
    // 同じ入力で、検索待ち・検索中・結果表示中なら何もしない。
    if (query == _query &&
        (_debounceTimer != null || state is! PlaceSearchIdle)) {
      return;
    }
    _query = query;
    _cancelDebounce();
    if (!isSearchablePlaceQuery(query)) {
      _cancelInFlight();
      state = PlaceSearchIdle(query);
      return;
    }
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_run(query));
    });
  }

  /// 確定・検索キー (間引きを待たずにすぐ検索する)。
  void submit() {
    _cancelDebounce();
    if (!isSearchablePlaceQuery(_query)) return;
    unawaited(_run(_query));
  }

  /// 再試行 (B4 の「再試行」)。同じ入力でもう一度検索する。
  void retry() => submit();

  /// 待機中・進行中の検索を取り消す (結果は反映しない)。検索中の表示は
  /// 未入力の状態に戻す。
  void cancel() {
    _cancelDebounce();
    _cancelInFlight();
    if (state is PlaceSearchLoading) state = PlaceSearchIdle(_query);
  }

  /// 入力を消した (フィールドの ×)。
  void clear() {
    _cancelDebounce();
    _cancelInFlight();
    _query = '';
    state = const PlaceSearchIdle();
  }

  Future<void> _run(String query) async {
    _cancelInFlight();
    final generation = _generation;
    final abort = _abort = Completer<void>();
    state = PlaceSearchLoading(query);
    try {
      final results = await _search(query, abortTrigger: abort.future);
      if (!_isCurrent(generation)) return;
      state = results.isEmpty
          ? PlaceSearchNoResults(query, isKanaOnly: isKanaOnlyText(query))
          : PlaceSearchResults(query, List.unmodifiable(results));
    } on PlaceSearchCancelledException {
      // 新しい入力・取り消しに置き換わった。
    } on AppException catch (e) {
      if (_isCurrent(generation)) state = PlaceSearchFailure(query, e);
    } catch (e) {
      if (_isCurrent(generation)) {
        state = PlaceSearchFailure(
          query,
          AppException(
            '地名を検索できませんでした。もう一度お試しください。',
            'Place search failed: $e',
            ErrorType.unknown,
          ),
        );
      }
    } finally {
      if (identical(_abort, abort)) _abort = null;
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// 進行中の検索を捨てる (結果を反映しない + 通信を打ち切る)。
  void _cancelInFlight() {
    _generation++;
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  void dispose() {
    _cancelDebounce();
    _cancelInFlight();
    super.dispose();
  }
}

/// 「地点を追加」の地名検索。シートを閉じると破棄され、進行中の検索も取り消す。
/// 検索の言語はアプリの表示言語 (ja / en / zh / es)。
final placeSearchControllerProvider =
    StateNotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(
        (ref) {
  final repository = ref.watch(placeSearchRepositoryProvider);
  return PlaceSearchController(
    search: (query, {abortTrigger}) => repository.search(
      query,
      language: ref.read(localeControllerProvider).languageCode,
      abortTrigger: abortTrigger,
    ),
  );
});
