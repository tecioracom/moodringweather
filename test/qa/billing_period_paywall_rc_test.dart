// test/qa/billing_period_paywall_rc_test.dart
//
// 1.3.0 (13) の QA: Paywall の月額・年額は、ストア商品の課金周期で決める (`af2e95b`)。
// 背景: RevenueCat の Offering で Play 側の紐づけが月額・年額で逆になっていた
// ($rc_monthly に年額の商品、$rc_annual に月額の商品。2026-09-30、ダッシュボードは
// 修正済み)。紐づけが逆のままでも、画面の「月額 / 年額」・価格・BEST VALUE・既定選択
// (月額) と、実際に購入される package (= その商品) が食い違わないことを、Paywall の
// 画面で確かめる。周期は本番と同じ PlusBillingPeriod.forPackage で決める
// (revenuecat_billing_gateway.dart の _mapPackage と同じ呼び方)。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';

import '../golden/golden_harness.dart';

class _RecordingGateway implements BillingGateway {
  _RecordingGateway(this.packages);
  final List<PlusPackage> packages;
  final purchased = <String>[];
  final _controller = StreamController<EntitlementState>.broadcast();

  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;
  @override
  Future<List<PlusPackage>> fetchPackages() async => packages;
  @override
  Future<PurchaseResult> purchase(String packageId) async {
    purchased.add(packageId);
    return const PurchaseResult(PurchaseStatus.cancelled);
  }

  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.error);
  @override
  Future<bool> openManageSubscriptions() async => true;
  @override
  Future<void> dispose() async => _controller.close();
}

/// Offering の 1 パッケージ (周期は本番と同じ関数で、商品の課金周期から決める)。
PlusPackage _package(
        String id, String isoPeriod, String price, String product) =>
    PlusPackage(
      packageId: id,
      period: PlusBillingPeriod.forPackage(
        packageId: id,
        subscriptionPeriod: isoPeriod,
      ),
      priceString: price,
      productIdentifier: product,
    );

/// 2026-09-30 に見つかった逆の紐づけ (Play の商品 ID は base plan 付き)。
final _swapped = [
  _package(r'$rc_monthly', 'P1Y', '¥3,000', 'mrw.plus.yearly:yearly'),
  _package(r'$rc_annual', 'P1M', '¥600', 'mrw.plus.monthly:monthly'),
];

/// 正しい紐づけ (ダッシュボード修正後)。
final _correct = [
  _package(r'$rc_annual', 'P1Y', '¥3,000', 'mrw.plus.yearly:yearly'),
  _package(r'$rc_monthly', 'P1M', '¥600', 'mrw.plus.monthly:monthly'),
];

Future<(_RecordingGateway, AppLocalizations)> _pump(
  WidgetTester tester,
  List<PlusPackage> packages, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gateway = _RecordingGateway(packages);
  await tester.pumpWidget(ProviderScope(
    overrides: [billingGatewayProvider.overrideWithValue(gateway)],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.dark, locale: locale)
          .copyWith(platform: TargetPlatform.android),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showPaywall(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
  return (gateway, t);
}

/// プラン名 [label] のカード (InkWell)。
Finder _card(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

Future<void> _tapCta(WidgetTester tester, AppLocalizations t) async {
  final cta = find.text(t.paywallStartCta);
  await tester.ensureVisible(cta);
  await tester.tap(cta);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, packages) in [('逆の紐づけ', _swapped), ('正しい紐づけ', _correct)]) {
    group(name, () {
      testWidgets('「月額」のカードに月額の価格、「年額」のカードに年額の価格と BEST VALUE', (tester) async {
        final (_, t) = await _pump(tester, packages);
        final monthly = _card(t.paywallPeriodMonthly);
        final annual = _card(t.paywallPeriodAnnual);
        expect(find.descendant(of: monthly, matching: find.text('¥600')),
            findsOneWidget);
        expect(find.descendant(of: annual, matching: find.text('¥3,000')),
            findsOneWidget);
        expect(find.descendant(of: annual, matching: find.byType(QuietBadge)),
            findsOneWidget);
        expect(find.descendant(of: monthly, matching: find.byType(QuietBadge)),
            findsNothing);
      });

      testWidgets('既定選択は「月額」のカードで、購入されるのは月額の商品の package', (tester) async {
        final (gateway, t) = await _pump(tester, packages);
        expect(
          find.descendant(
            of: _card(t.paywallPeriodMonthly),
            matching: find.byIcon(Icons.radio_button_checked),
          ),
          findsOneWidget,
        );
        await _tapCta(tester, t);
        final monthlyPackage = packages
            .firstWhere(
                (p) => p.productIdentifier.startsWith('mrw.plus.monthly'))
            .packageId;
        expect(gateway.purchased, [monthlyPackage]);
      });

      testWidgets('「年額」を選ぶと、購入されるのは年額の商品の package', (tester) async {
        final (gateway, t) = await _pump(tester, packages);
        await tester.tap(find.text(t.paywallPeriodAnnual));
        await tester.pumpAndSettle();
        await _tapCta(tester, t);
        final annualPackage = packages
            .firstWhere(
                (p) => p.productIdentifier.startsWith('mrw.plus.yearly'))
            .packageId;
        expect(gateway.purchased, [annualPackage]);
      });
    });
  }

  testWidgets('JA でも逆の紐づけで「月額」「年額」と価格が商品どおり', (tester) async {
    final (gateway, t) =
        await _pump(tester, _swapped, locale: const Locale('ja'));
    expect(
      find.descendant(
          of: _card(t.paywallPeriodMonthly), matching: find.text('¥600')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _card(t.paywallPeriodAnnual), matching: find.text('¥3,000')),
      findsOneWidget,
    );
    await _tapCta(tester, t);
    expect(gateway.purchased, [r'$rc_annual']);
  });
}
