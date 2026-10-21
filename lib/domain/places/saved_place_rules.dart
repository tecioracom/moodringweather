// lib/domain/places/saved_place_rules.dart
//
// 保存地点 (Plus 多地点。spec.md §12.11.5) の規則。純 Dart・Flutter 非依存。
// ユニットテスト: test/unit/saved_place_rules_test.dart
//
//   - resolveSavedPlaces: オンデバイス記録 → 保存地点 (追加順)。旧記録の座標を
//     同梱カタログで補う
//   - SavedPlaceQuota / checkSavedPlaceAdd: 上限 (無料 0 = Plus 限定 / Plus 5) と
//     追加可否。無料は新規追加できない (Plus 導線)。上限は**新規追加**だけを止め、
//     上限を超えて残っている地点は消さない (grandfathering。Plus 解約後に 5 件、
//     無料 1 件の時期 (〜1.3.0 (11)) に保存した 1 件が残ることがある)。同じ地点の
//     再保存は更新扱いで常に許可する。
//   - checkSavedPlaceRestore: 削除の「元に戻す」の可否。戻す時点の件数と上限で
//     判定し直す (削除の後に別の経路で追加されていたら上限を超えない)。無料でも
//     削除前の件数までは戻せる (持ち越した地点を消さないのと同じ扱い)。

import '../../data/models/city.dart';
import '../../data/models/comfort_record.dart';
import '../../data/models/place_location.dart';
import '../../data/models/saved_place.dart';

/// 記録 (新しい順) から保存地点を解決し、**追加順** (古い順) に並べる。
///
/// - 座標: 記録の `location` を正とする。旧記録 (v1.3.0 以前の Comfort-Twin 保存)
///   は `place-{cityId}` の cityId で [catalog] を引いて補う。補えなければ
///   `location == null` (天気は取れないが一覧からは消さない)。
/// - 追加時刻: `addedAt`。旧記録は `savedAt` で代用する。同時刻は記録の古い順。
List<SavedPlace> resolveSavedPlaces(
  List<ComfortRecord> records,
  List<City> catalog,
) {
  final citiesById = {for (final c in catalog) c.id: c};
  final resolved = <SavedPlace>[];
  // records は新しい順。逆順に積むと同時刻のときに古い記録が先になる。
  for (final r in records.reversed) {
    if (r.type != ComfortRecordType.place) continue;
    resolved.add(SavedPlace(
      id: r.id,
      name: r.label ?? '',
      location: r.location ?? _catalogLocation(r.id, citiesById),
      addedAt: r.addedAt ?? r.savedAt,
      emoji: r.emoji,
      recordedMri: r.mri,
    ));
  }
  final order = [for (var i = 0; i < resolved.length; i++) i];
  order.sort((a, b) {
    final byTime = resolved[a].addedAt.compareTo(resolved[b].addedAt);
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) resolved[i]];
}

PlaceLocation? _catalogLocation(String id, Map<String, City> citiesById) {
  if (!id.startsWith(kSavedPlaceIdPrefix) ||
      id.startsWith(kGeocodedPlaceIdPrefix)) {
    return null;
  }
  final city = citiesById[id.substring(kSavedPlaceIdPrefix.length)];
  if (city == null) return null;
  return catalogCityLocation(city);
}

/// 同梱カタログの都市を保存地点の位置にする (国名は英語表記のまま)。
PlaceLocation catalogCityLocation(City city) => PlaceLocation(
      latitude: city.latitude,
      longitude: city.longitude,
      country: city.country,
    );

/// 保存地点の件数と上限。
class SavedPlaceQuota {
  const SavedPlaceQuota({
    required this.count,
    required this.limit,
    required this.isPlus,
  });

  /// 保存済みの件数 (座標を補えない旧記録も含む)。
  final int count;

  /// 上限 (無料 kFreeSavedLocationLimit = 0 / Plus kPlusSavedLocationLimit = 5)。
  final int limit;

  final bool isPlus;

