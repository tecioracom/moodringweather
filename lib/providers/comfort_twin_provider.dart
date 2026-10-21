// lib/providers/comfort_twin_provider.dart
//
// Comfort-Twin の配線 (Riverpod)。
//   - cityCatalogProvider: 同梱カタログ (assets/cities.json)
//   - twinCandidatesProvider: 候補都市の現在気象を Open-Meteo 一括取得 →
//     各都市の MRI を算出 (テストでは本 provider を override して実通信しない)
//   - comfortRecordsProvider: オンデバイス記録 (今日の体感 / 保存地点)。
//     保存地点の読み出し・追加・上限判定は saved_places_provider.dart。
//
// プライバシー: 候補都市はアプリ同梱の静的リストで、ユーザーの現在地とは
// 無関係。記録は SharedPreferences のみ (spec.md §13: サーバー送信なし)。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/city_catalog_datasource.dart';
import '../data/models/city.dart';
import '../data/models/comfort_record.dart';
import '../data/models/saved_place.dart';
import '../domain/comfort_twin/twin_matcher.dart';
import '../domain/mri/mri_calculator.dart';
import '../domain/places/saved_place_rules.dart';
import '../presentation/locale/locale_controller.dart'
    show sharedPreferencesProvider;
import 'calibration_provider.dart';
import 'weather_provider.dart';

/// 永続化キー (settings_provider の単純キー方針に合わせる)。
const String kPrefKeyComfortRecords = 'comfort_twin_records';

/// 「今日の体感」の保持上限 (古いものから捨てる)。
///
/// 上限は**種類ごと**。v1.3.0 以前は保存地点と合算で 30 件だったため、
/// 体感を記録し続けると保存地点が古い順に消えていた。保存地点はここでは
/// 捨てない (上限は追加時に無料 0 = Plus 限定 / Plus 5 で判定し、上限を超えて
/// 残る地点は消さない = grandfathering。saved_places_provider.dart)。
const int kDayFeelRecordsLimit = 30;

/// 旧名 (「今日の体感」の上限と同じ値)。
const int kComfortRecordsLimit = kDayFeelRecordsLimit;

final cityCatalogDataSourceProvider = Provider<CityCatalogDataSource>(
  (ref) => const CityCatalogDataSource(),
);

/// 同梱の候補都市カタログ。
final cityCatalogProvider = FutureProvider<List<City>>((ref) async {
  return ref.watch(cityCatalogDataSourceProvider).load();
});

/// 候補都市の「現在の体感」一覧 (都市 + 気象 + MRI)。
/// Open-Meteo の複数地点一括取得 (カンマ区切り) を 1 リクエストで行い、
/// 学習済みの感受性ベクトル θ を適用した MRI を都市ごとに算出する。
final twinCandidatesProvider = FutureProvider<List<CityComfort>>((ref) async {
  final cities = await ref.watch(cityCatalogProvider.future);
  final client = ref.watch(weatherApiClientProvider);
  final profile = ref.watch(personalProfileProvider);

  final snapshots = await client.fetchCurrentBulk([
    for (final c in cities) (latitude: c.latitude, longitude: c.longitude),
  ]);

  return [
    for (var i = 0; i < cities.length; i++)
      if (snapshots[i] != null)
        CityComfort(
          city: cities[i],
          snapshot: snapshots[i]!,
          mri: MriCalculator.calculate(snapshots[i]!, profile: profile),
        ),
  ];
});

/// オンデバイス記録 (今日の体感 / 保存地点)。新しい順。
///
/// 保存地点の並び順 (追加順) は記録の順ではなく `addedAt` で決める
/// (domain/places/saved_place_rules.dart の resolveSavedPlaces)。
class ComfortRecordsController extends StateNotifier<List<ComfortRecord>> {
  ComfortRecordsController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  /// 「今日の体感」を記録する。同日重複は上書き (最新の値を残す)。
  Future<void> saveDayFeel(int mri, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final sameDay = state.where((r) =>
        r.type == ComfortRecordType.day &&
        r.savedAt.year == at.year &&
        r.savedAt.month == at.month &&
        r.savedAt.day == at.day);
    final next = [
      ComfortRecord(
        id: 'day-${at.millisecondsSinceEpoch}',
        type: ComfortRecordType.day,
        mri: mri,
        savedAt: at,
      ),
      for (final r in state)
        if (!sameDay.contains(r)) r,
    ];
    await _replace(next);
  }

