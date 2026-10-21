// lib/presentation/settings/debug_emergency_triggers.dart
//
// デバッグビルド限定の「テスト緊急通知」用 合成気象入力 (4 種)。
// 実機テストで緊急通知の経路 (権限・表示・免責 4 言語・Time-Sensitive・
// de-dup 無視の強制発火) を、実天気に依存せず検証するためのもの。
//
// 厳守:
//   - 本ファイルは合成入力の定義のみ。判定は本番と同じ EmergencyAdvisor、
//     表示は本番と同じ経路 (EmergencyAlertController._showAlerts →
//     NotificationGateway.show、l10n 本文 + 免責文) を通す。
//   - UI 側 (notification_settings_page.dart) は kDebugMode の時だけ
//     このトリガーを表示する。リリースビルドには出さない。
//   - ラベルは kDebugMode 限定のため l10n 不要 (英語固定)。通知本文自体は
//     既存 l10n (emergency_alert_messages.dart) が解決する。

import '../../data/models/weather_snapshot.dart';
import '../../domain/safety/emergency_advisor.dart';

/// デバッグトリガー 1 件。[buildSnapshot] が返す合成入力を EmergencyAdvisor
/// に渡すと、ちょうど [expectedKind] × [expectedSeverity] のアラート 1 件が
/// 生成される (ユニットテストで担保)。
class DebugEmergencyTrigger {
  const DebugEmergencyTrigger({
    required this.label,
    required this.description,
    required this.expectedKind,
    required this.expectedSeverity,
    required this.buildSnapshot,
  });

  /// デバッグ UI のボタンラベル (英語固定。l10n 不要)。
  final String label;

  /// 合成入力の内容説明 (英語固定)。
  final String description;

  final EmergencyKind expectedKind;
  final EmergencySeverity expectedSeverity;

  /// 合成 WeatherSnapshot を生成する。座標はダミー (東京駅近辺)。
  final WeatherSnapshot Function() buildSnapshot;
}

WeatherSnapshot _snapshot({
  required double temperature,
  double? humidity,
  double? windSpeed,
  double? solarRadiationWm2,
  double? snowfallCm,
}) {
  return WeatherSnapshot(
    timestamp: DateTime.now(),
    latitude: 35.681,
    longitude: 139.767,
    temperature: temperature,
    apparentTemperature: temperature,
    humidity: humidity,
    pressure: 1013,
    windSpeed: windSpeed,
    solarRadiationWm2: solarRadiationWm2,
    snowfallCm: snowfallCm,
    condition: 'unknown',
  );
}

/// デバッグ発火トリガー 4 種。
///
/// 合成値の根拠 (EmergencyAdvisor のしきい値: 熱中症 WBGT 31/33・
/// 暴風 20/30 m/s・大雪 3/5 cm/h):
///   ① 32°C / RH58% / SR520 W/m² → WBGT ≈ 31.4 (31 ≤ x < 33 = severe)
///   ② 34°C / RH60% / SR600 W/m² → WBGT ≈ 34.1 (≥ 33 = danger →
///      Time-Sensitive 相当で表示される)
///   ③ 風速 25 m/s (20 ≤ x < 30 = severe)
///   ④ 降雪 4 cm/h (3 ≤ x < 5 = severe)
final List<DebugEmergencyTrigger> debugEmergencyTriggers = [
  DebugEmergencyTrigger(
    label: 'Heatstroke: severe',
    description: 'WBGT ~31.4 (32C / 58% / 520 W/m2)',
    expectedKind: EmergencyKind.heatStroke,
    expectedSeverity: EmergencySeverity.severe,
    buildSnapshot: () => _snapshot(
      temperature: 32,
      humidity: 58,
      solarRadiationWm2: 520,
    ),
  ),
  DebugEmergencyTrigger(
    label: 'Heatstroke: danger (Time-Sensitive)',
    description: 'WBGT ~34.1 (34C / 60% / 600 W/m2)',
    expectedKind: EmergencyKind.heatStroke,
    expectedSeverity: EmergencySeverity.danger,
    buildSnapshot: () => _snapshot(
      temperature: 34,
      humidity: 60,
      solarRadiationWm2: 600,
    ),
  ),
  DebugEmergencyTrigger(
    label: 'Storm: severe',
    description: 'Wind 25 m/s',
    expectedKind: EmergencyKind.storm,
    expectedSeverity: EmergencySeverity.severe,
    buildSnapshot: () => _snapshot(temperature: 20, windSpeed: 25),
  ),
  DebugEmergencyTrigger(
    label: 'Heavy snow: severe',
    description: 'Snowfall 4 cm/h',
    expectedKind: EmergencyKind.heavySnow,
    expectedSeverity: EmergencySeverity.severe,
    buildSnapshot: () => _snapshot(temperature: -2, snowfallCm: 4),
  ),
];
