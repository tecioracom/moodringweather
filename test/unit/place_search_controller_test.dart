// test/unit/place_search_controller_test.dart
//
// 地名検索の状態 (providers/place_search_provider.dart の PlaceSearchController)。
//   - 入力の間引き 300ms
//   - IME の変換中は検索しない
//   - 通信エラー (Failure) と 0 件 (NoResults) を区別する
//   - 取り消し: 新しい入力・clear・cancel・破棄で古い結果を反映しない
// タイマーは testWidgets の擬似時間 (tester.pump) で進める。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/providers/place_search_provider.dart';

const _networkError = AppException(
  'インターネット接続を確認してください。',
  'HTTP 500',
  ErrorType.network,
);

PlaceCandidate _candidate(int id, String name) => PlaceCandidate(
      geocodingId: id,
      name: name,
      sourceName: name,
      latitude: 35,
      longitude: 135,
    );

/// 呼び出しを記録し、応答を Completer で制御できる検索のフェイク。
class _FakeSearch {
  final calls = <String>[];
  final aborts = <Future<void>?>[];
  final _pending = <Completer<List<PlaceCandidate>>>[];

  /// null なら手動で完了させる (complete / fail)。
  List<PlaceCandidate>? autoResult;
  AppException? autoError;

  Future<List<PlaceCandidate>> call(
    String query, {
    Future<void>? abortTrigger,
  }) {
    calls.add(query);
    aborts.add(abortTrigger);
    if (autoError != null) return Future.error(autoError!);
    if (autoResult != null) return Future.value(autoResult);
    final c = Completer<List<PlaceCandidate>>();
    _pending.add(c);
    return c.future;
  }

  void complete(int index, List<PlaceCandidate> result) =>
      _pending[index].complete(result);
}

PlaceSearchController _controller(_FakeSearch search) =>
    PlaceSearchController(search: search.call);

