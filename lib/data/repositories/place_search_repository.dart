// lib/data/repositories/place_search_repository.dart
//
// 地名検索の窓口 (data 層)。入力 1 回につき、補正した名前を含む複数の
// 問い合わせを**並行して**投げ、domain のルールで合わせて並べる
// (domain/places/place_search_rules.dart の PlaceQueryPlan / rankPlaceCandidates)。
//
// 戻り値:
//   - 候補のリスト (0 件なら空。空は「見つからなかった」)
//   - 通信失敗は AppException (どれか 1 つでも失敗したら全体を失敗にする。
//     本命を引く問い合わせだけが落ちたときに「0 件」と誤って見せないため)
//   - 取り消しは PlaceSearchCancelledException

import '../../domain/places/place_search_rules.dart';
import '../datasources/geocoding_api_client.dart';
import '../models/place_candidate.dart';

class PlaceSearchRepository {
  PlaceSearchRepository({required GeocodingApiClient client})
      : _client = client;

  final GeocodingApiClient _client;

  /// [input] を検索する。[language] は小文字の ISO 639-1 (アプリの表示言語)。
  Future<List<PlaceCandidate>> search(
    String input, {
    required String language,
    Future<void>? abortTrigger,
  }) async {
    final plan = PlaceQueryPlan.forInput(input);
    if (!plan.isSearchable) return const [];

    final batches = await Future.wait([
      for (final query in plan.queries)
        _client.search(
          query,
          language: language,
          count: kPlaceSearchMaxResults,
          abortTrigger: abortTrigger,
        ),
    ]);
    return rankPlaceCandidates(
      plan: plan,
      batches: batches,
      language: language,
    );
  }
}
