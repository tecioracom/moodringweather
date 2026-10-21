// test/unit/comfort_records_test.dart
//
// オンデバイス記録 (providers/comfort_twin_provider.dart の ComfortRecordsController)
// と ComfortRecord の保存形式。
//   - 上限の種類分け: 「今日の体感」30 件の巻き添えで保存地点が消えない
//   - grandfathering: 上限を超えて残っている保存地点を消さない
//   - 後方互換: v1.3.0 以前の記録 (座標なし) を読める / 壊れた 1 件だけ捨てる
//   - 保存地点の追加・更新 (位置と追加時刻を保つ)・元に戻す

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/comfort_record.dart';
import 'package:mood_ring_weather/data/models/place_location.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _legacyPlace(String cityId, {int mri = 60, int day = 1}) =>
    {
      'id': 'place-$cityId',
      'type': 'place',
      'mri': mri,
      'savedAt': '2026-06-${day.toString().padLeft(2, '0')}T10:00:00.000',
      'label': cityId,
      'emoji': '🌍',
    };

Map<String, dynamic> _legacyDay(int i) => {
      'id': 'day-$i',
      'type': 'day',
      'mri': 50 + (i % 40),
      'savedAt': DateTime(2026, 5, 1).add(Duration(days: i)).toIso8601String(),
      'label': null,
      'emoji': null,
    };

