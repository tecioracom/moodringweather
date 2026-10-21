// lib/data/push/firebase_push_runtime.dart
//
// firebase_messaging / cloud_firestore / firebase_auth を使った実装と、起動時初期化。
// 計画 S8 / S10 (docs/fcm-activation-plan-v1.3.0.md)、設計 §5.2 / §5.3。
//
// グレースフル・デグラデーション (どの失敗でもアプリは通常起動・ローカル通知は不変):
//   - Firebase 構成ファイル無し / initializeApp 失敗 → PushRuntime.disabled
//   - Anonymous Auth 無効 (S1 未実施) / signInAnonymously 失敗 → disabled
//   - iOS / Android 以外 → disabled
//   - トークン取得失敗・Firestore 書き込み拒否 → Coordinator 内で握る (ログのみ)
//
// 課金基盤 (billing_initializer.dart) は RC 鍵が無いと Firebase を触らないため、
// プッシュは独立して Firebase を初期化する (initializeApp は多重呼び出し安全)。

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/permissions/permission_request_queue.dart';
import '../../presentation/locale/locale_controller.dart';
import '../../providers/emergency_alert_provider.dart';
import '../../providers/settings_provider.dart';
import '../services/notification_service.dart';
import 'push_subscription.dart';

/// 起動時初期化の成果物。Provider override に流し込む。
class PushRuntime {
  const PushRuntime({
    required this.available,
    this.uid,
    this.platform,
    this.gateway,
    this.store,
    this.notificationOpened,
  });

  /// Firebase (Auth + Firestore + Messaging) が利用可能で uid が取れたか。
  final bool available;
  final String? uid;

  /// 'ios' | 'android'。
  final String? platform;
  final PushMessagingGateway? gateway;
  final PushSubscriptionStore? store;

  /// OS が表示した FCM 通知 (iOS のハイブリッド / Android のパーソナル) を
  /// タップしてバックグラウンドから戻ったとき (FirebaseMessaging.onMessageOpenedApp)。
  /// 保存地点を表示中でも現在地へ戻すのに使う (place_selection_provider.dart)。
  final Stream<void>? notificationOpened;

  static const PushRuntime disabled = PushRuntime(available: false);
}

/// 現在のプラットフォーム名 (購読ドキュメントの platform)。対象外は null。
String? pushPlatformName([TargetPlatform? platform]) {
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return null;
  }
}

/// Firebase を (未初期化なら) 初期化し、匿名 uid を取得する。
/// 例外は内部で握りつぶし、必ず PushRuntime を返す。
Future<PushRuntime> initPushRuntime() async {
  final platform = pushPlatformName();
  if (platform == null || kIsWeb) return PushRuntime.disabled;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    final uid = user?.uid;
    if (uid == null) return PushRuntime.disabled;
    return PushRuntime(
      available: true,
      uid: uid,
      platform: platform,
      gateway: FirebaseMessagingGateway(FirebaseMessaging.instance),
      store: FirestorePushSubscriptionStore(FirebaseFirestore.instance),
      notificationOpened:
          FirebaseMessaging.onMessageOpenedApp.map<void>((_) {}),
    );
  } catch (e, st) {
    // 構成ファイル未配置・Anonymous Auth 無効 (S1 未実施) などで失敗 → 無効化。
    debugPrint('[push] Firebase init skipped, push disabled: $e');
    if (kDebugMode) debugPrintStack(stackTrace: st);
    return PushRuntime.disabled;
  }
}

/// firebase_messaging 実装。
class FirebaseMessagingGateway implements PushMessagingGateway {
  FirebaseMessagingGateway(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<Object?, Object?>> get onForegroundData =>
      FirebaseMessaging.onMessage.map((m) => m.data);

  @override
  Future<bool> requestPermission() async {
    // 他の権限ダイアログと重ねない (permission_request_queue.dart)。
    final settings = await runPermissionRequest(
      () => _messaging.requestPermission(alert: true, badge: true, sound: true),
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}

/// Firestore 実装。`updatedAt` は必ず serverTimestamp (ルールが request.time 一致を強制)。
class FirestorePushSubscriptionStore implements PushSubscriptionStore {
  FirestorePushSubscriptionStore(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<void> upsert(String uid, Map<String, Object> fields) {
    return _firestore.doc('push_subscriptions/$uid').set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// background / terminated 時の FCM 受信ハンドラ (設計 §5.3)。
///
/// background isolate は Riverpod コンテナ外で動くため、コントローラを直接組み立てる。
/// 現在値経路と同じ _showAlerts (l10n + 免責 + de-dup + gateway) を通る。失敗は握る。
/// Android では data-only で届く (fcm.ts)。iOS は OS が表示するため本ハンドラは
/// 実行されない場合がある (設計 §6.2、best-effort)。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await handleBackgroundPushData(message.data);
  } catch (e) {
    debugPrint('[push] background handler failed: $e');
  }
}

/// background isolate で data push を 1 件処理する (Firebase の初期化の後)。
///
/// firebase_messaging (Android) の background isolate は、プロセスが生きている間は
/// 使い回される。SharedPreferences のインスタンスも最初に読んだ値を持ち続けるので、
/// 前景 (別の isolate) で変えた設定 — 風速の単位・言語・重複抑止の記録 — を読むため、
/// 使う前に必ず読み直す (QA-23)。読み直しに失敗しても、手元の値で通知は出す
/// (緊急通知を設定の読み込みで落とさない。compliance-review-v1.3.0 §9-4 U4)。
/// [prefs] / [gateway] はテスト用の差し替え口。
@visibleForTesting
Future<void> handleBackgroundPushData(
  Map<String, dynamic> data, {
  SharedPreferences? prefs,
  NotificationGateway? gateway,
}) async {
  final store = prefs ?? await SharedPreferences.getInstance();
  try {
    await store.reload();
  } catch (e) {
    debugPrint('[push] prefs reload failed, using cached values: $e');
  }
  final controller = EmergencyAlertController(
    // headless isolate には Activity が無いため権限要求はしない (前景で確定済み)。
    gateway: gateway ?? LocalNotificationGateway(requestPermissions: false),
    prefs: store,
    // OS 言語リストが空の isolate でも前景で最後に解決した言語へ倒す。
    localeOf: () => resolveLocaleFromPrefs(store),
    // 暴風の風速は前景と同じ単位 (保存済みの設定、無ければ前景で記録した地域の
    // 初期値)。解決に失敗しても m/s で通知は出す (コントローラ側で握る)。
    windUnitOf: () => resolveWindSpeedUnitFromPrefs(store),
  );
  await controller.onPushData(data);
}

/// background ハンドラの登録 (Firebase が使えるときだけ。多重登録はしない)。
bool _backgroundHandlerRegistered = false;
void registerPushBackgroundHandler(PushRuntime runtime) {
  if (!runtime.available || _backgroundHandlerRegistered) return;
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  } catch (e) {
    debugPrint('[push] background handler registration failed: $e');
  }
}
