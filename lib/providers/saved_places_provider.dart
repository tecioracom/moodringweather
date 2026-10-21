// lib/providers/saved_places_provider.dart
//
// 保存地点 (Plus 多地点。spec.md §12.11.5) の配線 (Riverpod)。UI はここの
// provider だけを参照する (地点タブ・地点を追加・地点管理)。
//
//   - savedPlacesProvider: 保存地点 (追加順)。旧記録の座標は同梱カタログで補う
//   - savedPlaceByIdProvider / isSavedPlaceProvider: 1 地点の参照・保存済み判定
//   - savedPlaceQuotaProvider: 件数と上限 (無料 0 = Plus 限定 / Plus 5)
//   - savedPlacesControllerProvider: 追加 (候補タップ時に上限を再判定)・元に戻す・削除
//     (削除の「元に戻す」も戻す時点の上限で再判定)
//
// 正本はオンデバイス記録 (comfortRecordsProvider、SharedPreferences のみ。
// サーバーへは送らない。spec.md §13)。上限は**新規追加**だけを止め、上限を
// 超えて残っている地点は消さない (grandfathering。無料でも表示・削除はできる)。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/city.dart';
import '../data/models/comfort_record.dart';
import '../data/models/place_candidate.dart';
import '../data/models/saved_place.dart';
import '../domain/places/saved_place_rules.dart';
import 'clock_provider.dart';
import 'comfort_twin_provider.dart';
import 'entitlement_provider.dart';

/// 保存地点 (追加順 = 古い順)。
final savedPlacesProvider = Provider<List<SavedPlace>>((ref) {
  final records = ref.watch(comfortRecordsProvider);
  // 旧 Comfort-Twin 記録の座標を補うためのカタログ (読み込み前は空 → 補えた
  // 時点で再計算される)。
  final catalog = ref.watch(cityCatalogProvider).valueOrNull ?? const <City>[];
  return resolveSavedPlaces(records, catalog);
});

/// 保存地点 1 件 (無ければ null)。値が同じなら再通知しない (SavedPlace は値比較)。
final savedPlaceByIdProvider =
    Provider.autoDispose.family<SavedPlace?, String>((ref, placeId) {
  for (final place in ref.watch(savedPlacesProvider)) {
    if (place.id == placeId) return place;
  }
  return null;
});

/// [placeId] (例: 候補の `placeId`) が保存済みか。候補行の「保存済み」表示用。
final isSavedPlaceProvider = Provider.autoDispose.family<bool, String>(
  (ref, placeId) => ref.watch(savedPlaceByIdProvider(placeId)) != null,
);

/// 保存地点の件数と上限 (無料 0 = Plus 限定 / Plus 5)。
final savedPlaceQuotaProvider = Provider<SavedPlaceQuota>((ref) {
  return SavedPlaceQuota(
    count: ref.watch(savedPlacesProvider).length,
    limit: ref.watch(savedLocationLimitProvider),
    isPlus: ref.watch(isPlusProvider),
  );
});

/// 保存地点の追加・元に戻す・削除。
final savedPlacesControllerProvider = Provider<SavedPlacesController>(
  (ref) => SavedPlacesController(ref),
);

/// 候補を保存した結果。[undo] に渡すと元に戻せる。
class SavedPlaceAddResult {
  const SavedPlaceAddResult._({
    required this.check,
    required this.placeId,
    ComfortRecord? previous,
  }) : _previous = previous;

  /// 保存しようとしたときの判定 (追加 / 更新 / Plus 導線 / 上限)。
  final SavedPlaceAddCheck check;

  /// 対象の保存地点 ID (`place-geo-{geonamesId}`)。
  final String placeId;

  /// 更新前の記録 (新規追加なら null)。
  final ComfortRecord? _previous;

  /// 保存 (追加または更新) したか。false なら何も書いていない。
  bool get saved =>
      check == SavedPlaceAddCheck.allowed ||
      check == SavedPlaceAddCheck.alreadySaved;

  /// 新しく追加したか (false: 更新 or 保存していない)。
  bool get isNew => check == SavedPlaceAddCheck.allowed;
}

/// 保存地点を削除した結果。「元に戻す」で [SavedPlacesController.restore] に渡す。
class SavedPlaceRemoval {
  const SavedPlaceRemoval._({required this.record, required this.countBefore});

  /// 削除した記録 (元に戻すとこの内容・追加時刻のまま戻る)。
  final ComfortRecord record;

  /// 削除する直前の保存地点の件数。元に戻すときの上限の判定に使う
  /// (grandfathering で持ち越した件数までは戻せる。checkSavedPlaceRestore)。
  final int countBefore;

  /// 削除した保存地点の ID。
  String get placeId => record.id;
}

class SavedPlacesController {
  SavedPlacesController(this._ref);

  final Ref _ref;

  /// [candidate] を保存しようとしたときの判定。**候補をタップした時点で**
  /// 呼ぶ (シートを開いた後に購入・解約・別端末での追加があっても最新の
  /// 課金状態と件数で判定する)。
  SavedPlaceAddCheck check(PlaceCandidate candidate) => checkSavedPlaceAdd(
        places: _ref.read(savedPlacesProvider),
        placeId: candidate.placeId,
        quota: _ref.read(savedPlaceQuotaProvider),
      );

