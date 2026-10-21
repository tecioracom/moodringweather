// test/qa/notification_settings_hidden_static_test.dart
//
// 配信の仕組みが無い通知設定が画面に戻らないことの静的検査
// (2026-09-30 ユーザー決裁 P1-5、compliance-review-v1.3.0 §8 N1〜N3)。
// 「天気の変化」「パーソナル通知」(マスター + 個別 5 種)・「静音時間」・「1 日の上限」は、
// オンにしても何も届かない (端末のローカル通知は緊急の 1 経路だけ、FCM も緊急以外は
// 捨てる、Workers のパーソナル通知は対象 0 件)。1.3.0 から設定 › 通知には緊急通知の
// カードだけを出す。
//
// lib/presentation の Dart ソース (コメントを除く) が、外した設定の文言キーと、
// 通知設定の値・provider を参照していないことを確かめる。保存データ・モデル・provider
// (lib/data・lib/providers) は残してある (配信を作ったら戻せるように)。
// 戻すときは compliance の再審査のうえでこの検査を外す。

import 'package:flutter_test/flutter_test.dart';

import '../fixtures/presentation_source_scan.dart';

/// 表示に使ってはいけない識別子 (ARB のキー・通知設定の値・provider)。
final Map<String, RegExp> _forbidden = {
  // N1 天気の変化
  'notifWeatherChange': RegExp(r'\bnotifWeatherChange\b'),
  // N2 パーソナル通知 (マスター + 個別)
  'notifPersonal': RegExp(r'\bnotifPersonal\b'),
  'notifPressure / notifHumidity / notifAqi / notifUv / notifPollen':
      RegExp(r'\bnotif(Pressure|Humidity|Aqi|Uv|Pollen)\b'),
  // N3 静音時間・1 日の上限
  'notifQuietHours / notifQuietStart / notifQuietEnd':
      RegExp(r'\bnotifQuiet(Hours|Start|End)\b'),
  'notifDailyLimit / notifDailyLimitValue':
      RegExp(r'\bnotifDailyLimit(Value)?\b'),
  // 設定の値と provider (画面から読み書きしない)
  'notificationPreferencesProvider':
      RegExp(r'\bnotificationPreferencesProvider\b'),
  'weatherChangeEnabled / personalEnabled':
      RegExp(r'\b(weatherChangeEnabled|personalEnabled)\b'),
  'personalToggles': RegExp(r'\bpersonalToggles\b'),
  'quietHours / QuietHours': RegExp(r'\b[qQ]uietHours\b'),
  'dailyLimit': RegExp(r'\bdailyLimit\b'),
};

void main() {
  test('外した通知設定の文言キー・値・provider を画面で使っていない (P1-5)', () {
    final hits = findForbiddenReferences(_forbidden);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('緊急通知の文言は画面に残っている (外しすぎていない)', () {
    // 緊急通知 (永久無料・常時オン) のカードは残す。
    final hits = findForbiddenReferences({
      'notifEmergency': RegExp(r'\bnotifEmergency\b'),
      'notifEmergencyAlwaysOn': RegExp(r'\bnotifEmergencyAlwaysOn\b'),
      'notifEmergencyAlwaysOnDesc': RegExp(r'\bnotifEmergencyAlwaysOnDesc\b'),
    });
    expect(hits, isNotEmpty);
  });

  test('検査の仕組みが外した設定の参照を拾える (検出器の自己確認)', () {
    const sample = '''
      title: t.notifWeatherChange,
      value: prefs.quietHours.start,
      t.notifDailyLimitValue(prefs.dailyLimit),
      QuietHours(start: hhmm, end: p.quietHours.end),
      // t.notifPersonal はコメントなので拾わない
      final prefs = ref.watch(notificationPreferencesProvider);
''';
    final body = withoutComments(sample);
    bool hit(String name) => _forbidden[name]!.hasMatch(body);
    expect(hit('notifWeatherChange'), isTrue);
    expect(hit('notifPersonal'), isFalse);
    expect(hit('notifDailyLimit / notifDailyLimitValue'), isTrue);
    expect(hit('dailyLimit'), isTrue);
    expect(_forbidden['quietHours / QuietHours']!.allMatches(body).length, 3);
    expect(hit('notificationPreferencesProvider'), isTrue);
  });
}
