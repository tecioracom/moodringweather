// test/qa/wallpaper_deletion_consistency_rc_test.dart
//
// 1.3.0 (13) の QA: 「データを削除」のあとのライブ壁紙 (色と重ね描き) の整合。
// 本番と同じ MoodRingApp を組む。色は main.dart の mriProvider の監視
// (WallpaperMriSync)、重ね描きは MaterialApp.builder の WallpaperOverlayHost が送る。
// 削除は設定 › プライバシーの画面から行う (privacy_page.dart → deleteAll →
// invalidateLocalStateAfterDeletion)。
//
// 守りたい約束: **重ね描きが出ているなら、その区分名と壁紙の色の区分が同じ**。
// 色だけ送り直して重ね描きが無い状態 (設定オフと同じ見え方) は食い違いではない。
//
// QA-25 (Sev3、docs/qa-report-saved-places-2026-09-29.md §V.8):
//   キャリブレーションをしていない人は、削除でプロファイルを読み直しても同じ const の
//   既定値 (PersonalProfile.initial()) なので mriProvider が計算し直されず、色は
//   送り直されない (既定の快適の緑のまま)。一方、削除後の読み直しで
//   localeControllerProvider が新しい Locale (値は同じ、別のインスタンス) を出すため
//   MoodRingApp が作り直され、MaterialApp.builder の WallpaperOverlayHost が今の天気で
//   重ね描きを送り直す (clear() で「前回送った内容」を忘れているため)。今の区分が快適
//   以外だと「緑の地に HOT」になり、次に天気を取り直す (引っ張って更新・アプリの
//   再起動) まで続く。設定の値に関係なく、未調整の人の削除では毎回起きる。
//   実機手順書 D-16 手順 2 の期待 (重ね描きが出て、色は今の区分) とも食い違う。
//   → 再現テスト 2 件は skip。修正したら `_qa25Open` を false にする。
//   エミュレータでも再現 (クウェート MRI 34「暑い」、設定オフ → 削除 → 緑の地に
//   「☀ 97° / HOT · 11:45 PM」。引っ張って更新で色が戻る)。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/city.dart';
import 'package:mood_ring_weather/data/models/personal_profile.dart';
import 'package:mood_ring_weather/data/services/notification_service.dart';
import 'package:mood_ring_weather/data/wallpaper/wallpaper_bridge.dart';
import 'package:mood_ring_weather/domain/mri/mri_band.dart';
import 'package:mood_ring_weather/main.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/calibration_provider.dart';
import 'package:mood_ring_weather/providers/clock_provider.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/emergency_alert_provider.dart';
import 'package:mood_ring_weather/providers/mri_provider.dart';
import 'package:mood_ring_weather/providers/settings_provider.dart';
import 'package:mood_ring_weather/providers/wallpaper_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart';
import '../fixtures/wallpaper_overlay_fixtures.dart';
import '../golden/golden_harness.dart';

/// QA-25 (1.3.0 (13) Sev3): 削除後に重ね描きだけ描き直され、色は既定の緑のまま。
/// 再現テストはこれが true の間 skip する。修正したら false にする。
const bool _qa25Open = false;

class _FakeGateway implements NotificationGateway {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {}
}

/// 壁紙の色の受け渡しを記録する ('set <区分名>' / 'clear')。
class _ColorBridge implements WallpaperBridge {
  final calls = <String>[];

  @override
  Future<bool> setMriState(WallpaperState state) async {
    calls.add('set ${state.band.name}');
    return true;
  }

  @override
  Future<bool> clearMriState() async {
    calls.add('clear');
    return true;
  }
}

class _App {
  _App(this.container, this.color, this.overlay);

  final ProviderContainer container;
  final _ColorBridge color;
  final RecordingWallpaperOverlay overlay;

  /// 今の現在地の区分 (重ね描きのホストと色の両方の元)。
  MriBand get band => container.read(mriProvider).requireValue.band;
}

