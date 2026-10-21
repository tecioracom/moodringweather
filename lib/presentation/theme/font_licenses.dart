// lib/presentation/theme/font_licenses.dart
//
// 同梱フォント (SIL OFL 1.1) のライセンス本文をアプリ内ライセンス画面
// (設定 > About > オープンソースライセンス = showLicensePage) に載せる。
// OFL は再配布時にライセンス本文の同梱を求める。フォントファイルの name テーブルにも
// 本文が埋め込まれているが、人が読める形で表示するため assets/fonts/OFL-*.txt を
// 同梱し LicenseRegistry へ登録する。

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 同梱フォントと OFL 本文アセットの対応。
const List<({String name, String asset})> kBundledFontLicenses = [
  (name: 'Fraunces', asset: 'assets/fonts/OFL-Fraunces.txt'),
  (name: 'Inter', asset: 'assets/fonts/OFL-Inter.txt'),
  (name: 'IBM Plex Mono', asset: 'assets/fonts/OFL-IBMPlexMono.txt'),
  (name: 'IBM Plex Sans JP', asset: 'assets/fonts/OFL-IBMPlexSansJP.txt'),
];

bool _registered = false;

/// 起動時に 1 回呼ぶ。多重登録はしない。本文の読み込みは遅延 (ライセンス画面を
/// 開いたとき) で、失敗してもその項目を飛ばすだけでアプリは落ちない。
void registerBundledFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final entry in kBundledFontLicenses) {
      String text;
      try {
        text = await rootBundle.loadString(entry.asset);
      } catch (e) {
        debugPrint('[fonts] license asset unavailable: ${entry.asset} ($e)');
        continue;
      }
      yield LicenseEntryWithLineBreaks([entry.name], text);
    }
  });
}
