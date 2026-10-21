// test/store/app_store_screenshots_zh_test.dart
//
// App Store のスクリーンショット (iOS 1.3.0、6.9 インチ 1320×2868) — zh (簡体字)。
// 簡体字は同梱の IBM Plex Sans JP に無い字があり、端末ではシステムの PingFang SC へ
// フォールバックする。flutter_test はフォールバックしないので、このファイルでは
// IBMPlexSansJP の名前で macOS の PingFang SC を読み込む (ja と同じプロセスでは
// 両立できないため別ファイル)。詳細は store_shots_harness.dart。
//
// **既定では実行しない** (CI・通常の flutter test では skip):
//
//   flutter test test/store --update-goldens --dart-define=MRW_STORE_SHOTS=true
//
// 出力: store-listings/ios-1.3.0/screenshots/6.9/zh_{1..5}_*.png

@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'store_shots_harness.dart';

void main() {
  setUpAll(() async {
    if (kStoreShotsEnabled) await loadStoreFonts(simplifiedChinese: true);
  });

  defineStoreShots(const [kStoreZh]);
}
