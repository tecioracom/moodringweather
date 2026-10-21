// test/unit/locale_resolver_test.dart
//
// spec.md §21 のロケール解決ロジックのユニットテスト。
// Flutter に依存しない純 Dart テスト (test パッケージ)。

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/domain/locale/locale_resolver.dart';

void main() {
  group('LocaleTag.parse', () {
    test('言語のみ', () {
      expect(LocaleTag.parse('ja'), const LocaleTag('ja'));
    });
    test('script 付き (ハイフン / アンダースコア両対応)', () {
      expect(LocaleTag.parse('zh-Hans'), const LocaleTag('zh', 'Hans'));
      expect(LocaleTag.parse('zh_Hant'), const LocaleTag('zh', 'Hant'));
    });
    test('country は無視し script を拾う', () {
      expect(LocaleTag.parse('zh-Hant-TW'), const LocaleTag('zh', 'Hant'));
      expect(LocaleTag.parse('en-US'), const LocaleTag('en'));
    });
  });

  group('resolveLocale — 手動選択の優先', () {
    test('手動選択がサポート対象なら OS 設定より優先', () {
      final r = resolveLocale(
        override: const LocaleTag('es'),
        systemPreferred: const [LocaleTag('ja')],
      );
      expect(r, const LocaleTag('es'));
    });

    test('手動 "zh" (script 未指定) は正規形 zh-Hans に揃う', () {
      final r = resolveLocale(
        override: const LocaleTag('zh'),
        systemPreferred: const [LocaleTag('en')],
      );
      expect(r, const LocaleTag('zh', 'Hans'));
    });

    test('未サポートの手動選択は無視して OS 設定にフォールバック', () {
      final r = resolveLocale(
        override: const LocaleTag('fr'),
        systemPreferred: const [LocaleTag('es')],
      );
      expect(r, const LocaleTag('es'));
    });
  });

  group('resolveLocale — OS 言語からの解決', () {
    test('完全一致', () {
      expect(
        resolveLocale(systemPreferred: const [LocaleTag('ja')]),
        const LocaleTag('ja'),
      );
    });

    test('en-US → en (script/country は無視)', () {
      expect(
        resolveLocale(systemPreferred: const [LocaleTag('en')]),
        const LocaleTag('en'),
      );
    });

    test('zh-Hans → 簡体字', () {
      expect(
        resolveLocale(systemPreferred: const [LocaleTag('zh', 'Hans')]),
        const LocaleTag('zh', 'Hans'),
      );
    });

    test('zh-Hant (未サポート) → 簡体字にフォールバック', () {
      expect(
        resolveLocale(systemPreferred: const [LocaleTag('zh', 'Hant')]),
        const LocaleTag('zh', 'Hans'),
      );
    });

    test('zh (script 不明) → 簡体字', () {
      expect(
        resolveLocale(systemPreferred: const [LocaleTag('zh')]),
        const LocaleTag('zh', 'Hans'),
      );
    });

    test('優先順位: 先頭の対応言語を採用 (ko 未対応→ 次の ja)', () {
      expect(
        resolveLocale(
          systemPreferred: const [LocaleTag('ko'), LocaleTag('ja')],
        ),
        const LocaleTag('ja'),
      );
    });

    test('どの OS 言語も未対応なら英語フォールバック', () {
      expect(
        resolveLocale(
          systemPreferred: const [LocaleTag('fr'), LocaleTag('de')],
        ),
        const LocaleTag('en'),
      );
    });

    test('OS 言語リストが空でも英語フォールバック', () {
      expect(resolveLocale(systemPreferred: const []), const LocaleTag('en'));
    });
  });
}
