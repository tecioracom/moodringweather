// lib/presentation/locale/locale_controller.dart
//
// 表示言語の状態管理 (spec.md §21)。
//   - 端末 (OS) の言語設定を既定とする
//   - ユーザーが言語セレクタで選んだ場合はそれを優先し、オンデバイスに永続化
//   - 解決ロジックそのものは純 Dart の locale_resolver.dart に委譲
//
// プライバシー (spec.md §13): 選択値は SharedPreferences のみに保存し、
// サーバーへは送らない。

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/locale/locale_resolver.dart';

/// 永続化キー。値は LocaleTag.toTag() ("ja" / "zh-Hans" など)。
const String _kPrefKey = 'app_locale_override';

/// 前景で最後に解決した表示ロケール (LocaleTag.toTag())。
/// FCM background isolate など OS 言語リストが取れない環境のフォールバック用。
/// 端末内にしか保存しない (spec.md §13)。
const String _kLastResolvedKey = 'app_locale_last_resolved';

/// SharedPreferences を Riverpod に注入するための Provider。
/// main() で `overrideWithValue(await SharedPreferences.getInstance())` する。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main() で override してください'),
);

/// アプリの表示ロケールを管理する Notifier。
///
/// `state` は「画面に渡す Locale」。null を `MaterialApp.locale` に渡すと
/// Flutter が OS 設定に従うが、本アプリでは未対応言語のフォールバックを
/// 自前で制御したいので、常に解決済みの Locale を保持する。
class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs) : super(const Locale('en')) {
    _init();
  }

  final SharedPreferences _prefs;

  /// ユーザーが「端末の設定に従う」を選んでいるか (override 未設定なら true)。
  bool get isFollowingSystem => _prefs.getString(_kPrefKey) == null;

  void _init() {
    state = resolveLocaleFromPrefs(_prefs);
    _remember(state);
  }

  /// OS の優先言語リストを LocaleResolver 用に変換して解決する。
  Locale _resolve({LocaleTag? override}) {
    final locale = _resolveWithSystem(override);
    _remember(locale);
    return locale;
  }

  /// 解決結果を background isolate 用に記憶する (失敗は無視)。
  void _remember(Locale locale) {
    final tag = LocaleTag(locale.languageCode, locale.scriptCode).toTag();
    if (_prefs.getString(_kLastResolvedKey) == tag) return;
    _prefs.setString(_kLastResolvedKey, tag).catchError((_) => false);
  }

  /// 言語セレクタからの選択。null = 「端末の設定に従う」に戻す。
  Future<void> select(LocaleTag? tag) async {
    if (tag == null) {
      await _prefs.remove(_kPrefKey);
    } else {
      await _prefs.setString(_kPrefKey, tag.toTag());
    }
    state = _resolve(override: tag);
  }

  /// OS 言語がアプリ実行中に変わった場合 (システム設定変更) の再解決。
  /// `WidgetsBindingObserver.didChangeLocales` から呼ぶ。
  void onSystemLocalesChanged() {
    if (isFollowingSystem) {
      state = _resolve();
    }
  }
}

/// 保存済みの言語選択 (無ければ OS 言語) から表示ロケールを解決する。
///
/// Riverpod コンテナ外 (FCM background isolate など) からも使えるよう
/// トップレベル関数にしている。LocaleController の解決と同一規則。
///
/// 解決順: 手動選択 (override) → OS 言語リスト → 前景で最後に解決した言語
/// (OS リストが空の isolate のみ) → 既定 (en)。
/// [systemLocales] はテスト用の差し替え口 (既定は PlatformDispatcher)。
Locale resolveLocaleFromPrefs(
  SharedPreferences prefs, {
  List<Locale>? systemLocales,
}) {
  final overrideTag = prefs.getString(_kPrefKey);
  final override = overrideTag == null ? null : LocaleTag.parse(overrideTag);
  final system = systemLocales ?? PlatformDispatcher.instance.locales;
  if (override == null && system.isEmpty) {
    final last = prefs.getString(_kLastResolvedKey);
    if (last != null) {
      return _resolveWithSystem(LocaleTag.parse(last), systemLocales: const []);
    }
  }
  return _resolveWithSystem(override, systemLocales: system);
}

Locale _resolveWithSystem(LocaleTag? override, {List<Locale>? systemLocales}) {
  final system = (systemLocales ?? PlatformDispatcher.instance.locales)
      .map((l) => LocaleTag(
            l.languageCode.toLowerCase(),
            l.scriptCode,
          ))
      .toList();
  final tag = resolveLocale(override: override, systemPreferred: system);
  return Locale.fromSubtags(
      languageCode: tag.languageCode, scriptCode: tag.scriptCode);
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController(ref.watch(sharedPreferencesProvider));
});

/// MaterialApp.supportedLocales に渡す一覧 (locale_resolver の正本から生成)。
final List<Locale> supportedFlutterLocales = kSupportedLocales
    .map((t) => Locale.fromSubtags(
          languageCode: t.languageCode,
          scriptCode: t.scriptCode,
        ))
    .toList();