  /// [candidate] が保存済みか。
  bool isSaved(PlaceCandidate candidate) => isSavedId(candidate.placeId);

  /// [placeId] が保存済みか。
  bool isSavedId(String placeId) =>
      _ref.read(savedPlacesProvider).any((p) => p.id == placeId);

  /// 候補を保存する (候補タップで即追加)。上限はここで判定し直す。
  ///
  /// - 新規: 末尾 (追加順の最後) に加わる
  /// - 保存済み: 表示名・地域・座標を更新する (並び順は変えない)
  /// - 無料 (保存地点は Plus 限定) / Plus の上限: 何も書かずに判定だけ返す
  ///   (UI は needsPlus → paywall、limitReached → 理由を表示)
  Future<SavedPlaceAddResult> add(
    PlaceCandidate candidate, {
    DateTime? now,
  }) async {
    final check = this.check(candidate);
    if (check == SavedPlaceAddCheck.needsPlus ||
        check == SavedPlaceAddCheck.limitReached) {
      return SavedPlaceAddResult._(check: check, placeId: candidate.placeId);
    }

    ComfortRecord? previous;
    for (final r in _ref.read(comfortRecordsProvider)) {
      if (r.id == candidate.placeId) previous = r;
    }
    final at = now ?? _ref.read(clockProvider)();
    await _ref.read(comfortRecordsProvider.notifier).upsertPlace(
          ComfortRecord(
            id: candidate.placeId,
            type: ComfortRecordType.place,
            // 候補の時点では天気を取っていない (MRI は地点ごとの取得で出す)。
            mri: null,
            savedAt: at,
            label: candidate.name,
            location: candidate.toLocation(),
            addedAt:
                previous == null ? at : previous.addedAt ?? previous.savedAt,
          ),
        );
    return SavedPlaceAddResult._(
      check: check,
      placeId: candidate.placeId,
      previous: previous,
    );
  }

  /// [add] を元に戻す (トーストの「元に戻す」)。新規なら削除、更新なら更新前へ。
  /// 表示中の地点だった場合、表示は現在地に戻る (place_selection_provider)。
  Future<void> undo(SavedPlaceAddResult result) async {
    if (!result.saved) return;
    final notifier = _ref.read(comfortRecordsProvider.notifier);
    final previous = result._previous;
    if (previous == null) {
      await notifier.remove(result.placeId);
    } else {
      await notifier.restorePlace(previous);
    }
  }

  /// 今の件数と上限 (無料 0 / Plus 5)。
  SavedPlaceQuota get quota => _ref.read(savedPlaceQuotaProvider);

  /// 保存地点 [placeId] を削除する (地点管理)。表示中なら表示は現在地に戻る。
  ///
  /// 戻り値は削除の結果 (「元に戻す」で [restore] に渡す)。無ければ null。
  Future<SavedPlaceRemoval?> remove(String placeId) async {
    ComfortRecord? removed;
    for (final r in _ref.read(comfortRecordsProvider)) {
      if (r.id == placeId) removed = r;
    }
    if (removed == null) return null;
    final countBefore = _ref.read(savedPlacesProvider).length;
    await _ref.read(comfortRecordsProvider.notifier).remove(placeId);
    return SavedPlaceRemoval._(record: removed, countBefore: countBefore);
  }

  /// [remove] で消した地点を元に戻す (追加時刻を保つので並び順も元どおり)。
  ///
  /// **戻す時点の**課金状態と件数で上限を判定し直す (QA-07。削除の後に
  /// Comfort-Twin の保存などで追加されていると、そのまま戻すと上限を超える)。
  /// 戻り値が [SavedPlaceRestoreCheck.limitReached] のときは何も書いていない
  /// (UI は理由を表示する)。
  Future<SavedPlaceRestoreCheck> restore(SavedPlaceRemoval removal) async {
    final check = checkSavedPlaceRestore(
      places: _ref.read(savedPlacesProvider),
      placeId: removal.placeId,
      quota: quota,
      countBeforeRemoval: removal.countBefore,
    );
    if (check == SavedPlaceRestoreCheck.limitReached) return check;
    await _ref.read(comfortRecordsProvider.notifier).restorePlace(
          removal.record,
        );
    return check;
  }

  /// Comfort-Twin の比較画面「この場所を保存」。上限の判定はここで行う
  /// (地名検索の追加と同じ規則: 無料 0 = Plus 限定 / Plus 5、保存済みの
  /// 再保存は更新扱い、上限を超えて残る地点は消さない)。無料は needsPlus
  /// (UI は Paywall を開く)。
  ///
  /// 戻り値が needsPlus / limitReached のときは何も書いていない。
  Future<SavedPlaceAddCheck> saveCatalogCity(City city, int mri) async {
    final check = checkSavedPlaceAdd(
      places: _ref.read(savedPlacesProvider),
      placeId: savedPlaceIdForCatalogCity(city.id),
      quota: _ref.read(savedPlaceQuotaProvider),
    );
    if (check == SavedPlaceAddCheck.needsPlus ||
        check == SavedPlaceAddCheck.limitReached) {
      return check;
    }
    await _ref.read(comfortRecordsProvider.notifier).savePlace(city, mri);
    return check;
  }
}
