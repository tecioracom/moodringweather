// lib/data/privacy/data_deletion.dart
//
// ユーザーデータの削除 (プライバシーポリシー §5「設定 → データを削除」、
// spec §13、Data Safety「削除リクエストの手段 = はい」。決裁 D3、2026-09-19)。
//
// 削除するもの:
//   (i)   通知購読の記録 `push_subscriptions/{uid}` (プッシュトークン・粗い座標・
//         プラットフォーム・言語) — クライアントから削除可 (firestore.rules)
//   (ii)  サブスクリプションの権利記録 `users/{uid}/entitlement/current` — 所有者の
//         delete だけ許可 (firestore.rules)。Webhook が再作成しうるが、それは
//         「払っている人の Plus」であり削除請求の対象ではない
//   (iii) 端末内のパーソナルデータ (SharedPreferences: キャリブレーション・体感記憶・
//         設定・保存した地点)
//   (iv)  FCM トークンの失効と匿名アカウントの削除 (best-effort)
//   (v)   ライブ壁紙 (Android) の保存: 色の状態 (MRI・区分) と重ね描き (天気・気温の
//         PNG と設定)。壁紙は既定 (快適の配色・重ね描きなし) に戻る。アプリが現在地の
//         MRI を計算し直すと、通常どおり描き直す (1.3.0 (13)。消し方は呼び出し側が
//         [DataDeletionService.eraseWallpaper] で渡す)
// 削除しないもの: Apple / Google / RevenueCat が保持する購入記録 (会計・法令上の
// 保存義務。ポリシーに明記)。
//
// サーバー側は 1 件ずつ best-effort で進め、失敗しても端末内の消去は必ず行う。
// 結果は [DataDeletionOutcome] で UI に返し、部分失敗を正直に伝える。
// 純 Dart (Firebase 非依存)。Firebase 実装は firebase_data_eraser.dart。

import 'package:shared_preferences/shared_preferences.dart';

/// サーバー側 (Firebase) の削除操作。テストでは差し替える。
abstract class RemoteDataEraser {
  Future<void> deletePushSubscription(String uid);
  Future<void> deleteEntitlement(String uid);
  Future<void> deleteFcmToken();

  /// 匿名アカウントの削除。**最後に**呼ぶ (以後 Firestore の所有者判定が通らない)。
  Future<void> deleteAuthUser();
}

/// 削除の各段階の成否。
class DataDeletionOutcome {
  const DataDeletionOutcome({
    required this.localCleared,
    required this.remoteAttempted,
    required this.pushSubscriptionDeleted,
    required this.entitlementDeleted,
    required this.fcmTokenDeleted,
    required this.authUserDeleted,
    this.wallpaperCleared = true,
  });

  final bool localCleared;

  /// ライブ壁紙の保存を消せたか (壁紙の無い端末・消し方を渡していないときは true)。
  final bool wallpaperCleared;

  /// サーバー側の削除を試みたか (uid があり Firebase が使えるとき true)。
  final bool remoteAttempted;
  final bool pushSubscriptionDeleted;
  final bool entitlementDeleted;
  final bool fcmTokenDeleted;
  final bool authUserDeleted;

  /// 削除請求として完了と言えるか (端末内 + サーバー側の記録 2 件)。
  /// FCM トークンの失効と匿名アカウントの削除は付随処理なので判定に含めない。
  bool get isComplete =>
      localCleared &&
      wallpaperCleared &&
      (!remoteAttempted || (pushSubscriptionDeleted && entitlementDeleted));
}

class DataDeletionService {
  DataDeletionService({
    required this.prefs,
    this.uid,
    this.remote,
    this.eraseWallpaper,
  });

  final SharedPreferences prefs;
  final String? uid;
  final RemoteDataEraser? remote;

  /// ライブ壁紙の保存 (色の状態・重ね描き) を消す (Android)。消せなければ例外を投げる
  /// (結果を「一部」にする)。壁紙の無い端末では何もしない関数か null。
  final Future<void> Function()? eraseWallpaper;

  Future<DataDeletionOutcome> deleteAll() async {
    final id = uid;
    final eraser = remote;
    final remoteAttempted = id != null && eraser != null;

    var push = false;
    var entitlement = false;
    var token = false;
    var auth = false;
    if (remoteAttempted) {
      push = await _tryStep(() => eraser.deletePushSubscription(id));
      entitlement = await _tryStep(() => eraser.deleteEntitlement(id));
      token = await _tryStep(eraser.deleteFcmToken);
    }

    // 端末内は必ず消す (サーバー側の失敗に関係なく)。
    final localCleared = await _tryStep(() async {
      await prefs.clear();
    });
    // ライブ壁紙の保存 (Android)。端末内の設定の消去とは別に試みる。
    final wallpaper = eraseWallpaper;
    final wallpaperCleared = wallpaper == null || await _tryStep(wallpaper);

    if (remoteAttempted) {
      // 最後に匿名アカウント。ここで失敗しても記録は消えている。
      auth = await _tryStep(eraser.deleteAuthUser);
    }

    return DataDeletionOutcome(
      localCleared: localCleared,
      remoteAttempted: remoteAttempted,
      pushSubscriptionDeleted: push,
      entitlementDeleted: entitlement,
      fcmTokenDeleted: token,
      authUserDeleted: auth,
      wallpaperCleared: wallpaperCleared,
    );
  }

  Future<bool> _tryStep(Future<void> Function() step) async {
    try {
      await step();
      return true;
    } catch (_) {
      return false;
    }
  }
}
