// lib/domain/safety/emergency_advisor.dart
//
// 緊急アラート判定器 (v1.0 公開ゲート / qa-test-report.md Sev1-1 対応)。
// WeatherSnapshot から緊急 3 種 (①熱中症 ②暴風 ③大雪) を評価して
// EmergencyAlert のリストを返す。純 Dart (Flutter 非依存・ユニットテスト対象)。
//
// 方針 (docs/pricing-decision.md / spec §12.2.1):
//   - 緊急通知は課金状態に関わらず永久無料・常時 ON。静音時間も貫通する。
//     設定 (NotificationPreferences) を一切参照しないのはそのため。
//   - 本判定は気象庁・環境省の公式警報/アラートではなく Open-Meteo 由来
//     データからの独自判定 (mri-spec.md §5.4 / spec §12.10.4)。通知本文には
//     必ず免責文 (l10n: emergencyDisclaimer) を併記すること。

import '../../data/models/weather_snapshot.dart';
import 'wbgt_calculator.dart';

/// 緊急通知 3 種 (spec §12.2.1)。
enum EmergencyKind {
  /// 熱中症 (WBGT 31/33 の発火ルール。mri-spec.md §5.3.1)
  heatStroke,

  /// 暴風
  storm,

  /// 大雪
  heavySnow,
}

/// アラートの深刻度 2 段階。
/// severe = 通常の緊急通知、danger = Time-Sensitive / Critical 級。
enum EmergencySeverity { severe, danger }

/// 判定結果 1 件。種別・深刻度・表示用の実測値を持つ。
/// メッセージ本文の組み立て (l10n) は presentation 層
/// (emergency_alert_messages.dart) が行い、免責文をそこで必ず併記する。
class EmergencyAlert {
  const EmergencyAlert({
    required this.kind,
    required this.severity,
    required this.metricValue,
    this.source = EmergencySource.current,
  });

  final EmergencyKind kind;
  final EmergencySeverity severity;

  /// 表示用の値。heatStroke: WBGT °C / storm: 風速 m/s / heavySnow: 降雪 cm/h。
  final double metricValue;

  /// [metricValue] の実体 (現在値か予報か)。文言の選択にのみ使い、de-dup キー
  /// ([dedupKey]) には含めない (予報プッシュと同日の現在値発火の二重通知を
  /// 抑止するため。mri-spec §5.3.2)。既定は現在値 (EmergencyAdvisor の経路)。
  final EmergencySource source;

  /// 通知 ID は kind ごとに固定 (同種は OS 側で上書き表示される)。
  /// 1001=熱中症, 1002=暴風, 1003=大雪。
  int get notificationId => 1001 + kind.index;

  /// オンデバイス重複防止 (de-dup) 用キー。種別 × 深刻度で同一視する
  /// (深刻度が上がった場合は別キーになり再通知される)。
  String get dedupKey => '${kind.name}:${severity.name}';
}

/// [EmergencyAlert.metricValue] の実体。文言を「いま」と「見込み」で
/// 選び分けるための区別 (安全に関わる数値の誤読防止)。
enum EmergencySource {
  /// 前景の天気取得から算出した現在値 (EmergencyAdvisor)。
  current,

  /// Workers Cron の予報判定 (予報日最高 WBGT / 今後 24h の風・雪)。
  /// FCM data push 経由でのみ到来する (emergency_push_payload.dart)。
  forecast,
}

/// 緊急 3 種の判定器。
///
/// しきい値の根拠 (いずれも「独自判定の参考情報」であり公式警報基準そのもの
/// ではない。免責文併記が前提):
///
/// - 熱中症 (mri-spec.md §5.3.1。表示用の WbgtLevel 区分からは発火を導出
///   しない): WBGT ≥ 31 で severe (環境省「危険」区分到達 = 外出を
///   なるべく避けるべきレベル)、WBGT ≥ 33 で danger (公式「熱中症警戒
///   アラート」の発表基準値に実況が到達)。28-31 (厳重警戒) はプッシュせず
///   アプリ内の Heat Alert 表示のみ (通知疲れによる安全上の逆転を防ぐ)。
/// - 暴風: 気象庁「風の強さと吹き方」の区分を参考に、平均風速 20 m/s 以上
///   (非常に強い風 = 何かにつかまらないと立てない・暴風警報級の目安) で
///   severe、30 m/s 以上 (猛烈な風) で danger。
/// - 大雪: 1 時間降雪量 3 cm/h 以上 (大雪注意報級の強い降り方の目安) で
///   severe、5 cm/h 以上 (大雪警報・「顕著な大雪に関する気象情報」級:
///   3 時間 15 cm 前後に相当) で danger。
class EmergencyAdvisor {
  const EmergencyAdvisor();

