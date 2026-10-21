// lib/data/models/notification_preferences.dart
//
// 通知設定モデル。spec.md §12.5 / §12.6 / §12.9 に対応。
// freezed 化は v1.1 機能取り込みのタイミングで一括して行う前提とし、
// 本ファイルでは依存ゼロの素の Dart クラスとして定義する(MRI 計算と同じ純 Dart 方針)。

/// パーソナル通知 5 種(spec.md §12.2.3)の個別 ON/OFF。
class PersonalNotificationToggles {
  final bool pressure; // 気圧急変
  final bool humidity; // 湿度急上昇
  final bool aqi; // PM2.5 / AQI
  final bool uv; // 強紫外線
  final bool pollen; // 花粉激増

  const PersonalNotificationToggles({
    this.pressure = false,
    this.humidity = false,
    this.aqi = false,
    this.uv = false,
    this.pollen = false,
  });

  bool get hasAny => pressure || humidity || aqi || uv || pollen;

  PersonalNotificationToggles copyWith({
    bool? pressure,
    bool? humidity,
    bool? aqi,
    bool? uv,
    bool? pollen,
  }) =>
      PersonalNotificationToggles(
        pressure: pressure ?? this.pressure,
        humidity: humidity ?? this.humidity,
        aqi: aqi ?? this.aqi,
        uv: uv ?? this.uv,
        pollen: pollen ?? this.pollen,
      );

  Map<String, dynamic> toJson() => {
        'pressure': pressure,
        'humidity': humidity,
        'aqi': aqi,
        'uv': uv,
        'pollen': pollen,
      };

  factory PersonalNotificationToggles.fromJson(Map<String, dynamic> json) =>
      PersonalNotificationToggles(
        pressure: json['pressure'] as bool? ?? false,
        humidity: json['humidity'] as bool? ?? false,
        aqi: json['aqi'] as bool? ?? false,
        uv: json['uv'] as bool? ?? false,
        pollen: json['pollen'] as bool? ?? false,
      );
}

/// spec.md §12.3「静音時間設定(デフォルト 22:00-7:00)」。
class QuietHours {
  /// "HH:MM"
  final String start;
  final String end;

  const QuietHours({this.start = '22:00', this.end = '07:00'});

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory QuietHours.fromJson(Map<String, dynamic> json) => QuietHours(
        start: (json['start'] as String?) ?? '22:00',
        end: (json['end'] as String?) ?? '07:00',
      );
}

/// 個別配信モード(spec.md §12.3 集約モード)。
enum NotificationDelivery { individual, digest }

/// spec.md §12.9 NotificationPreferences。
/// `personalToggles` を構造体化し、誤キーを防ぐ。
///
/// 注意: 緊急通知のトグルは**意図的に存在しない** (spec §12.2.1: 永久無料・
/// 常時 ON・オフ不可)。誤って `emergencyEnabled` を復活させないこと。
class NotificationPreferences {
  final bool weatherChangeEnabled;
  final bool personalEnabled;
  final bool lifestyleEnabled;
  final PersonalNotificationToggles personalToggles;
  final QuietHours quietHours;

  /// 1 日あたりの通知上限(1-10、デフォルト 3)
  final int dailyLimit;
  final NotificationDelivery deliveryMode;

  /// Plus: 先行アラート(リードタイム延長。spec §12.11.3)。
  /// Plus 加入者のみ ON にできる。配信側 (Workers Cron 高頻度化) は
  /// バックエンド連携後に本フラグを参照する。
  final bool leadTimeEnabled;

  /// Plus: ピンポイント補正(spec §12.11.4)。同上。
  final bool pinpointEnabled;

  const NotificationPreferences({
    this.weatherChangeEnabled = true,
    this.personalEnabled = true,
    this.lifestyleEnabled = false,
    this.personalToggles = const PersonalNotificationToggles(),
    this.quietHours = const QuietHours(),
    this.dailyLimit = 3,
    this.deliveryMode = NotificationDelivery.individual,
    this.leadTimeEnabled = false,
    this.pinpointEnabled = false,
  });

  NotificationPreferences copyWith({
    bool? weatherChangeEnabled,
    bool? personalEnabled,
    bool? lifestyleEnabled,
    PersonalNotificationToggles? personalToggles,
    QuietHours? quietHours,
    int? dailyLimit,
    NotificationDelivery? deliveryMode,
    bool? leadTimeEnabled,
    bool? pinpointEnabled,
  }) =>
      NotificationPreferences(
        weatherChangeEnabled: weatherChangeEnabled ?? this.weatherChangeEnabled,
        personalEnabled: personalEnabled ?? this.personalEnabled,
        lifestyleEnabled: lifestyleEnabled ?? this.lifestyleEnabled,
        personalToggles: personalToggles ?? this.personalToggles,
        quietHours: quietHours ?? this.quietHours,
        dailyLimit: dailyLimit ?? this.dailyLimit,
        deliveryMode: deliveryMode ?? this.deliveryMode,
        leadTimeEnabled: leadTimeEnabled ?? this.leadTimeEnabled,
        pinpointEnabled: pinpointEnabled ?? this.pinpointEnabled,
      );

  Map<String, dynamic> toJson() => {
        'weatherChangeEnabled': weatherChangeEnabled,
        'personalEnabled': personalEnabled,
        'lifestyleEnabled': lifestyleEnabled,
        'personalToggles': personalToggles.toJson(),
        'quietHours': quietHours.toJson(),
        'dailyLimit': dailyLimit,
        'deliveryMode': deliveryMode.name,
        'leadTimeEnabled': leadTimeEnabled,
        'pinpointEnabled': pinpointEnabled,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      // 旧バージョンが保存した 'emergencyEnabled' キーは単に無視される
      // (緊急通知は設定に依存しないため移行処理は不要)。
      NotificationPreferences(
        weatherChangeEnabled: json['weatherChangeEnabled'] as bool? ?? true,
        personalEnabled: json['personalEnabled'] as bool? ?? true,
        lifestyleEnabled: json['lifestyleEnabled'] as bool? ?? false,
        personalToggles: json['personalToggles'] is Map<String, dynamic>
            ? PersonalNotificationToggles.fromJson(
                json['personalToggles'] as Map<String, dynamic>)
            : const PersonalNotificationToggles(),
        quietHours: json['quietHours'] is Map<String, dynamic>
            ? QuietHours.fromJson(json['quietHours'] as Map<String, dynamic>)
            : const QuietHours(),
        dailyLimit: (json['dailyLimit'] as int?)?.clamp(1, 10) ?? 3,
        deliveryMode: _parseDelivery(json['deliveryMode']),
        leadTimeEnabled: json['leadTimeEnabled'] as bool? ?? false,
        pinpointEnabled: json['pinpointEnabled'] as bool? ?? false,
      );

  static NotificationDelivery _parseDelivery(Object? raw) {
    if (raw is String) {
      for (final v in NotificationDelivery.values) {
        if (v.name == raw) return v;
      }
    }
    return NotificationDelivery.individual;
  }
}
