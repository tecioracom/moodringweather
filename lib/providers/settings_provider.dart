// lib/providers/settings_provider.dart
//
// 設定 (一般 / 通知) の状態管理。locale_controller.dart と同じ流儀:
//   StateNotifier + SharedPreferences でオンデバイス永続化 (spec.md §13:
//   サーバーへは送らない)。UI はここの provider のみを参照する。
//
// 単位 (気温 °C / °F・風速 m/s / km/h / mph) の初期値は端末の地域で決める
// (docs/design-metric-units-proposal.md §2.6、core/utils/regional_unit_defaults.dart)。
// 使うのは **保存済みの設定が無いときだけ**。一度選んだ値 (初期値と同じ値を
// 選んだ場合も) は保存され、地域が変わっても変えない。

import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/regional_unit_defaults.dart';
import '../core/utils/temperature_unit.dart';
import '../core/utils/wind_speed_unit.dart';
import '../data/models/notification_preferences.dart';
import '../presentation/locale/locale_controller.dart'
    show
        localeControllerProvider,
        resolveLocaleFromPrefs,
        sharedPreferencesProvider;

/// 永続化キー (locale の app_locale_override と同じ単純キー方針)。
const String kPrefKeyTemperatureUnit = 'settings_temperature_unit';
const String kPrefKeyWindSpeedUnit = 'settings_wind_speed_unit';
const String kPrefKeyThemeMode = 'settings_theme_mode';
const String kPrefKeyNotificationPrefs = 'settings_notification_prefs';
const String kPrefKeyWallpaperWeather = 'settings_wallpaper_weather';

/// 前景で最後に読んだ端末の地域 (国コード。地域の無いロケールは空文字)。
/// FCM background isolate など OS のロケールが取れない環境で、風速の単位の
/// 初期値を前景と揃えるために使う。端末内にしか保存しない (spec.md §13)。
const String kPrefKeyUnitRegionLastSeen = 'settings_unit_region_last_seen';

/// 端末の地域 (単位の初期値の決め手)。国コードは端末のロケール
/// (`PlatformDispatcher.locales` の先頭) から取り、アプリの表示言語ではない。
/// 国コードが無いときに使う言語はアプリの言語。テストでは override して注入する。
final unitRegionProvider = Provider<UnitRegion>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final appLanguage = ref.watch(localeControllerProvider).languageCode;
  return resolveUnitRegion(
    prefs,
    appLanguageCode: appLanguage,
    remember: true,
  );
});

/// 端末の地域を解決する。Riverpod の外 (FCM background isolate) からも使う。
///
/// [systemLocales] (既定は PlatformDispatcher) の先頭の国コード。リストが空の
/// isolate では、前景で最後に記録した地域 ([kPrefKeyUnitRegionLastSeen]) を使う。
/// [appLanguageCode] は国コードが無いときの言語 (省略時は保存済みの言語選択から
/// 解決する)。[remember] が true なら、取れた地域を background 用に記録する。
UnitRegion resolveUnitRegion(
  SharedPreferences prefs, {
  List<Locale>? systemLocales,
  String? appLanguageCode,
  bool remember = false,
}) {
  final locales = systemLocales ?? PlatformDispatcher.instance.locales;
  final String? country;
  if (locales.isEmpty) {
    country = prefs.getString(kPrefKeyUnitRegionLastSeen);
  } else {
    country = locales.first.countryCode ?? '';
    if (remember && prefs.getString(kPrefKeyUnitRegionLastSeen) != country) {
      prefs
          .setString(kPrefKeyUnitRegionLastSeen, country)
          .catchError((_) => false);
    }
  }
  return UnitRegion.fromCodes(
    countryCode: country,
    languageCode: appLanguageCode ??
        resolveLocaleFromPrefs(prefs, systemLocales: locales).languageCode,
  );
}

/// 保存済みの風速の単位 (無ければ地域の初期値)。[windSpeedUnitProvider] と同じ規則を
/// Riverpod の外 (FCM background isolate の緊急通知) で使うための入口。
/// 例外は投げない (解決できなければ m/s)。緊急通知を単位の解決で落とさないため
/// (compliance-review-v1.3.0 §9-4 U4)。
WindSpeedUnit resolveWindSpeedUnitFromPrefs(
  SharedPreferences prefs, {
  List<Locale>? systemLocales,
}) {
  try {
    final saved =
        WindSpeedUnitX.tryParse(prefs.getString(kPrefKeyWindSpeedUnit));
    if (saved != null) return saved;
    return resolveUnitRegion(prefs, systemLocales: systemLocales)
        .defaultWindSpeedUnit;
  } catch (_) {
    return WindSpeedUnit.metersPerSecond;
  }
}