/// 本番と同じ MoodRingApp を、現在地 = 暑い (那覇の天気) で組み立てる。
Future<_App> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final color = _ColorBridge();
  final overlay = RecordingWallpaperOverlay();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      clockProvider.overrideWithValue(() => kPlacesNow),
      cityCatalogProvider.overrideWith((ref) async => const <City>[]),
      // 既定地点ではない現在地 (重ね描きを出す)。本物の Geolocator は呼ばない。
      currentLocationProvider
          .overrideWith((ref) async => const GeoPoint(26.21, 127.68)),
      weatherSnapshotProvider
          .overrideWith((ref) async => nahaSnapshot(kPlacesNow)),
      hourlyWeatherProvider
          .overrideWith((ref) async => hourlyAround(nahaSnapshot)),
      cityNameProvider.overrideWith((ref) async => 'Naha'),
      ...entitlementOverrides(plus: false),
      ...savedPlaceWeatherOverrides(),
      notificationGatewayProvider.overrideWithValue(_FakeGateway()),
      liveWallpaperSupportedProvider.overrideWithValue(true),
      wallpaperBridgeProvider.overrideWithValue(color),
      overlay.providerOverride,
    ],
    child: const MoodRingApp(),
  ));
  await settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MainShell)));
  return _App(container, color, overlay);
}

/// 設定 › プライバシー › データを削除 → 削除 (本番の画面の流れ)。
Future<void> _deleteAllData(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  unawaited(navigator
      .push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())));
  await settle(tester);
  final open = find.widgetWithText(TextButton, 'Delete my data');
  await tester.ensureVisible(open);
  await tester.tap(open);
  await settle(tester);
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await settle(tester);
  expect(find.text('Your data has been deleted.'), findsOneWidget);
}

/// 重ね描きが出ているなら、壁紙の色は同じ区分で描かれている。
void _expectOverlayMatchesColor(_App app) {
  final overlayShown = app.overlay.calls.last == 'set';
  if (!overlayShown) return; // 色だけ (設定オフと同じ見え方) は食い違いではない
  expect(
    app.color.calls.last,
    'set ${app.band.name}',
    reason: '重ね描きは「${app.overlay.contents.last.bandLabel}」なのに、'
        '壁紙の色の最後の受け渡しは ${app.color.calls.last} '
        '(clear = 既定の快適の緑)。color: ${app.color.calls}, '
        'overlay: ${app.overlay.calls}',
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('前提: 現在地は暑い区分で、色と重ね描きを送っている', (tester) async {
    final app = await _pumpApp(tester);
    expect(app.band, isNot(MriBand.comfortable));
    expect(app.color.calls, ['set ${app.band.name}']);
    expect(app.overlay.calls, ['set']);
  });

  testWidgets(
      'キャリブレーション済みなら、削除で既定に戻ったプロファイルで計算し直し、'
      '色も重ね描きも今の区分で描き直す', (tester) async {
    const calibrated = PersonalProfile(deltaT: 1.0, mOpt: 70, feedbackCount: 5);
    final app = await _pumpApp(tester, prefs: {
      kPrefKeyPersonalProfile: jsonEncode(calibrated.toJson()),
    });
    await _deleteAllData(tester);
    expect(app.color.calls, contains('clear'));
    expect(app.overlay.calls, contains('clear'));
    expect(app.color.calls.last, 'set ${app.band.name}');
    expect(app.overlay.calls.last, 'set');
    _expectOverlayMatchesColor(app);
  });

  testWidgets('QA-25: 未調整・設定が既定のままで削除しても、重ね描きと色の区分は食い違わない', skip: _qa25Open,
      (tester) async {
    final app = await _pumpApp(tester);
    await _deleteAllData(tester);
    expect(app.color.calls, contains('clear'));
    expect(app.overlay.calls, contains('clear'));
    _expectOverlayMatchesColor(app);
  });

  testWidgets(
      'QA-25: 設定オフのまま削除すると (D-16 手順 2)、設定が既定のオンに戻って重ね描きが'
      '出る。色も今の区分で描き直す',
      skip: _qa25Open, (tester) async {
    final app =
        await _pumpApp(tester, prefs: {kPrefKeyWallpaperWeather: false});
    expect(app.overlay.calls, ['clear']);
    await _deleteAllData(tester);
    expect(app.container.read(wallpaperWeatherProvider), isTrue);
    expect(app.overlay.calls.last, 'set');
    _expectOverlayMatchesColor(app);
  });
}
