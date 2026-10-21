// lib/data/privacy/firebase_data_eraser.dart
//
// RemoteDataEraser の Firebase 実装 (data_deletion.dart を参照)。
// Firebase が初期化済みで匿名 uid があるときだけ生成する (push_provider と同じ前提)。

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'data_deletion.dart';

class FirebaseDataEraser implements RemoteDataEraser {
  FirebaseDataEraser({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;

  @override
  Future<void> deletePushSubscription(String uid) =>
      _firestore.doc('push_subscriptions/$uid').delete();

  @override
  Future<void> deleteEntitlement(String uid) =>
      _firestore.doc('users/$uid/entitlement/current').delete();

  @override
  Future<void> deleteFcmToken() => _messaging.deleteToken();

  @override
  Future<void> deleteAuthUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }
}
