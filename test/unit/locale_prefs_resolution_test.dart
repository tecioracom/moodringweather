// resolveLocaleFromPrefs (locale_controller.dart) のユニット。
//   FCM background isolate は Riverpod 外で動き、OS 言語リストが空になり得る。
//   その場合でも前景で最後に解決した言語 (app_locale_last_resolved) に倒し、
//   日本語端末の予報プッシュが英語で表示されないことを担保する。

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('手動選択があればそれを優先 (OS リストが空でも)', () async {
    SharedPreferences.setMockInitialValues({'app_locale_override': 'zh-Hans'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      resolveLocaleFromPrefs(prefs, systemLocales: const []).toLanguageTag(),
      'zh-Hans',
    );
  });

  test('OS リストがあればそれで解決し、last_resolved は無視', () async {
    SharedPreferences.setMockInitialValues({'app_locale_last_resolved': 'es'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      resolveLocaleFromPrefs(prefs, systemLocales: const [Locale('ja', 'JP')])
          .languageCode,
      'ja',
    );
  });

  test('OS リストが空 (background isolate) なら前景の最終解決に倒す', () async {
    SharedPreferences.setMockInitialValues({'app_locale_last_resolved': 'ja'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      resolveLocaleFromPrefs(prefs, systemLocales: const []).languageCode,
      'ja',
    );
  });

  test('何も無ければ既定の en', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(
      resolveLocaleFromPrefs(prefs, systemLocales: const []).languageCode,
      'en',
    );
  });

  test('LocaleController は解決結果を last_resolved に記憶する', () async {
    SharedPreferences.setMockInitialValues({'app_locale_override': 'ja'});
    final prefs = await SharedPreferences.getInstance();
    final controller = LocaleController(prefs);
    expect(controller.state.languageCode, 'ja');
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString('app_locale_last_resolved'), 'ja');
    controller.dispose();
  });
}
