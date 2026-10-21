// test/unit/city_catalog_test.dart
//
// 同梱カタログ assets/cities.json の健全性 (スキーマ・件数・座標範囲・
// ID 一意性) と CityCatalogDataSource のパース (AssetBundle 注入)。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/errors/app_exception.dart';
import 'package:mood_ring_weather/data/datasources/city_catalog_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';

/// メモリ上の文字列を返す AssetBundle (実アセット I/O を避ける)。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.content);
  final String content;

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(content);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

void main() {
  group('assets/cities.json', () {
    late List<dynamic> raw;

    setUpAll(() {
      // flutter test はプロジェクトルートを CWD として実行される。
      raw = jsonDecode(File('assets/cities.json').readAsStringSync())
          as List<dynamic>;
    });

    test('40〜80 都市が同梱されている', () {
      expect(raw.length, inInclusiveRange(40, 80));
    });

    test('全エントリが必須フィールドを持ち City としてパースできる', () {
      for (final e in raw) {
        final city = City.fromJson(e as Map<String, dynamic>);
        expect(city.id, isNotEmpty);
        expect(city.name, isNotEmpty);
        expect(city.country, isNotEmpty);
        expect(city.emoji, isNotEmpty);
        expect(city.latitude, inInclusiveRange(-90.0, 90.0));
        expect(city.longitude, inInclusiveRange(-180.0, 180.0));
      }
    });

    test('ID は一意 (保存記録の参照キーになるため)', () {
      final ids = [
        for (final e in raw) (e as Map<String, dynamic>)['id'] as String,
      ];
      expect(ids.toSet().length, ids.length);
    });
  });

  group('CityCatalogDataSource', () {
    test('注入した AssetBundle の JSON をパースする', () async {
      const json = '[{"id":"tokyo","name":"Tokyo","country":"Japan",'
          '"latitude":35.68,"longitude":139.69,"emoji":"🇯🇵"}]';
      final source = CityCatalogDataSource(bundle: _FakeBundle(json));

      final cities = await source.load();

      expect(cities, hasLength(1));
      expect(cities.first.id, 'tokyo');
      expect(cities.first.latitude, closeTo(35.68, 1e-9));
    });

    test('壊れた JSON は AppException (日本語 userMessage)', () async {
      final source = CityCatalogDataSource(bundle: _FakeBundle('{not json'));

      await expectLater(
        source.load(),
        throwsA(isA<AppException>()
            .having((e) => e.type, 'type', ErrorType.parsing)
            .having((e) => e.userMessage, 'userMessage', contains('都市データ'))),
      );
    });
  });
}
