// test/qa/live_open_meteo_probe_test.dart
//
// QA の実 API 検証 (読み取りのみ)。**既定では実行しない** (CI・通常の flutter test は
// skip。通信しない)。リリース候補の QA で、録画フィクスチャ (2026-09-28) の前提が
// 今日の Open-Meteo でも成り立つかを確かめる:
//
//   flutter test test/qa/live_open_meteo_probe_test.dart \
//     --dart-define=MRW_LIVE_API=true
//
// 1. 地名検索 (Open-Meteo Geocoding) の受け入れ基準
//    - 京都・東京・大阪・札幌・那覇・神戸・横浜・福岡・Kyoto で本命が 1 件目
//    - 新宿 / Springfield のような同名地点は地域行 (市区町村・州) で区別できる
//    - ひらがなだけ (きょうと) は 0 件 (UI は「漢字かローマ字で」と案内する)
//    - 1 検索あたりの HTTP 問い合わせ回数 (漢字だけの入力は補正ぶん並行して引く)
// 2. 海外地点の時差 (utc_offset_seconds): レイキャビク (UTC+0)・ホノルル (UTC−10)
//    で時間別の窓の「今」が現地の現在時刻に一致し、時刻ラベル (axisLocalTime) が
//    現地時刻になる。
//
// 結果は LIVE_GEOCODING|... / LIVE_WEATHER|... の 1 行ずつで出力する
// (docs/qa-report-saved-places-2026-09-29.md に転記)。
//
// 注意: flutter_test のバインディングを初期化しない (testWidgets を使わない)。
// 初期化すると HTTP が全て 400 に差し替えられ、実通信できない。

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mood_ring_weather/data/datasources/geocoding_api_client.dart';
import 'package:mood_ring_weather/data/datasources/weather_api_client.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/data/repositories/place_search_repository.dart';
import 'package:mood_ring_weather/domain/mri/mri_timeline.dart';
import 'package:mood_ring_weather/domain/places/place_search_rules.dart';
import 'package:mood_ring_weather/presentation/shared/chart_axes.dart';

const bool _live = bool.fromEnvironment('MRW_LIVE_API');
const String? _skip =
    _live ? null : '--dart-define=MRW_LIVE_API=true を付けたときだけ実 API に問い合わせる';

/// 送った HTTP リクエストを数える (中身は本物の http.Client に渡す)。
class _CountingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<Uri> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request.url);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void _out(String line) {
  // ignore: avoid_print
  print(line);
}

String _row(PlaceCandidate c, String separator) =>
    '${c.name} / ${c.regionParts.join(separator)} '
    '(id=${c.geocodingId}, ${c.featureCode}, pop=${c.population})';

Future<({List<PlaceCandidate> results, int requests})> _search(
  String input,
  String language,
) async {
  final client = _CountingClient();
  addTearDown(client.close);
  final repository = PlaceSearchRepository(
    client: GeocodingApiClient(httpClient: client),
  );
  final results = await repository.search(input, language: language);
  final separator = language == 'ja' ? '・' : ', ';
  _out('LIVE_GEOCODING|$language|$input|requests=${client.requests.length}|'
      'results=${results.length}');
  for (var i = 0; i < results.length; i++) {
    _out('LIVE_GEOCODING|$language|$input|#${i + 1}|'
        '${_row(results[i], separator)}');
  }
  return (results: results, requests: client.requests.length);
}

