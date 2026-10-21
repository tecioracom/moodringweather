// lib/core/permissions/permission_request_queue.dart
//
// 実行時権限 (位置情報・通知) の要求を 1 つずつ順に行う。
//
// Android は権限ダイアログを同時に 1 つしか出せず、表示中に来た別の要求は
// 取り消される (Activity: "Can request only one set of permissions at a time")。
// geolocator_android (4.6.2) は取り消しに応答しないため、Dart 側の
// Geolocator.requestPermission() が終わらない。初回起動で通知の許可ダイアログと
// 重なると、位置情報のダイアログが出ないまま現在地の取得が止まり、ホームが
// 「読み込み中」のままになっていた (2026-09-29 実機で発見、エミュレータで再現。
// 製品版 1.1.0 にもある)。
//
// アプリ内の権限要求は必ず [runPermissionRequest] を通す。
// 先の要求が終わらないと後続もすべて止まるため、回答の来ない位置情報の要求は
// unanswered_permission_request.dart で見切る (QA-17)。

import 'dart:async';

Future<void> _tail = Future<void>.value();

/// [request] を、先に入った権限要求がすべて終わってから実行する。
///
/// [request] の結果・例外はそのまま返す。失敗しても後続の要求は止めない。
Future<T> runPermissionRequest<T>(Future<T> Function() request) {
  final previous = _tail;
  final done = Completer<void>();
  _tail = done.future;
  return previous.then((_) => request()).whenComplete(done.complete);
}
