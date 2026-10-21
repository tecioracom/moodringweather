// lib/domain/notification/personal_notification_advisor.dart
//
// パーソナル通知の自動有効化「提案」ロジック(spec.md §12.6)。
// 純 Dart。Flutter / Firebase に依存しない。MRI 計算と同様にユニットテスト対象。
//
// 提案表(spec.md §12.6 そのまま):
//   気圧感受性 75%+  → 気圧急変アラート
//   湿度感受性 80%+  → 湿度急上昇アラート
//   日射感受性 70%+  → 強紫外線アラート
//   空気質感受性 70%+ → PM2.5 / AQI 急悪化
//   ※ 花粉はキャリブレーションではなく「既知の花粉アレルギーユーザー」のセルフ申告(§12.2.3)
//
// 重要: 自動 ON にはしない(§12.6)。本クラスは「提案すべきか」だけを返す。

import '../../data/models/notification_preferences.dart';

/// パーソナルキャリブレーション後の感受性ベクトル(0.0 - 1.0)。
class SensitivityVector {
  final double pressure;
  final double humidity;
  final double uv;
  final double airQuality;

  const SensitivityVector({
    this.pressure = 0,
    this.humidity = 0,
    this.uv = 0,
    this.airQuality = 0,
  });
}

/// spec.md §12.6 の閾値。Workers 側 personal-alerts.ts の SENS_* と同期させること。
class SensitivityThresholds {
  static const double pressure = 0.75;
  static const double humidity = 0.80;
  static const double uv = 0.70;
  static const double airQuality = 0.70;
}

/// 1 つの提案イベント。UI 層で「ON にしますか?」ダイアログを出す材料。
class PersonalToggleSuggestion {
  /// `personalToggles` のフィールド名と一致させる(`pressure` / `humidity` / `aqi` / `uv`)。
  final String togglekey;

  /// 表示用ラベル(日本語、spec.md §12.5 表記)。
  final String label;

  /// 提案理由(spec.md §12.6 例文)。
  final String reason;

  const PersonalToggleSuggestion({
    required this.togglekey,
    required this.label,
    required this.reason,
  });
}

class PersonalNotificationAdvisor {
  /// 感受性ベクトルと現状の設定から、まだ ON になっていない提案を返す。
  static List<PersonalToggleSuggestion> suggest(
    SensitivityVector v,
    PersonalNotificationToggles current,
  ) {
    final out = <PersonalToggleSuggestion>[];

    if (!current.pressure && v.pressure >= SensitivityThresholds.pressure) {
      out.add(const PersonalToggleSuggestion(
        togglekey: 'pressure',
        label: '気圧急変アラート',
        reason: 'キャリブレーション結果から、気圧変化に敏感な傾向がわかりました。'
            '気圧急変アラートを有効にしますか?',
      ));
    }
    if (!current.humidity && v.humidity >= SensitivityThresholds.humidity) {
      out.add(const PersonalToggleSuggestion(
        togglekey: 'humidity',
        label: '湿度急上昇アラート',
        reason: 'キャリブレーション結果から、湿度の影響を受けやすい傾向がわかりました。'
            '湿度急上昇アラートを有効にしますか?',
      ));
    }
    if (!current.uv && v.uv >= SensitivityThresholds.uv) {
      out.add(const PersonalToggleSuggestion(
        togglekey: 'uv',
        label: '強紫外線アラート',
        reason: 'キャリブレーション結果から、日射の影響を受けやすい傾向がわかりました。'
            '強紫外線アラートを有効にしますか?',
      ));
    }
    if (!current.aqi && v.airQuality >= SensitivityThresholds.airQuality) {
      out.add(const PersonalToggleSuggestion(
        togglekey: 'aqi',
        label: 'PM2.5 / AQI 急悪化アラート',
        reason: 'キャリブレーション結果から、空気質の影響を受けやすい傾向がわかりました。'
            'PM2.5 / AQI 急悪化アラートを有効にしますか?',
      ));
    }
    return out;
  }
}
