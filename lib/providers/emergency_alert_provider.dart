// lib/providers/emergency_alert_provider.dart
//
// 緊急通知のトリガ配線 (qa-test-report.md Sev1-1 対応)。
// 天気取得 (weather_provider の weatherSnapshotProvider) が成功するたびに
// EmergencyAdvisor で判定し、必要ならローカル通知を発火する。
//
// 厳守 (spec §12.2.1 / docs/pricing-decision.md):
//   - 緊急通知は課金状態に関わらず永久無料・常時 ON。
//     NotificationPreferences (quietHours / dailyLimit 等) を一切参照しない
//     のは意図的 (静音時間を貫通し、上限にも数えない)。緊急トグルは
//     モデル自体に存在しない (誤って復活させないこと)。
//   - 通知本文には免責文を必ず併記 (emergency_alert_messages.dart)。
//
// 配信の限界 (正直な申告):
//   v1.0 はフォアグラウンドの天気取得をトリガにしたローカル通知のみ。
//   アプリを開いていない間は届かない。
//   TODO(background): workmanager / BGTaskScheduler による定期チェックは
//     iOS の実行保証がなく best-effort にしかならないため v1.0 では見送り
//     (weather-science 決定)。
//   FCM/APNs + Workers Cron によるサーバープッシュ (予報判定) は onPushData() で
//     受ける。配線: lib/data/push/firebase_push_runtime.dart (前景 / background)。
//     実配信はコンソール側の前提 (docs/fcm-activation-plan-v1.3.0.md S1〜S5) が
//     揃ってから。揃うまでは Firebase 初期化が失敗し push は無効のまま (無害)。

import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/wind_speed_unit.dart';
import '../data/models/weather_snapshot.dart';
import '../data/services/notification_service.dart';
import '../domain/safety/emergency_advisor.dart';
import '../domain/safety/emergency_push_payload.dart';
import '../l10n/app_localizations.dart';
import '../presentation/locale/locale_controller.dart';
import '../presentation/notifications/emergency_alert_messages.dart';
import 'notification_tap_provider.dart';
import 'settings_provider.dart';

/// de-dup の直近発火記録 (オンデバイス) の永続化キー。
const String kPrefKeyEmergencyLastFired = 'emergency_alert_last_fired';

/// 緊急通知コントローラ。判定 → de-dup → 表示 を 1 箇所に集約する。
///
/// 暴風の本文の風速は [windUnitOf] の単位 (既定は保存済みの設定、無ければ地域の
/// 初期値 = resolveWindSpeedUnitFromPrefs。前景・FCM background isolate とも同じ)。
/// 単位の解決に失敗しても通知は出す (m/s に倒す。compliance-review-v1.3.0 §9-4 U4)。
class EmergencyAlertController {
  EmergencyAlertController({
    required NotificationGateway gateway,
    required SharedPreferences prefs,
    required Locale Function() localeOf,
    WindSpeedUnit Function()? windUnitOf,
    EmergencyAdvisor advisor = const EmergencyAdvisor(),
    DateTime Function()? now,
  })  : _gateway = gateway,
        _prefs = prefs,
        _localeOf = localeOf,
        _windUnitOf =
            windUnitOf ?? (() => resolveWindSpeedUnitFromPrefs(prefs)),
        _advisor = advisor,
        _now = now ?? DateTime.now;

  final NotificationGateway _gateway;
  final SharedPreferences _prefs;
  final Locale Function() _localeOf;
  final WindSpeedUnit Function() _windUnitOf;
  final EmergencyAdvisor _advisor;
  final DateTime Function() _now;

  /// 暴風の本文に使う風速の単位。解決に失敗したら m/s (通知そのものは止めない)。
  WindSpeedUnit _windUnit() {
    try {
      return _windUnitOf();
    } catch (_) {
      return WindSpeedUnit.metersPerSecond;
    }
  }

  /// 天気取得成功時に呼ぶ。判定 → de-dup → ローカル通知発火。
  /// 通知まわりの失敗で天気表示を巻き込まない (best-effort・例外は握る)。
  Future<void> onSnapshot(WeatherSnapshot snapshot) async {
    try {
      await _showAlerts(_advisor.evaluate(snapshot));
    } catch (_) {
      // 通知は付帯機能。失敗しても天気取得フローを止めない。
    }
  }

