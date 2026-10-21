// lib/data/billing/entitlement_firestore_source.dart
//
// Firestore `users/{uid}/entitlement/current` を購読し、Webhook 反映済みの
// エンタイトルメントを EntitlementState へ正規化する
// (docs/revenuecat-integration-plan.md §3.3 スキーマ / §3.6 リアルタイム反映)。
//
// Webhook (Workers) が書き込み、クライアントは read-only (Security Rules §6)。
// Firebase 未初期化環境では本ソースは生成されず、RC SDK 単独へ縮退する。

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/entitlement.dart';

class EntitlementFirestoreSource {
  EntitlementFirestoreSource(this._firestore);

  final FirebaseFirestore _firestore;

  /// `users/{uid}/entitlement/current` のスナップショットを購読。
  Stream<EntitlementState> watch(String uid) {
    return _firestore
        .doc('users/$uid/entitlement/current')
        .snapshots()
        .map(_fromSnapshot);
  }

  EntitlementState _fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return EntitlementState.free;
    return EntitlementState(
      tier: EntitlementTier.parse(data['tier']),
      activeEntitlements: <String>{
        for (final e in (data['activeEntitlements'] as List? ?? const []))
          if (e is String) e,
      },
      expiresAt: _toDate(data['expiresAt']),
      willRenew: data['willRenew'] as bool? ?? false,
      isInGracePeriod: data['isInGracePeriod'] as bool? ?? false,
      store: data['store'] as String?,
      updatedAt: _toDate(data['updatedAt']),
      source: EntitlementSource.firestore,
    );
  }

  static DateTime? _toDate(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
