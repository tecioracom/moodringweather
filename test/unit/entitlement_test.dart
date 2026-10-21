// test/unit/entitlement_test.dart
//
// エンタイトルメントのドメインモデルと二系統合議の純ロジック検証。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';

void main() {
  group('EntitlementTier 継承順位', () {
    test('rank は pro > plus > free', () {
      expect(EntitlementTier.pro.rank, greaterThan(EntitlementTier.plus.rank));
      expect(EntitlementTier.plus.rank, greaterThan(EntitlementTier.free.rank));
    });

    test('parse は未知値を free にフォールバック', () {
      expect(EntitlementTier.parse('plus'), EntitlementTier.plus);
      expect(EntitlementTier.parse('???'), EntitlementTier.free);
      expect(EntitlementTier.parse(null), EntitlementTier.free);
    });
  });

  group('EntitlementState 機能判定', () {
    test('free は Plus 機能を一切持たない', () {
      const s = EntitlementState.free;
      expect(s.hasPlus, isFalse);
      for (final f in PlusFeature.values) {
        expect(s.can(f), isFalse, reason: '$f は free で不可');
      }
      expect(s.savedLocationLimit, kFreeSavedLocationLimit);
      // 保存地点は Plus 限定 (2026-09-30 ユーザー決裁。無料は現在地のみ)。
      expect(s.savedLocationLimit, 0);
    });

    test('plus は全 Plus 機能と地点上限5', () {
      const s = EntitlementState(tier: EntitlementTier.plus);
      expect(s.hasPlus, isTrue);
      for (final f in PlusFeature.values) {
        expect(s.can(f), isTrue);
      }
      expect(s.savedLocationLimit, kPlusSavedLocationLimit);
    });

    test('pro は plus を継承', () {
      const s = EntitlementState(tier: EntitlementTier.pro);
      expect(s.hasPlus, isTrue);
      expect(s.hasPro, isTrue);
    });

    test('JSON 往復で保持される', () {
      final s = EntitlementState(
        tier: EntitlementTier.pro,
        activeEntitlements: const {'plus', 'pro'},
        expiresAt: DateTime.utc(2027, 1, 2, 3, 4, 5),
        willRenew: true,
        isInGracePeriod: true,
        store: 'app_store',
        updatedAt: DateTime.utc(2026, 6, 25),
        source: EntitlementSource.firestore,
      );
      final round = EntitlementState.fromJson(s.toJson());
      expect(round, s);
    });
  });

  group('mergeEntitlementsByUpdatedAt (§3.6 新しい方を採用)', () {
    final older = EntitlementState(
      tier: EntitlementTier.plus,
      updatedAt: DateTime.utc(2026, 6, 1),
      source: EntitlementSource.revenueCat,
    );
    final newerFree = EntitlementState(
      tier: EntitlementTier.free,
      updatedAt: DateTime.utc(2026, 6, 20),
      source: EntitlementSource.firestore,
    );

    test('更新時刻が新しい方 (失効=free) を採用', () {
      expect(mergeEntitlementsByUpdatedAt(older, newerFree), newerFree);
    });

    test('updatedAt が無い側は劣後', () {
      const noTime = EntitlementState(tier: EntitlementTier.free);
      expect(mergeEntitlementsByUpdatedAt(older, noTime), older);
    });

    test('両方 null は free', () {
      expect(mergeEntitlementsByUpdatedAt(null, null), EntitlementState.free);
    });

    test('片方 null はもう片方', () {
      expect(mergeEntitlementsByUpdatedAt(null, older), older);
      expect(mergeEntitlementsByUpdatedAt(older, null), older);
    });
  });
}
