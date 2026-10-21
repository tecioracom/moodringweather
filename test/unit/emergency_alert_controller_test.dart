// 緊急通知コントローラ (emergency_alert_provider.dart) のユニット。
// NotificationGateway をフェイクに差し替え、実プラグイン/実通信なしで
//   - 判定 → 発火 (タイトル/本文に免責文)
//   - de-dup (再発火防止・永続化・深刻度エスカレーション)
//   - 設定非依存 (緊急通知は常時 ON・静音時間貫通)
// を検証する。

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/wind_speed_unit.dart';
import 'package:mood_ring_weather/data/models/notification_preferences.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ShownNotification {
  _ShownNotification(this.id, this.title, this.body, this.critical);
  final int id;
  final String title;
  final String body;
  final bool critical;
}

/// 実プラグインを使わないフェイクゲートウェイ。
class _FakeGateway implements NotificationGateway {
  final shown = <_ShownNotification>[];
  int initializeCount = 0;
  bool failOnShow = false;

  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    if (failOnShow) throw StateError('plugin unavailable');
    shown.add(_ShownNotification(id, title, body, critical));
  }
}

WeatherSnapshot _snapshot({
  double temp = 25,
  double humidity = 50,
  double wind = 3,
  double? solar,
  double? snow,
}) =>
    WeatherSnapshot(
      timestamp: DateTime(2026, 7, 15, 12),
      latitude: 35.66,
      longitude: 139.75,
      temperature: temp,
      apparentTemperature: temp,
      humidity: humidity,
      pressure: 1013,
      windSpeed: wind,
      solarRadiationWm2: solar,
      snowfallCm: snow,
      condition: 'sunny',
    );

