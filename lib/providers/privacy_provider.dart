// lib/providers/privacy_provider.dart
//
// 「設定 → データを削除」の配線 (data/privacy/data_deletion.dart)。
// uid と Firebase の可否は push / billing の起動時初期化の成果物から取る。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/privacy/data_deletion.dart';
import '../data/privacy/firebase_data_eraser.dart';
import '../presentation/locale/locale_controller.dart';
import 'calibration_provider.dart';
import 'comfort_twin_provider.dart';
import 'entitlement_provider.dart';
import 'mri_provider.dart';
import 'place_selection_provider.dart';
import 'push_provider.dart';
import 'saved_place_weather_provider.dart';
import 'settings_provider.dart';
import 'wallpaper_provider.dart';

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final push = ref.watch(pushRuntimeProvider);
  final billing = ref.watch(billingRuntimeProvider);
  final uid = push.uid ?? billing.uid;
  final firebaseReady = push.available || billing.firebaseAvailable;
  return DataDeletionService(
    prefs: prefs,
    uid: uid,
    remote: firebaseReady && uid != null ? FirebaseDataEraser() : null,
    // ライブ壁紙の保存 (色の状態・重ね描き。Android だけ)。
    eraseWallpaper: ref.watch(wallpaperDataEraserProvider),
  );
});

/// 削除後に、端末内の設定を持つ provider を読み直させる (prefs を消したので
/// すべて既定値に戻る)。ここに無い provider は次に参照されたときに読み直す。
void invalidateLocalStateAfterDeletion(WidgetRef ref) {
  ref.invalidate(personalProfileProvider);
  ref.invalidate(notificationPreferencesProvider);
  ref.invalidate(temperatureUnitProvider);
  ref.invalidate(windSpeedUnitProvider);
  // 単位の初期値の地域 (前景で記録した地域も消えたので読み直す)。
  ref.invalidate(unitRegionProvider);
  ref.invalidate(themeModeProvider);
  // ライブ壁紙の「壁紙に天気と気温を表示」(既定のオンに戻る)。
  ref.invalidate(wallpaperWeatherProvider);
  ref.invalidate(localeControllerProvider);
  ref.invalidate(comfortRecordsProvider);
  ref.invalidate(entitlementProvider);
  // 保存地点: 表示を現在地へ戻し、メモリ上の地点ごとの天気 (座標を含む) を捨てる。
  ref.invalidate(selectedPlaceIdProvider);
  ref.invalidate(savedPlaceWeatherRepositoryProvider);
  // ライブ壁紙の色: 削除で既定 (快適) に戻したので、今の MRI で送り直す。
  // 未調整の人は θ が既定値のままで mriProvider が計算し直されず、色だけ
  // 既定の緑に残って重ね描きの区分と食い違っていた (QA-25)。
  unawaited(
    ref
        .read(wallpaperMriSyncProvider)
        .onMri(ref.read(mriProvider).valueOrNull?.value),
  );
}
