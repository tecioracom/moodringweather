// lib/providers/push_provider.dart
//
// 緊急プッシュ購読 (計画 S8) の Riverpod 配線。
//   - pushRuntimeProvider: main() で initPushRuntime() の結果を override する
//     (テストの既定は disabled = 何もしない)。
//   - pushSubscriptionCoordinatorProvider: 前景受信 → EmergencyAlertController.onPushData、
//     天気取得成功 → 購読 upsert。
//
// 厳守: 課金状態 / NotificationPreferences を参照しない (spec §12.2.1)。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/push/firebase_push_runtime.dart';
import '../data/push/push_subscription.dart';
import '../presentation/locale/locale_controller.dart';
import 'emergency_alert_provider.dart';

final pushRuntimeProvider =
    Provider<PushRuntime>((ref) => PushRuntime.disabled);

final pushSubscriptionCoordinatorProvider =
    Provider<PushSubscriptionCoordinator>((ref) {
  final runtime = ref.watch(pushRuntimeProvider);
  if (!runtime.available) return PushSubscriptionCoordinator.disabled();
  final coordinator = PushSubscriptionCoordinator(
    gateway: runtime.gateway!,
    store: runtime.store!,
    uid: runtime.uid!,
    platform: runtime.platform!,
    localeOf: () => ref.read(localeControllerProvider),
    onPushData: (data) =>
        ref.read(emergencyAlertControllerProvider).onPushData(data),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
