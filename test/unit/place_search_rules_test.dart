// test/unit/place_search_rules_test.dart
//
// 地名検索の補正ルール (domain/places/place_search_rules.dart) の純ロジック。
// 実 API を使った受け入れ基準は place_search_repository_test.dart。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/domain/places/place_search_rules.dart';

GeocodingHit _hit({
  int id = 1,
  String name = '京都市',
  String? featureCode = 'PPLA',
  String? countryCode = 'JP',
  String? country = '日本',
  String? admin1 = '京都府',
  String? admin2,
  String? admin3,
  int? population,
}) {
  return GeocodingHit(
    id: id,
    name: name,
    latitude: 35.0,
    longitude: 135.7,
    featureCode: featureCode,
    countryCode: countryCode,
    country: country,
    admin1: admin1,
    admin2: admin2,
    admin3: admin3,
    timezone: 'Asia/Tokyo',
    population: population,
  );
}

void main() {
  group('normalizePlaceQuery', () {
    test('前後の空白を除き、全角英数・全角空白を半角にし、連続空白を 1 つに', () {
      expect(normalizePlaceQuery('  京都　'), '京都');
      expect(normalizePlaceQuery('Ｋｙｏｔｏ'), 'Kyoto');
      expect(normalizePlaceQuery('San　 Francisco'), 'San Francisco');
      expect(normalizePlaceQuery(''), '');
    });
  });

  group('文字種の判定', () {
    test('isHanOnlyText: 漢字 (と地名に混ざる ヶ) だけ', () {
      expect(isHanOnlyText('京都'), isTrue);
      expect(isHanOnlyText('京都市'), isTrue);
      expect(isHanOnlyText('茅ヶ崎'), isTrue);
      expect(isHanOnlyText('津'), isTrue);
      expect(isHanOnlyText('きょうと'), isFalse);
      expect(isHanOnlyText('Kyoto'), isFalse);
      expect(isHanOnlyText('京 都'), isFalse);
      expect(isHanOnlyText('ヶ'), isFalse); // 漢字を含まない
      expect(isHanOnlyText(''), isFalse);
    });

    test('isKanaOnlyText: ひらがな・カタカナだけ', () {
      expect(isKanaOnlyText('きょうと'), isTrue);
      expect(isKanaOnlyText('リスボン'), isTrue);
      expect(isKanaOnlyText('レイキャビク'), isTrue);
      expect(isKanaOnlyText('京都'), isFalse);
      expect(isKanaOnlyText('Kyoto'), isFalse);
      expect(isKanaOnlyText(''), isFalse);
    });

    test('isSearchablePlaceQuery: 漢字は 1 文字から、それ以外は 2 文字から', () {
      expect(isSearchablePlaceQuery(''), isFalse);
      expect(isSearchablePlaceQuery('K'), isFalse); // API は 1 文字を空で返す
      expect(isSearchablePlaceQuery('き'), isFalse);
      expect(isSearchablePlaceQuery('Ky'), isTrue);
      expect(isSearchablePlaceQuery('津'), isTrue); // 津 → 津市
    });
  });

  group('PlaceQueryPlan.forInput', () {
    test('漢字だけの入力は 市・都・町・村 を補った名前も引く (府・県は補わない)', () {
      final plan = PlaceQueryPlan.forInput('京都');
      expect(plan.queries, ['京都', '京都市', '京都都', '京都町', '京都村']);
      expect(plan.isSearchable, isTrue);
      expect(plan.strippedNames['京都市'], '京都');
      expect(plan.strippedNames['京都都'], '京都');
      // 町・村は表示名から外さない (神戸町は別の町)
      expect(plan.strippedNames.containsKey('京都町'), isFalse);
    });

    test('「京都府」「福岡県」「東京都」は語幹 +「市」も引く', () {
      expect(PlaceQueryPlan.forInput('京都府').queries, ['京都府', '京都市']);
      expect(PlaceQueryPlan.forInput('福岡県').queries, ['福岡県', '福岡市']);
      expect(PlaceQueryPlan.forInput('東京都').queries, ['東京都', '東京市']);
      expect(PlaceQueryPlan.forInput('京都府').strippedNames['京都市'], '京都');
    });

    test('2 文字の「京都」は都道府県扱いしない (京 + 市 にしない)', () {
      expect(PlaceQueryPlan.forInput('京都').queries.first, '京都');
      expect(PlaceQueryPlan.forInput('京都').queries, isNot(contains('京市')));
    });

    test('ローマ字・かなは補正しない (入力そのものだけ)', () {
      expect(PlaceQueryPlan.forInput('Kyoto').queries, ['Kyoto']);
      expect(PlaceQueryPlan.forInput('きょうと').queries, ['きょうと']);
      expect(PlaceQueryPlan.forInput('リスボン').queries, ['リスボン']);
    });

    test('検索しない入力 (空・1 文字の英字) は問い合わせ 0', () {
      expect(PlaceQueryPlan.forInput('').isSearchable, isFalse);
      expect(PlaceQueryPlan.forInput('  ').isSearchable, isFalse);
      expect(PlaceQueryPlan.forInput('K').queries, isEmpty);
    });

    test('入力は正規化してから組み立てる', () {
      expect(PlaceQueryPlan.forInput(' 那覇 ').input, '那覇');
      expect(PlaceQueryPlan.forInput('Ｎａｈａ').queries, ['Naha']);
    });
  });

  group('isInhabitedPlace (居住地 PPL* だけ)', () {
    test('現存する居住地は採る', () {
      for (final code in ['PPL', 'PPLA', 'PPLA2', 'PPLC', 'PPLX', 'PPLL']) {
        expect(isInhabitedPlace(code), isTrue, reason: code);
      }
    });

    test('歴史的・廃村・消滅と、空港・公園・島・山は採らない', () {
      for (final code in [
        'PPLH',
        'PPLQ',
        'PPLW',
        'PPLCH',
        'AIRP',
        'AIRH',
        'PRK',
        'ISL',
        'MT',
        null,
      ]) {
        expect(isInhabitedPlace(code), isFalse, reason: '$code');
      }
    });
  });

  group('displayPlaceName (表示名の正規化)', () {
    test('補った「市」を外す: 入力「京都」→「京都市」→「京都」', () {
      final plan = PlaceQueryPlan.forInput('京都');
      expect(displayPlaceName(_hit(), plan: plan, language: 'ja'), '京都');
    });

    test('補った「都」を外す: 入力「東京」→「東京都」→「東京」', () {
      final plan = PlaceQueryPlan.forInput('東京');
      final hit = _hit(name: '東京都', featureCode: 'PPLC', admin1: '東京都');
      expect(displayPlaceName(hit, plan: plan, language: 'ja'), '東京');
    });

    test('入力「四日市」→「四日市市」(PPLA2) →「四日市」', () {
      final plan = PlaceQueryPlan.forInput('四日市');
      final hit = _hit(name: '四日市市', featureCode: 'PPLA2', admin1: '三重県');
      expect(displayPlaceName(hit, plan: plan, language: 'ja'), '四日市');
    });

    test('日本語表示の県庁所在地・首都は入力がローマ字でも「市」「都」を外す', () {
      final plan = PlaceQueryPlan.forInput('Kyoto');
      expect(displayPlaceName(_hit(), plan: plan, language: 'ja'), '京都');
      final tokyo = _hit(name: '東京都', featureCode: 'PPLC', admin1: '東京都');
      expect(
        displayPlaceName(
          tokyo,
          plan: PlaceQueryPlan.forInput('東京都'),
          language: 'ja',
        ),
        '東京',
      );
    });

    test('2 文字の「津市」は「津」にしない (入力が「津」なら外す)', () {
      final hit = _hit(name: '津市', admin1: '三重県');
      expect(
        displayPlaceName(hit,
            plan: PlaceQueryPlan.forInput('Tsu'), language: 'ja'),
        '津市',
      );
      expect(
        displayPlaceName(hit,
            plan: PlaceQueryPlan.forInput('津'), language: 'ja'),
        '津',
      );
    });

    test('町・村は外さない (神戸町は岐阜県の別の町)', () {
      final hit = _hit(
        name: '神戸町',
        featureCode: 'PPL',
        admin1: '岐阜県',
        admin2: '安八郡',
        admin3: '神戸町',
      );
      expect(
        displayPlaceName(hit,
            plan: PlaceQueryPlan.forInput('神戸'), language: 'ja'),
        '神戸町',
      );
    });

    test('日本以外の「〜特別市」や他言語はそのまま', () {
      final seoul = _hit(
        name: 'ソウル特別市',
        featureCode: 'PPLC',
        countryCode: 'KR',
        admin1: 'ソウル特別市',
      );
      expect(
        displayPlaceName(seoul,
            plan: PlaceQueryPlan.forInput('ソウル'), language: 'ja'),
        'ソウル特別市',
      );
      // 中国語表示は入力に補った「市」だけ外す
      final osakaZh = _hit(name: '大阪市', admin1: '大阪府');
      expect(
        displayPlaceName(osakaZh,
            plan: PlaceQueryPlan.forInput('大阪'), language: 'zh'),
        '大阪',
      );
      expect(
        displayPlaceName(osakaZh,
            plan: PlaceQueryPlan.forInput('Osaka'), language: 'zh'),
        '大阪市',
      );
    });
  });

  group('municipalityOf (同名地点を見分ける市区町村)', () {
    test('特別区の中の地点は区 (新宿 → 新宿区)', () {
      final hit = _hit(
        name: '新宿',
        featureCode: 'PPLX',
        admin1: '東京都',
        admin2: '新宿区',
      );
      expect(municipalityOf(hit), '新宿区');
    });

    test('郡の下の町村は admin3 (新宿 → 神川町)', () {
      final hit = _hit(
        name: '新宿',
        featureCode: 'PPL',
        admin1: '埼玉県',
        admin2: '児玉郡',
        admin3: '神川町',
      );
      expect(municipalityOf(hit), '神川町');
    });

    test('政令市の区は「市 + 区」', () {
      final hit = _hit(
        name: '神戸町',
        featureCode: 'PPL',
        admin1: '神奈川県',
        admin2: '横浜市',
        admin3: '保土ヶ谷区',
      );
      expect(municipalityOf(hit), '横浜市保土ヶ谷区');
    });

    test('地点そのものが市・首都・県庁所在地なら出さない', () {
      expect(municipalityOf(_hit(admin2: '京都市', admin3: '上京区')), isNull);
      expect(
        municipalityOf(_hit(
          name: '四日市市',
          featureCode: 'PPLA2',
          admin2: '四日市市',
        )),
        isNull,
      );
    });

    test('海外の地点は出さない (郡・タウンシップで地域行を長くしない)', () {
      final hit = _hit(
        name: 'Lisbon',
        featureCode: 'PPL',
        countryCode: 'US',
        country: 'United States',
        admin1: 'Ohio',
        admin2: 'Columbiana',
        admin3: 'Township of Center',
      );
      expect(municipalityOf(hit), isNull);
    });

    test('名前・都道府県と同じなら出さない', () {
      expect(
        municipalityOf(_hit(name: '逗子', featureCode: 'PPL', admin2: '逗子')),
        isNull,
      );
      expect(
        municipalityOf(_hit(featureCode: 'PPL', admin1: '東京都', admin2: '東京都')),
        isNull,
      );
    });
  });

  group('rankPlaceCandidates', () {
    test('人口の多い順。人口不明は後ろで元の順を保つ', () {
      final plan = PlaceQueryPlan.forInput('横浜');
      // 同名の小集落 (市区町村で見分けられる)。
      final raw = [
        _hit(
            id: 1,
            name: '横浜',
            featureCode: 'PPL',
            admin1: '青森県',
            admin2: '上北郡',
            admin3: '横浜町',
            population: 4412),
        _hit(
            id: 2,
            name: '横浜',
            featureCode: 'PPLX',
            admin1: '熊本県',
            admin2: '天草市'),
        _hit(
            id: 3,
            name: '横浜',
            featureCode: 'PPLL',
            admin1: '熊本県',
            admin2: '上天草市'),
      ];
      final city = [
        _hit(id: 10, name: '横浜市', admin1: '神奈川県', population: 3777491),
      ];
      final ranked = rankPlaceCandidates(
        plan: plan,
        batches: [raw, city, const [], const [], const []],
        language: 'ja',
      );
      expect(ranked.map((c) => c.geocodingId), [10, 1, 2, 3]);
      expect(ranked.first.name, '横浜');
      expect(ranked.first.regionParts, ['神奈川県', '日本']);
    });

    test('補った名前の結果は同じ名前だけ採る (福岡町蓑島 は混ぜない)', () {
      final plan = PlaceQueryPlan.forInput('福岡');
      final ranked = rankPlaceCandidates(
        plan: plan,
        batches: [
          const [],
          [_hit(id: 5, name: '福岡市', admin1: '福岡県', population: 1612392)],
          const [],
          [_hit(id: 6, name: '福岡町蓑島', featureCode: 'PPL')],
          const [],
        ],
        language: 'ja',
      );
      expect(ranked.map((c) => c.geocodingId), [5]);
    });

    test('居住地以外 (公園・空港) は除き、同じ地点は 1 件にまとめる', () {
      final plan = PlaceQueryPlan.forInput('奈良');
      final nara = _hit(id: 7, name: '奈良', admin1: '奈良県', population: 367353);
      final ranked = rankPlaceCandidates(
        plan: plan,
        batches: [
          [nara, _hit(id: 8, name: '奈良公園', featureCode: 'PRK')],
          [nara], // 「奈良市」の問い合わせでも同じ地点が返る
          const [],
          const [],
          const [],
        ],
        language: 'ja',
      );
      expect(ranked.map((c) => c.geocodingId), [7]);
    });

    test('上限 10 件', () {
      final plan = PlaceQueryPlan.forInput('Lisbon');
      final ranked = rankPlaceCandidates(
        plan: plan,
        batches: [
          [
            for (var i = 0; i < 15; i++)
              _hit(
                id: 100 + i,
                name: 'Lisbon',
                featureCode: 'PPL',
                countryCode: 'US',
                country: 'United States',
                admin1: 'State $i',
              ),
          ],
        ],
        language: 'en',
      );
      expect(ranked, hasLength(kPlaceSearchMaxResults));
      expect(ranked.first.geocodingId, 100);
    });

    // QA-08: 「横浜」の 4・5 件目がどちらも「横浜 / 天草市・熊本県・日本」
    // (GeoNames id 11247763 / 11265390) で、利用者には区別できなかった。
    group('表示名も地域行も同じ候補は 1 行にまとめる (QA-08)', () {
      GeocodingHit amakusa(int id, {int? population}) => _hit(
            id: id,
            name: '横浜',
            featureCode: 'PPLL',
            admin1: '熊本県',
            admin2: '天草市',
            population: population,
          );

      test('先の 1 件 (人口の多い方) だけを残す', () {
        final plan = PlaceQueryPlan.forInput('横浜');
        final ranked = rankPlaceCandidates(
          plan: plan,
          batches: [
            [amakusa(11247763), amakusa(11265390, population: 120)],
            [_hit(id: 10, name: '横浜市', admin1: '神奈川県', population: 3777491)],
            const [],
            const [],
            const [],
          ],
          language: 'ja',
        );
        expect(ranked.map((c) => c.geocodingId), [10, 11265390]);
        expect(ranked.last.regionParts, ['天草市', '熊本県', '日本']);
      });

      test('人口が同じ (不明) なら元の順で先の方', () {
        final ranked = rankPlaceCandidates(
          plan: PlaceQueryPlan.forInput('横浜'),
          batches: [
            [amakusa(11247763), amakusa(11265390)],
            const [],
            const [],
            const [],
            const [],
          ],
          language: 'ja',
        );
        expect(ranked.map((c) => c.geocodingId), [11247763]);
      });

      test('名前が同じでも市区町村が違えば両方出す', () {
        final ranked = rankPlaceCandidates(
          plan: PlaceQueryPlan.forInput('新宿'),
          batches: [
            [
              _hit(
                  id: 1,
                  name: '新宿',
                  featureCode: 'PPL',
                  admin1: '東京都',
                  admin2: '新宿区'),
              _hit(
                  id: 2,
                  name: '新宿',
                  featureCode: 'PPL',
                  admin1: '埼玉県',
                  admin2: '児玉郡',
                  admin3: '神川町'),
            ],
            const [],
            const [],
            const [],
            const [],
          ],
          language: 'ja',
        );
        expect(ranked.map((c) => c.geocodingId), [1, 2]);
      });

      test('上限 10 件は重複をまとめた後に数える', () {
        final plan = PlaceQueryPlan.forInput('Springfield');
        final ranked = rankPlaceCandidates(
          plan: plan,
          batches: [
            [
              // 同じ州に同じ表示の 2 件 (Missouri、別の id) + 別の州 10 件
              for (final id in [901, 902])
                _hit(
                  id: id,
                  name: 'Springfield',
                  featureCode: 'PPL',
                  countryCode: 'US',
                  country: 'United States',
                  admin1: 'Missouri',
                ),
              for (var i = 0; i < 10; i++)
                _hit(
                  id: 100 + i,
                  name: 'Springfield',
                  featureCode: 'PPL',
                  countryCode: 'US',
                  country: 'United States',
                  admin1: 'State $i',
                ),
            ],
          ],
          language: 'en',
        );
        expect(ranked, hasLength(kPlaceSearchMaxResults));
        final rows = {
          for (final c in ranked) '${c.name}|${c.regionParts.join(', ')}',
        };
        expect(rows, hasLength(ranked.length));
      });
    });

    test('候補は保存地点 ID (place-geo-{id}) と位置情報を持つ', () {
      final ranked = rankPlaceCandidates(
        plan: PlaceQueryPlan.forInput('京都'),
        batches: [
          const [],
          [_hit(id: 1857910, admin2: '京都市', admin3: '上京区', population: 1)],
          const [],
          const [],
          const [],
        ],
        language: 'ja',
      );
      final c = ranked.single;
      expect(c.placeId, 'place-geo-1857910');
      expect(c.sourceName, '京都市');
      expect(c.name, '京都');
      final location = c.toLocation();
      expect(location.geocodingId, 1857910);
      expect(location.timezone, 'Asia/Tokyo');
      expect(location.regionParts, ['京都府', '日本']);
    });
  });
}
