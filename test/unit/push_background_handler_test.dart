// test/unit/push_background_handler_test.dart
//
// FCM の background isolate での緊急プッシュの処理 (firebase_push_runtime.dart の
// handleBackgroundPushData)。QA-23: firebase_messaging (Android) の background
// isolate はプロセスが生きている間は使い回され、SharedPreferences のインスタンスも
// 最初に読んだ値を持ち続ける。前景 (別の isolate) で風速の単位を変えたあとの 2 通目も、
// 変えた単位で出ること (使う前に読み直していること) を確かめる。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/push/firebase_push_runtime.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 表示を記録するだけのゲートウェイ (プラットフォームの通知は出さない)。
class _RecordingGateway implements NotificationGateway {
  final bodies = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    bodies.add(body);
  }
}

Map<String, dynamic> _storm(String severity, String metric) => {
      'type': 'emergency',
      'kind': 'strong_wind',
      'severity': severity,
      'metric': metric,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('使い回される isolate でも、前景で変えた風速の単位を 2 通目から使う (QA-23)', () async {
    const nbsp = ' ';
    SharedPreferences.setMockInitialValues({
      kPrefKeyWindSpeedUnit: 'metersPerSecond',
      'app_locale_override': 'en',
    });
    // isolate が最初に取った (以後使い回される) インスタンス。
    final isolatePrefs = await SharedPreferences.getInstance();
    final gateway = _RecordingGateway();

    // 1 通目: m/s。
    await handleBackgroundPushData(
      _storm('severe', '20.0'),
      prefs: isolatePrefs,
      gateway: gateway,
    );
    expect(gateway.bodies.single, contains('20${nbsp}m/s'));

    // 前景 (別の isolate) が設定 › 一般で mph に変えた = 端末の保存先だけが変わり、
    // この isolate のインスタンスの手元の値は古いまま。
    SharedPreferences.setMockInitialValues({
      kPrefKeyWindSpeedUnit: 'milesPerHour',
      'app_locale_override': 'en',
    });
    expect(isolatePrefs.getString(kPrefKeyWindSpeedUnit), 'metersPerSecond',
        reason: '前提: 読み直すまでは古い値');

    // 2 通目 (深刻度が上がったので重複抑止には掛からない): mph で出る。
    await handleBackgroundPushData(
      _storm('danger', '30.0'),
      prefs: isolatePrefs,
      gateway: gateway,
    );
    expect(gateway.bodies, hasLength(2));
    expect(gateway.bodies.last, contains('67${nbsp}mph'));
    expect(gateway.bodies.last, isNot(contains('m/s')));
  });
}
