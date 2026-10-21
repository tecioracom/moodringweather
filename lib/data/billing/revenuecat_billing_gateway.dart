// lib/data/billing/revenuecat_billing_gateway.dart
//
// BillingGateway の RevenueCat 実装 (purchases_flutter 10.x)。
// SDK 型は本ファイルに閉じ込め (`as rc`)、上位へは正規化済みモデルだけ返す。
//
// マッピングの正本: docs/revenuecat-integration-plan.md §2.4 (Entitlement) /
//   §3.4 (イベント→挙動)。継承は pro > plus。

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../core/billing/billing_config.dart';
import '../../core/utils/external_url.dart';
import '../models/entitlement.dart';
import 'billing_gateway.dart';
import 'billing_models.dart';

/// RevenueCat ダッシュボードの Entitlement 識別子 (計画書 §2.4)。
const String _kEntPlus = 'plus';
const String _kEntPro = 'pro';

class RevenueCatBillingGateway implements BillingGateway {
  RevenueCatBillingGateway();

  final StreamController<EntitlementState> _controller =
      StreamController<EntitlementState>.broadcast();

  /// fetchPackages で取得した Package を purchase 時に引くためのキャッシュ。
  final Map<String, rc.Package> _packageCache = {};

  rc.CustomerInfoUpdateListener? _listener;
  bool _configured = false;

  /// RC SDK の configure が完了しているか。false のまま purchase/restore は
  /// billingUnavailable を返す (片側プラットフォームの鍵しか無いビルドなど)。
  bool get isConfigured => _configured;

  static String? _platformKey() {
    if (Platform.isIOS) {
      return BillingConfig.revenueCatKeyIos.isEmpty
          ? null
          : BillingConfig.revenueCatKeyIos;
    }
    if (Platform.isAndroid) {
      return BillingConfig.revenueCatKeyAndroid.isEmpty
          ? null
          : BillingConfig.revenueCatKeyAndroid;
    }
    return null;
  }

  @override
  Future<void> configure({String? appUserId}) async {
    final key = _platformKey();
    if (key == null) return; // 鍵なし: 何もしない (factory 側で縮退済みのはず)
    await rc.Purchases.setLogLevel(
        BillingConfig.isProd ? rc.LogLevel.warn : rc.LogLevel.debug);
    final config = rc.PurchasesConfiguration(key);
    if (appUserId != null && appUserId.isNotEmpty) {
      config.appUserID = appUserId;
    }
    await rc.Purchases.configure(config);
    _configured = true;
    _listener = (info) => _controller.add(mapCustomerInfo(info));
    rc.Purchases.addCustomerInfoUpdateListener(_listener!);
  }

  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;

  @override
  Future<EntitlementState> fetchEntitlement() async {
    if (!_configured) return EntitlementState.free;
    final info = await rc.Purchases.getCustomerInfo();
    return mapCustomerInfo(info);
  }

  @override
  Future<List<PlusPackage>> fetchPackages() async {
    if (!_configured) return const <PlusPackage>[];
    final offerings = await rc.Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const <PlusPackage>[];
    _packageCache.clear();
    final result = <PlusPackage>[];
    for (final pkg in current.availablePackages) {
      _packageCache[pkg.identifier] = pkg;
      result.add(_mapPackage(pkg));
    }
    return result;
  }

  @override
  Future<PurchaseResult> purchase(String packageId) async {
    if (!_configured) {
      return const PurchaseResult(PurchaseStatus.billingUnavailable);
    }
    final pkg = _packageCache[packageId];
    if (pkg == null) {
      return const PurchaseResult(PurchaseStatus.error,
          errorMessage: 'package_not_found');
    }
    try {
      final result =
          await rc.Purchases.purchase(rc.PurchaseParams.package(pkg));
      return PurchaseResult(PurchaseStatus.purchased,
          entitlement: mapCustomerInfo(result.customerInfo));
    } on PlatformException catch (e) {
      return _mapPurchaseError(e);
    }
  }

