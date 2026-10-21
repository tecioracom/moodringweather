// lib/presentation/notifications/emergency_alert_messages.dart
//
// EmergencyAlert (domain) → 通知タイトル/本文 (l10n) の解決。
// BuildContext なしで使えるよう lookupAppLocalizations(locale) で取得した
// AppLocalizations を受け取る (通知はウィジェットツリー外で発火するため)。
//
// 厳守 (compliance §12.10.4 / mri-spec.md §5.4): すべての緊急通知本文に
// 免責文 (emergencyDisclaimer) を併記する。医療的な断定はしない。
//
// 暴風の風速は利用者の風速の単位 (設定。m/s / km/h / mph) で出す
// (compliance-review-v1.3.0 §9-4)。{wind} には WindSpeedUnit.formatRounded の
// 「20 m/s」「72 km/h」「45 mph」(数値と単位は U+00A0) を単位込みで渡し、ARB に
// 単位を書かない。判定のしきい値 (20 / 30 m/s) は m/s のまま (EmergencyAdvisor)。
// 熱中症の WBGT は °C のまま (環境省の基準の値。§9-5 R2)。

import '../../core/utils/wind_speed_unit.dart';
import '../../domain/safety/emergency_advisor.dart';
import '../../l10n/app_localizations.dart';

/// 通知 1 件分の表示文言。body には免責文が必ず含まれる。
class EmergencyAlertMessage {
  const EmergencyAlertMessage({required this.title, required this.body});

  final String title;
  final String body;
}

/// [alert] を [t] の言語でタイトル/本文に解決する。免責文を本文末尾に併記。
/// 暴風の風速は [windUnit] (既定 m/s) で、単位込みの整数 (「72 km/h」) にする。
///
/// 本文は [EmergencyAlert.source] で選び分ける:
///   - current  → 「約{値}です」(現在値。既存のローカル通知経路。文面不変)
///   - forecast → 「…の見込みです / 予想されます」(*Forecast キー。予報プッシュ)
/// 予報の数値を現在形で出すと「いまその値」と誤読させるため、混用しない。
/// サーバー側 (workers/src/cron/emergency-notifier.ts) の iOS フォールバック本文は
/// *Forecast キーと同一文字列。
EmergencyAlertMessage resolveEmergencyAlertMessage(
  AppLocalizations t,
  EmergencyAlert alert, {
  WindSpeedUnit windUnit = WindSpeedUnit.metersPerSecond,
}) {
  final value = alert.metricValue.round().toString();
  // 暴風だけは単位込み (数値と単位を 1 つの関数でまとめて作る。§9-4 U1)。
  final wind = windUnit.formatRounded(alert.metricValue);
  final danger = alert.severity == EmergencySeverity.danger;
  final String title;
  final String body;
  switch (alert.source) {
    case EmergencySource.current:
      switch (alert.kind) {
        case EmergencyKind.heatStroke:
          title = t.emergencyHeatTitle;
          body = danger
              ? t.emergencyHeatBodyDanger(value)
              : t.emergencyHeatBodySevere(value);
        case EmergencyKind.storm:
          title = t.emergencyStormTitle;
          body = t.emergencyStormBody(wind);
        case EmergencyKind.heavySnow:
          title = t.emergencySnowTitle;
          body = t.emergencySnowBody(value);
      }
    case EmergencySource.forecast:
      switch (alert.kind) {
        case EmergencyKind.heatStroke:
          title = t.emergencyHeatTitle;
          body = danger
              ? t.emergencyHeatBodyDangerForecast(value)
              : t.emergencyHeatBodySevereForecast(value);
        case EmergencyKind.storm:
          title = t.emergencyStormTitle;
          body = t.emergencyStormBodyForecast(wind);
        case EmergencyKind.heavySnow:
          title = t.emergencySnowTitle;
          body = t.emergencySnowBodyForecast(value);
      }
  }
  // 免責文の併記は必須 (独自判定であり公式警報ではない)。
  return EmergencyAlertMessage(
    title: title,
    body: '$body\n${t.emergencyDisclaimer}',
  );
}