Future<(ProviderContainer, SharedPreferences)> _container(
  List<Map<String, dynamic>> stored,
) async {
  SharedPreferences.setMockInitialValues({
    if (stored.isNotEmpty) kPrefKeyComfortRecords: jsonEncode(stored),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

List<ComfortRecord> _stored(SharedPreferences prefs) => [
      for (final e
          in jsonDecode(prefs.getString(kPrefKeyComfortRecords)!) as List)
        ComfortRecord.fromJson(e as Map<String, dynamic>),
    ];

void main() {
  group('上限の種類分け', () {
    test('「今日の体感」を 30 件以上記録しても保存地点は消えない', () async {
      // 旧実装では合算 30 件 = 体感 28 + 地点 2。体感を足すと古い地点から消えていた。
      final (c, prefs) = await _container([
        for (var i = 27; i >= 0; i--) _legacyDay(i),
        _legacyPlace('lisbon', day: 1),
        _legacyPlace('naha', day: 2),
      ]);
      final notifier = c.read(comfortRecordsProvider.notifier);

      for (var i = 0; i < 10; i++) {
        await notifier.saveDayFeel(60, now: DateTime(2026, 7, 1 + i));
      }

      final records = c.read(comfortRecordsProvider);
      final days = records.where((r) => r.type == ComfortRecordType.day);
      final places = records.where((r) => r.type == ComfortRecordType.place);
      expect(days, hasLength(kDayFeelRecordsLimit));
      expect(places.map((r) => r.id), ['place-lisbon', 'place-naha']);
      // 永続化にも残っている
      expect(
        _stored(prefs).where((r) => r.type == ComfortRecordType.place),
        hasLength(2),
      );
      // 体感は新しいものが残る (古い順に捨てる)
      expect(days.first.savedAt, DateTime(2026, 7, 10));
    });

    test('grandfathering: 上限 (Plus 5) を超えて残っている保存地点を消さない', () async {
      final (c, _) = await _container([
        for (var i = 0; i < 8; i++) _legacyPlace('city$i', day: i + 1),
      ]);
      await c.read(comfortRecordsProvider.notifier).saveDayFeel(64);
      final places = c
          .read(comfortRecordsProvider)
          .where((r) => r.type == ComfortRecordType.place);
      expect(places, hasLength(8));
    });

    test('applyComfortRecordLimits は体感だけを新しい 30 件に絞る', () {
      final records = [
        for (var i = 0; i < 40; i++)
          ComfortRecord(
            id: 'day-$i',
            type: ComfortRecordType.day,
            mri: 60,
            savedAt: DateTime(2026, 1, 1),
          ),
        for (var i = 0; i < 6; i++)
          ComfortRecord(
            id: 'place-$i',
            type: ComfortRecordType.place,
            mri: null,
            savedAt: DateTime(2026, 1, 1),
          ),
      ];
      final capped = applyComfortRecordLimits(records);
      expect(
          capped.where((r) => r.type == ComfortRecordType.day), hasLength(30));
      expect(capped.where((r) => r.type == ComfortRecordType.day).last.id,
          'day-29');
      expect(
          capped.where((r) => r.type == ComfortRecordType.place), hasLength(6));
    });
  });

  group('後方互換', () {
    test('v1.3.0 以前の記録 (location / addedAt なし) を読める', () async {
      final (c, _) = await _container([_legacyPlace('lisbon', mri: 72)]);
      final r = c.read(comfortRecordsProvider).single;
      expect(r.id, 'place-lisbon');
      expect(r.mri, 72);
      expect(r.location, isNull);
      expect(r.addedAt, isNull);
    });

    test('壊れた 1 件だけを捨て、他の記録 (保存地点) は残す', () async {
      final (c, _) = await _container([
        _legacyPlace('lisbon'),
        {'id': 'broken', 'type': 'place'}, // savedAt なし
        {'type': 'day', 'mri': 50, 'savedAt': '2026-06-01T00:00:00.000'},
        _legacyDay(1),
      ]);
      final ids = c.read(comfortRecordsProvider).map((r) => r.id);
      expect(ids, ['place-lisbon', 'day-1']);
    });

    test('保存地点の位置・追加時刻・MRI なしを JSON で往復できる', () {
      final record = ComfortRecord(
        id: 'place-geo-1857910',
        type: ComfortRecordType.place,
        mri: null,
        savedAt: DateTime(2026, 9, 28, 10),
        label: '京都',
        location: const PlaceLocation(
          latitude: 35.02107,
          longitude: 135.75385,
          admin1: '京都府',
          country: '日本',
          countryCode: 'JP',
          timezone: 'Asia/Tokyo',
          geocodingId: 1857910,
        ),
        addedAt: DateTime(2026, 9, 27, 9),
      );
      final restored = ComfortRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
      );
      expect(restored.mri, isNull);
      expect(restored.location, record.location);
      expect(restored.addedAt, DateTime(2026, 9, 27, 9));
      expect(restored.label, '京都');
      // 座標が壊れている位置は「座標なし」として読む
      expect(PlaceLocation.tryParse({'lat': 'x', 'lon': 1}), isNull);
      expect(PlaceLocation.tryParse({'lat': 95, 'lon': 1}), isNull);
    });
  });

  group('保存地点の追加・更新', () {
    test('Comfort-Twin の保存は座標を持ち、再保存でも追加時刻は変えない', () async {
      final (c, _) = await _container(const []);
      final notifier = c.read(comfortRecordsProvider.notifier);
      const lisbon = City(
        id: 'lisbon',
        name: 'Lisbon',
        country: 'Portugal',
        latitude: 38.72,
        longitude: -9.14,
        emoji: '🇵🇹',
      );

      await notifier.savePlace(lisbon, 60, now: DateTime(2026, 9, 1));
      await notifier.savePlace(lisbon, 70, now: DateTime(2026, 9, 5));

      final r = c.read(comfortRecordsProvider).single;
      expect(r.mri, 70);
      expect(r.savedAt, DateTime(2026, 9, 5));
      expect(r.addedAt, DateTime(2026, 9, 1));
      expect(r.location!.latitude, 38.72);
      expect(r.location!.longitude, -9.14);
      expect(r.location!.country, 'Portugal');
    });

    test('旧記録を Comfort-Twin で再保存すると、追加時刻は旧 savedAt を引き継ぐ', () async {
      final (c, _) = await _container([_legacyPlace('lisbon', day: 3)]);
      const lisbon = City(
        id: 'lisbon',
        name: 'Lisbon',
        country: 'Portugal',
        latitude: 38.72,
        longitude: -9.14,
        emoji: '🇵🇹',
      );
      await c
          .read(comfortRecordsProvider.notifier)
          .savePlace(lisbon, 70, now: DateTime(2026, 9, 5));
      expect(
        c.read(comfortRecordsProvider).single.addedAt,
        DateTime(2026, 6, 3, 10),
      );
    });

    test('upsertPlace: 新規は先頭 + addedAt、既存は位置と addedAt を保って置き換え', () async {
      final (c, prefs) = await _container([
        _legacyDay(1),
        _legacyPlace('lisbon', day: 2),
      ]);
      final notifier = c.read(comfortRecordsProvider.notifier);

      await notifier.upsertPlace(ComfortRecord(
        id: 'place-geo-1',
        type: ComfortRecordType.place,
        mri: null,
        savedAt: DateTime(2026, 9, 1),
        label: 'A',
      ));
      expect(c.read(comfortRecordsProvider).first.id, 'place-geo-1');
      expect(
          c.read(comfortRecordsProvider).first.addedAt, DateTime(2026, 9, 1));

      await notifier.upsertPlace(ComfortRecord(
        id: 'place-lisbon',
        type: ComfortRecordType.place,
        mri: null,
        savedAt: DateTime(2026, 9, 9),
        label: 'Lisboa',
      ));
      final ids = c.read(comfortRecordsProvider).map((r) => r.id).toList();
      expect(ids, ['place-geo-1', 'day-1', 'place-lisbon']);
      final lisbon = c.read(comfortRecordsProvider).last;
      expect(lisbon.label, 'Lisboa');
      expect(lisbon.addedAt, DateTime(2026, 6, 2, 10)); // 旧 savedAt
      expect(_stored(prefs).last.label, 'Lisboa');
    });

    test('restorePlace: 以前の記録に戻す (無ければ入れ直す)', () async {
      final (c, _) = await _container([_legacyPlace('lisbon', mri: 61)]);
      final notifier = c.read(comfortRecordsProvider.notifier);
      final before = c.read(comfortRecordsProvider).single;

      await notifier.upsertPlace(ComfortRecord(
        id: 'place-lisbon',
        type: ComfortRecordType.place,
        mri: null,
        savedAt: DateTime(2026, 9, 9),
        label: 'Changed',
      ));
      await notifier.restorePlace(before);
      final r = c.read(comfortRecordsProvider).single;
      expect(r.label, before.label);
      expect(r.mri, 61);

      await notifier.remove('place-lisbon');
      await notifier.restorePlace(before);
      expect(c.read(comfortRecordsProvider).single.id, 'place-lisbon');
    });
  });
}
