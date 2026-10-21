// lib/providers/clock_provider.dart
//
// 「現在時刻」の注入点。画面が DateTime.now() を直接呼ぶと、ゴールデンテスト
// (test/golden/) が実行時刻で変わって回帰検出にならないため、時刻に依存する
// 表示 (鮮度バナー・時間別ストリップの「今」位置) は本 Provider を経由する。
// 本番は DateTime.now のまま。テストは固定時刻で override する。

import 'package:flutter_riverpod/flutter_riverpod.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