  /// 「この場所を保存」(Compare 画面)。同一都市は最新の MRI で上書きし、
  /// 先頭 (新しい順) へ移す。座標は同梱カタログの値を持たせる。
  /// 追加時刻 (addedAt) は最初に保存したときのまま (保存地点の並び順を保つ)。
  Future<void> savePlace(City city, int mri, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final id = savedPlaceIdForCatalogCity(city.id);
    final existing = _find(id);
    final next = [
      ComfortRecord(
        id: id,
        type: ComfortRecordType.place,
        mri: mri,
        savedAt: at,
        label: city.name,
        emoji: city.emoji,
        location: catalogCityLocation(city),
        addedAt: existing == null ? at : existing.addedAt ?? existing.savedAt,
      ),
      for (final r in state)
        if (r.id != id) r,
    ];
    await _replace(next);
  }

  /// 保存地点を追加・更新する (地名検索の候補から)。
  ///
  /// 同じ id があれば、記録の位置と追加時刻 (addedAt) を保ったまま中身を
  /// 置き換える (再保存は更新扱い。並び順は変えない)。無ければ先頭に入れ、
  /// addedAt を付ける。**上限判定はしない** (呼び出し側 = SavedPlacesController)。
  Future<void> upsertPlace(ComfortRecord record) async {
    assert(record.type == ComfortRecordType.place);
    final index = state.indexWhere((r) => r.id == record.id);
    if (index < 0) {
      await _replace([
        record.copyWith(addedAt: record.addedAt ?? record.savedAt),
        ...state,
      ]);
      return;
    }
    final existing = state[index];
    final next = [...state];
    next[index] = record.copyWith(
      addedAt: existing.addedAt ?? existing.savedAt,
    );
    await _replace(next);
  }

  /// 以前の状態の保存地点に戻す (追加の「元に戻す」で、更新前へ戻すとき)。
  /// 同じ id があればその位置で置き換え、無ければ先頭に入れる。
  Future<void> restorePlace(ComfortRecord previous) async {
    assert(previous.type == ComfortRecordType.place);
    final index = state.indexWhere((r) => r.id == previous.id);
    if (index < 0) {
      await _replace([previous, ...state]);
      return;
    }
    final next = [...state];
    next[index] = previous;
    await _replace(next);
  }

  Future<void> remove(String id) async {
    await _replace([
      for (final r in state)
        if (r.id != id) r,
    ]);
  }

  ComfortRecord? _find(String id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _replace(List<ComfortRecord> next) async {
    final capped = applyComfortRecordLimits(next);
    state = capped;
    await _prefs.setString(
      kPrefKeyComfortRecords,
      jsonEncode([for (final r in capped) r.toJson()]),
    );
  }

  static List<ComfortRecord> _load(SharedPreferences prefs) {
    final raw = prefs.getString(kPrefKeyComfortRecords);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        // 壊れた 1 件だけを捨てる (1 件の破損で保存地点まで全部失わない)。
        return [
          for (final e in decoded)
            if (ComfortRecord.tryParse(e) case final record?) record,
        ];
      }
    } catch (_) {
      // 壊れた保存値は空へフォールバック (再保存で上書きされる)。
    }
    return const [];
  }
}

/// 種類ごとの保持上限を当てる (記録は新しい順)。
///
/// 「今日の体感」は新しい [kDayFeelRecordsLimit] 件だけ残す。保存地点は捨てない
/// (体感の記録で保存地点が巻き添えに消えないようにする。上限は追加時に判定)。
List<ComfortRecord> applyComfortRecordLimits(List<ComfortRecord> records) {
  var days = 0;
  return [
    for (final r in records)
      if (r.type != ComfortRecordType.day || ++days <= kDayFeelRecordsLimit) r,
  ];
}

final comfortRecordsProvider =
    StateNotifierProvider<ComfortRecordsController, List<ComfortRecord>>((ref) {
  return ComfortRecordsController(ref.watch(sharedPreferencesProvider));
});
