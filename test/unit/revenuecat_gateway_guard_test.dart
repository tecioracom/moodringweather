// RevenueCat gateway の未 configure ガード (release-plan-billing.md F9)。
// 片側プラットフォームの鍵しか無いビルドでは SDK が configure されないまま
// 「課金有効」になり得る。その状態で purchase / restore を呼んでも SDK に触れず
// billingUnavailable を返すこと。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/data/billing/revenuecat_billing_gateway.dart';

void main() {
  test('未 configure の purchase は billingUnavailable (SDK を呼ばない)', () async {
    final gateway = RevenueCatBillingGateway();
    expect(gateway.isConfigured, isFalse);
    final result = await gateway.purchase(r'$rc_monthly');
    expect(result.status, PurchaseStatus.billingUnavailable);
    await gateway.dispose();
  });

  test('未 configure の restore も billingUnavailable', () async {
    final gateway = RevenueCatBillingGateway();
    final result = await gateway.restore();
    expect(result.status, PurchaseStatus.billingUnavailable);
    await gateway.dispose();
  });

  test('未 configure の fetchPackages は空、fetchEntitlement は free', () async {
    final gateway = RevenueCatBillingGateway();
    expect(await gateway.fetchPackages(), isEmpty);
    expect(await gateway.fetchEntitlement(), EntitlementState.free);
    await gateway.dispose();
  });
}
