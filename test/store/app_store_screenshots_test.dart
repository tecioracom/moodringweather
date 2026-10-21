// test/store/app_store_screenshots_test.dart
//
// App Store のスクリーンショット (iOS 1.3.0、6.9 インチ 1320×2868) — ja / en / es。
// zh は app_store_screenshots_zh_test.dart (フォントの都合で別プロセス)。
// 撮る画面・固定データ・出力先は store_shots_harness.dart。
//
// **既定では実行しない** (CI・通常の flutter test では skip):
//
//   flutter test test/store --update-goldens --dart-define=MRW_STORE_SHOTS=true
//
// 出力: store-listings/ios-1.3.0/screenshots/6.9/{ja,en,es}_{1..5}_*.png

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_shots_harness.dart';

void main() {
  setUpAll(() => loadStoreFonts(simplifiedChinese: false));

  defineStoreShots(const [Locale('ja'), Locale('en'), Locale('es')]);
}