void main() {
  group('地名検索 (Open-Meteo Geocoding の実 API)', () {
    // 本命の GeoNames id と地域行 (録画フィクスチャと同じ受け入れ基準)。
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
      test('ja「${entry.key}」: 本命が 1 件目。漢字だけの入力は 5 回並行して引く', skip: _skip,
          () async {
        final r = await _search(entry.key, 'ja');
        expect(r.results, isNotEmpty);
        expect(r.results.first.geocodingId, entry.value.id);
        expect(r.results.first.name, entry.key);
        expect(r.results.first.regionParts.join('・'), entry.value.region);
        // 入力そのもの + 市・都・町・村
        expect(r.requests, 5);
      });
    }

    test('ja「新宿」: 同名の地点は市区町村 (地域行) で区別できる', skip: _skip, () async {
      final r = await _search('新宿', 'ja');
      final same = r.results.where((c) => c.name == '新宿').toList();
      expect(same.length, greaterThanOrEqualTo(2));
      final regions = [for (final c in same) c.regionParts.join('・')];
      expect(regions.toSet().length, regions.length,
          reason: '同名で地域行も同じ候補がある: $regions');
      expect(r.requests, 5);
    });

    test('ja「京都府」: 都道府県名は語幹 +「市」も引く (2 回)', skip: _skip, () async {
      final r = await _search('京都府', 'ja');
      expect(r.results.first.geocodingId, 1857910);
      expect(r.requests, 2);
    });

    test('ja「きょうと」: ひらがなだけは 0 件 (補正しない、1 回)', skip: _skip, () async {
      final r = await _search('きょうと', 'ja');
      expect(r.results, isEmpty);
      expect(isKanaOnlyText('きょうと'), isTrue);
      expect(r.requests, 1);
    });

    test('ja「Kyoto」(日本語表示でローマ字): 京都が 1 件目、1 回', skip: _skip, () async {
      final r = await _search('Kyoto', 'ja');
      expect(r.results.first.geocodingId, 1857910);
      expect(r.results.first.name, '京都');
      expect(r.requests, 1);
    });

    test('en「Kyoto」: Kyoto (Japan) が 1 件目、1 回', skip: _skip, () async {
      final r = await _search('Kyoto', 'en');
      expect(r.results.first.geocodingId, 1857910);
      expect(r.results.first.name, 'Kyoto');
      expect(r.results.first.regionParts.join(', '), 'Kyoto, Japan');
      expect(r.requests, 1);
    });

    test('en「Springfield」: 同名は州で区別できる (地域行の重複を記録)', skip: _skip, () async {
      final r = await _search('Springfield', 'en');
      expect(r.results.length, greaterThanOrEqualTo(5));
      expect(r.requests, 1);
      final same = r.results.where((c) => c.name == 'Springfield').toList();
      final regions = [for (final c in same) c.regionParts.join(', ')];
      final duplicated = {
        for (final region in regions)
          if (regions.where((x) => x == region).length > 1) region,
      };
      _out('LIVE_GEOCODING|en|Springfield|duplicated_regions=$duplicated');
      final other = r.results.where((c) => c.name != 'Springfield').toList();
      _out('LIVE_GEOCODING|en|Springfield|other_names='
          '${other.map((c) => c.name).toList()}');
    });

    // zh / es の表示言語 (参考。合否は付けず 1 件目を記録する)。
    // 2026-09-29 の QA で、zh (簡体字) の主要都市名の多くが本命に当たらないことを
    // 確認した (东京 → 中国の同名の村、首尔・纽约 → 0 件、伦敦 → カナダのロンドン)。
    // docs/qa-report-saved-places-2026-09-29.md の不具合一覧を参照。
    const reference = <(String, String, int?)>[
      // (言語, 入力, 本命の GeoNames id)
      ('zh', '东京', 1850147),
      ('zh', '東京', 1850147),
      ('zh', '京都', 1857910),
      ('zh', '大阪', 1853909),
      ('zh', '札幌', 2128295),
      ('zh', '那霸', 1856035),
      ('zh', '北京', 1816670),
      ('zh', '上海', 1796236),
      ('zh', '首尔', 1835848),
      ('zh', '纽约', 5128581),
      ('zh', '伦敦', 2643743),
      ('zh', 'Tokyo', 1850147),
      ('zh', 'London', 2643743),
      ('es', 'Kioto', 1857910),
      ('es', 'Tokio', 1850147),
      ('es', 'Londres', 2643743),
      ('es', 'Nueva York', 5128581),
    ];
    test('zh / es の表示言語 (参考: 本命が 1 件目か記録する)', skip: _skip, () async {
      final summary = <String>[];
      for (final (language, input, expected) in reference) {
        final r = await _search(input, language);
        final first = r.results.isEmpty ? null : r.results.first.geocodingId;
        final hit = r.results.indexWhere((c) => c.geocodingId == expected);
        summary.add('$language $input: first=${first ?? '-'} '
            '${first == expected ? 'OK' : 'NG'} '
            '(本命の順位=${hit < 0 ? '圏外' : hit + 1}, 問い合わせ=${r.requests})');
      }
      for (final line in summary) {
        _out('LIVE_GEOCODING|summary|$line');
      }
    });
  });

  group('海外地点の時差 (Open-Meteo Forecast の実 API)', () {
    // (名前, 緯度, 経度, 期待する UTC オフセット秒)。どちらも夏時間なし。
    const places = [
      ('Reykjavik', 64.15, -21.94, 0),
      ('Honolulu', 21.31, -157.86, -36000),
      ('Tokyo', 35.68, 139.77, 32400),
    ];
    for (final (name, lat, lon, offset) in places) {
      test('$name: 「今」は現地の現在時刻、ラベルは現地時刻', skip: _skip, () async {
        final client = _CountingClient();
        addTearDown(client.close);
        final api = WeatherApiClient(httpClient: client);
        final now = DateTime.now();

        final current = await api.fetchCurrent(lat, lon);
        expect(current.utcOffsetSeconds, offset);
        // 観測時刻は現在から 1 時間以内 (15 分ごとの観測)
        expect(now.difference(current.timestamp).inMinutes.abs(),
            lessThanOrEqualTo(60));

        final hourly = await api.fetchHourly(lat, lon, now: now);
        expect(hourly, hasLength(24));
        final timeline = MriTimeline.fromSnapshots(hourly);
        final nowIndex = MriTimeline.indexNearest(timeline, reference: now);
        final nearest = hourly[nowIndex];
        // 「今」に最も近い点は現在から 30 分以内 (絶対時刻で比べる)
        expect(nearest.timestamp.difference(now).inMinutes.abs(),
            lessThanOrEqualTo(30));
        // 窓は過去 6 時間〜未来 17 時間。窓の「今」は現在の時 (切り捨て) = 7 点目。
        // 最寄りの点は分が 30 以上なら次の時 (8 点目) になる。
        expect(nowIndex, anyOf(6, 7));
        // ラベルは現地の壁時計 (端末のタイムゾーンに依らない)
        final expectedLocal = nearest.timestamp.toUtc().add(
              Duration(seconds: offset),
            );
        final label =
            axisLocalTime(nearest.timestamp, nearest.utcOffsetSeconds);
        expect(label.hour, expectedLocal.hour);
        expect(nearest.placeLocalTime.hour, expectedLocal.hour);
        final localNow = now.toUtc().add(Duration(seconds: offset));
        _out('LIVE_WEATHER|$name|offset=${current.utcOffsetSeconds}|'
            'device_now=${now.toIso8601String()}|place_now=${localNow.toIso8601String()}|'
            'now_index=$nowIndex|now_label_hour=${label.hour}|'
            'window=${axisLocalTime(hourly.first.timestamp, offset).hour}h..'
            '${axisLocalTime(hourly.last.timestamp, offset).hour}h|'
            'requests=${client.requests.length}');
      });
    }
  });
}
