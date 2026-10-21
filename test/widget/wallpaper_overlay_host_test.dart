// アプリの根元に置く重ね描きのホスト (lib/presentation/wallpaper/wallpaper_overlay_host.dart)。
//   - 現在地の天気があれば描いて渡す。区分名はホームと同じ判定 (推定最適に近ければ「最適」)
//   - 設定でオフにすると消し、オンに戻すと描き直す
//   - 既定地点 (東京) では出さない
//   - iOS (ライブ壁紙なし) では何もしない
//   - 子はそのまま表示する

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/utils/temperature_unit.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_overlay_bridge.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_content.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_host.dart';
import 'package:mood_ring_weather/presentation/wallpaper/wallpaper_overlay_sync.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/unit_region_fixtures.dart';
import '../golden/golden_harness.dart' show goldenSnapshot, kGoldenNow;

class _RecordingBridge implements WallpaperOverlayBridge {
  final calls = <String>[];

  @override
  Future<bool> setOverlay(WallpaperOverlayPayload payload) async {
    calls.add('set');
    return true;
  }

  @override
  Future<bool> clearOverlay() async {
    calls.add('clear');
    return true;
  }
}

class _Host {
  _Host(this.bridge, this.contents, this.container);
  final _RecordingBridge bridge;
  final List<WallpaperOverlayContent> contents;
  final ProviderContainer container;
}

Future<_Host> _pumpHost(
  WidgetTester tester, {
  GeoPoint location = const GeoPoint(35.68, 139.77),
  bool supported = true,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final bridge = _RecordingBridge();
  final contents = <WallpaperOverlayContent>[];
  final sync = WallpaperOverlaySync(
    bridge,
    render: (content) async {
      contents.add(content);
      return WallpaperOverlayPayload(
        asOf: content.asOf,
        freshPng: Uint8List(1),
        stalePng: Uint8List(1),
        pixelRatio: content.pixelRatio,
      );
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        unitRegionOverride(),
        liveWallpaperSupportedProvider.overrideWithValue(supported),
        currentLocationProvider.overrideWith((ref) async => location),
        weatherSnapshotProvider
            .overrideWith((ref) async => goldenSnapshot(kGoldenNow)),
        wallpaperOverlaySyncProvider.overrideWithValue(sync),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: supportedFlutterLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => WallpaperOverlayHost(child: child!),
        home: const Text('home'),
      ),
    ),
  );
  await _settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.text('home')));
  return _Host(bridge, contents, container);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('現在地の天気を描いて渡す。区分名はホームと同じ (推定最適に近ければ「最適」)', (tester) async {
    final host = await _pumpHost(tester);
    expect(find.text('home'), findsOneWidget);
    expect(host.bridge.calls, ['set']);
    final content = host.contents.single;
    // golden の天気 (22°C・晴れ) は MRI 64 = 未学習の推定最適 64 → 最適
    expect(content.temperature, '22°');
    expect(content.bandAndTime, startsWith('最適 · '));
    expect(content.asOf, kGoldenNow);
  });

  testWidgets('設定でオフにすると消し、オンに戻すと描き直す', (tester) async {
    final host = await _pumpHost(tester);
    await host.container.read(wallpaperWeatherProvider.notifier).select(false);
    await _settle(tester);
    expect(host.bridge.calls, ['set', 'clear']);
    await host.container.read(wallpaperWeatherProvider.notifier).select(true);
    await _settle(tester);
    expect(host.bridge.calls, ['set', 'clear', 'set']);
  });

  testWidgets('保存済みの設定がオフなら、起動時に消す', (tester) async {
    final host = await _pumpHost(
      tester,
      prefs: {kPrefKeyWallpaperWeather: false},
    );
    expect(host.bridge.calls, ['clear']);
    expect(host.contents, isEmpty);
  });

  testWidgets('既定地点 (現在地が分からない) では出さない', (tester) async {
    final host = await _pumpHost(tester, location: LocationDataSource.fallback);
    expect(host.bridge.calls, ['clear']);
    expect(host.contents, isEmpty);
  });

  testWidgets('°F に切り替えると描き直す', (tester) async {
    final host = await _pumpHost(tester);
    await host.container
        .read(temperatureUnitProvider.notifier)
        .select(TemperatureUnit.fahrenheit);
    await _settle(tester);
    expect(host.bridge.calls, ['set', 'set']);
    expect(host.contents.last.temperature, '72°');
  });

  testWidgets('iOS (ライブ壁紙なし) では何もしない', (tester) async {
    final host = await _pumpHost(tester, supported: false);
    expect(host.bridge.calls, isEmpty);
    expect(find.text('home'), findsOneWidget);
  });
}
