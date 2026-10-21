// test/golden/paywall_golden_test.dart
//
// Paywall の見た目の回帰検出 (Dark/Light × en/ja)。v1.3 S7: 色は commerce/plus と
// 無彩のみ、免責文はヘッドライン直下、自動更新の開示は CTA 直上。
// 更新: flutter test test/golden --update-goldens (差分を目視してから)

@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';

import 'golden_harness.dart';

class _GoldenGateway implements BillingGateway {
  final _controller = StreamController<EntitlementState>.broadcast();
  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;
  @override
  Future<List<PlusPackage>> fetchPackages() async => const [
        PlusPackage(
          packageId: r'$rc_monthly',
          period: PlusBillingPeriod.monthly,
          priceString: '¥600',
          productIdentifier: 'mrw.plus.monthly',
          hasIntroOffer: true,
        ),
        PlusPackage(
          packageId: r'$rc_annual',
          period: PlusBillingPeriod.annual,
          priceString: '¥3,000',
          productIdentifier: 'mrw.plus.yearly',
          hasIntroOffer: true,
        ),
      ];
  @override
  Future<PurchaseResult> purchase(String packageId) async =>
      const PurchaseResult(PurchaseStatus.cancelled);
  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.error);
  @override
  Future<bool> openManageSubscriptions() async => true;
  @override
  Future<void> dispose() async => _controller.close();
}

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final locale in const [
      Locale('en'),
      Locale('ja'),
      Locale('es'),
      Locale('zh'),
    ]) {
      testWidgets('Paywall (${brightness.name}/${locale.languageCode})',
          (tester) async {
        useGoldenViewport(tester);
        final overrides = await goldenOverrides();
        await tester.pumpWidget(goldenApp(
          home: const PaywallPage(),
          brightness: brightness,
          locale: locale,
          overrides: [
            ...overrides,
            billingGatewayProvider.overrideWithValue(_GoldenGateway()),
          ],
        ));
        await settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(goldenName('paywall', brightness, locale)),
        );
      });
    }
  }
}
