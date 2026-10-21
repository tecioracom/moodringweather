// Paywall に出す課金周期の判定 (billing_models.dart)。
//
// 回帰: RevenueCat の Offering で Play 側の商品の紐づけが月額・年額で逆に
// なっており (2026-09-30)、パッケージ識別子で決めた表示「月額」と、実際に
// 購入される商品 (年額) が食い違っていた。商品の課金周期を優先する。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';

void main() {
  group('PlusBillingPeriod.fromIsoPeriod', () {
    test('月額・年額の ISO 8601 を読む', () {
      expect(PlusBillingPeriod.fromIsoPeriod('P1M'), PlusBillingPeriod.monthly);
      expect(PlusBillingPeriod.fromIsoPeriod('P4W'), PlusBillingPeriod.monthly);
      expect(PlusBillingPeriod.fromIsoPeriod('P1Y'), PlusBillingPeriod.annual);
      expect(PlusBillingPeriod.fromIsoPeriod('P12M'), PlusBillingPeriod.annual);
      expect(
          PlusBillingPeriod.fromIsoPeriod(' p1y '), PlusBillingPeriod.annual);
    });

    test('分からなければ null', () {
      expect(PlusBillingPeriod.fromIsoPeriod(null), isNull);
      expect(PlusBillingPeriod.fromIsoPeriod(''), isNull);
      expect(PlusBillingPeriod.fromIsoPeriod('P1W'), isNull);
    });
  });

  group('PlusBillingPeriod.forPackage', () {
    test('紐づけが逆でも、商品の課金周期で表示する', () {
      // $rc_monthly に年額の商品 (mrw.plus.yearly:yearly = P1Y) が付いていた。
      expect(
        PlusBillingPeriod.forPackage(
          packageId: r'$rc_monthly',
          subscriptionPeriod: 'P1Y',
        ),
        PlusBillingPeriod.annual,
      );
      // $rc_annual に月額の商品 (mrw.plus.monthly:monthly = P1M) が付いていた。
      expect(
        PlusBillingPeriod.forPackage(
          packageId: r'$rc_annual',
          subscriptionPeriod: 'P1M',
        ),
        PlusBillingPeriod.monthly,
      );
    });

    test('課金周期が分からなければパッケージ識別子で決める', () {
      expect(
        PlusBillingPeriod.forPackage(packageId: r'$rc_annual'),
        PlusBillingPeriod.annual,
      );
      expect(
        PlusBillingPeriod.forPackage(
          packageId: r'$rc_monthly',
          subscriptionPeriod: '',
        ),
        PlusBillingPeriod.monthly,
      );
      expect(
        PlusBillingPeriod.forPackage(packageId: 'custom'),
        PlusBillingPeriod.unknown,
      );
    });
  });
}
