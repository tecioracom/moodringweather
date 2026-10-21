// lib/domain/places/place_search_rules.dart
//
// 地名検索の補正ルール (純 Dart・Flutter 非依存)。
// ユニットテスト: test/unit/place_search_rules_test.dart /
//                 test/unit/place_search_repository_test.dart
//
// Open-Meteo Geocoding (= GeoNames) の実測 (2026-09-28、language=ja、count=10):
//   京都 0 / 京都市 1 / 東京 0 / 東京都 1 / 大阪 0 / 大阪市 1 / 札幌 0 /
//   札幌市 1 / 那覇 0 / 那覇市 1 / Kyoto 5 / 新宿 10 / きょうと 0
//   神戸 6・横浜 4・福岡 8 は**同名の小集落だけ**が返り、本命 (神戸市・
//   横浜市・福岡市) は「市」を付けた名前でしか出てこない。
//   → 漢字だけの入力は「市」「都」「町」「村」を補った名前も**並行して**引き、
//     合わせて人口の多い順に並べる (0 件のときだけ補うと神戸・横浜・福岡で
//     本命が出ない。順番に引くと往復が 2 回になり体感が遅い)。
//   「府」「県」は補わない: 都道府県は GeoNames では行政区 (ADM1) で居住地
//   (PPL*) ではないため候補にならない (京都府 0 / 大阪府 0 / 沖縄県 0 /
//   神奈川県 0 / 奈良県 0 / 福岡県 = 公園のみ)。代わりに「京都府」「福岡県」の
//   ような入力は「京都市」「福岡市」も引く。
//   ひらがな・カタカナだけの入力は補正しない (きょうと 0 のまま。UI で
//   「漢字かローマ字で」と案内する)。

import '../../data/models/place_candidate.dart';

/// 1 回の検索で返す候補の上限 (API の count と同じ)。
const int kPlaceSearchMaxResults = 10;

/// 漢字だけの入力に補う接尾辞 (この順で並行して引く)。
const List<String> kHanPlaceSuffixes = ['市', '都', '町', '村'];

/// 補って見つけた名前から外してよい接尾辞 (京都市 → 京都、東京都 → 東京)。
/// 町・村は外さない: 「神戸町」は岐阜県の別の町 (ごうどちょう) で、外すと
/// 神戸市と紛れる。「箱根町」「白馬村」はそのまま出す。
const List<String> kStrippablePlaceSuffixes = ['市', '都'];

/// 都道府県の接尾辞。「京都府」「福岡県」「東京都」の入力は語幹 +「市」も引く。
const List<String> kPrefectureSuffixes = ['府', '県', '都'];

/// 現存しない居住地の feature code (歴史的・廃村・消滅・旧首都)。
const Set<String> _kGonePlaceCodes = {'PPLH', 'PPLQ', 'PPLW', 'PPLCH'};

/// 地点そのものが自治体・首都の中心である feature code。地域行に市区町村を
/// 重ねて出さない (京都市 → 「京都府・日本」)。
const Set<String> _kSeatPlaceCodes = {'PPLC', 'PPLA', 'PPLA2'};

