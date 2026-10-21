// lib/data/billing/billing_gateway.dart
//
// 課金処理の抽象境界。UI / Provider はこのインターフェイスのみに依存し、
// 実体 (RevenueCat) / 無効モード / テスト用フェイクを差し替えられる。
//
// 実装:
//   - RevenueCatBillingGateway  : 実課金 (revenuecat_billing_gateway.dart)
//   - DisabledBillingGateway    : 鍵未設定時の縮退 / テスト既定 (本ファイル)

import '../models/entitlement.dart';
import 'billing_models.dart';

abstract class BillingGateway {
  /// SDK 初期化。[appUserId] は Firebase Anonymous UID (無ければ null で
  /// RC の匿名 ID に委ねる)。
  Future<void> configure({String? appUserId});

  /// customerInfo 更新の購読 (購入/復元/更新/失効で発火)。
  Stream<EntitlementState> entitlementChanges();

  /// 現在のエンタイトルメントを取得 (起動時 / 明示更新)。
  Future<EntitlementState> fetchEntitlement();

  /// Paywall に出すプラン一覧 (current Offering)。空なら準備中表示。
  Future<List<PlusPackage>> fetchPackages();

  /// パッケージを購入。
  Future<PurchaseResult> purchase(String packageId);

  /// 購入を復元 (機種変更/再インストール)。
  Future<PurchaseResult> restore();

  /// ストアのサブスク管理画面を開く (任意。未対応なら false)。
  Future<bool> openManageSubscriptions();

  /// 後始末 (listener 解除など)。
  Future<void> dispose();
}

/// 課金無効モード。鍵が未注入のとき、および host VM テストの既定。
/// すべて free / 空 / billingUnavailable を返し、例外を投げない。
class DisabledBillingGateway implements BillingGateway {
  const DisabledBillingGateway();

  @override
  Future<void> configure({String? appUserId}) async {}

  @override
  Stream<EntitlementState> entitlementChanges() =>
      const Stream<EntitlementState>.empty();

  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;

  @override
  Future<List<PlusPackage>> fetchPackages() async => const <PlusPackage>[];

  @override
  Future<PurchaseResult> purchase(String packageId) async =>
      const PurchaseResult(PurchaseStatus.billingUnavailable);

  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.billingUnavailable);

  @override
  Future<bool> openManageSubscriptions() async => false;

  @override
  Future<void> dispose() async {}
}