  /// FCM data push (Workers Cron の予報判定) 受信時に呼ぶ。
  ///
  /// 契約は workers/src/lib/forecast-emergency.ts buildEmergencyDataPayload()。
  /// 現在値判定 (onSnapshot) と同じ表示経路 (l10n + 免責文) と de-dup ストアを
  /// 通すため、予報プッシュと現在値発火の同日二重通知は dedupKey 共有で抑止
  /// される (mri-spec §5.3.2)。不正な payload は黙って無視する。
  ///
  /// 呼び出し元: 前景は PushSubscriptionCoordinator (FirebaseMessaging.onMessage)、
  ///   background / terminated は firebaseMessagingBackgroundHandler
  ///   (lib/data/push/firebase_push_runtime.dart。Riverpod コンテナ外で直接組み立て)。
  Future<void> onPushData(Map<Object?, Object?> data) async {
    try {
      final alert = EmergencyPushPayload.parse(data);
      if (alert == null) return;
      await _showAlerts([alert]);
    } catch (_) {
      // 通知は付帯機能。失敗しても呼び出し元 (受信ハンドラ) を巻き込まない。
    }
  }

  /// デバッグビルド限定: 合成 [snapshot] を本番と同じ EmergencyAdvisor で
  /// 判定し、**de-dup を無視して**本番と同じ表示経路 (_showAlerts →
  /// NotificationGateway.show、l10n 本文 + 免責文、danger は Time-Sensitive
  /// 相当) で実通知を発火する。実機での経路検証 (権限・表示・4 言語) 用。
  ///
  /// 厳守:
  ///   - リリースビルドでは何もしない (kDebugMode ガード)。
  ///   - 本番経路 (onSnapshot / onPushData) の de-dup は不変。本メソッドは
  ///     発火記録を**残さない**ため、テスト発火が実アラートを抑止することも
  ///     ない (de-dup ストアを汚さない)。
  ///
  /// 戻り値は判定されたアラート (UI のフィードバック表示・テスト検証用)。
  Future<List<EmergencyAlert>> debugFire(WeatherSnapshot snapshot) async {
    if (!kDebugMode) return const [];
    final alerts = _advisor.evaluate(snapshot);
    await _showAlerts(alerts, debugIgnoreDedup: true);
    return alerts;
  }

  /// 判定済みアラート列を de-dup を通して表示する共通経路。
  ///
  /// [debugIgnoreDedup] は kDebugMode の debugFire 専用 (de-dup の参照も
  /// 記録もしない)。本番呼び出し (onSnapshot / onPushData) は常に既定値。
  Future<void> _showAlerts(
    List<EmergencyAlert> alerts, {
    bool debugIgnoreDedup = false,
  }) async {
    if (alerts.isEmpty) return;

    await _gateway.initialize();
    final t = lookupAppLocalizations(_localeOf());
    final windUnit = _windUnit();
    final deduper = _loadDeduper();
    var fired = false;

    for (final alert in alerts) {
      final now = _now();
      // 同一 (種別 × 深刻度) はクールダウン内は再発火しない。
      // 深刻度が上がった場合はキーが変わるため即時に通知される。
      if (!debugIgnoreDedup && !deduper.shouldFire(alert.dedupKey, now)) {
        continue;
      }

      final message = resolveEmergencyAlertMessage(
        t,
        alert,
        windUnit: windUnit,
      );
      await _gateway.show(
        id: alert.notificationId,
        title: message.title,
        body: message.body,
        critical: alert.severity == EmergencySeverity.danger,
      );
      if (!debugIgnoreDedup) {
        deduper.recordFired(alert.dedupKey, now);
        fired = true;
      }
    }

    if (fired) {
      await _prefs.setString(
        kPrefKeyEmergencyLastFired,
        jsonEncode(deduper.toJson()),
      );
    }
  }

  EmergencyAlertDeduper _loadDeduper() {
    final raw = _prefs.getString(kPrefKeyEmergencyLastFired);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return EmergencyAlertDeduper.fromJson(decoded);
        }
      } on FormatException {
        // 壊れた保存値は捨てて新規に始める (再通知側に倒す = 安全側)。
      }
    }
    return EmergencyAlertDeduper();
  }
}

/// プラットフォーム通知ゲートウェイ。テストではフェイクに override する。
/// 通知のタップは notificationTapSignalProvider へ流す (保存地点を表示中でも
/// 現在地へ戻す。表示・de-dup の経路には関与しない)。
final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  final tapSignal = ref.watch(notificationTapSignalProvider);
  return LocalNotificationGateway(onTap: tapSignal.notifyTapped);
});

final emergencyAlertControllerProvider =
    Provider<EmergencyAlertController>((ref) {
  return EmergencyAlertController(
    gateway: ref.watch(notificationGatewayProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    localeOf: () => ref.read(localeControllerProvider),
    // 前景は画面と同じ設定 (保存済み、無ければ地域の初期値)。
    windUnitOf: () => ref.read(windSpeedUnitProvider),
  );
});