/// 猛暑 (WBGT 危険級) のスナップショット。
WeatherSnapshot _dangerHeat() => _snapshot(temp: 36, humidity: 70, solar: 800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGateway gateway;
  late SharedPreferences prefs;

  Future<EmergencyAlertController> makeController({
    DateTime Function()? now,
    Locale locale = const Locale('ja'),
    Map<String, Object> initialPrefs = const {},
    WindSpeedUnit Function()? windUnitOf,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();
    gateway = _FakeGateway();
    return EmergencyAlertController(
      gateway: gateway,
      prefs: prefs,
      localeOf: () => locale,
      windUnitOf: windUnitOf,
      now: now ?? () => DateTime(2026, 7, 15, 12),
    );
  }

  test('危険級の猛暑で通知が 1 件発火し、本文に免責文が併記される', () async {
    final controller = await makeController();
    await controller.onSnapshot(_dangerHeat());

    expect(gateway.shown, hasLength(1));
    final n = gateway.shown.single;
    final t = lookupAppLocalizations(const Locale('ja'));
    expect(n.id, 1001);
    expect(n.title, t.emergencyHeatTitle);
    expect(n.body, contains(t.emergencyDisclaimer));
    expect(n.critical, isTrue); // danger 級は Time-Sensitive 相当
  });

  test('快適時は初期化も発火もしない', () async {
    final controller = await makeController();
    await controller.onSnapshot(_snapshot());
    expect(gateway.initializeCount, 0);
    expect(gateway.shown, isEmpty);
  });

  test('de-dup: 同一アラートはクールダウン内に再発火しない', () async {
    var time = DateTime(2026, 7, 15, 12);
    final controller = await makeController(now: () => time);

    await controller.onSnapshot(_dangerHeat());
    time = time.add(const Duration(minutes: 30));
    await controller.onSnapshot(_dangerHeat());
    expect(gateway.shown, hasLength(1), reason: '30 分後の同一アラートは抑止');

    time = time.add(const Duration(hours: 6));
    await controller.onSnapshot(_dangerHeat());
    expect(gateway.shown, hasLength(2), reason: 'クールダウン経過後は再発火');
  });

  test('de-dup: 発火記録は SharedPreferences に永続化される', () async {
    final controller = await makeController();
    await controller.onSnapshot(_dangerHeat());

    final raw = prefs.getString(kPrefKeyEmergencyLastFired);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded.keys, contains('heatStroke:danger'));

    // 同じ prefs から作り直した別コントローラでも抑止が効く (再起動相当)。
    final controller2 = EmergencyAlertController(
      gateway: gateway,
      prefs: prefs,
      localeOf: () => const Locale('ja'),
      now: () => DateTime(2026, 7, 15, 12, 30),
    );
    await controller2.onSnapshot(_dangerHeat());
    expect(gateway.shown, hasLength(1));
  });

  test('de-dup: 深刻度が上がると即時に再発火する (安全側)', () async {
    var wind = 22.0; // severe
    var time = DateTime(2026, 7, 15, 12);
    final controller = await makeController(now: () => time);

    await controller.onSnapshot(_snapshot(wind: wind));
    expect(gateway.shown, hasLength(1));
    expect(gateway.shown.last.critical, isFalse);

    wind = 32.0; // danger へエスカレーション
    time = time.add(const Duration(minutes: 10));
    await controller.onSnapshot(_snapshot(wind: wind));
    expect(gateway.shown, hasLength(2), reason: 'キーが変わるので即時再発火');
    expect(gateway.shown.last.critical, isTrue);
  });

  test('常時 ON: 終日静音・上限 1 件という設定が保存されていても発火する', () async {
    final controller = await makeController();
    // ユーザーが終日静音・上限 1 件の設定を持っていても緊急通知は貫通する
    // (spec §12.2.1。コントローラは NotificationPreferences を参照しない。
    // 緊急トグル自体がモデルに存在しないため OFF にする経路もない)。
    await prefs.setString(
      kPrefKeyNotificationPrefs,
      jsonEncode(
        const NotificationPreferences(
          quietHours: QuietHours(start: '00:00', end: '23:59'),
          dailyLimit: 1,
        ).toJson(),
      ),
    );

    await controller.onSnapshot(_dangerHeat());
    expect(gateway.shown, hasLength(1));
  });

  test('複数アラート同時発生時は全件発火する', () async {
    final controller = await makeController();
    await controller.onSnapshot(
        _snapshot(temp: 36, humidity: 70, solar: 800, wind: 25, snow: 6));
    expect(gateway.shown.map((n) => n.id).toSet(), {1001, 1002, 1003});
  });

  test('ゲートウェイの失敗は握りつぶし、呼び出し元に伝播しない', () async {
    final controller = await makeController();
    gateway.failOnShow = true;
    await expectLater(controller.onSnapshot(_dangerHeat()), completes);
  });

  group('暴風の本文の風速の単位 (compliance-review-v1.3.0 §9-4)', () {
    const nbsp = '\u00A0';

    test('渡された単位で出す (22 m/s → 49 mph)。判定は m/s のまま', () async {
      final controller = await makeController(
        locale: const Locale('en'),
        windUnitOf: () => WindSpeedUnit.milesPerHour,
      );
      await controller.onSnapshot(_snapshot(wind: 22));
      final n = gateway.shown.single;
      expect(n.id, 1002);
      expect(n.body, contains('49${nbsp}mph')); // 22 × 2.237 = 49.2
      expect(n.body, isNot(contains('m/s')));
      // 19.9 m/s は km/h にしても発火しない (しきい値は m/s)。
      final quiet = await makeController(
        windUnitOf: () => WindSpeedUnit.kilometersPerHour,
      );
      await quiet.onSnapshot(_snapshot(wind: 19.9));
      expect(gateway.shown, isEmpty);
    });

    test('単位の解決に失敗しても m/s で通知は出す', () async {
      final controller = await makeController(
        locale: const Locale('en'),
        windUnitOf: () => throw StateError('prefs unavailable'),
      );
      await controller.onSnapshot(_snapshot(wind: 25));
      expect(gateway.shown, hasLength(1));
      expect(gateway.shown.single.body, contains('25${nbsp}m/s'));
      final t = lookupAppLocalizations(const Locale('en'));
      expect(gateway.shown.single.body, contains(t.emergencyDisclaimer));
    });

    test('既定 (FCM background isolate と同じ): 保存済みの設定を読む', () async {
      final controller = await makeController(
        locale: const Locale('en'),
        initialPrefs: {kPrefKeyWindSpeedUnit: 'kilometersPerHour'},
      );
      await controller.onPushData({
        'type': 'emergency',
        'kind': 'strong_wind',
        'severity': 'severe',
        'metric': '20.0',
      });
      expect(gateway.shown.single.body, contains('72${nbsp}km/h'));
    });

    test('既定: 保存が無く OS のロケールも取れない isolate は、前景で記録した地域', () async {
      final controller = await makeController(
        locale: const Locale('en'),
        initialPrefs: {kPrefKeyUnitRegionLastSeen: 'US'},
        windUnitOf: () => resolveWindSpeedUnitFromPrefs(
          prefs,
          systemLocales: const [],
        ),
      );
      await controller.onPushData({
        'type': 'emergency',
        'kind': 'strong_wind',
        'severity': 'danger',
        'metric': '30.0',
      });
      expect(gateway.shown.single.body, contains('67${nbsp}mph'));
    });
  });

  test('言語設定に応じた言語で通知文言が解決される (en)', () async {
    final controller = await makeController(locale: const Locale('en'));
    await controller.onSnapshot(_dangerHeat());
    final t = lookupAppLocalizations(const Locale('en'));
    expect(gateway.shown.single.title, t.emergencyHeatTitle);
    expect(gateway.shown.single.body, contains(t.emergencyDisclaimer));
  });
}
