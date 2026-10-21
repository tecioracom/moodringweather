// lib/providers/place_selection_provider.dart
//
// ホーム / 詳細で「どの地点を表示しているか」(null = 現在地)。
//
// 出荷条件 G3:
//   - 永続化しない。アプリ起動時は常に現在地 (状態はメモリのみ)
//   - 通知をタップして開いたら現在地 (緊急アラートは現在地の話)
//   - バックグラウンドに 30 分以上いたら、戻ったとき現在地
//   - 表示中の保存地点が削除されたら現在地 (元に戻す・データ削除を含む)
// 表示の切り替えだけを担う。現在地の天気・緊急アラート・push 購読・壁紙は
// 選択に関係なく現在地のまま (weather_provider.dart / main.dart)。
//
// アプリのライフサイクルは main.dart (MoodRingApp.didChangeAppLifecycleState) から
// onAppLifecycleChanged に渡す。

import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clock_provider.dart';
import 'notification_tap_provider.dart';
import 'push_provider.dart';
import 'saved_places_provider.dart';

/// この時間以上バックグラウンドにいたら、戻ったときに現在地の表示へ戻す。
const Duration kPlaceSelectionBackgroundTimeout = Duration(minutes: 30);

class PlaceSelectionController extends StateNotifier<String?> {
  PlaceSelectionController({
    required bool Function(String placeId) isSaved,
    DateTime Function()? clock,
    this.backgroundTimeout = kPlaceSelectionBackgroundTimeout,
  })  : _isSaved = isSaved,
        _clock = clock ?? DateTime.now,
        super(null);

  /// [placeId] が今保存されているか (呼んだ時点の保存地点で判定する)。
  final bool Function(String placeId) _isSaved;

  final DateTime Function() _clock;

  /// これ以上バックグラウンドにいたら現在地へ戻す。
  final Duration backgroundTimeout;

  DateTime? _backgroundedAt;

  /// 表示中が現在地か。
  bool get isShowingCurrentLocation => state == null;

  /// 保存地点 [placeId] を表示する (null なら現在地)。保存されていない ID は
  /// 現在地として扱う (削除済みの地点を表示しない)。追加した直後の地点も
  /// そのまま選べる (保存地点をその場で引き直して判定する)。
  void select(String? placeId) {
    state = placeId != null && _isSaved(placeId) ? placeId : null;
  }

  /// 現在地の表示に戻す (「現在地」タブ・現在地行のタップ・「現在地に戻る」)。
  void showCurrentLocation() => state = null;

  /// 通知をタップして開いた (G3)。
  void onNotificationOpened() => state = null;

  /// 保存地点の一覧が変わった。表示中の地点が消えたら現在地へ戻す。
  void onSavedPlacesChanged(Iterable<String> placeIds) {
    final current = state;
    if (current != null && !placeIds.contains(current)) state = null;
  }

  /// アプリのライフサイクル (main.dart から)。見えなくなった時刻を覚え、
  /// 戻ったときに [backgroundTimeout] 以上経っていれば現在地へ戻す。
  void onAppLifecycleChanged(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundedAt ??= _clock();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && _clock().difference(since) >= backgroundTimeout) {
          state = null;
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // inactive (通知センター・着信の重なりなど) は前面のまま扱う。
        break;
    }
  }
}

/// 表示中の保存地点 ID (null = 現在地)。永続化しない (G3)。
final selectedPlaceIdProvider =
    StateNotifierProvider<PlaceSelectionController, String?>((ref) {
  final controller = PlaceSelectionController(
    isSaved: (placeId) =>
        ref.read(savedPlacesProvider).any((p) => p.id == placeId),
    clock: ref.watch(clockProvider),
  );

  // 表示中の地点が削除されたら現在地へ。
  ref.listen(
    savedPlacesProvider,
    (_, places) =>
        controller.onSavedPlacesChanged([for (final p in places) p.id]),
  );

  // 通知 (ローカル通知・OS が表示した FCM 通知) から開いたら現在地へ。
  final subscriptions = <StreamSubscription<void>>[
    ref
        .watch(notificationTapSignalProvider)
        .taps
        .listen((_) => controller.onNotificationOpened()),
    if (ref.watch(pushRuntimeProvider).notificationOpened case final opened?)
      opened.listen(
        (_) => controller.onNotificationOpened(),
        onError: (Object _) {},
      ),
  ];
  ref.onDispose(() {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
  });
  return controller;
});
