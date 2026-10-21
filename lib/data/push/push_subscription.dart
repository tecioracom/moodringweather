// lib/data/push/push_subscription.dart
//
// 緊急プッシュ購読 `push_subscriptions/{uid}` の登録ロジック (純 Dart・Firebase 非依存)。
// 計画: docs/fcm-activation-plan-v1.3.0.md S8 / 設計: docs/notification-delivery-design.md §4.2, §5。
// スキーマとルールの正本: firestore.rules (キー集合は hasOnly で固定)。
//
// 厳守:
//   - 緊急通知は課金状態に関わらず永久無料・常時 ON (spec §12.2.1)。
//     本モジュールは NotificationPreferences (quietHours / dailyLimit) も
//     エンタイトルメントも参照しない。opt-out フィールドを書く経路は存在しない。
//   - 座標は小数 1 桁 (≈ 10 km) に丸めて 1 点だけ上書き保存する (COARSE・履歴非保持。spec §13)。
//     サーバー側 (emergency-notifier.ts) は同一粗座標で予報取得を共有する。
//   - 位置情報が使えず既定地点 (東京) にフォールバックしている間は登録しない
//     (本人と無関係な地点のアラートを送らないため)。
//   - Firebase / FCM が使えない環境では PushSubscriptionCoordinator.disabled が
//     何もしない (ローカル通知経路は影響を受けない)。
//
// テスト方針: プラットフォーム呼び出しは PushMessagingGateway / PushSubscriptionStore
// 抽象に隔離し、ユニットテストではフェイクを注入する (firebase_push_runtime.dart が実装)。

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;

/// firestore.rules が許可するキー集合 (updatedAt はストア側が serverTimestamp で付与)。
const Set<String> kPushSubscriptionClientKeys = {
  'fcmToken',
  'platform',
  'locale',
  'lat',
  'lon',
};

/// 小数 1 桁 (≈ 10 km) へ丸める。サーバーの `lat.toFixed(1)` キーと一致させる。
double roundCoarse(double v) => (v * 10).roundToDouble() / 10;

/// 購読ドキュメントのクライアント側フィールド (updatedAt を除く)。
///
/// 返す Map のキーは [kPushSubscriptionClientKeys] と完全一致する
/// (firestore.rules の hasOnly/hasAll を満たす)。
Map<String, Object> buildPushSubscriptionFields({
  required String fcmToken,
  required String platform,
  required Locale locale,
  required double latitude,
  required double longitude,
}) {
  assert(platform == 'ios' || platform == 'android');
  return {
    'fcmToken': fcmToken,
    'platform': platform,
    'locale': locale.toLanguageTag(),
    'lat': roundCoarse(latitude),
    'lon': roundCoarse(longitude),
  };
}

/// FCM (firebase_messaging) への薄い出口。
abstract class PushMessagingGateway {
  /// 現在の登録トークン。未取得・失敗時は null。
  Future<String?> getToken();

  /// トークン更新 (onTokenRefresh)。
  Stream<String> get onTokenRefresh;

  /// 前景受信の data payload (RemoteMessage.data)。
  Stream<Map<Object?, Object?>> get onForegroundData;

  /// 通知権限の要求 (iOS: alert/badge/sound、Android 13+: POST_NOTIFICATIONS)。
  /// 許可されていれば true。拒否・失敗は false (例外にしない)。
  ///
  /// 呼び出しタイミングは UX 設計に委ねる (docs/activation-definition.md:
  /// 価値を見せた後に出す)。Coordinator は自動では呼ばない。
  Future<bool> requestPermission();
}

/// Firestore `push_subscriptions/{uid}` への薄い出口。
abstract class PushSubscriptionStore {
  /// ドキュメント全体を [fields] + `updatedAt: serverTimestamp()` で置き換える
  /// (merge しない = 余計なキーが残らない)。
  Future<void> upsert(String uid, Map<String, Object> fields);
}