  /// 新しい地点を追加できるか (無料は常に false)。
  bool get canAddNew => count < limit;

  /// 上限を超えて残っているか (Plus 解約後や、無料 1 件の時期に保存した地点が
  /// ある無料ユーザー。削除はしない)。
  bool get isOverLimit => count > limit;

  /// あと何件追加できるか。
  int get remaining => count >= limit ? 0 : limit - count;

  @override
  bool operator ==(Object other) =>
      other is SavedPlaceQuota &&
      other.count == count &&
      other.limit == limit &&
      other.isPlus == isPlus;

  @override
  int get hashCode => Object.hash(count, limit, isPlus);

  @override
  String toString() => 'SavedPlaceQuota($count / $limit, plus=$isPlus)';
}

/// 候補を保存しようとしたときの判定。
enum SavedPlaceAddCheck {
  /// 新しく追加できる。
  allowed,

  /// 保存済み。再保存は更新扱い (上限に数えない)。
  alreadySaved,

  /// 無料 (保存地点は Plus 限定) → Plus 導線 (paywall)。
  needsPlus,

  /// Plus の上限に達している → 追加できない (理由を表示)。
  limitReached,
}

/// [placeId] を保存しようとしたときの判定 (候補をタップした時点の状態で呼ぶ)。
SavedPlaceAddCheck checkSavedPlaceAdd({
  required List<SavedPlace> places,
  required String placeId,
  required SavedPlaceQuota quota,
}) {
  if (places.any((p) => p.id == placeId)) {
    return SavedPlaceAddCheck.alreadySaved;
  }
  if (quota.canAddNew) return SavedPlaceAddCheck.allowed;
  return quota.isPlus
      ? SavedPlaceAddCheck.limitReached
      : SavedPlaceAddCheck.needsPlus;
}

/// 削除した地点を「元に戻す」ときの判定。
enum SavedPlaceRestoreCheck {
  /// 戻せる (件数が 1 増える)。
  allowed,

  /// 同じ地点が保存されている (削除の後に同じ地点を追加し直した)。削除前の
  /// 記録に戻すだけで件数は増えないので、上限に関係なく戻せる。
  alreadySaved,

  /// 戻すと上限を超える → 戻さない (理由を表示)。
  limitReached,
}

/// 削除した [placeId] を元に戻せるか。**元に戻す時点の**件数と上限 ([quota]) で
/// 判定する (削除した時点ではなく。QA-07)。
///
/// 戻せるのは、戻した後の件数が「今の上限」と「削除する直前の件数
/// ([countBeforeRemoval])」の大きい方を超えないとき。
/// - Plus 5 / 5 → 削除 → 別の経路 (Comfort-Twin の保存など) で 1 件追加 → 元に戻す:
///   6 > max(5, 5) で戻さない (6 / 5 にしない)。
/// - grandfathering: 地点を持ち越した無料ユーザー (上限 0) が 1 件削除 → 元に戻す:
///   5 件なら 5 ≤ max(0, 5)、1 件なら 1 ≤ max(0, 1) で戻せる。削除を取り消すだけで、
///   削除前より増えることはない (上限は新規追加だけを止め、持ち越した地点は
///   消さない、と同じ扱い)。
/// - Plus 1 件 → 削除 → Comfort-Twin で保存 (1 件) → 解約 → 元に戻す:
///   2 > max(0, 1) で戻さない (無料で削除前より増やさない)。
SavedPlaceRestoreCheck checkSavedPlaceRestore({
  required List<SavedPlace> places,
  required String placeId,
  required SavedPlaceQuota quota,
  required int countBeforeRemoval,
}) {
  if (places.any((p) => p.id == placeId)) {
    return SavedPlaceRestoreCheck.alreadySaved;
  }
  final ceiling =
      quota.limit > countBeforeRemoval ? quota.limit : countBeforeRemoval;
  return quota.count + 1 <= ceiling
      ? SavedPlaceRestoreCheck.allowed
      : SavedPlaceRestoreCheck.limitReached;
}
