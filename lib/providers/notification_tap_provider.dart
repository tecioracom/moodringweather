// lib/providers/notification_tap_provider.dart
//
// 「通知をタップしてアプリを開いた」ことを知らせる信号。
//
// 使い道: 保存地点を表示中でも、通知 (緊急アラート = 現在地の話) から開いたら
// 表示を現在地に戻す (保存地点の出荷条件 G3。place_selection_provider.dart)。
//
// 発信元:
//   - ローカル通知 (flutter_local_notifications) のタップ
//     → LocalNotificationGateway(onTap: …) (emergency_alert_provider.dart で配線)
//   - OS が表示した FCM 通知 (iOS のハイブリッド / Android のパーソナル) からの起動
//     → PushRuntime.notificationOpened (place_selection_provider.dart で購読)
// アプリ終了状態からの起動は ProviderScope が新しく作られるため、何もしなくても
// 現在地から始まる。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationTapSignal {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// 通知のタップ (1 回ごとに 1 イベント)。
  Stream<void> get taps => _controller.stream;

  /// 通知がタップされた。例外は投げない (通知の処理を巻き込まない)。
  void notifyTapped() {
    if (_controller.isClosed) return;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}

final notificationTapSignalProvider = Provider<NotificationTapSignal>((ref) {
  final signal = NotificationTapSignal();
  ref.onDispose(signal.dispose);
  return signal;
});
