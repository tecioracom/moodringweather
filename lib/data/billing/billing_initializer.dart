// lib/data/billing/billing_initializer.dart
//
// 課金基盤の起動時初期化 (main から runApp 前に 1 回呼ぶ)。
// docs/revenuecat-integration-plan.md §1.4 を本コードベースの流儀
// (manual provider / override) に合わせて実装。
//
// グレースフル・デグラデーション (どの失敗でもアプリは通常起動):
//   1. 鍵未設定 (BillingConfig.billingEnabled == false)
//        → DisabledBillingGateway。Firebase も触らない。
//   2. 鍵あり + Firebase 成功
//        → Anonymous Auth の uid を RC appUserID に揃える (Webhook 突合キー)。
//          Firestore ソースも有効化。
//   3. 鍵あり + Firebase 失敗 (config ファイル無し等)
//        → RC 単独。appUserID は RC の匿名 ID に委ねる。Firestore ソース無効。

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/billing/billing_config.dart';
import 'billing_gateway.dart';
import 'entitlement_firestore_source.dart';
import 'revenuecat_billing_gateway.dart';

/// 初期化の成果物。Provider override に流し込む。
class BillingRuntime {
  final BillingGateway gateway;

  /// Firebase Anonymous Auth + Firestore が利用可能か。
  final bool firebaseAvailable;

  /// Firebase Anonymous UID (firebaseAvailable のときのみ非 null)。
  final String? uid;

  /// Firestore エンタイトルメントソース (firebaseAvailable のときのみ非 null)。
  final EntitlementFirestoreSource? firestoreSource;

  const BillingRuntime({
    required this.gateway,
    this.firebaseAvailable = false,
    this.uid,
    this.firestoreSource,
  });

  /// 課金無効 (鍵なし) の既定 — テストの ProviderScope 既定にも使う。
  static const BillingRuntime disabled =
      BillingRuntime(gateway: DisabledBillingGateway());
}

/// 起動時に 1 回だけ呼ぶ。例外は内部で握りつぶし、必ず BillingRuntime を返す。
Future<BillingRuntime> initBilling() async {
  if (!BillingConfig.billingEnabled) {
    return BillingRuntime.disabled;
  }

  String? uid;
  EntitlementFirestoreSource? firestoreSource;
  var firebaseAvailable = false;

  if (BillingConfig.firebaseEnabled) {
    try {
      await Firebase.initializeApp();
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      uid = user?.uid;
      if (uid != null) {
        firestoreSource =
            EntitlementFirestoreSource(FirebaseFirestore.instance);
        firebaseAvailable = true;
      }
    } catch (e, st) {
      // config ファイル未配置などで失敗 → RC 単独へ縮退 (アプリは通常起動)。
      debugPrint('[billing] Firebase init skipped, RC-only mode: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st);
      uid = null;
      firestoreSource = null;
      firebaseAvailable = false;
    }
  }

  final gateway = RevenueCatBillingGateway();
  // RC が使えないときの縮退先。Firestore ソース (Webhook 経由の権利) は残す —
  // 課金導線は「準備中」でも、既に払っている人の Plus は失わせない。
  BillingRuntime degraded() => BillingRuntime(
        gateway: const DisabledBillingGateway(),
        firebaseAvailable: firebaseAvailable,
        uid: uid,
        firestoreSource: firestoreSource,
      );
  try {
    await gateway.configure(appUserId: uid);
  } catch (e) {
    // RC configure 失敗時も落とさない (課金導線は準備中扱いになる)。
    debugPrint('[billing] RevenueCat configure failed: $e');
    await gateway.dispose();
    return degraded();
  }
  if (!gateway.isConfigured) {
    // 片側プラットフォームの鍵しか無い (例: iOS 鍵だけで Android ビルド)。
    // billingEnabled は true でも SDK は未 configure なので、購入導線は出さない。
    debugPrint(
        '[billing] no RevenueCat key for this platform; billing disabled');
    await gateway.dispose();
    return degraded();
  }

  return BillingRuntime(
    gateway: gateway,
    firebaseAvailable: firebaseAvailable,
    uid: uid,
    firestoreSource: firestoreSource,
  );
}
