// test/widget/privacy_page_test.dart
//
// 設定 > プライバシー の「データを削除」(決裁 D3): 確認 → 削除 → 結果表示。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/privacy/data_deletion.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/providers/privacy_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/wallpaper_overlay_fixtures.dart';

class _Eraser implements RemoteDataEraser {
  _Eraser({this.failEntitlement = false});
  final bool failEntitlement;
  int calls = 0;
  @override
  Future<void> deletePushSubscription(String uid) async => calls++;
  @override
  Future<void> deleteEntitlement(String uid) async {
    calls++;
    if (failEntitlement) throw StateError('entitlement');
  }

  @override
  Future<void> deleteFcmToken() async => calls++;
  @override
  Future<void> deleteAuthUser() async => calls++;
}

Future<(SharedPreferences, _Eraser)> _pump(WidgetTester tester,
    {bool failEntitlement = false}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'k': 'v'});
  final prefs = await SharedPreferences.getInstance();
  final eraser = _Eraser(failEntitlement: failEntitlement);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataDeletionServiceProvider.overrideWithValue(
        DataDeletionService(prefs: prefs, uid: 'u1', remote: eraser),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.dark),
      home: const PrivacyPage(),
    ),
  ));
  await tester.pumpAndSettle();
  return (prefs, eraser);
}

class _ColorBridge implements WallpaperBridge {
  final calls = <String>[];

  @override
  Future<bool> setMriState(WallpaperState state) async {
    calls.add('set');
    return true;
  }

  @override
  Future<bool> clearMriState() async {
    calls.add('clear');
    return true;
  }
}

void main() {
  testWidgets('ライブ壁紙の保存 (色・重ね描き) も消し、壁紙の設定は既定のオンに戻る', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({kPrefKeyWallpaperWeather: false});
    final prefs = await SharedPreferences.getInstance();
    final color = _ColorBridge();
    final overlay = RecordingWallpaperOverlay();
    await tester.pumpWidget(ProviderScope(
      // dataDeletionServiceProvider は本物 (Firebase なし = 端末内だけ)。
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        liveWallpaperSupportedProvider.overrideWithValue(true),
        wallpaperBridgeProvider.overrideWithValue(color),
        overlay.providerOverride,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildAppTheme(Brightness.dark),
        home: const PrivacyPage(),
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PrivacyPage)));
    expect(container.read(wallpaperWeatherProvider), isFalse);

    await tester.tap(find.widgetWithText(TextButton, 'Delete my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(color.calls, ['clear']);
    expect(overlay.calls, ['clear']);
    expect(prefs.getKeys(), isEmpty);
    expect(find.text('Your data has been deleted.'), findsOneWidget);
    // 端末内の設定を消したので、「壁紙に天気と気温を表示」は既定のオン
    expect(container.read(wallpaperWeatherProvider), isTrue);
  });

  testWidgets('キャンセルすると何も消えない', (tester) async {
    final (prefs, eraser) = await _pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete my data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all your data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(eraser.calls, 0);
    expect(prefs.getKeys(), isNotEmpty);
  });

  testWidgets('確認するとサーバー側と端末内を消し、完了を表示する', (tester) async {
    final (prefs, eraser) = await _pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(eraser.calls, 4);
    expect(prefs.getKeys(), isEmpty);
    expect(find.text('Your data has been deleted.'), findsOneWidget);
  });

  testWidgets('サーバー側が一部失敗したら部分失敗を正直に表示する', (tester) async {
    final (prefs, _) = await _pump(tester, failEntitlement: true);
    await tester.tap(find.widgetWithText(TextButton, 'Delete my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(prefs.getKeys(), isEmpty);
    expect(find.textContaining('could not be deleted'), findsOneWidget);
  });
}