/// 温度単位 (°C / °F)。Home / Detail の気温・体感表示が watch する。
/// 保存済みの値が無い (または壊れている) ときは [fallback] (地域の初期値)。
class TemperatureUnitController extends StateNotifier<TemperatureUnit> {
  TemperatureUnitController(
    this._prefs, {
    TemperatureUnit fallback = TemperatureUnit.celsius,
  }) : super(
          TemperatureUnitX.tryParse(
                  _prefs.getString(kPrefKeyTemperatureUnit)) ??
              fallback,
        );

  final SharedPreferences _prefs;

  Future<void> select(TemperatureUnit unit) async {
    state = unit;
    await _prefs.setString(kPrefKeyTemperatureUnit, unit.toTag());
  }
}

final temperatureUnitProvider =
    StateNotifierProvider<TemperatureUnitController, TemperatureUnit>((ref) {
  return TemperatureUnitController(
    ref.watch(sharedPreferencesProvider),
    fallback: ref.watch(unitRegionProvider).defaultTemperatureUnit,
  );
});

/// 風速の単位 (m/s / km/h / mph)。ホーム・詳細の風のタイル、Twin の比較、
/// 緊急通知 (暴風) の本文が使う。保存済みの値が無いときは [fallback] (地域の初期値)。
class WindSpeedUnitController extends StateNotifier<WindSpeedUnit> {
  WindSpeedUnitController(
    this._prefs, {
    WindSpeedUnit fallback = WindSpeedUnit.metersPerSecond,
  }) : super(
          WindSpeedUnitX.tryParse(_prefs.getString(kPrefKeyWindSpeedUnit)) ??
              fallback,
        );

  final SharedPreferences _prefs;

  Future<void> select(WindSpeedUnit unit) async {
    state = unit;
    await _prefs.setString(kPrefKeyWindSpeedUnit, unit.toTag());
  }
}

final windSpeedUnitProvider =
    StateNotifierProvider<WindSpeedUnitController, WindSpeedUnit>((ref) {
  return WindSpeedUnitController(
    ref.watch(sharedPreferencesProvider),
    fallback: ref.watch(unitRegionProvider).defaultWindSpeedUnit,
  );
});

/// テーマ (system / light / dark)。MaterialApp.themeMode に実反映する。
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs)
      : super(_parse(_prefs.getString(kPrefKeyThemeMode)));

  final SharedPreferences _prefs;

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(kPrefKeyThemeMode, mode.name);
  }

  static ThemeMode _parse(String? tag) {
    for (final mode in ThemeMode.values) {
      if (mode.name == tag) return mode;
    }
    return ThemeMode.system;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(sharedPreferencesProvider));
});

/// ライブ壁紙に天気と気温を重ねて描くか (設定 › 一般。既定オン。Android だけ。
/// docs/design-wallpaper-weather-overlay.md §6)。オフでは重ね描きを消し、壁紙は
/// 区分の色だけになる (lib/presentation/wallpaper/)。
class WallpaperWeatherController extends StateNotifier<bool> {
  WallpaperWeatherController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  Future<void> select(bool enabled) async {
    state = enabled;
    await _prefs.setBool(kPrefKeyWallpaperWeather, enabled);
  }

  static bool _load(SharedPreferences prefs) {
    try {
      return prefs.getBool(kPrefKeyWallpaperWeather) ?? true;
    } catch (_) {
      // 型の違う保存値 (壊れたデータ) は既定のオン。
      return true;
    }
  }
}

final wallpaperWeatherProvider =
    StateNotifierProvider<WallpaperWeatherController, bool>((ref) {
  return WallpaperWeatherController(ref.watch(sharedPreferencesProvider));
});

/// 通知設定 (spec.md §12.9 NotificationPreferences)。
/// JSON 1 キーで丸ごと永続化し、モデルの toJson/fromJson を正本とする。
class NotificationPreferencesController
    extends StateNotifier<NotificationPreferences> {
  NotificationPreferencesController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  /// 部分更新 → 保存。UI のトグルはすべてここを通す。
  Future<void> update(
    NotificationPreferences Function(NotificationPreferences current) change,
  ) async {
    state = change(state);
    await _prefs.setString(
        kPrefKeyNotificationPrefs, jsonEncode(state.toJson()));
  }

  static NotificationPreferences _load(SharedPreferences prefs) {
    final raw = prefs.getString(kPrefKeyNotificationPrefs);
    if (raw == null) return const NotificationPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return NotificationPreferences.fromJson(decoded);
      }
    } on FormatException {
      // 壊れた保存値は既定値へフォールバック (ユーザー操作で上書きされる)。
    }
    return const NotificationPreferences();
  }
}

final notificationPreferencesProvider = StateNotifierProvider<
    NotificationPreferencesController, NotificationPreferences>((ref) {
  return NotificationPreferencesController(
      ref.watch(sharedPreferencesProvider));
});
