// test/unit/saved_places_provider_test.dart
//
// 保存地点の配線 (providers/saved_places_provider.dart)。
//   - 追加は末尾 (追加順)・保存済みの再保存は更新 (並びは変えない)
//   - 上限 (無料 0 = Plus 限定 / Plus 5) を候補タップ時の最新状態で判定し直す
//   - 無料で残っている地点 (grandfathering) は消さない・削除と元に戻すはできる
//   - 元に戻す (新規 → 削除 / 更新 → 更新前へ)
//   - 旧記録の座標を同梱カタログで補う

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/comfort_record.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/place_candidate.dart';
import 'package:mood_ring_weather/domain/places/saved_place_rules.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:mood_ring_weather/providers/saved_places_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catalog = [
  City(
    id: 'lisbon',
    name: 'Lisbon',
    country: 'Portugal',
    latitude: 38.72,
    longitude: -9.14,
    emoji: '🇵🇹',
  ),
];

PlaceCandidate _candidate(
  int id,
  String name, {
  String admin1 = '京都府',
  double lat = 35.0,
  double lon = 135.7,
}) =>
    PlaceCandidate(
      geocodingId: id,
      name: name,
      sourceName: '$name市',
      latitude: lat,
      longitude: lon,
      featureCode: 'PPLA',
      admin1: admin1,
      country: '日本',
      countryCode: 'JP',
      timezone: 'Asia/Tokyo',
      population: 1000,
    );

final _kyoto = _candidate(1857910, '京都');
final _naha = _candidate(1856035, '那覇', admin1: '沖縄県', lat: 26.2, lon: 127.7);
final _sapporo =
    _candidate(2128295, '札幌', admin1: '北海道', lat: 43.07, lon: 141.35);

/// テスト用の課金状態 (true = Plus)。
final _plusProvider = StateProvider<bool>((ref) => false);

Future<(ProviderContainer, SharedPreferences)> _container({
  List<Map<String, dynamic>> stored = const [],
  bool plus = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (stored.isNotEmpty) kPrefKeyComfortRecords: jsonEncode(stored),
  });
  final prefs = await SharedPreferences.getInstance();
  var minutes = 0;
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      cityCatalogProvider.overrideWith((ref) async => _catalog),
      isPlusProvider.overrideWith((ref) => ref.watch(_plusProvider)),
      savedLocationLimitProvider.overrideWith(
        (ref) => ref.watch(_plusProvider)
            ? kPlusSavedLocationLimit
            : kFreeSavedLocationLimit,
      ),
      // 呼ぶたびに 1 分進む時計 (追加順を区別する)。
      clockProvider.overrideWithValue(
        () => DateTime(2026, 9, 28, 9).add(Duration(minutes: minutes++)),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(_plusProvider.notifier).state = plus;
  await container.read(cityCatalogProvider.future);
  return (container, prefs);
}

/// 保存地点の記録 (SharedPreferences の JSON。無料 1 件の時期・Plus 解約前に
/// 保存したものの再現)。
Map<String, dynamic> _storedPlace(PlaceCandidate p, DateTime at) => {
      'id': p.placeId,
      'type': 'place',
      'mri': null,
      'savedAt': at.toIso8601String(),
      'label': p.name,
      'location': {'lat': p.latitude, 'lon': p.longitude},
      'addedAt': at.toIso8601String(),
    };