/// 入力を検索用に整える。前後の空白を除き、全角英数記号・全角空白を半角に、
/// 連続する空白を 1 つにする (日本語 IME の全角ローマ字「Ｋｙｏｔｏ」対策)。
String normalizePlaceQuery(String input) {
  final buf = StringBuffer();
  for (final r in input.runes) {
    if (r == 0x3000) {
      buf.writeCharCode(0x20);
    } else if (r >= 0xFF01 && r <= 0xFF5E) {
      buf.writeCharCode(r - 0xFEE0);
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool _isHanRune(int r) =>
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0x20000 && r <= 0x2FA1F) ||
    r == 0x3005 || // 々
    r == 0x3006; // 〆

/// 漢字の地名に混ざる小さなカナ (茅ヶ崎・鶴ヶ島・霞ケ関)。
bool _isHanCompanionRune(int r) =>
    r == 0x30F6 || // ヶ
    r == 0x30F5 || // ヵ
    r == 0x30B1; // ケ

bool _isKanaRune(int r) =>
    (r >= 0x3041 && r <= 0x309F) || // ひらがな
    (r >= 0x30A0 && r <= 0x30FF) || // カタカナ (ー を含む)
    (r >= 0x31F0 && r <= 0x31FF) || // カタカナ拡張
    (r >= 0xFF66 && r <= 0xFF9F); // 半角カナ

/// 漢字 (と地名に混ざる「ヶ」など) だけでできているか。1 字以上の漢字を含む。
bool isHanOnlyText(String text) {
  var hasHan = false;
  for (final r in text.runes) {
    if (_isHanRune(r)) {
      hasHan = true;
    } else if (!_isHanCompanionRune(r)) {
      return false;
    }
  }
  return hasHan;
}

/// ひらがな・カタカナだけか (空白は無視)。0 件のとき UI が
/// 「漢字かローマ字で試してください」と案内する判断材料。
bool isKanaOnlyText(String text) {
  var hasKana = false;
  for (final r in text.runes) {
    if (r == 0x20 || r == 0x3000) continue;
    if (!_isKanaRune(r)) return false;
    hasKana = true;
  }
  return hasKana;
}

/// 検索を投げる価値のある入力か。API は 1 文字の英字などを空で返すため、
/// 漢字以外は 2 文字から。漢字は 1 文字でも引ける (津 → 津市)。
bool isSearchablePlaceQuery(String normalized) {
  if (normalized.isEmpty) return false;
  if (isHanOnlyText(normalized)) return true;
  return normalized.runes.length >= 2;
}

/// 1 回の入力に対して API へ投げる名前の一覧 (先頭が入力そのもの)。
class PlaceQueryPlan {
  const PlaceQueryPlan._({
    required this.input,
    required this.queries,
    required this.strippedNames,
  });

  factory PlaceQueryPlan.forInput(String rawInput) {
    final input = normalizePlaceQuery(rawInput);
    if (!isSearchablePlaceQuery(input)) {
      return PlaceQueryPlan._(
        input: input,
        queries: const [],
        strippedNames: const {},
      );
    }
    if (!isHanOnlyText(input)) {
      return PlaceQueryPlan._(
        input: input,
        queries: [input],
        strippedNames: const {},
      );
    }

    final runes = input.runes.toList();
    final last = String.fromCharCode(runes.last);
    final queries = <String>[input];
    final stripped = <String, String>{};
    if (runes.length >= 3 && kPrefectureSuffixes.contains(last)) {
      // 「京都府」「福岡県」「東京都」→ 語幹 +「市」も引く (京都市 → 京都)。
      final stem = String.fromCharCodes(runes.sublist(0, runes.length - 1));
      queries.add('$stem市');
      stripped['$stem市'] = stem;
    } else {
      for (final suffix in kHanPlaceSuffixes) {
        queries.add('$input$suffix');
      }
    }
    for (final suffix in kStrippablePlaceSuffixes) {
      stripped.putIfAbsent('$input$suffix', () => input);
    }
    return PlaceQueryPlan._(
      input: input,
      queries: [
        for (final q in {...queries}) q,
      ],
      strippedNames: stripped,
    );
  }

  /// 正規化した入力。
  final String input;

  /// API に投げる名前。空なら検索しない (未入力・1 文字の英字など)。
  final List<String> queries;

  /// 補った名前 → 表示名 (京都市 → 京都)。
  final Map<String, String> strippedNames;

  bool get isSearchable => queries.isNotEmpty;

  /// [index] 番目の問い合わせが補正 (入力そのものではない) か。
  bool isVariantAt(int index) => index > 0;
}

/// 居住地 (populated place = GeoNames の PPL*) か。歴史的・廃村・消滅は除く。
/// 空港 (AIRP)・公園 (PRK)・島 (ISL)・山 (MT) などは候補にしない。
bool isInhabitedPlace(String? featureCode) {
  if (featureCode == null || !featureCode.startsWith('PPL')) return false;
  return !_kGonePlaceCodes.contains(featureCode);
}

/// 候補の表示名。
///
/// 1. 補った「市」「都」を外す (入力「京都」→「京都市」→「京都」、
///    入力「京都府」→「京都市」→「京都」、入力「四日市」→「四日市市」→「四日市」)。
/// 2. 日本語表示の日本の県庁所在地・首都 (PPLA / PPLC) は末尾の「市」「都」を
///    外す (「Kyoto」で引いた「京都市」→「京都」、入力「東京都」→「東京」)。
///    3 文字以上に限る (「津市」は「津」にしない)。
String displayPlaceName(
  GeocodingHit hit, {
  required PlaceQueryPlan plan,
  required String language,
}) {
  final name = hit.name;
  final stripped = plan.strippedNames[name];
  if (stripped != null) return stripped;

  final isSeat = hit.featureCode == 'PPLA' || hit.featureCode == 'PPLC';
  if (language == 'ja' && hit.countryCode == 'JP' && isSeat) {
    final runes = name.runes.toList();
    if (runes.length >= 3 &&
        kStrippablePlaceSuffixes.contains(String.fromCharCode(runes.last))) {
      return String.fromCharCodes(runes.sublist(0, runes.length - 1));
    }
  }
  return name;
}

/// 同名地点を見分けるための市区町村 (新宿区 / 神川町 / 横浜市保土ヶ谷区)。
///
/// - **日本の地点だけ**。海外の admin2 / admin3 は郡・タウンシップ・地区
///   (Township of Center / Muleba District Council …) で地域行を長くするだけ
///   なので出さない (Figma EN: 「Springfield / Missouri, United States」
///   「Kyoto / Kagera, Tanzania」= 州・国のみ)。
/// - 地点そのものが市・首都・県庁所在地 (PPLC / PPLA / PPLA2) なら出さない。
/// - GeoNames の日本の admin2 は市・郡・特別区、admin3 は区・町・村。
///   郡の下の町村は admin3 を、政令市の区は「市 + 区」を出す。
/// - 名前・都道府県・国と同じなら出さない。
String? municipalityOf(GeocodingHit hit) {
  if (hit.countryCode != 'JP') return null;
  if (_kSeatPlaceCodes.contains(hit.featureCode)) return null;
  final admin2 = hit.admin2;
  final admin3 = hit.admin3;
  String? municipality;
  if (admin2 != null &&
      admin3 != null &&
      admin2.endsWith('市') &&
      admin3.endsWith('区')) {
    municipality = '$admin2$admin3';
  } else {
    municipality = admin3 ?? admin2;
  }
  if (municipality == null) return null;
  if (municipality == hit.name ||
      municipality == hit.admin1 ||
      municipality == hit.country) {
    return null;
  }
  return municipality;
}

/// 各問い合わせの結果 ([batches] は [plan].queries と同じ順) を合わせて、
/// 候補行に出す順に並べる。
///
/// - 居住地 (PPL*) だけに絞る。
/// - 補った名前の結果は「その名前そのもの」だけ採る (「福岡町」で返る
///   「福岡町蓑島」のような別地点を混ぜない)。
/// - 同じ地点 (GeoNames id) は 1 件にまとめる。
/// - 人口の多い順。人口が無い地点は後ろに、元の順 (入力そのものの結果が先)
///   を保つ。上限 [limit] 件。
/// - 表示名も地域行 (市区町村・都道府県・国) も同じ候補は、見分けがつかないので
///   先の 1 件 (人口の多い方 / 元の順で先) だけを残す (QA-08: 「横浜 / 天草市・
///   熊本県・日本」が GeoNames の別 id で 2 行並んでいた)。上限は重複を除いた後に
///   数える。
List<PlaceCandidate> rankPlaceCandidates({
  required PlaceQueryPlan plan,
  required List<List<GeocodingHit>> batches,
  required String language,
  int limit = kPlaceSearchMaxResults,
}) {
  final seen = <int>{};
  final merged = <GeocodingHit>[];
  for (var i = 0; i < batches.length && i < plan.queries.length; i++) {
    final query = plan.queries[i];
    for (final hit in batches[i]) {
      if (!isInhabitedPlace(hit.featureCode)) continue;
      if (plan.isVariantAt(i) && hit.name != query) continue;
      if (!seen.add(hit.id)) continue;
      merged.add(hit);
    }
  }

  final order = [for (var i = 0; i < merged.length; i++) i];
  order.sort((a, b) {
    final pa = merged[a].population ?? -1;
    final pb = merged[b].population ?? -1;
    if (pa != pb) return pb.compareTo(pa);
    return a.compareTo(b); // 安定 (List.sort は安定ソートを保証しない)
  });

  final candidates = <PlaceCandidate>[];
  final shownRows = <String>{};
  for (final i in order) {
    if (candidates.length >= limit) break;
    final candidate = PlaceCandidate(
      geocodingId: merged[i].id,
      name: displayPlaceName(merged[i], plan: plan, language: language),
      sourceName: merged[i].name,
      latitude: merged[i].latitude,
      longitude: merged[i].longitude,
      featureCode: merged[i].featureCode,
      municipality: municipalityOf(merged[i]),
      admin1: merged[i].admin1,
      country: merged[i].country,
      countryCode: merged[i].countryCode,
      timezone: merged[i].timezone,
      population: merged[i].population,
    );
    if (!shownRows.add(_candidateRowKey(candidate))) continue;
    candidates.add(candidate);
  }
  return candidates;
}

/// 候補行の見た目 (表示名 + 地域行)。これが同じ候補は利用者には区別できない。
String _candidateRowKey(PlaceCandidate candidate) =>
    [candidate.name, ...candidate.regionParts].join('\u0000');
