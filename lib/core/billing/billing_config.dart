// lib/core/billing/billing_config.dart
//
// 課金 (RevenueCat / Firebase) のビルド時設定を一元化する。
// revenuecat-integration-plan.md §1.2「環境変数の二層構造」に対応するクライアント側。
//
// 鍵はすべて --dart-define で注入する公開可能な SDK Key のみ:
//   flutter run \
//     --dart-define=RC_PUBLIC_API_KEY_IOS=appl_xxx \
//     --dart-define=RC_PUBLIC_API_KEY_ANDROID=goog_xxx \
//     --dart-define=ENV=prod
//
// シークレット (sk_xxx) はクライアントに置かない (agents.md 厳守 / 計画書 §1.1)。
//
// グレースフル・デグラデーション:
//   鍵が未注入 (= 開発ビルドやキー発行前) のときは `billingEnabled == false` となり、
//   アプリは「課金無効モード」で通常起動する。Paywall は準備中表示、
//   エンタイトルメントは free 固定 (kDebugMode のデバッグ上書きのみ可)。
//   App Store Connect / Play Console / RevenueCat の設定と鍵が揃えば、
//   --dart-define を渡すだけで実課金が有効化される。
library;

/// dart:io / Flutter に依存しない純設定 (host VM テストから参照可能)。
class BillingConfig {
  const BillingConfig._();

  /// RevenueCat 公開 SDK Key (iOS)。`appl_xxx`。
  static const String revenueCatKeyIos =
      String.fromEnvironment('RC_PUBLIC_API_KEY_IOS');

  /// RevenueCat 公開 SDK Key (Android)。`goog_xxx`。
  static const String revenueCatKeyAndroid =
      String.fromEnvironment('RC_PUBLIC_API_KEY_ANDROID');

  /// 実行環境 ('dev' / 'prod')。Firestore プロジェクト分離や RC ログ量に使う。
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// Firebase (Anonymous Auth + Firestore) を使う構成か。
  /// 既定 true だが、実初期化は config ファイル有無に依存するため
  /// BillingInitializer 側で try/catch して失敗時は RC 単独へ縮退する。
  static const bool firebaseEnabled =
      bool.fromEnvironment('FIREBASE_ENABLED', defaultValue: true);

  static bool get isProd => env == 'prod';

  /// 少なくとも片方のプラットフォーム鍵が注入されているか。
  /// false の間は課金無効モード (UI は準備中表示)。
  static bool get billingEnabled =>
      revenueCatKeyIos.isNotEmpty || revenueCatKeyAndroid.isNotEmpty;
}
