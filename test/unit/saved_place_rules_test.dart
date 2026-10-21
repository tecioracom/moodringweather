// test/unit/saved_place_rules_test.dart
//
// 保存地点の規則 (domain/places/saved_place_rules.dart)。
//   - 追加順の並び・旧記録の座標をカタログで補う
//   - 上限 (無料 0 = Plus 限定 / Plus 5。2026-09-30 ユーザー決裁)・grandfathering・
//     再保存は更新扱い
//   - 削除の「元に戻す」の上限の再判定 (QA-07)

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/comfort_record.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/models/place_location.dart';
import 'package:mood_ring_weather/data/models/saved_place.dart';
import 'package:mood_ring_weather/domain/places/saved_place_rules.dart';

const _catalog = [
  City(
    id: 'lisbon',
    name: 'Lisbon',
    country: 'Portugal',
    latitude: 38.72,
    longitude: -9.14,
    emoji: '🇵🇹',
  ),
  City(
    id: 'tokyo',
    name: 'Tokyo',
    country: 'Japan',
    latitude: 35.68,
    longitude: 139.69,
    emoji: '🇯🇵',
  ),
];

ComfortRecord _place(
  String id, {
  required DateTime savedAt,
  DateTime? addedAt,
  PlaceLocation? location,
  int? mri,
  String? label,
}) =>
    ComfortRecord(
      id: id,
      type: ComfortRecordType.place,
      mri: mri,
      savedAt: savedAt,
      addedAt: addedAt,
      location: location,
      label: label ?? id,
    );

SavedPlace _saved(String id) =>
    SavedPlace(id: id, name: id, addedAt: DateTime(2026));