void main() {
  testWidgets('間引き: 最後の入力から 300ms 待って 1 回だけ検索する', (tester) async {
    final search = _FakeSearch()..autoResult = [_candidate(1, '京都')];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京');
    await tester.pump(const Duration(milliseconds: 200));
    c.onQueryChanged('京都');
    await tester.pump(const Duration(milliseconds: 299));
    expect(search.calls, isEmpty);
    expect(c.state, isA<PlaceSearchIdle>());

    await tester.pump(const Duration(milliseconds: 1));
    expect(search.calls, ['京都']);
    expect(c.state, isA<PlaceSearchResults>());
    final results = c.state as PlaceSearchResults;
    expect(results.query, '京都');
    expect(results.candidates.single.name, '京都');
  });

  testWidgets('検索中は Loading、完了で Results', (tester) async {
    final search = _FakeSearch();
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce);
    expect(c.state, isA<PlaceSearchLoading>());
    expect(c.state.query, '京都');

    search.complete(0, [_candidate(1, '京都')]);
    await tester.pump();
    expect(c.state, isA<PlaceSearchResults>());
  });

  testWidgets('IME の変換中は検索しない。確定後に検索する', (tester) async {
    final search = _FakeSearch()..autoResult = [_candidate(1, '京都')];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('きょうと', isComposing: true);
    await tester.pump(const Duration(seconds: 2));
    expect(search.calls, isEmpty);

    c.onQueryChanged('京都'); // 変換を確定
    await tester.pump(kPlaceSearchDebounce);
    expect(search.calls, ['京都']);
  });

  testWidgets('確定済みの検索待ちの後で変換を始めたら、その検索は取りやめる', (tester) async {
    final search = _FakeSearch()..autoResult = const [];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(const Duration(milliseconds: 100));
    c.onQueryChanged('京都おおさか', isComposing: true);
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, isEmpty);
  });

  test('isImeComposing: 未確定の範囲があるときだけ true', () {
    expect(
      isImeComposing(const TextEditingValue(
        text: 'きょうと',
        composing: TextRange(start: 0, end: 4),
      )),
      isTrue,
    );
    expect(isImeComposing(const TextEditingValue(text: '京都')), isFalse);
    expect(
      isImeComposing(const TextEditingValue(
        text: '京都',
        composing: TextRange.collapsed(2),
      )),
      isFalse,
    );
  });

  testWidgets('0 件は NoResults (通信成功)。かなだけの入力は isKanaOnly', (tester) async {
    final search = _FakeSearch()..autoResult = const [];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('きょうと');
    await tester.pump(kPlaceSearchDebounce);
    expect(c.state, isA<PlaceSearchNoResults>());
    expect((c.state as PlaceSearchNoResults).isKanaOnly, isTrue);

    c.onQueryChanged('ゑをん町');
    await tester.pump(kPlaceSearchDebounce);
    expect((c.state as PlaceSearchNoResults).isKanaOnly, isFalse);
  });

  testWidgets('通信エラーは Failure (0 件とは別)。retry で同じ入力を再検索', (tester) async {
    final search = _FakeSearch()..autoError = _networkError;
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce);
    expect(c.state, isA<PlaceSearchFailure>());
    expect((c.state as PlaceSearchFailure).error.type, ErrorType.network);

    search
      ..autoError = null
      ..autoResult = [_candidate(1, '京都')];
    c.retry();
    await tester.pump();
    expect(search.calls, ['京都', '京都']);
    expect(c.state, isA<PlaceSearchResults>());
  });

  testWidgets('取り消し: 新しい入力に置き換わった古い結果は反映しない (通信も打ち切る)', (tester) async {
    final search = _FakeSearch();
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce); // 京都 を検索中
    c.onQueryChanged('大阪');
    await tester.pump(kPlaceSearchDebounce); // 大阪 を検索中 (京都 は取り消し)

    // 京都 の abortTrigger は完了している (IOClient なら通信を打ち切る)
    var aborted = false;
    unawaited(search.aborts[0]!.then((_) => aborted = true));
    await tester.pump();
    expect(aborted, isTrue);

    search.complete(1, [_candidate(2, '大阪')]);
    await tester.pump();
    search.complete(0, [_candidate(1, '京都')]); // 遅れて届いた古い結果
    await tester.pump();

    final state = c.state as PlaceSearchResults;
    expect(state.query, '大阪');
    expect(state.candidates.single.name, '大阪');
  });

  testWidgets('clear: 未入力に戻し、進行中の結果は反映しない', (tester) async {
    final search = _FakeSearch();
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce);
    c.clear();
    expect(c.state, isA<PlaceSearchIdle>());
    expect(c.state.query, '');

    search.complete(0, [_candidate(1, '京都')]);
    await tester.pump();
    expect(c.state, isA<PlaceSearchIdle>());
  });

  testWidgets('cancel: 待機中の検索を取りやめる', (tester) async {
    final search = _FakeSearch()..autoResult = const [];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(const Duration(milliseconds: 100));
    c.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, isEmpty);
  });

  testWidgets('submit: 間引きを待たずにすぐ検索する', (tester) async {
    final search = _FakeSearch()..autoResult = [_candidate(1, '京都')];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    c.submit();
    await tester.pump();
    expect(search.calls, ['京都']);
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, ['京都']); // 間引きの分は二重に走らない
  });

  testWidgets('短すぎる入力 (1 文字の英字・空) は検索せず未入力扱い', (tester) async {
    final search = _FakeSearch()..autoResult = const [];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('K');
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, isEmpty);
    expect(c.state, isA<PlaceSearchIdle>());

    c.onQueryChanged('  ');
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, isEmpty);
  });

  testWidgets('同じ入力が再び届いても検索し直さない (結果を保つ)', (tester) async {
    final search = _FakeSearch()..autoResult = [_candidate(1, '京都')];
    final c = _controller(search);
    addTearDown(c.dispose);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce);
    c.onQueryChanged('京都 '); // 正規化すると同じ
    await tester.pump(const Duration(seconds: 1));
    expect(search.calls, ['京都']);
    expect(c.state, isA<PlaceSearchResults>());
  });

  testWidgets('破棄 (シートを閉じる) で進行中の検索を打ち切る', (tester) async {
    final search = _FakeSearch();
    final c = _controller(search);

    c.onQueryChanged('京都');
    await tester.pump(kPlaceSearchDebounce);
    c.dispose();

    var aborted = false;
    unawaited(search.aborts.single!.then((_) => aborted = true));
    await tester.pump();
    expect(aborted, isTrue);
    // 破棄後に結果が届いても例外にならない
    search.complete(0, [_candidate(1, '京都')]);
    await tester.pump();
  });
}
