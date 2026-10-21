// 同梱フォント (OFL 1.1) のライセンス登録 (presentation/theme/font_licenses.dart)。
//   - 4 書体すべてがアプリ内ライセンス画面 (LicenseRegistry) に載る
//   - 本文が SIL OFL 1.1 であること (再配布時の同梱要件)

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/theme/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('4 書体の OFL 本文が LicenseRegistry に登録される', () async {
    registerBundledFontLicenses();
    registerBundledFontLicenses(); // 多重登録しない
    final entries = await LicenseRegistry.licenses.toList();
    final fontEntries = entries
        .where((e) => e.packages
            .any((p) => kBundledFontLicenses.map((f) => f.name).contains(p)))
        .toList();
    expect(fontEntries.map((e) => e.packages.first).toSet(),
        {'Fraunces', 'Inter', 'IBM Plex Mono', 'IBM Plex Sans JP'});
    for (final e in fontEntries) {
      final text = e.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License, Version 1.1'),
          reason: e.packages.first);
      expect(text, contains('Copyright'));
    }
  });
}