  /// 熱中症 (WBGT °C)。mri-spec.md §5.3.1 の発火しきい値。
  /// 31 = 環境省「危険」区分到達 / 33 = 熱中症警戒アラート発表基準値。
  static const double heatSevereWbgtC = 31.0;
  static const double heatDangerWbgtC = 33.0;

  /// 暴風 (m/s)。
  static const double stormSevereWindMs = 20.0;
  static const double stormDangerWindMs = 30.0;

  /// 大雪 (cm/h)。
  static const double snowSevereCmPerHour = 3.0;
  static const double snowDangerCmPerHour = 5.0;

  /// [snapshot] を評価し、発火すべき緊急アラートを返す (0-3 件)。
  ///
  /// [solarRadiationWm2] / [snowfallCm] は snapshot に値がない場合の
  /// 明示注入フック (テスト・将来の別データ源用)。両方ある場合は引数優先。
  List<EmergencyAlert> evaluate(
    WeatherSnapshot snapshot, {
    double? solarRadiationWm2,
    double? snowfallCm,
  }) {
    final alerts = <EmergencyAlert>[];

    // ① 熱中症: WBGT ≥ 31 (severe) / ≥ 33 (danger) で発火 (mri-spec §5.3.1)。
    //    表示用の WbgtLevel 区分とは独立した発火しきい値。
    final humidity = snapshot.humidity;
    if (humidity != null) {
      final wbgt = WbgtCalculator.compute(
        tempC: snapshot.temperature,
        humidityPercent: humidity,
        solarRadiationWm2: solarRadiationWm2 ?? snapshot.solarRadiationWm2,
      );
      if (wbgt >= heatSevereWbgtC) {
        alerts.add(EmergencyAlert(
          kind: EmergencyKind.heatStroke,
          severity: wbgt >= heatDangerWbgtC
              ? EmergencySeverity.danger
              : EmergencySeverity.severe,
          metricValue: wbgt,
        ));
      }
    }

    // ② 暴風: 平均風速のしきい値判定。
    final wind = snapshot.windSpeed;
    if (wind != null && wind >= stormSevereWindMs) {
      alerts.add(EmergencyAlert(
        kind: EmergencyKind.storm,
        severity: wind >= stormDangerWindMs
            ? EmergencySeverity.danger
            : EmergencySeverity.severe,
        metricValue: wind,
      ));
    }

    // ③ 大雪: 1 時間降雪量のしきい値判定。
    final snow = snowfallCm ?? snapshot.snowfallCm;
    if (snow != null && snow >= snowSevereCmPerHour) {
      alerts.add(EmergencyAlert(
        kind: EmergencyKind.heavySnow,
        severity: snow >= snowDangerCmPerHour
            ? EmergencySeverity.danger
            : EmergencySeverity.severe,
        metricValue: snow,
      ));
    }

    return alerts;
  }
}

/// オンデバイスの再発火防止 (de-dup)。純 Dart。
///
/// 同一 dedupKey (種別 × 深刻度) はクールダウン時間内は再発火しない。
/// 深刻度が上がるとキーが変わるため即時に再通知される (安全側)。
/// 状態は JSON で永続化できる (SharedPreferences 等に保存する想定)。
class EmergencyAlertDeduper {
  EmergencyAlertDeduper({
    Map<String, DateTime>? lastFired,
    this.cooldown = const Duration(hours: 6),
  }) : _lastFired = Map.of(lastFired ?? const {});

  /// 同一アラートを抑止する時間。公式の警報運用に合わせた厳密値ではなく、
  /// 「同じ危険が続く間に通知を連打しない」ための実用値。
  final Duration cooldown;

  final Map<String, DateTime> _lastFired;

  /// [key] のアラートを [now] 時点で発火してよいか。
  bool shouldFire(String key, DateTime now) {
    final last = _lastFired[key];
    if (last == null) return true;
    return now.difference(last) >= cooldown;
  }

  /// 発火を記録する。
  void recordFired(String key, DateTime now) {
    _lastFired[key] = now;
  }

  Map<String, dynamic> toJson() =>
      _lastFired.map((k, v) => MapEntry(k, v.toIso8601String()));

  factory EmergencyAlertDeduper.fromJson(
    Map<String, dynamic> json, {
    Duration cooldown = const Duration(hours: 6),
  }) {
    final map = <String, DateTime>{};
    json.forEach((k, v) {
      final t = v is String ? DateTime.tryParse(v) : null;
      if (t != null) map[k] = t;
    });
    return EmergencyAlertDeduper(lastFired: map, cooldown: cooldown);
  }
}