/// 購読登録の司令塔。
///
/// - `onSnapshot`: 天気取得成功 (= 自分の MRI が表示された後) に呼ぶ。
///   トークン・座標・言語・platform が前回登録と同じなら書き込まない (冪等)。
/// - `start`: 前景受信とトークン更新の購読を開始する。
/// - どの失敗も握りつぶす (通知は付帯機能。天気表示を巻き込まない)。
class PushSubscriptionCoordinator {
  PushSubscriptionCoordinator({
    required PushMessagingGateway gateway,
    required PushSubscriptionStore store,
    required String uid,
    required String platform,
    required Locale Function() localeOf,
    required Future<void> Function(Map<Object?, Object?> data) onPushData,
  })  : _gateway = gateway,
        _store = store,
        _uid = uid,
        _platform = platform,
        _localeOf = localeOf,
        _onPushData = onPushData,
        enabled = true;

  /// Firebase 不在・対象外プラットフォーム・uid 未取得のときの無効実装。
  /// すべてのメソッドが何もせずに返る。
  PushSubscriptionCoordinator.disabled()
      : _gateway = null,
        _store = null,
        _uid = null,
        _platform = null,
        _localeOf = null,
        _onPushData = null,
        enabled = false;

  final PushMessagingGateway? _gateway;
  final PushSubscriptionStore? _store;
  final String? _uid;
  final String? _platform;
  final Locale Function()? _localeOf;
  final Future<void> Function(Map<Object?, Object?> data)? _onPushData;

  /// 有効 (Firebase 利用可) か。
  final bool enabled;

  /// 直近に登録が成功したフィールド (冪等判定用)。
  Map<String, Object>? _lastRegistered;

  /// 直近の実座標 (トークン更新時の再登録に使う)。
  ({double lat, double lon})? _lastPosition;

  final List<StreamSubscription<Object?>> _subs = [];
  bool _started = false;

  /// 直近に登録したフィールド (テスト・デバッグ表示用)。
  Map<String, Object>? get lastRegistered =>
      _lastRegistered == null ? null : Map.unmodifiable(_lastRegistered!);

  /// 前景受信 → onPushData、トークン更新 → 再登録 の購読を開始 (1 回だけ)。
  void start() {
    if (!enabled || _started) return;
    _started = true;
    final gateway = _gateway!;
    _subs.add(gateway.onForegroundData.listen(
      (data) => _guard(() => _onPushData!(data)),
      onError: (_) {},
    ));
    _subs.add(gateway.onTokenRefresh.listen(
      (token) => _guard(() => _registerWithToken(token)),
      onError: (_) {},
    ));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  /// 天気取得成功時に呼ぶ。[isFallbackLocation] が true (既定地点) なら登録しない。
  Future<void> onSnapshot({
    required double latitude,
    required double longitude,
    bool isFallbackLocation = false,
  }) async {
    if (!enabled || isFallbackLocation) return;
    _lastPosition = (lat: latitude, lon: longitude);
    await _guard(() async {
      final token = await _gateway!.getToken();
      if (token == null || token.isEmpty) return;
      await _registerWithToken(token);
    });
  }

  /// 通知権限を要求する呼び出し口 (UX の文脈で呼ぶ)。無効時は false。
  Future<bool> requestPermission() async {
    if (!enabled) return false;
    try {
      return await _gateway!.requestPermission();
    } catch (e) {
      debugPrint('[push] requestPermission failed: $e');
      return false;
    }
  }

  Future<void> _registerWithToken(String token) async {
    final pos = _lastPosition;
    if (pos == null) return; // 実座標が無い (フォールバック中/未取得) 間は登録しない
    final fields = buildPushSubscriptionFields(
      fcmToken: token,
      platform: _platform!,
      locale: _localeOf!(),
      latitude: pos.lat,
      longitude: pos.lon,
    );
    if (_sameFields(fields, _lastRegistered)) return; // 冪等: 変化なしなら書かない
    await _store!.upsert(_uid!, fields);
    _lastRegistered = fields;
  }

  static bool _sameFields(Map<String, Object> a, Map<String, Object>? b) {
    if (b == null || a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      // 通知は付帯機能。失敗は記録だけして呼び出し元を巻き込まない。
      debugPrint('[push] subscription step failed: $e');
    }
  }
}