void main() {
  test('追加: Plus 0 件 → 追加でき、座標・地域・タイムゾーンを保存する', () async {
    final (c, prefs) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);

    final result = await controller.add(_kyoto);

    expect(result.check, SavedPlaceAddCheck.allowed);
    expect(result.saved, isTrue);
    expect(result.isNew, isTrue);
    expect(result.placeId, 'place-geo-1857910');
    final place = c.read(savedPlacesProvider).single;
    expect(place.id, 'place-geo-1857910');
    expect(place.name, '京都');
    expect(place.location!.latitude, 35.0);
    expect(place.location!.timezone, 'Asia/Tokyo');
    expect(place.location!.geocodingId, 1857910);
    expect(place.regionParts, ['京都府', '日本']);
    expect(place.recordedMri, isNull); // 候補の時点では天気を取っていない
    expect(
        prefs.getString(kPrefKeyComfortRecords), contains('place-geo-1857910'));
    expect(c.read(isSavedPlaceProvider(_kyoto.placeId)), isTrue);
    expect(controller.isSaved(_kyoto), isTrue);
  });

  test('元に戻す (新規): 追加した地点を消す', () async {
    final (c, _) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);

    final result = await controller.add(_kyoto);
    await controller.undo(result);

    expect(c.read(savedPlacesProvider), isEmpty);
    expect(c.read(isSavedPlaceProvider(_kyoto.placeId)), isFalse);
  });

  test('並び順は追加順 (末尾に追加)', () async {
    final (c, _) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);

    await controller.add(_naha);
    await controller.add(_kyoto);
    await controller.add(_sapporo);

    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇', '京都', '札幌']);
  });

  test('保存済みの再保存は更新扱い: 並びは変えず、元に戻すと更新前へ', () async {
    final (c, _) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);
    await controller.add(_naha);
    await controller.add(_kyoto);
    await controller.add(_sapporo);

    final renamed =
        _candidate(1856035, '那覇市', admin1: '沖縄県', lat: 26.2, lon: 127.7);
    final result = await controller.add(renamed);

    expect(result.check, SavedPlaceAddCheck.alreadySaved);
    expect(result.saved, isTrue);
    expect(result.isNew, isFalse);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇市', '京都', '札幌']);

    await controller.undo(result);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇', '京都', '札幌']);
  });

  test('無料 0 件 → Plus 導線 (保存地点は Plus 限定)。何も書かない', () async {
    final (c, prefs) = await _container();
    final controller = c.read(savedPlacesControllerProvider);
    final quota = c.read(savedPlaceQuotaProvider);
    expect(quota.limit, 0);
    expect(quota.canAddNew, isFalse);
    expect(quota.isOverLimit, isFalse);

    expect(controller.check(_kyoto), SavedPlaceAddCheck.needsPlus);
    final result = await controller.add(_kyoto);

    expect(result.check, SavedPlaceAddCheck.needsPlus);
    expect(result.saved, isFalse);
    expect(c.read(savedPlacesProvider), isEmpty);
    expect(prefs.getString(kPrefKeyComfortRecords), isNull);
    await controller.undo(result); // 保存していない結果の undo は何もしない
    expect(c.read(savedPlacesProvider), isEmpty);
  });

  test('無料で 1 件残っている (無料 1 件の時期に保存): 消えず、新規は Plus 導線。何も書かない', () async {
    final (c, prefs) = await _container(
      stored: [_storedPlace(_naha, DateTime(2026, 9, 1, 9))],
    );
    final controller = c.read(savedPlacesControllerProvider);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇']);
    expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);
    final before = prefs.getString(kPrefKeyComfortRecords);

    final result = await controller.add(_kyoto);

    expect(result.check, SavedPlaceAddCheck.needsPlus);
    expect(result.saved, isFalse);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇']);
    expect(prefs.getString(kPrefKeyComfortRecords), before);
  });

  test('Plus の上限 (5 件) → 追加できない (理由を出す)', () async {
    final (c, _) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);
    for (var i = 0; i < 5; i++) {
      await controller.add(_candidate(100 + i, '地点$i'));
    }

    final result = await controller.add(_kyoto);

    expect(result.check, SavedPlaceAddCheck.limitReached);
    expect(c.read(savedPlacesProvider), hasLength(5));
    expect(c.read(savedPlaceQuotaProvider).canAddNew, isFalse);
  });

  test('候補タップ時に最新の課金状態で判定し直す (シート表示後の購入・解約)', () async {
    final (c, _) = await _container();
    final controller = c.read(savedPlacesControllerProvider);
    expect(controller.check(_naha), SavedPlaceAddCheck.needsPlus);

    c.read(_plusProvider.notifier).state = true; // 購入
    expect(controller.check(_naha), SavedPlaceAddCheck.allowed);
    expect((await controller.add(_naha)).isNew, isTrue);
    expect((await controller.add(_kyoto)).isNew, isTrue);

    c.read(_plusProvider.notifier).state = false; // 解約 (2 件は残る)
    expect(c.read(savedPlacesProvider), hasLength(2));
    expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);
    expect(controller.check(_sapporo), SavedPlaceAddCheck.needsPlus);
    expect((await controller.add(_sapporo)).saved, isFalse);
    expect(c.read(savedPlacesProvider), hasLength(2));
    // 保存済みの再保存は上限を超えていても更新できる
    expect(controller.check(_kyoto), SavedPlaceAddCheck.alreadySaved);
  });

  test('savedPlaceQuotaProvider: 件数・上限・Plus', () async {
    final (c, _) = await _container(plus: true);
    await c.read(savedPlacesControllerProvider).add(_kyoto);
    final quota = c.read(savedPlaceQuotaProvider);
    expect(quota.count, 1);
    expect(quota.limit, 5);
    expect(quota.isPlus, isTrue);
    expect(quota.remaining, 4);
  });

  test('旧 Comfort-Twin 記録も保存地点に並び、座標はカタログで補う', () async {
    final (c, _) = await _container(stored: [
      {
        'id': 'place-lisbon',
        'type': 'place',
        'mri': 72,
        'savedAt': '2026-06-01T10:00:00.000',
        'label': 'Lisbon',
        'emoji': '🇵🇹',
      },
      {
        'id': 'day-1',
        'type': 'day',
        'mri': 64,
        'savedAt': '2026-06-02T10:00:00.000',
      },
    ]);

    final places = c.read(savedPlacesProvider);
    expect(places.map((p) => p.id), ['place-lisbon']);
    expect(places.single.location!.latitude, 38.72);
    expect(places.single.recordedMri, 72);
    expect(c.read(savedPlaceQuotaProvider).count, 1);
  });

  test('削除: 保存地点から消える (無料で残っている地点も削除できる)', () async {
    final (c, _) = await _container(
      stored: [_storedPlace(_kyoto, DateTime(2026, 9, 1, 9))],
    );
    final controller = c.read(savedPlacesControllerProvider);
    expect(c.read(savedPlacesProvider), hasLength(1));
    await controller.remove(_kyoto.placeId);
    expect(c.read(savedPlacesProvider), isEmpty);
    expect(
      c
          .read(comfortRecordsProvider)
          .where((r) => r.type == ComfortRecordType.place),
      isEmpty,
    );
  });

  test('削除の元に戻す: 並び順 (追加順) も元どおり', () async {
    final (c, _) = await _container(plus: true);
    final controller = c.read(savedPlacesControllerProvider);
    await controller.add(_naha);
    await controller.add(_kyoto);
    await controller.add(_sapporo);

    final removed = await controller.remove(_kyoto.placeId);
    expect(removed, isNotNull);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇', '札幌']);

    expect(removed!.placeId, _kyoto.placeId);
    expect(removed.countBefore, 3);
    expect(await controller.restore(removed), SavedPlaceRestoreCheck.allowed);
    expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇', '京都', '札幌']);
    // 無い地点の削除は null
    expect(await controller.remove('place-geo-404'), isNull);
  });

  group('削除の元に戻すは戻す時点の上限で判定し直す (QA-07)', () {
    const lisbon = City(
      id: 'lisbon',
      name: 'Lisbon',
      country: 'Portugal',
      latitude: 38.72,
      longitude: -9.14,
      emoji: '🇵🇹',
    );

    test('Plus 1 件 → 削除 → Comfort-Twin で保存 → 解約 → 元に戻す: 戻さず、何も書かない', () async {
      final (c, prefs) = await _container(plus: true);
      final controller = c.read(savedPlacesControllerProvider);
      await controller.add(_naha);
      final removed = await controller.remove(_naha.placeId);
      expect(await controller.saveCatalogCity(lisbon, 70),
          SavedPlaceAddCheck.allowed);
      c.read(_plusProvider.notifier).state = false; // 解約
      final before = prefs.getString(kPrefKeyComfortRecords);

      expect(await controller.restore(removed!),
          SavedPlaceRestoreCheck.limitReached);
      expect(c.read(savedPlacesProvider).map((p) => p.id), ['place-lisbon']);
      expect(c.read(savedPlaceQuotaProvider).count, 1);
      expect(prefs.getString(kPrefKeyComfortRecords), before);
    });

    test('無料で 1 件残っている → 削除 → Comfort-Twin の保存は Plus 導線 → 元に戻す: 1 件に戻る',
        () async {
      final (c, _) = await _container(
        stored: [_storedPlace(_naha, DateTime(2026, 9, 1, 9))],
      );
      final controller = c.read(savedPlacesControllerProvider);
      final removed = await controller.remove(_naha.placeId);
      expect(c.read(savedPlacesProvider), isEmpty);
      expect(await controller.saveCatalogCity(lisbon, 70),
          SavedPlaceAddCheck.needsPlus);

      expect(
          await controller.restore(removed!), SavedPlaceRestoreCheck.allowed);
      expect(c.read(savedPlacesProvider).map((p) => p.id), [_naha.placeId]);
      // 削除前の件数 (1) を超えない。上限 (0) は超えたまま = 持ち越し。
      expect(c.read(savedPlaceQuotaProvider).count, 1);
      expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);
    });

    test('Plus 5 / 5 → 削除 → 別の地点を追加 → 元に戻す: 戻さない (6 件にしない)', () async {
      final (c, _) = await _container(plus: true);
      final controller = c.read(savedPlacesControllerProvider);
      for (var i = 0; i < 5; i++) {
        await controller.add(_candidate(100 + i, '地点$i'));
      }
      final removed = await controller.remove(_candidate(100, '地点0').placeId);
      expect((await controller.add(_kyoto)).isNew, isTrue);

      expect(await controller.restore(removed!),
          SavedPlaceRestoreCheck.limitReached);
      expect(c.read(savedPlacesProvider), hasLength(5));
    });

    test('grandfathering: 解約後に持ち越した 5 件から 1 件消して戻すと 5 件に戻る', () async {
      final (c, _) = await _container(plus: true);
      final controller = c.read(savedPlacesControllerProvider);
      for (var i = 0; i < 5; i++) {
        await controller.add(_candidate(100 + i, '地点$i'));
      }
      c.read(_plusProvider.notifier).state = false; // 解約 (5 件は残る)
      expect(c.read(savedPlaceQuotaProvider).isOverLimit, isTrue);

      final removed = await controller.remove(_candidate(102, '地点2').placeId);
      expect(c.read(savedPlacesProvider), hasLength(4));
      expect(
          await controller.restore(removed!), SavedPlaceRestoreCheck.allowed);
      // 並び順 (追加順) も元どおり
      expect(c.read(savedPlacesProvider).map((p) => p.name),
          ['地点0', '地点1', '地点2', '地点3', '地点4']);
    });

    test('同じ地点を追加し直した後の元に戻すは、件数を増やさず削除前の記録に戻す', () async {
      final (c, _) = await _container(plus: true);
      final controller = c.read(savedPlacesControllerProvider);
      await controller.add(_naha);
      final removed = await controller.remove(_naha.placeId);
      final renamed =
          _candidate(1856035, '那覇市', admin1: '沖縄県', lat: 26.2, lon: 127.7);
      expect((await controller.add(renamed)).isNew, isTrue);

      expect(await controller.restore(removed!),
          SavedPlaceRestoreCheck.alreadySaved);
      expect(c.read(savedPlacesProvider).map((p) => p.name), ['那覇']);
    });
  });

  group('Comfort-Twin の「この場所を保存」(saveCatalogCity)', () {
    const paris = City(
      id: 'paris',
      name: 'Paris',
      country: 'France',
      latitude: 48.86,
      longitude: 2.35,
      emoji: '🇫🇷',
    );

    test('Plus 0 件なら保存でき、座標を持つ', () async {
      final (c, _) = await _container(plus: true);
      final check = await c
          .read(savedPlacesControllerProvider)
          .saveCatalogCity(paris, 70);
      expect(check, SavedPlaceAddCheck.allowed);
      final place = c.read(savedPlacesProvider).single;
      expect(place.id, 'place-paris');
      expect(place.location!.latitude, 48.86);
      expect(place.recordedMri, 70);
    });

    test('無料 0 件なら Plus 導線 (保存地点は Plus 限定。何も書かない)', () async {
      final (c, prefs) = await _container();
      final check = await c
          .read(savedPlacesControllerProvider)
          .saveCatalogCity(paris, 70);
      expect(check, SavedPlaceAddCheck.needsPlus);
      expect(c.read(savedPlacesProvider), isEmpty);
      expect(prefs.getString(kPrefKeyComfortRecords), isNull);
    });

    test('無料で地点が残っていても新規は Plus 導線 (何も書かない)', () async {
      final (c, prefs) = await _container(
        stored: [_storedPlace(_naha, DateTime(2026, 9, 1, 9))],
      );
      final before = prefs.getString(kPrefKeyComfortRecords);

      final check = await c
          .read(savedPlacesControllerProvider)
          .saveCatalogCity(paris, 70);
      expect(check, SavedPlaceAddCheck.needsPlus);
      expect(prefs.getString(kPrefKeyComfortRecords), before);
    });

    test('Plus の上限なら limitReached、保存済みの再保存は上限に関係なく更新', () async {
      final (c, _) = await _container(plus: true);
      final controller = c.read(savedPlacesControllerProvider);
      await controller.saveCatalogCity(paris, 60);
      for (var i = 0; i < 4; i++) {
        await controller.add(_candidate(100 + i, '地点$i'));
      }
      expect(c.read(savedPlacesProvider), hasLength(5));

      const lisbon = City(
        id: 'lisbon',
        name: 'Lisbon',
        country: 'Portugal',
        latitude: 38.72,
        longitude: -9.14,
        emoji: '🇵🇹',
      );
      expect(
        await controller.saveCatalogCity(lisbon, 70),
        SavedPlaceAddCheck.limitReached,
      );
      expect(
        await controller.saveCatalogCity(paris, 80),
        SavedPlaceAddCheck.alreadySaved,
      );
      final paris80 =
          c.read(savedPlacesProvider).firstWhere((p) => p.id == 'place-paris');
      expect(paris80.recordedMri, 80);
    });
  });
}
