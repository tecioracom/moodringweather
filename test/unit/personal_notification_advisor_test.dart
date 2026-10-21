// test/unit/personal_notification_advisor_test.dart
//
// spec.md §12.6 提案ロジックのユニットテスト。
// 純 Dart テスト(flutter_test に依存せず test パッケージで実行可能だが、
// プロジェクト方針に合わせて flutter_test を使う想定で書く)。

import 'package:flutter_test/flutter_test.dart';

import 'package:mood_ring_weather/data/models/notification_preferences.dart';
import 'package:mood_ring_weather/domain/notification/personal_notification_advisor.dart';

void main() {
  group('PersonalNotificationAdvisor.suggest', () {
    test('気圧感受性 0.75 ジャストで気圧提案が出る', () {
      final s = PersonalNotificationAdvisor.suggest(
        const SensitivityVector(pressure: 0.75),
        const PersonalNotificationToggles(),
      );
      expect(s.length, 1);
      expect(s.first.togglekey, 'pressure');
    });

    test('既に ON のトグルは提案されない', () {
      final s = PersonalNotificationAdvisor.suggest(
        const SensitivityVector(pressure: 0.9),
        const PersonalNotificationToggles(pressure: true),
      );
      expect(s, isEmpty);
    });

    test('全項目が閾値超 → 4 種提案(花粉はセルフ申告のため対象外)', () {
      final s = PersonalNotificationAdvisor.suggest(
        const SensitivityVector(
            pressure: 0.9, humidity: 0.9, uv: 0.9, airQuality: 0.9),
        const PersonalNotificationToggles(),
      );
      expect(s.map((e) => e.togglekey).toSet(),
          {'pressure', 'humidity', 'uv', 'aqi'});
    });

    test('湿度は 0.79 では提案されない(閾値 0.80)', () {
      final s = PersonalNotificationAdvisor.suggest(
        const SensitivityVector(humidity: 0.79),
        const PersonalNotificationToggles(),
      );
      expect(s, isEmpty);
    });
  });

  group('NotificationPreferences JSON', () {
    test('toJson / fromJson でラウンドトリップ', () {
      const pref = NotificationPreferences(
        personalToggles:
            PersonalNotificationToggles(pressure: true, uv: true, pollen: true),
        quietHours: QuietHours(start: '23:00', end: '06:30'),
        dailyLimit: 5,
        deliveryMode: NotificationDelivery.digest,
      );
      final round = NotificationPreferences.fromJson(pref.toJson());
      expect(round.personalToggles.pressure, true);
      expect(round.personalToggles.uv, true);
      expect(round.personalToggles.pollen, true);
      expect(round.quietHours.start, '23:00');
      expect(round.dailyLimit, 5);
      expect(round.deliveryMode, NotificationDelivery.digest);
    });

    test('dailyLimit は 1-10 にクランプされる', () {
      final pref = NotificationPreferences.fromJson({
        'dailyLimit': 20,
      });
      expect(pref.dailyLimit, 10);
      final pref2 = NotificationPreferences.fromJson({
        'dailyLimit': 0,
      });
      expect(pref2.dailyLimit, 1);
    });
  });
}
