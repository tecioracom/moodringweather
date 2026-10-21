// test/unit/l10n_parity_test.dart
//
// ARB 4 言語 (en/ja/es/zh) の機械的整合チェック。
//   - キー集合が en と完全一致 (欠落キーは実行時 MissingTranslation で
//     英語フォールバックになり気づきにくいため、ここで機械検出する)
//   - 全訳文が非空
//   - プレースホルダ ({value} 等) が en と同一集合 (訳抜けで実行時に
//     生の {name} が表示される事故を防ぐ)
//   - 緊急通知の免責文キー (compliance §12.10.4) が全言語に存在し非空
//
// レイアウト崩れ・文言の自然さは自動化できないため対象外
// (docs/manual-device-test-plan.md L10N 章で人手確認する)。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _locales = ['en', 'ja', 'es', 'zh'];

final RegExp _placeholderPattern = RegExp(r'\{[a-zA-Z0-9_]+\}');

Map<String, dynamic> _loadArb(String locale) {
  // main() 直下 (テスト本体の外) でも呼べるよう expect は使わない。
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('${file.path} が存在しない');
  }
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// メタ (@ 始まり) を除いた翻訳キーのみを返す。
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final arbs = <String, Map<String, dynamic>>{
    for (final locale in _locales) locale: _loadArb(locale),
  };
  final enKeys = _messageKeys(arbs['en']!);

  test('en の翻訳キーが空でない', () {
    expect(enKeys, isNotEmpty);
  });

  for (final locale in _locales.skip(1)) {
    test('$locale: キー集合が en と完全一致する', () {
      final keys = _messageKeys(arbs[locale]!);
      expect(enKeys.difference(keys), isEmpty, reason: '$locale に欠落しているキー');
      expect(keys.difference(enKeys), isEmpty, reason: '$locale にだけ存在する余剰キー');
    });
  }

  for (final locale in _locales) {
    test('$locale: 全訳文が非空の文字列である', () {
      final arb = arbs[locale]!;
      for (final key in _messageKeys(arb)) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale/$key が文字列でない');
        expect((value as String).trim(), isNotEmpty,
            reason: '$locale/$key が空文字');
      }
    });
  }

  for (final locale in _locales.skip(1)) {
    test('$locale: プレースホルダ集合が en と一致する', () {
      final arb = arbs[locale]!;
      for (final key in enKeys) {
        final enPlaceholders = _placeholderPattern
            .allMatches(arbs['en']![key] as String)
            .map((m) => m.group(0))
            .toSet();
        final localized = _placeholderPattern
            .allMatches(arb[key] as String)
            .map((m) => m.group(0))
            .toSet();
        expect(localized, equals(enPlaceholders),
            reason: '$locale/$key のプレースホルダが en と不一致');
      }
    });
  }

  test('緊急通知の免責文 (emergencyDisclaimer) が全言語に存在し非空', () {
    for (final locale in _locales) {
      final value = arbs[locale]!['emergencyDisclaimer'];
      expect(value, isA<String>(), reason: '$locale に emergencyDisclaimer がない');
      expect((value as String).trim(), isNotEmpty);
    }
  });

  test('l10n/untranslated.txt に未訳が残っていない', () {
    final file = File('lib/l10n/untranslated.txt');
    if (!file.existsSync()) return; // 生成物なし = 未訳なし
    final content = file.readAsStringSync().trim();
    expect(content == '' || content == '{}', isTrue,
        reason: '未訳キーが残っている: $content');
  });
}
