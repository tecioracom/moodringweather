// lib/data/billing/billing_models.dart
//
// UI / Provider が参照する**正規化済み**課金モデル。
// purchases_flutter (RevenueCat SDK) の型をここで吸収し、
// 上位レイヤへ SDK 型を漏らさない (差し替え可能性・テスト容易性のため)。

import '../models/entitlement.dart';

/// 課金周期 (Offering の package 種別)。
enum PlusBillingPeriod {
  monthly,
  annual,
  unknown;

  static PlusBillingPeriod fromPackageId(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('annual') || lower.contains('year')) {
      return PlusBillingPeriod.annual;
    }
    if (lower.contains('month')) return PlusBillingPeriod.monthly;
    return PlusBillingPeriod.unknown;
  }

  /// ストア商品の課金周期 (ISO 8601。例: 'P1M' / 'P1Y') から判定する。
  /// 分からなければ null。
  static PlusBillingPeriod? fromIsoPeriod(String? iso) {
    switch (iso?.trim().toUpperCase()) {
      case 'P1M':
      case 'P4W':
        return PlusBillingPeriod.monthly;
      case 'P1Y':
      case 'P12M':
        return PlusBillingPeriod.annual;
    }
    return null;
  }

  /// Paywall に出す周期。**ストア商品の課金周期を優先**し、分からないときだけ
  /// パッケージ識別子 (`$rc_monthly` / `$rc_annual`) で決める。
  ///
  /// RevenueCat でパッケージに紐づけた商品が逆だと、識別子で決めた表示
  /// (「月額」) と実際に購入される商品 (年額) が食い違う。2026-09-30 に
  /// Play 側の紐づけが月額・年額で逆になっていたのを見つけたため、表示を
  /// 購入内容に合わせる。
  static PlusBillingPeriod forPackage({
    required String packageId,
    String? subscriptionPeriod,
  }) =>
      fromIsoPeriod(subscriptionPeriod) ?? fromPackageId(packageId);
}

/// Paywall に表示する 1 プラン。価格文字列は SDK がロケール込みで整形した
/// `priceString` をそのまま使う (自前で通貨整形しない = 計画書 §4.2)。
class PlusPackage {
  /// RevenueCat Package 識別子 (例: '\$rc_monthly')。purchase 時のキー。
  final String packageId;
  final PlusBillingPeriod period;

  /// ストア整形済みの現地価格 (例: "¥600" / "$4.99")。
  final String priceString;

  /// ストア Product ID (例: 'mrw.plus.monthly')。監視/ログ用。
  final String productIdentifier;

  /// 無料トライアルなど導入価格の有無 (例: 7 日トライアル)。
  final bool hasIntroOffer;

  /// 導入価格の説明 (ローカライズはストア整形値を優先、無ければ null)。
  final String? introDescription;

  const PlusPackage({
    required this.packageId,
    required this.period,
    required this.priceString,
    required this.productIdentifier,
    this.hasIntroOffer = false,
    this.introDescription,
  });
}

/// 購入/復元の結果ステータス。
enum PurchaseStatus {
  /// 購入成功 (entitlement 反映済み)。
  purchased,

  /// ユーザーが購入ダイアログをキャンセル (エラー表示しない)。
  cancelled,

  /// 承認待ち (Ask to Buy 等)。完了は後続の customerInfo 更新で反映。
  pending,

  /// 課金が無効 (鍵未設定/未対応プラットフォーム)。
  billingUnavailable,

  /// その他の失敗 (errorMessage を表示)。
  error,
}

/// 購入/復元の結果。
class PurchaseResult {
  final PurchaseStatus status;

  /// 成功時の最新エンタイトルメント (失敗時は null)。
  final EntitlementState? entitlement;

  /// error 時の表示メッセージ (ローカライズ済みでない素のメッセージ可)。
  final String? errorMessage;

  const PurchaseResult(this.status, {this.entitlement, this.errorMessage});

  bool get isSuccess => status == PurchaseStatus.purchased;
}