void main() {
  group('resolveSavedPlaces', () {
    test('追加順 (addedAt。旧記録は savedAt) に並べ、体感の記録は含めない', () {
      // 記録は新しい順に保存されている
      final records = [
        _place('place-geo-3',
            savedAt: DateTime(2026, 9, 30), addedAt: DateTime(2026, 9, 3)),
        ComfortRecord(
          id: 'day-1',
          type: ComfortRecordType.day,
          mri: 64,
          savedAt: DateTime(2026, 9, 20),
        ),
        // 再保存で savedAt が新しくなっても、追加時刻 (9/1) の位置のまま
        _place('place-geo-1',
            savedAt: DateTime(2026, 9, 25), addedAt: DateTime(2026, 9, 1)),
        _place('place-lisbon', savedAt: DateTime(2026, 9, 2)), // 旧記録
      ];

      final places = resolveSavedPlaces(records, _catalog);

      expect(places.map((p) => p.id),
          ['place-geo-1', 'place-lisbon', 'place-geo-3']);
    });

    test('旧 Comfort-Twin 記録は同梱カタログで座標を補う', () {
      final places = resolveSavedPlaces(
        [_place('place-lisbon', savedAt: DateTime(2026, 9, 2), mri: 72)],
        _catalog,
      );
      final lisbon = places.single;
      expect(lisbon.hasCoordinates, isTrue);
      expect(lisbon.location!.latitude, 38.72);
      expect(lisbon.location!.longitude, -9.14);
      expect(lisbon.source, SavedPlaceSource.comfortTwin);
      expect(lisbon.catalogCityId, 'lisbon');
      expect(lisbon.recordedMri, 72);
    });

    test('カタログに無い旧記録は座標なし (一覧からは消さない)', () {
      final places = resolveSavedPlaces(
        [_place('place-atlantis', savedAt: DateTime(2026, 9, 2))],
        _catalog,
      );
      expect(places.single.hasCoordinates, isFalse);
      expect(places.single.regionParts, isEmpty);
    });

    test('カタログ読み込み前 (空) でも一覧は出る (座標は後で補われる)', () {
      final places = resolveSavedPlaces(
        [_place('place-lisbon', savedAt: DateTime(2026, 9, 2))],
        const [],
      );
      expect(places.single.id, 'place-lisbon');
      expect(places.single.hasCoordinates, isFalse);
    });

    test('地名検索由来は記録の座標・地域を使い、カタログを引かない', () {
      const location = PlaceLocation(
        latitude: 26.213,
        longitude: 127.67851,
        admin1: '沖縄県',
        country: '日本',
        geocodingId: 1856035,
      );
      final places = resolveSavedPlaces(
        [
          _place('place-geo-1856035',
              savedAt: DateTime(2026, 9, 2), location: location, label: '那覇'),
        ],
        _catalog,
      );
      final naha = places.single;
      expect(naha.name, '那覇');
      expect(naha.location, location);
      expect(naha.source, SavedPlaceSource.geocoding);
      expect(naha.catalogCityId, isNull);
      expect(naha.regionParts, ['沖縄県', '日本']);
    });

    test('SavedPlace は値で比較できる (同じ内容なら再通知しない)', () {
      final a = resolveSavedPlaces(
        [_place('place-lisbon', savedAt: DateTime(2026, 9, 2))],
        _catalog,
      ).single;
      final b = resolveSavedPlaces(
        [_place('place-lisbon', savedAt: DateTime(2026, 9, 2))],
        _catalog,
      ).single;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SavedPlaceQuota', () {
    test('上限は無料 0 (保存地点は Plus 限定) / Plus 5', () {
      expect(kFreeSavedLocationLimit, 0);
      expect(kPlusSavedLocationLimit, 5);
    });

    test('無料 0 件: 追加できない。上限超過でもない (件数を出さない A1)', () {
      const free0 = SavedPlaceQuota(
          count: 0, limit: kFreeSavedLocationLimit, isPlus: false);
      expect(free0.canAddNew, isFalse);
      expect(free0.isOverLimit, isFalse);
      expect(free0.remaining, 0);
    });

    test('無料で 1 件残っている (無料 1 件の時期に保存): 上限超過の残存 (A5)', () {
      const free1 = SavedPlaceQuota(
          count: 1, limit: kFreeSavedLocationLimit, isPlus: false);
      expect(free1.canAddNew, isFalse);
      expect(free1.isOverLimit, isTrue);
      expect(free1.remaining, 0);
    });

    test('Plus: 4 件はあと 1 件、5 件で上限 (超過ではない)', () {
      const plus0 = SavedPlaceQuota(
          count: 0, limit: kPlusSavedLocationLimit, isPlus: true);
      expect(plus0.canAddNew, isTrue);
      expect(plus0.remaining, 5);

      const plus4 = SavedPlaceQuota(
          count: 4, limit: kPlusSavedLocationLimit, isPlus: true);
      expect(plus4.canAddNew, isTrue);
      expect(plus4.remaining, 1);

      const plus5 = SavedPlaceQuota(
          count: 5, limit: kPlusSavedLocationLimit, isPlus: true);
      expect(plus5.canAddNew, isFalse);
      expect(plus5.isOverLimit, isFalse);
      expect(plus5.remaining, 0);
    });

    test('Plus 解約後に 5 件残っている (grandfathering)', () {
      const lapsed = SavedPlaceQuota(
          count: 5, limit: kFreeSavedLocationLimit, isPlus: false);
      expect(lapsed.canAddNew, isFalse);
      expect(lapsed.isOverLimit, isTrue);
      expect(lapsed.remaining, 0);
    });
  });

  group('checkSavedPlaceAdd', () {
    SavedPlaceAddCheck check(
      List<String> saved,
      String candidate, {
      required bool isPlus,
    }) =>
        checkSavedPlaceAdd(
          places: [for (final id in saved) _saved(id)],
          placeId: candidate,
          quota: SavedPlaceQuota(
            count: saved.length,
            limit: isPlus ? kPlusSavedLocationLimit : kFreeSavedLocationLimit,
            isPlus: isPlus,
          ),
        );

    test('無料: 0 件でも追加できない (Plus 導線。「上限 N 件」ではない)', () {
      expect(check([], 'place-geo-1', isPlus: false),
          SavedPlaceAddCheck.needsPlus);
    });

    test('無料で 1 件残っている: 新規は Plus 導線、同じ地点の再保存は更新扱い', () {
      expect(check(['place-geo-1'], 'place-geo-2', isPlus: false),
          SavedPlaceAddCheck.needsPlus);
      expect(check(['place-geo-1'], 'place-geo-1', isPlus: false),
          SavedPlaceAddCheck.alreadySaved);
    });

    test('Plus: 0〜4 件なら追加できる、5 件で上限', () {
      final four = [for (var i = 0; i < 4; i++) 'place-geo-$i'];
      final five = [for (var i = 0; i < 5; i++) 'place-geo-$i'];
      expect(
          check([], 'place-geo-9', isPlus: true), SavedPlaceAddCheck.allowed);
      expect(
          check(four, 'place-geo-9', isPlus: true), SavedPlaceAddCheck.allowed);
      expect(check(five, 'place-geo-9', isPlus: true),
          SavedPlaceAddCheck.limitReached);
    });

    test('保存済みの再保存は上限に関係なく更新扱い (grandfathering 中でも)', () {
      final five = [for (var i = 0; i < 5; i++) 'place-geo-$i'];
      expect(check(five, 'place-geo-3', isPlus: false),
          SavedPlaceAddCheck.alreadySaved);
      expect(check(five, 'place-geo-3', isPlus: true),
          SavedPlaceAddCheck.alreadySaved);
    });

    test('解約後に上限を超えて残っていても、新規は Plus 導線', () {
      final five = [for (var i = 0; i < 5; i++) 'place-geo-$i'];
      expect(check(five, 'place-geo-9', isPlus: false),
          SavedPlaceAddCheck.needsPlus);
    });
  });

  // QA-07: 削除の「元に戻す」は戻す時点の件数と上限で判定し直す。
  group('checkSavedPlaceRestore', () {
    SavedPlaceRestoreCheck restore(
      List<String> saved,
      String removed, {
      required bool isPlus,
      required int countBefore,
    }) =>
        checkSavedPlaceRestore(
          places: [for (final id in saved) _saved(id)],
          placeId: removed,
          quota: SavedPlaceQuota(
            count: saved.length,
            limit: isPlus ? kPlusSavedLocationLimit : kFreeSavedLocationLimit,
            isPlus: isPlus,
          ),
          countBeforeRemoval: countBefore,
        );

    test('無料で 1 件残っている → 削除 (0 件) → 戻す: 上限 0 でも削除前の 1 件に戻せる', () {
      expect(restore([], 'place-geo-1', isPlus: false, countBefore: 1),
          SavedPlaceRestoreCheck.allowed);
    });

    test('Plus 1 件 → 削除 → 別の地点を保存 → 解約 → 戻すと削除前より増えるので戻さない', () {
      expect(
        restore(['place-lisbon'], 'place-geo-1', isPlus: false, countBefore: 1),
        SavedPlaceRestoreCheck.limitReached,
      );
    });

    test('Plus 0 件 → 追加 → 削除 → 戻す: 戻せる (1 / 5)', () {
      expect(restore([], 'place-geo-1', isPlus: true, countBefore: 1),
          SavedPlaceRestoreCheck.allowed);
    });

    test('Plus 5 / 5 → 削除 → 別の地点を追加 → 戻すと 6 件になるので戻さない', () {
      final five = [for (var i = 0; i < 5; i++) 'place-geo-$i'];
      expect(restore(five, 'place-geo-9', isPlus: true, countBefore: 5),
          SavedPlaceRestoreCheck.limitReached);
      // 追加していなければ (4 件) 戻せる
      expect(
        restore(five.take(4).toList(), 'place-geo-9',
            isPlus: true, countBefore: 5),
        SavedPlaceRestoreCheck.allowed,
      );
    });

    test('grandfathering: 解約後に持ち越した 5 件から 1 件消して戻すのは、元の 5 件まで戻せる', () {
      final four = [for (var i = 0; i < 4; i++) 'place-geo-$i'];
      expect(restore(four, 'place-geo-9', isPlus: false, countBefore: 5),
          SavedPlaceRestoreCheck.allowed);
      // 2 件消して 3 件 → 後に消した方を戻す (削除前は 4 件) → 4 件まで
      final three = four.take(3).toList();
      expect(restore(three, 'place-geo-8', isPlus: false, countBefore: 4),
          SavedPlaceRestoreCheck.allowed);
      // 削除前の件数を超える戻し方はしない (4 件のまま、削除前 4 件の地点を戻す = 5 件)
      expect(restore(four, 'place-geo-8', isPlus: false, countBefore: 4),
          SavedPlaceRestoreCheck.limitReached);
    });

    test('削除した後に Plus が切れても、削除前の件数までは戻せる', () {
      // Plus 3 件 → 1 件削除 (2 件) → 解約 (無料の上限 0) → 戻す: 3 件 (削除前と同じ)
      expect(
        restore(['place-geo-1', 'place-geo-2'], 'place-geo-3',
            isPlus: false, countBefore: 3),
        SavedPlaceRestoreCheck.allowed,
      );
    });

    test('同じ地点を追加し直していれば、件数は増えないので上限に関係なく戻せる', () {
      expect(
        restore(['place-geo-1'], 'place-geo-1', isPlus: false, countBefore: 1),
        SavedPlaceRestoreCheck.alreadySaved,
      );
    });
  });
}
