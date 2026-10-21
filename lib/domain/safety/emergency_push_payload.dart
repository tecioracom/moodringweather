// lib/domain/safety/emergency_push_payload.dart
//
// FCM data メッセージ → EmergencyAlert 復元パーサ (純 Dart・Flutter 非依存)。
//
// 契約の送信側正本: workers/src/lib/forecast-emergency.ts buildEmergencyDataPayload()
//   { type: 'emergency', kind: 'heat_stroke'|'strong_wind'|'heavy_snow',
//     severity: 'severe'|'danger', metric: '34.2', special?: '1',
//     source?: 'forecast'|'current' }
// キー・値を変更する場合は Workers 側と同時に改訂すること。
//
// source: Workers は予報判定しか送らないため、欠落時は forecast として扱う
// (予報の数値を現在値の文言で表示しない。安全側)。
//
// 設計 (docs/notification-delivery-design.md §5):
//   サーバー (Workers Cron) は予報判定の結果だけを data push で送り、表示文言は
//   端末側で l10n + 免責文込みで組み立てる (emergency_alert_messages.dart を再利用)。
//   dedup も端末側の EmergencyAlertDeduper を通すため、予報プッシュと現在値発火
//   (EmergencyAdvisor) の同日二重通知は dedupKey 共有で抑止される (mri-spec §5.3.2)。
//
// TODO(fcm): firebase_messaging 導入後、background message handler から
//   EmergencyAlertController.onPushData(message.data) を呼ぶ。Firebase プロジェクト
//   (google-services.json / GoogleService-Info.plist / APNs 鍵) が揃うまで未活性。

import 'emergency_advisor.dart';

/// FCM data メッセージから [EmergencyAlert] を復元するパーサ。
class EmergencyPushPayload {
  const EmergencyPushPayload._();

  /// data['type'] がこの値のときのみ緊急通知として扱う。
  static const String messageType = 'emergency';

  /// [data] (FCM RemoteMessage.data 相当) をパースする。
  ///
  /// 不正・未知の payload は null を返して黙って無視する (前方互換: 将来サーバーが
  /// 新種別を追加しても旧クライアントはクラッシュせず単に表示しない)。
  ///
  /// 'special' フィールド (予報 WBGT ≥ 35 = 特別警戒相当) は現状未使用。
  /// danger 深刻度として扱われるため安全側。最上級文言の l10n キー追加時に対応する。
  static EmergencyAlert? parse(Map<Object?, Object?> data) {
    if (data['type'] != messageType) return null;
    final kind = _kindOf(data['kind']);
    if (kind == null) return null;
    final severity = _severityOf(data['severity']);
    if (severity == null) return null;
    final metric = double.tryParse('${data['metric'] ?? ''}');
    if (metric == null || !metric.isFinite) return null;
    return EmergencyAlert(
      kind: kind,
      severity: severity,
      metricValue: metric,
      source: _sourceOf(data['source']),
    );
  }

  /// 'current' を明示されたときだけ現在値。それ以外 (欠落・未知) は予報。
  static EmergencySource _sourceOf(Object? raw) => switch (raw) {
        'current' => EmergencySource.current,
        _ => EmergencySource.forecast,
      };

  static EmergencyKind? _kindOf(Object? raw) => switch (raw) {
        'heat_stroke' => EmergencyKind.heatStroke,
        // Workers は fcm.ts の AlertKind に合わせ 'strong_wind' を送る。
        // 'storm' (Dart enum 名由来) も将来の揺れに備えて受理する。
        'strong_wind' || 'storm' => EmergencyKind.storm,
        'heavy_snow' => EmergencyKind.heavySnow,
        _ => null,
      };

  static EmergencySeverity? _severityOf(Object? raw) => switch (raw) {
        'severe' => EmergencySeverity.severe,
        'danger' => EmergencySeverity.danger,
        _ => null,
      };
}
