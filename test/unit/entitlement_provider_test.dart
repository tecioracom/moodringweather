// test/unit/entitlement_provider_test.dart
//
// EntitlementController の合議・デバッグ上書きを Fake ゲートウェイで検証する。
// (実 RevenueCat / Firebase には依存しない host VM テスト。)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_initializer.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBillingGateway implements BillingGateway {
  final StreamController<EntitlementState> _controller =
      StreamController<EntitlementState>.broadcast();
  EntitlementState fetchResult = EntitlementState.free;

  void emit(EntitlementState s) => _controller.add(s);

  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => fetchResult;
  @override
  Future<List<PlusPackage>> fetchPackages() async => const [];
  @override
  Future<PurchaseResult> purchase(String packageId) async =>
      const PurchaseResult(PurchaseStatus.purchased);
  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.purchased);
  @override
  Future<bool> openManageSubscriptions() async => true;
  @override
  Future<void> dispose() async => _controller.close();
}

Future<(ProviderContainer, FakeBillingGateway)> _build({
  EntitlementState fetch = EntitlementState.free,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = FakeBillingGateway()..fetchResult = fetch;
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    billingRuntimeProvider.overrideWithValue(BillingRuntime(gateway: fake)),
  ]);
  addTearDown(container.dispose);
  return (container, fake);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('既定 (鍵なし相当) は free', () async {
    final (c, _) = await _build();
    expect(c.read(entitlementProvider).hasPlus, isFalse);
    expect(c.read(isPlusProvider), isFalse);
    expect(c.read(savedLocationLimitProvider), kFreeSavedLocationLimit);
  });

  test('起動フェッチで Plus が反映される', () async {
    final (c, _) = await _build(
      fetch: EntitlementState(
        tier: EntitlementTier.plus,
        updatedAt: DateTime.utc(2026, 6, 25),
        source: EntitlementSource.revenueCat,
      ),
    );
    c.read(entitlementProvider); // controller を起動
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isTrue);
    expect(c.read(savedLocationLimitProvider), kPlusSavedLocationLimit);
  });

  test('customerInfo 更新ストリームで Plus→失効が反映される', () async {
    final (c, fake) = await _build();
    c.read(entitlementProvider);
    await Future<void>.delayed(Duration.zero);

    fake.emit(EntitlementState(
      tier: EntitlementTier.plus,
      updatedAt: DateTime.utc(2026, 6, 25),
      source: EntitlementSource.revenueCat,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isTrue);

    // 失効 (より新しい updatedAt)
    fake.emit(EntitlementState(
      tier: EntitlementTier.free,
      updatedAt: DateTime.utc(2026, 6, 26),
      source: EntitlementSource.revenueCat,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isFalse);
  });

  test('デバッグ上書きで実購入なしに Plus 化できる (kDebugMode)', () async {
    final (c, _) = await _build();
    c.read(entitlementProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isFalse);

    await c.read(debugPlusTierProvider.notifier).select(EntitlementTier.pro);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isTrue);
    expect(c.read(entitlementProvider).tier, EntitlementTier.pro);

    // 解除で free に戻る
    await c.read(debugPlusTierProvider.notifier).select(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(isPlusProvider), isFalse);
  });
}