  @override
  Future<PurchaseResult> restore() async {
    if (!_configured) {
      return const PurchaseResult(PurchaseStatus.billingUnavailable);
    }
    try {
      final info = await rc.Purchases.restorePurchases();
      return PurchaseResult(PurchaseStatus.purchased,
          entitlement: mapCustomerInfo(info));
    } on PlatformException catch (e) {
      return _mapPurchaseError(e);
    }
  }

  @override
  Future<bool> openManageSubscriptions() async {
    if (!_configured) return false;
    try {
      final info = await rc.Purchases.getCustomerInfo();
      final url = info.managementURL;
      if (url == null || url.isEmpty) return false;
      return await openExternalUrl(url);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    final l = _listener;
    if (l != null) rc.Purchases.removeCustomerInfoUpdateListener(l);
    _listener = null;
    await _controller.close();
  }

  PurchaseResult _mapPurchaseError(PlatformException e) {
    final code = rc.PurchasesErrorHelper.getErrorCode(e);
    return switch (code) {
      rc.PurchasesErrorCode.purchaseCancelledError =>
        const PurchaseResult(PurchaseStatus.cancelled),
      rc.PurchasesErrorCode.paymentPendingError =>
        const PurchaseResult(PurchaseStatus.pending),
      _ => PurchaseResult(PurchaseStatus.error, errorMessage: e.message),
    };
  }

  PlusPackage _mapPackage(rc.Package pkg) {
    final product = pkg.storeProduct;
    final intro = product.introductoryPrice;
    return PlusPackage(
      packageId: pkg.identifier,
      // 商品の課金周期を優先する (パッケージの紐づけの誤りで表示と購入内容が
      // 食い違わないように。billing_models.dart)。
      period: PlusBillingPeriod.forPackage(
        packageId: pkg.identifier,
        subscriptionPeriod: product.subscriptionPeriod,
      ),
      priceString: product.priceString,
      productIdentifier: product.identifier,
      hasIntroOffer: intro != null,
      introDescription: intro?.priceString,
    );
  }
}

/// CustomerInfo → EntitlementState の純粋マッピング (テストから直接呼べるよう公開)。
EntitlementState mapCustomerInfo(rc.CustomerInfo info) {
  final active = info.entitlements.active; // Map<String, EntitlementInfo>
  final ids = active.keys.toSet();
  final tier = _tierFromActive(ids);
  final primary = _primaryEntitlement(active, tier);
  return EntitlementState(
    tier: tier,
    activeEntitlements: ids,
    expiresAt: _parseRcDate(primary?.expirationDate),
    willRenew: primary?.willRenew ?? false,
    isInGracePeriod: primary?.billingIssueDetectedAt != null,
    store: _storeTag(primary?.store),
    updatedAt: _parseRcDate(info.requestDate),
    source: EntitlementSource.revenueCat,
  );
}

EntitlementTier _tierFromActive(Set<String> ids) {
  if (ids.contains(_kEntPro)) return EntitlementTier.pro;
  if (ids.contains(_kEntPlus)) return EntitlementTier.plus;
  return EntitlementTier.free;
}

/// 決定済み tier に対応する EntitlementInfo を選ぶ (無ければ任意の active)。
rc.EntitlementInfo? _primaryEntitlement(
  Map<String, rc.EntitlementInfo> active,
  EntitlementTier tier,
) {
  final key = switch (tier) {
    EntitlementTier.pro => _kEntPro,
    EntitlementTier.plus => _kEntPlus,
    EntitlementTier.free => null,
  };
  if (key != null && active.containsKey(key)) return active[key];
  return active.isNotEmpty ? active.values.first : null;
}

String? _storeTag(rc.Store? store) => switch (store) {
      rc.Store.appStore || rc.Store.macAppStore => 'app_store',
      rc.Store.playStore => 'play_store',
      null => null,
      _ => store.name,
    };

DateTime? _parseRcDate(String? raw) =>
    (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
