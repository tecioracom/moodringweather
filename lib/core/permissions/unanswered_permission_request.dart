// lib/core/permissions/unanswered_permission_request.dart
//
// 回答の来ない権限の要求で、アプリが止まらないようにする (QA-17)。
//
// geolocator_android (4.6.2) は、要求が取り消されると (結果の配列が空) 何も
// 返さない (PermissionManager.java 148〜153 行)。取り消しはアプリの外からも
// 起こりうる (端末メーカーの許可画面、許可画面の異常終了、キューを通らない
// 要求など)。そのままでは Geolocator.requestPermission() が終わらず、権限の
// 要求のキュー (permission_request_queue.dart) も空かない。現在地の取得・
// 引っ張って更新・通知の初期化 (= FCM 前景の緊急アラートの表示) がすべて止まる。
//
// 見分け方: 許可ダイアログが出ている間、アプリは前面にいない
// (Android: 許可画面の Activity が前に来て onPause・フォーカスも失う → inactive。
//  iOS: システムのアラートで inactive)。要求のあと、回答が無いまま
// アプリが resumed で続けて [kPermissionGiveUpAfter] たったら、ダイアログは
// 出ていない (要求が取り消された) とみなして見切り、今の許可状態で進める。
// inactive / hidden / paused の間 (ダイアログを見ている・裏に回している) は
// 数え直す。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 回答が無いまま、アプリが前面 (resumed) で続けてこの時間たったら見切る。
///
/// 許可ダイアログを出すとき、アプリはすぐに inactive になる (Android は許可画面の
/// Activity を前に出す前に、今の Activity を onPause する)。余裕を持たせた値。
/// 見切りが早すぎても、遅れて届いた回答は [requestPermissionOrGiveUp] の
/// onLateAnswer で呼び出し元へ渡る。
const Duration kPermissionGiveUpAfter = Duration(seconds: 4);

/// アプリの状態を見る間隔。
const Duration _pollInterval = Duration(milliseconds: 250);

/// 権限の要求 [request] の回答を待つ。ただし、回答が無いままアプリが前面
/// (resumed) で続けて [giveUpAfter] たったら見切り、[check] (今の許可状態) の
/// 結果を返す。
///
/// - 見切る前に届いた [request] の結果・例外は、そのまま返す ([check] は呼ばない)。
/// - 見切ったあとに [request] の回答が届き、見切りで返した値と違えば
///   [onLateAnswer] に渡す (1 回だけ)。見切ったあとの例外は捨てる。
/// - [lifecycleState] はテスト用 (既定は SchedulerBinding の状態)。状態が
///   分からない (null) ときは前面として数える。ダイアログが出ているとは
///   言えないため、止まらない側に倒す。
Future<T> requestPermissionOrGiveUp<T>({
  required Future<T> Function() request,
  required Future<T> Function() check,
  void Function(T answer)? onLateAnswer,
  Duration giveUpAfter = kPermissionGiveUpAfter,
  AppLifecycleState? Function()? lifecycleState,
}) {
  final readState =
      lifecycleState ?? () => SchedulerBinding.instance.lifecycleState;
  final result = Completer<T>();
  Timer? watch;
  var gaveUp = false;
  // 見切りで返した値 (gaveUp のときだけ意味がある)。
  late T gaveUpWith;

  unawaited(Future<T>.sync(request).then(
    (answer) {
      if (!result.isCompleted) {
        watch?.cancel();
        result.complete(answer);
        return;
      }
      if (!gaveUp || answer == gaveUpWith) return;
      debugPrint('[permissions] late answer after giving up: $answer');
      try {
        onLateAnswer?.call(answer);
      } catch (_) {
        // 取り直しは付帯処理。要求の後始末を巻き込まない。
      }
    },
    onError: (Object e, StackTrace s) {
      // 見切ったあとの失敗は捨てる (呼び出し元には見切りの結果を返し済み)。
      if (result.isCompleted) return;
      watch?.cancel();
      result.completeError(e, s);
    },
  ));

  var resumedFor = Duration.zero;
  watch = Timer.periodic(_pollInterval, (timer) {
    final state = readState();
    if (state == null || state == AppLifecycleState.resumed) {
      resumedFor += _pollInterval;
    } else {
      // ダイアログを見ている・裏に回している。続けて前面にいた時間を数え直す。
      resumedFor = Duration.zero;
    }
    if (resumedFor < giveUpAfter) return;
    timer.cancel();
    unawaited(Future<T>.sync(check).then(
      (current) {
        // 確かめている間に本物の回答が届いていれば、そちらを返し済み。
        if (result.isCompleted) return;
        gaveUp = true;
        gaveUpWith = current;
        debugPrint('[permissions] no answer while resumed for '
            '${giveUpAfter.inMilliseconds} ms; continuing with $current');
        result.complete(current);
      },
      onError: (Object e, StackTrace s) {
        if (!result.isCompleted) result.completeError(e, s);
      },
    ));
  });

  return result.future;
}
