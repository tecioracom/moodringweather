// lib/data/services/notification_service.dart
//
// ローカル通知サービス (flutter_local_notifications ラッパ)。
// qa-test-report.md Sev1-1「通知の実配信」を v1.0 でローカル通知として成立
// させる (docs/pricing-decision.md: 緊急安全通知は永久無料・常時 ON)。
//
// TODO(fcm): 将来はサーバープッシュ (FCM/APNs + Cloudflare Workers Cron) へ
// 移行し、アプリ未起動でも配信できるようにする。v1.0 はフォアグラウンドの
// 天気取得をトリガにしたローカル通知 (best-effort) であり、アプリを開いて
// いない間は届かない。この制約は docs/qa-test-report.md に正直に申告済み。
//
// テスト方針: プラグイン呼び出しは NotificationGateway 抽象に隔離し、
// ユニットテストではフェイク実装を注入して実通信しない。

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/permissions/permission_request_queue.dart';

/// プラットフォーム通知への薄い出口。テストではフェイクに差し替える。
abstract class NotificationGateway {
  /// プラグイン初期化 + 通知権限リクエスト
  /// (iOS: alert/badge/sound、Android 13+: POST_NOTIFICATIONS)。
  /// 権限が拒否された場合も例外にしない (以後の show が黙って無視される)。
  Future<void> initialize();

  /// 通知を 1 件表示する。[critical] は WBGT 危険級など
  /// Time-Sensitive 相当の表示を要求する (対応 OS のみ)。
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  });
}

/// flutter_local_notifications 実装。
///
/// 緊急チャンネルは Importance.max。アプリ内の静音時間 (quiet hours) は
/// 緊急通知には適用しない (spec §12.2.1: 安全通知は静音時間を貫通)。
/// iOS の Critical Alert は Apple の特別な entitlement が必要なため
/// v1.0 では Time-Sensitive 相当 (interruptionLevel.timeSensitive) に留める。
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.requestPermissions = true,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// 通知がタップされてアプリが前面に来たとき (アプリ起動中・バックグラウンド中)。
  /// 保存地点を表示中でも現在地へ戻すのに使う (notification_tap_provider.dart)。
  /// 表示の経路には関与しない。FCM background isolate では渡さない (null)。
  final void Function()? onTap;

  /// initialize() で通知権限を要求するか。
  ///
  /// **FCM background isolate では false にすること。** Android 実装
  /// (flutter_local_notifications) の requestNotificationsPermission は
  /// Activity を前提にしており、アプリ終了状態の headless isolate では
  /// Activity が無く例外になる → 初期化が失敗し通知が出ない。権限は前景の
  /// 初回起動で既に確定しているため、背景では要求せず表示だけ行う
  /// (未許可なら OS が黙って捨てるだけで落ちない)。
  final bool requestPermissions;

  /// Android 通知チャンネル (緊急安全通知専用)。
  static const String emergencyChannelId = 'emergency_alerts';
  static const String emergencyChannelName = 'Emergency alerts';

  /// 実行中の初期化。起動時と緊急アラートの表示が同時に呼んでも、権限の要求を
  /// 1 回にする (2 回目の要求は Android に取り消される)。失敗したら次回やり直す。
  Future<void>? _initializing;

  @override
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize().catchError((Object e, StackTrace s) {
      _initializing = null;
      Error.throwWithStackTrace(e, s);
    });
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // 権限は下の requestPermissions でまとめて求める。
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse:
          onTap == null ? null : (_) => _notifyTap(),
    );

    // 通知権限 (拒否されても例外にしない。show が無効になるだけ)。
    // 位置情報など他の権限ダイアログと重ねない (permission_request_queue.dart)。
    if (requestPermissions) {
      await runPermissionRequest<void>(() async {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      });
    }

    _initialized = true;
  }

  /// タップの通知先の失敗でプラグインのコールバックを落とさない。
  void _notifyTap() {
    try {
      onTap?.call();
    } catch (_) {
      // 表示の切り替えは付帯機能。
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          emergencyChannelId,
          emergencyChannelName,
          channelDescription:
              'Heatstroke / storm / heavy-snow safety alerts (always on, free).',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: critical
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }
}
