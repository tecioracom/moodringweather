// FCM data push 受信スキャフォールドのユニット。
//   - EmergencyPushPayload: Workers 契約 (forecast-emergency.ts) のパース
//   - EmergencyAlertController.onPushData: 予報プッシュと現在値発火の
//     dedup 共有 (mri-spec §5.3.2)・免責文併記・不正 payload の無視
// firebase_messaging 未導入 (未活性) でもロジックが正しいことを担保する。

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/domain/safety/emergency_advisor.dart';
import 'package:mood_ring_weather/domain/safety/emergency_push_payload.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ShownNotification {
  _ShownNotification(this.id, this.title, this.body, this.critical);
  final int id;
  final String title;
  final String body;
  final bool critical;
}

class _FakeGateway implements NotificationGateway {
  final shown = <_ShownNotification>[];
  int initializeCount = 0;

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
    shown.add(_ShownNotification(id, title, body, critical));
  }
}

/// Workers buildEmergencyDataPayload() と同形の payload。
Map<Object?, Object?> _payload({
  String type = 'emergency',
  String kind = 'heat_stroke',
  String severity = 'danger',
  String metric = '34.2',
  String? special,
}) =>
    {
      'type': type,
      'kind': kind,
      'severity': severity,
      'metric': metric,
      if (special != null) 'special': special,
    };

/// 猛暑 (現在値 WBGT 危険級) のスナップショット。
WeatherSnapshot _dangerHeatSnapshot() => WeatherSnapshot(
      timestamp: DateTime(2026, 7, 15, 9),
      latitude: 35.66,
      longitude: 139.75,
      temperature: 36,
      apparentTemperature: 36,
      humidity: 70,
      pressure: 1013,
      windSpeed: 3,
      solarRadiationWm2: 800,
      condition: 'sunny',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmergencyPushPayload.parse', () {
    test('熱中症 danger payload を EmergencyAlert に復元する', () {
      final alert = EmergencyPushPayload.parse(_payload())!;
      expect(alert.kind, EmergencyKind.heatStroke);
      expect(alert.severity, EmergencySeverity.danger);
      expect(alert.metricValue, 34.2);
      expect(alert.notificationId, 1001);
      // 現在値発火 (EmergencyAdvisor) と同じ dedupKey 形式 → ストア共有で
      // 同日二重通知を抑止できる (mri-spec §5.3.2)。
      expect(alert.dedupKey, 'heatStroke:danger');
    });

    test('strong_wind (fcm.ts 名) と storm (Dart 名) の両方を暴風として受理する', () {
      for (final raw in ['strong_wind', 'storm']) {
        final alert = EmergencyPushPayload.parse(
            _payload(kind: raw, severity: 'severe', metric: '22.0'))!;
        expect(alert.kind, EmergencyKind.storm, reason: raw);
        expect(alert.severity, EmergencySeverity.severe);
      }
    });

    test('heavy_snow severe を復元する', () {
      final alert = EmergencyPushPayload.parse(
          _payload(kind: 'heavy_snow', severity: 'severe', metric: '3.5'))!;
      expect(alert.kind, EmergencyKind.heavySnow);
      expect(alert.notificationId, 1003);
    });

    test('special フィールド (予報 WBGT ≥ 35) があってもパースできる', () {
      final alert =
          EmergencyPushPayload.parse(_payload(metric: '35.6', special: '1'));
      expect(alert, isNotNull);
      expect(alert!.severity, EmergencySeverity.danger);
    });

    test('source: 欠落・forecast は予報、current を明示したときだけ現在値', () {
      expect(EmergencyPushPayload.parse(_payload())!.source,
          EmergencySource.forecast);
      expect(
        EmergencyPushPayload.parse({..._payload(), 'source': 'forecast'})!
            .source,
        EmergencySource.forecast,
      );
      expect(
        EmergencyPushPayload.parse({..._payload(), 'source': 'current'})!
            .source,
        EmergencySource.current,
      );
      expect(
        EmergencyPushPayload.parse({..._payload(), 'source': 'unknown'})!
            .source,
        EmergencySource.forecast,
      );
      // source は de-dup キーに影響しない (予報プッシュと現在値発火の二重通知抑止)
      expect(EmergencyPushPayload.parse(_payload())!.dedupKey,
          'heatStroke:danger');
    });

    test('type 不一致・未知 kind・未知 severity・不正 metric は null (前方互換)', () {
      expect(EmergencyPushPayload.parse(_payload(type: 'personal')), isNull);
      expect(EmergencyPushPayload.parse(_payload(kind: 'tsunami')), isNull);
      expect(EmergencyPushPayload.parse(_payload(severity: 'extreme')), isNull);
      expect(EmergencyPushPayload.parse(_payload(metric: 'abc')), isNull);
      expect(EmergencyPushPayload.parse(_payload(metric: 'NaN')), isNull);
      expect(EmergencyPushPayload.parse(const {}), isNull);
    });
  });

  group('EmergencyAlertController.onPushData', () {
    late _FakeGateway gateway;
    late SharedPreferences prefs;

    Future<EmergencyAlertController> makeController(
        {DateTime Function()? now}) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      gateway = _FakeGateway();
      return EmergencyAlertController(
        gateway: gateway,
        prefs: prefs,
        localeOf: () => const Locale('ja'),
        now: now ?? () => DateTime(2026, 7, 15, 5),
      );
    }

    test('予報プッシュで通知が発火し、本文に免責文が併記される', () async {
      final controller = await makeController();
      await controller.onPushData(_payload());

      expect(gateway.shown, hasLength(1));
      final n = gateway.shown.single;
      final t = lookupAppLocalizations(const Locale('ja'));
      expect(n.id, 1001);
      expect(n.title, t.emergencyHeatTitle);
      expect(n.body, contains(t.emergencyDisclaimer));
      expect(n.critical, isTrue, reason: 'danger は Time-Sensitive 相当');
    });

    test('dedup 共有: 予報プッシュ後の現在値発火 (onSnapshot) は同日抑止される', () async {
      var time = DateTime(2026, 7, 15, 5); // 予報プッシュ (5:00 JST 相当)
      final controller = await makeController(now: () => time);

      await controller.onPushData(_payload()); // heatStroke:danger
      expect(gateway.shown, hasLength(1));

      // 同日昼にアプリを開き、実況も danger 級だった場合 → 二重通知しない。
      time = DateTime(2026, 7, 15, 9);
      await controller.onSnapshot(_dangerHeatSnapshot());
      expect(gateway.shown, hasLength(1),
          reason: '予報発火と現在値発火は dedupKey を共有する (mri-spec §5.3.2)');

      // クールダウン経過後は再発火 (継続する危険の再周知)。
      time = DateTime(2026, 7, 15, 12);
      await controller.onSnapshot(_dangerHeatSnapshot());
      expect(gateway.shown, hasLength(2));
    });

    test('不正な payload は初期化も発火もせず黙って無視する', () async {
      final controller = await makeController();
      await controller.onPushData(const {'type': 'unknown'});
      await controller.onPushData(const {});
      expect(gateway.initializeCount, 0);
      expect(gateway.shown, isEmpty);
    });
  });
}
