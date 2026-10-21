// lib/domain/locale/locale_resolver.dart
//
// OS 言語設定とユーザーの手動選択から「実際に表示するロケール」を決める
// 純 Dart ロジック (spec.md §21)。Flutter に依存しないのでユニットテスト対象。
// MRI 計算と同じく「ドメインロジックは純 Dart + テスト必須」の方針に従う
// (agents.md / spec.md §2.3)。

/// 言語タグの最小表現。Flutter の `Locale` から script を含めて変換できるよう
/// languageCode と scriptCode を持つ (country は表示切替に不要なので保持しない)。
class LocaleTag {
  final String languageCode; // ISO 639-1 小文字: ja / en / es / zh
  final String? scriptCode; // ISO 15924: Hans / Hant など。無ければ null

  const LocaleTag(this.languageCode, [this.scriptCode]);

  /// "ja" / "zh-Hans" 形式の BCP-47 風タグ。SharedPreferences 保存キーに使う。
  String toTag() =>
      scriptCode == null ? languageCode : '$languageCode-$scriptCode';

  /// "ja" / "zh-Hans" / "zh_Hans" / "zh-Hant-TW" などを緩くパースする。
  static LocaleTag parse(String raw) {
    final parts = raw.replaceAll('_', '-').split('-');
    final lang = parts.first.toLowerCase();
    String? script;
    for (final p in parts.skip(1)) {
      // 4 文字の部分を script とみなす (例: Hans/Hant)。country(2 文字)は無視。
      if (p.length == 4) {
        script = p[0].toUpperCase() + p.substring(1).toLowerCase();
        break;
      }
    }
    return LocaleTag(lang, script);
  }

  @override
  bool operator ==(Object other) =>
      other is LocaleTag &&
      other.languageCode == languageCode &&
      other.scriptCode == scriptCode;

  @override
  int get hashCode => Object.hash(languageCode, scriptCode);

  @override
  String toString() => toTag();
}

/// アプリがローカライズを提供するロケール (spec.md §21.1)。
/// 並び順 = 言語ピッカーの表示順 & マッチング優先順位。
const List<LocaleTag> kSupportedLocales = [
  LocaleTag('ja'),
  LocaleTag('en'),
  LocaleTag('zh', 'Hans'),
  LocaleTag('es'),
];

/// 中国語で script が判別できないときのデフォルト (簡体字)。
const LocaleTag kDefaultChinese = LocaleTag('zh', 'Hans');

/// どの OS 言語にも一致しなかった場合の最終フォールバック。
/// 国際展開の標準として英語に倒す (spec.md §21.2)。
const LocaleTag kFallbackLocale = LocaleTag('en');

/// 表示ロケールを解決する純関数。
///
/// - [override] : ユーザーが言語セレクタで明示選択したタグ (未選択なら null)。
/// - [systemPreferred] : OS の優先言語リスト (先頭ほど優先)。
///
/// 解決順:
///   1. 手動選択がサポート対象なら最優先で採用 (OS 設定より優先)。
///   2. OS の優先言語を順に走査し、サポート対象へマッチさせる。
///      - 言語 + script 完全一致を最優先。
///      - 言語のみ一致なら、zh は script を見て簡体/(将来)繁体を選び、
///        判別不能なら簡体字 ([kDefaultChinese])。
///   3. いずれも一致しなければ [kFallbackLocale] (英語)。
LocaleTag resolveLocale({
  LocaleTag? override,
  required List<LocaleTag> systemPreferred,
  List<LocaleTag> supported = kSupportedLocales,
}) {
  if (override != null && _isSupported(override, supported)) {
    return _canonical(override, supported);
  }

  for (final pref in systemPreferred) {
    // 1) 言語 + script 完全一致
    for (final s in supported) {
      if (s.languageCode == pref.languageCode &&
          s.scriptCode == pref.scriptCode) {
        return s;
      }
    }
    // 2) 言語のみ一致 (script は後で詰める)
    final sameLang =
        supported.where((s) => s.languageCode == pref.languageCode).toList();
    if (sameLang.isEmpty) continue;

    if (pref.languageCode == 'zh') {
      // 繁体字 (Hant/TW/HK/MO) 指定なら繁体候補を、無ければ簡体字を選ぶ。
      final wantsTraditional = pref.scriptCode == 'Hant';
      final match = sameLang.firstWhere(
        (s) =>
            wantsTraditional ? s.scriptCode == 'Hant' : s.scriptCode == 'Hans',
        orElse: () => sameLang.contains(kDefaultChinese)
            ? kDefaultChinese
            : sameLang.first,
      );
      return match;
    }
    return sameLang.first;
  }

  return _isSupported(kFallbackLocale, supported)
      ? _canonical(kFallbackLocale, supported)
      : supported.first;
}

bool _isSupported(LocaleTag tag, List<LocaleTag> supported) =>
    supported.any((s) =>
        s.languageCode == tag.languageCode &&
        (s.scriptCode == tag.scriptCode || tag.scriptCode == null));

/// override が "zh" のように script 未指定でも、サポート表の正規形 (zh-Hans) に揃える。
LocaleTag _canonical(LocaleTag tag, List<LocaleTag> supported) {
  return supported.firstWhere(
    (s) =>
        s.languageCode == tag.languageCode &&
        (tag.scriptCode == null || s.scriptCode == tag.scriptCode),
    orElse: () => tag,
  );
}
