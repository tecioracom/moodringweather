// test/unit/place_search_repository_test.dart
//
// 地名検索の受け入れ基準 (Open-Meteo Geocoding の実応答フィクスチャで再現)。
//
// 実測 (2026-09-28、language=ja): 京都 0 / 京都市 1 / 東京 0 / 那覇 0 / Kyoto 5 /
// 新宿 10。神戸・横浜・福岡は同名の小集落だけが返り、本命は「市」付きでしか出ない。
// 受け入れ基準: 京都・東京・大阪・札幌・那覇・神戸・横浜・福岡で本命が 1 件目。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/geocoding_api_client.dart';
import 'package:mood_ring_weather/data/repositories/place_search_repository.dart';

import '../fixtures/geocoding_fixture_server.dart';

void main() {
  late GeocodingFixtureServer server;
  late PlaceSearchRepository repository;

  setUp(() {
    server = GeocodingFixtureServer();
    repository = PlaceSearchRepository(
      client: GeocodingApiClient(httpClient: server.client),
    );
  });

  tearDown(() {
    // フィクスチャの無い問い合わせをしていないこと (テストデータの取りこぼし防止)。
    expect(server.missing, isEmpty);
  });

  group('受け入れ基準: 漢字 2 文字の和名で本命が 1 件目', () {
    const expectations = <String, ({int id, String region})>{
      '京都': (id: 1857910, region: '京都府・日本'),
      '東京': (id: 1850147, region: '東京都・日本'),
      '大阪': (id: 1853909, region: '大阪府・日本'),
      '札幌': (id: 2128295, region: '北海道・日本'),
      '那覇': (id: 1856035, region: '沖縄県・日本'),
      '神戸': (id: 1859171, region: '兵庫県・日本'),
      '横浜': (id: 1848354, region: '神奈川県・日本'),
      '福岡': (id: 1863967, region: '福岡県・日本'),
    };

    for (final entry in expectations.entries) {
      test('${entry.key} → 1 件目が本命、表示名は「${entry.key}」', () async {
        final results = await repository.search(entry.key, language: 'ja');

        expect(results, isNotEmpty);
        final first = results.first;
        expect(first.geocodingId, entry.value.id);
        expect(first.name, entry.key); // 京都市 → 京都、東京都 → 東京
        expect(first.regionParts.join('・'), entry.value.region);
        expect(first.placeId, 'place-geo-${entry.value.id}');
        expect(first.timezone, 'Asia/Tokyo');
        // 入力そのもの + 市・都・町・村 を並行して引いている
        expect(
          server.requestedNames.toSet(),
          {
            entry.key,
            '${entry.key}市',
            '${entry.key}都',
            '${entry.key}町',
            '${entry.key}村',
          },
        );
        expect(
          server.requests.every((u) =>
              u.queryParameters['language'] == 'ja' &&
              u.queryParameters['count'] == '10'),
          isTrue,
        );
      });
    }

    test('神戸: 同名の小集落は本命の後ろに並び、神戸町 (岐阜) は名前を変えない', () async {
      final results = await repository.search('神戸', language: 'ja');

      expect(results.first.name, '神戸');
      expect(results[1].name, '神戸町'); // 人口 19,361 (岐阜県安八郡)
      expect(results[1].regionParts.join('・'), '岐阜県・日本');
      // 人口不明の「神戸」集落は API の順のまま後ろに
      expect(results.skip(2).take(4).map((c) => c.name), everyElement('神戸'));
    });

    test('横浜: 青森の横浜町・福岡の横浜は地域行で区別できる', () async {
      final results = await repository.search('横浜', language: 'ja');

      expect(results.first.regionParts.join('・'), '神奈川県・日本');
      expect(results[1].regionParts.join('・'), '横浜町・青森県・日本');
      // 公園 (横浜市児童遊園地) は候補にしない
      expect(results.map((c) => c.sourceName), isNot(contains('横浜市児童遊園地')));
    });

    test('福岡: 補った「福岡町」の部分一致 (福岡町蓑島…) は混ぜない', () async {
      final results = await repository.search('福岡', language: 'ja');

      expect(results.first.name, '福岡');
      expect(
        results.map((c) => c.sourceName).where((n) => n.startsWith('福岡町')),
        isEmpty,
      );
      expect(results, hasLength(9)); // 福岡市 + 小集落 8
    });
  });

  test('新宿: 10 件、同名の「新宿」を市区町村・都道府県・国で区別できる (Figma B1b と同じ順)', () async {
    final results = await repository.search('新宿', language: 'ja');

    expect(results, hasLength(10));
    expect(results.map((c) => c.name), everyElement('新宿'));
    expect(results.map((c) => c.regionParts.join('・')), [
      '新宿区・東京都・日本',
      '神川町・埼玉県・日本',
      '逗子市・神奈川県・日本',
      '厚木市・神奈川県・日本',
      '清水町・静岡県・日本',
      '葛飾区・東京都・日本',
      '鮫川村・福島県・日本',
      '大井町・神奈川県・日本',
      '海老名市・神奈川県・日本',
      '御宿町・千葉県・日本',
    ]);
  });

  test('ひらがなだけの入力は補正しない (きょうと → 0 件、問い合わせ 1 回)', () async {
    final results = await repository.search('きょうと', language: 'ja');

    expect(results, isEmpty);
    expect(server.requestedNames, ['きょうと']);
  });

  test('ローマ字「Kyoto」: 京都市 → 京都、空港・公園は除く', () async {
    final results = await repository.search('Kyoto', language: 'ja');

    expect(server.requestedNames, ['Kyoto']);
    expect(results.first.name, '京都');
    expect(results.first.regionParts.join('・'), '京都府・日本');
    expect(results.map((c) => c.sourceName), isNot(contains('Kyoto Heliport')));
    expect(
      results.map((c) => c.sourceName),
      isNot(contains('Kyoto Imperial Palace')),
    );
    expect(results, hasLength(3)); // 京都市 / Kyoto (タンザニア) / Kyojomanyi
  });

  test('英語表示: Kyoto 3 件 (Figma EN B1 と同じ地域行。空港・公園は除く)', () async {
    final results = await repository.search('Kyoto', language: 'en');

    expect(results.map((c) => c.name), ['Kyoto', 'Kyoto', 'Kyojomanyi']);
    expect(results.map((c) => c.regionParts.join(', ')), [
      'Kyoto, Japan',
      'Kagera, Tanzania',
      'Central Region, Uganda',
    ]);
  });

  test('英語表示: Naha (Figma EN B1c の先頭 5 件と同じ順・地域行)', () async {
    final results = await repository.search('Naha', language: 'en');

    expect(
      results.take(5).map((c) => '${c.name} / ${c.regionParts.join(', ')}'),
      [
        'Naha / Okinawa, Japan',
        'Naha / Chiapas, Mexico',
        'Naha / Põlvamaa, Estonia',
        'Naha / Võrumaa, Estonia',
        'Nāhai / Shan State, Myanmar',
      ],
    );
    expect(results.first.placeId, 'place-geo-1856035');
  });

  test('海外の地点は郡・タウンシップを地域行に出さない (州・国のみ)', () async {
    final results = await repository.search('Springfield', language: 'en');

    expect(results, hasLength(10));
    expect(
      results.every((c) =>
          c.municipality == null &&
          c.regionParts.length == 2 &&
          c.regionParts.last == 'United States'),
      isTrue,
    );
    // 人口の多い順 (Missouri 170,188 → Massachusetts 154,341 → Illinois 114,394)
    expect(
      results.take(3).map((c) => c.regionParts.first),
      ['Missouri', 'Massachusetts', 'Illinois'],
    );
  });

  test('都道府県の入力「京都府」「東京都」は市・首都の本命を返す', () async {
    final kyoto = await repository.search('京都府', language: 'ja');
    expect(kyoto.first.geocodingId, 1857910);
    expect(kyoto.first.name, '京都');

    final tokyo = await repository.search('東京都', language: 'ja');
    expect(tokyo.first.geocodingId, 1850147);
    expect(tokyo.first.name, '東京');
  });

  test('1 文字「津」→ 津市 → 津 / 「四日市」→ 四日市市 (人口順で 1 件目) → 四日市', () async {
    final tsu = await repository.search('津', language: 'ja');
    expect(tsu.single.name, '津');
    expect(tsu.single.regionParts.join('・'), '三重県・日本');

    final yokkaichi = await repository.search('四日市', language: 'ja');
    expect(yokkaichi.first.sourceName, '四日市市');
    expect(yokkaichi.first.name, '四日市');
    expect(yokkaichi.first.population, 305424);
  });

  test('町は「町」付きのまま (箱根 → 箱根町)', () async {
    final results = await repository.search('箱根', language: 'ja');
    expect(results.single.name, '箱根町');
    expect(results.single.regionParts.join('・'), '神奈川県・日本');
  });

  test('中国語表示でも補正が効く (大阪 → 大阪市 → 大阪)', () async {
    final results = await repository.search('大阪', language: 'zh');
    expect(results.first.geocodingId, 1853909);
    expect(results.first.name, '大阪');
  });

  test('海外: Lisbon (英語) は首都が 1 件目で、同名の米国の町が後ろに並ぶ', () async {
    final results = await repository.search('Lisbon', language: 'en');
    expect(results.first.countryCode, 'PT');
    expect(results.first.timezone, 'Europe/Lisbon');
    expect(results.first.regionParts, ['Lisbon District', 'Portugal']);
    expect(results.skip(1).every((c) => c.countryCode == 'US'), isTrue);
  });

  test('補った問い合わせが 1 つでも通信エラーなら全体をエラーにする (0 件と誤表示しない)', () async {
    server = GeocodingFixtureServer(failNames: {'京都市'});
    repository = PlaceSearchRepository(
      client: GeocodingApiClient(httpClient: server.client),
    );

    await expectLater(
      repository.search('京都', language: 'ja'),
      throwsA(
          isA<AppException>().having((e) => e.type, 'type', ErrorType.network)),
    );
  });

  test('検索しない入力 (空・1 文字の英字) は通信しない', () async {
    expect(await repository.search('', language: 'ja'), isEmpty);
    expect(await repository.search('K', language: 'en'), isEmpty);
    expect(server.requests, isEmpty);
  });
}
