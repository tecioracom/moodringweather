// デバッグ専用「テスト緊急通知」トリガーのユニット/ウィジェットテスト。
//
//   - debug_emergency_triggers.dart の合成入力 4 種が、本番と同じ
//     EmergencyAdvisor でちょうど期待どおりの kind × severity を生成する
//   - EmergencyAlertController.debugFire が本番表示経路 (_showAlerts →
//     NotificationGateway.show、l10n 本文 + 免責文、danger = critical) を通る
//   - debugFire は de-dup を無視して毎回発火し、かつ de-dup ストアを汚さない
//     (本番経路 onSnapshot の抑止挙動は不変)
//   - 通知設定画面にデバッグセクションが表示され、タップで発火する
//
// flutter test は debug モードで実行されるため kDebugMode = true。
// リリースビルドで UI/発火が消えることは kDebugMode のコンパイル時定数
// (tree-shaking) で担保される (ここでは検証不能なのでコードレビュー事項)。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/domain/safety/emergency_advisor.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/debug_emergency_triggers.dart';
import 'package:mood_ring_weather/presentation/settings/notification_settings_page.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('debugEmergencyTriggers (合成入力の正しさ)', () {
    const advisor = EmergencyAdvisor();

    test('4 種のトリガーが期待どおりの kind × severity をちょうど 1 件生成する', () {
      expect(debugEmergencyTriggers, hasLength(4));
      for (final trigger in debugEmergencyTriggers) {
        final alerts = advisor.evaluate(trigger.buildSnapshot());
        expect(alerts, hasLength(1), reason: trigger.label);
        expect(alerts.single.kind, trigger.expectedKind, reason: trigger.label);
        expect(alerts.single.severity, trigger.expectedSeverity,
            reason: trigger.label);
      }
    });

    test('熱中症トリガーの WBGT がしきい値帯に収まる (severe≈31.4 / danger≈34.1)', () {
      final severe =
          advisor.evaluate(debugEmergencyTriggers[0].buildSnapshot()).single;
      expect(severe.metricValue, greaterThanOrEqualTo(31.0));
      expect(severe.metricValue, lessThan(33.0));

      final danger =
          advisor.evaluate(debugEmergencyTriggers[1].buildSnapshot()).single;
      expect(danger.metricValue, greaterThanOrEqualTo(33.0));
    });
  });

  group('EmergencyAlertController.debugFire', () {
    late _FakeGateway gateway;
    late SharedPreferences prefs;

    Future<EmergencyAlertController> makeController() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      gateway = _FakeGateway();
      return EmergencyAlertController(
        gateway: gateway,
        prefs: prefs,
        localeOf: () => const Locale('ja'),
        now: () => DateTime(2026, 7, 15, 12),
      );
    }

    test('本番表示経路で実通知が出る (l10n タイトル + 免責文、danger は critical)', () async {
      final controller = await makeController();
      final alerts = await controller
          .debugFire(debugEmergencyTriggers[1].buildSnapshot()); // 熱中症 danger

      expect(alerts.single.kind, EmergencyKind.heatStroke);
      expect(alerts.single.severity, EmergencySeverity.danger);

      final t = lookupAppLocalizations(const Locale('ja'));
      final n = gateway.shown.single;
      expect(n.id, 1001);
      expect(n.title, t.emergencyHeatTitle);
      expect(n.body, contains(t.emergencyDisclaimer));
      expect(n.critical, isTrue, reason: 'danger 級は Time-Sensitive 相当');
      expect(gateway.initializeCount, 1, reason: '権限要求 (initialize) を通る');
    });

    test('de-dup を無視して毎回発火し、de-dup ストアを汚さない (本番抑止は不変)', () async {
      final controller = await makeController();
      final snapshot = debugEmergencyTriggers[1].buildSnapshot();

      await controller.debugFire(snapshot);
      await controller.debugFire(snapshot);
      expect(gateway.shown, hasLength(2), reason: 'テスト発火は de-dup 無視');

      // テスト発火は発火記録を残さない → 直後の本番経路 (onSnapshot) でも
      // 同一アラートが抑止されず発火する (実アラートを巻き込まない)。
      expect(prefs.getString(kPrefKeyEmergencyLastFired), isNull);
      await controller.onSnapshot(snapshot);
      expect(gateway.shown, hasLength(3));

      // 本番経路は記録を残すので、以後の本番経路はクールダウン内で抑止される。
      expect(prefs.getString(kPrefKeyEmergencyLastFired), isNotNull);
      await controller.onSnapshot(snapshot);
      expect(gateway.shown, hasLength(3), reason: '本番 de-dup は不変');

      // 抑止中でもテスト発火は通る。
      await controller.debugFire(snapshot);
      expect(gateway.shown, hasLength(4));
    });

    test('暴風 25 m/s / 大雪 4 cm/h のトリガーも正しい通知 ID で発火する', () async {
      final controller = await makeController();
      await controller.debugFire(debugEmergencyTriggers[2].buildSnapshot());
      await controller.debugFire(debugEmergencyTriggers[3].buildSnapshot());
      expect(gateway.shown.map((n) => n.id).toList(), [1002, 1003]);
      expect(gateway.shown.every((n) => !n.critical), isTrue,
          reason: 'severe 級は critical ではない');
    });
  });

  group('通知設定画面のデバッグセクション (kDebugMode = true で実行される)', () {
    testWidgets('デバッグセクションが表示され、タップで実通知経路が発火する', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NotificationSettingsPage(),
        ),
      ));

      // v1.3: mono の区画ラベルは大文字化される。
      expect(find.text('DEBUG: FIRE TEST EMERGENCY ALERT'), findsOneWidget);
      expect(find.text('Heatstroke: severe'), findsOneWidget);
      expect(find.text('Heatstroke: danger (Time-Sensitive)'), findsOneWidget);
      expect(find.text('Storm: severe'), findsOneWidget);
      expect(find.text('Heavy snow: severe'), findsOneWidget);

      await tester.tap(find.text('Heatstroke: danger (Time-Sensitive)'));
      await tester.pumpAndSettle();

      final t = lookupAppLocalizations(const Locale('en'));
      expect(gateway.shown, hasLength(1));
      expect(gateway.shown.single.title, t.emergencyHeatTitle);
      expect(gateway.shown.single.body, contains(t.emergencyDisclaimer));
      expect(gateway.shown.single.critical, isTrue);
      // フィードバックの SnackBar が出る。
      expect(find.textContaining('Fired heatStroke'), findsOneWidget);
    });
  });
}
