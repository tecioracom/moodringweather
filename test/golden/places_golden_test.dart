// test/golden/places_golden_test.dart
//
// 保存地点 (Plus 多地点) の画面の見た目の回帰検出。Dark/Light × en/ja。
// 保存地点は Plus 限定 (無料 0 件、2026-09-30 ユーザー決裁)。
//   ホーム (案E' 段階 2): E1 保存 0 件 / E2 無料で 1 件残存 (無料 1 件の時期に保存。
//     見た目は旧 E2 と同じ) / E3 Plus 5 件 / E4 那覇を表示中 /
//     E5 現在地の熱中症アラート / E6a 取得中 / E6b 取得失敗 / E7 Plus 上限で「+」
//   地点を追加 (案S′): B0 未入力 / B1 候補 / B3 0 件 / B4 通信エラー
//   地点管理: A1 無料 0 件 (件数なし・Plus カードだけ) / A2 無料で 1 件残存 (保存 1 件 +
//     Plus カード。旧「1 / 1」) / A3 Plus 4/5 / A4 Plus 5/5 / A5 無料で 5 件残存
//
// 実行:   flutter test test/golden
// 更新:   flutter test test/golden --update-goldens   (差分を目視した後だけ)
// 端末は Figma と同じ 390×844 / DPR 1 (キーボードは描かない)。

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/data/models/weather_snapshot.dart';
import 'package:mood_ring_weather/presentation/places/add_place_sheet.dart';
import 'package:mood_ring_weather/presentation/places/place_tab_bar.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/shell/main_shell.dart';
import 'package:mood_ring_weather/providers/place_selection_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';

import '../fixtures/saved_places_fixtures.dart';
import 'golden_harness.dart';

class _HomeState {
  const _HomeState({
    required this.saved,
    required this.plus,
    this.select,
    this.current,
    this.modes = const {},
    this.tapAdd = false,
  });

  final int saved;
  final bool plus;
  final String? select;
  final WeatherSnapshot Function(DateTime)? current;
  final Map<String, PlaceWeatherMode> modes;
  final bool tapAdd;
}

class _SheetState {
  const _SheetState({this.ja, this.en, this.error = false});

  /// 入力 (null = 未入力の B0)。
  final String? ja;
  final String? en;
  final bool error;
}

class _LocationsState {
  const _LocationsState({required this.saved, required this.plus});
  final int saved;
  final bool plus;
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Brightness brightness,
  required Locale locale,
  required List<Override> overrides,
}) async {
  useGoldenViewport(tester);
  await tester.pumpWidget(goldenApp(
    home: const MainShell(),
    brightness: brightness,
    locale: locale,
    overrides: overrides,
  ));
  await settle(tester);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MainShell)));

void main() {
  setUpAll(loadAppFonts);

  const locales = [Locale('en'), Locale('ja')];
  const modes = [Brightness.dark, Brightness.light];

  const homeStates = <String, _HomeState>{
    'places_e1_empty': _HomeState(saved: 0, plus: false),
    'places_e2_free': _HomeState(saved: 1, plus: false),
    'places_e3_plus': _HomeState(saved: 5, plus: true),
    'places_e4_switched': _HomeState(saved: 5, plus: true, select: kNahaId),
    'places_e5_alert': _HomeState(
      saved: 5,
      plus: true,
      select: kNahaId,
      current: dangerousHeatSnapshot,
    ),
    'places_e6a_loading': _HomeState(
      saved: 5,
      plus: true,
      select: kSapporoId,
      modes: {kSapporoId: PlaceWeatherMode.loading},
    ),
    'places_e6b_failed': _HomeState(
      saved: 5,
      plus: true,
      select: kReykjavikId,
      modes: {kReykjavikId: PlaceWeatherMode.error},
    ),
    'places_e7_limit': _HomeState(saved: 5, plus: true, tapAdd: true),
  };

  const sheetStates = <String, _SheetState>{
    'add_place_b0': _SheetState(),
    'add_place_b1': _SheetState(ja: '京都', en: 'Kyoto'),
    'add_place_b3': _SheetState(ja: 'きょうと', en: 'kyouto'),
    'add_place_b4': _SheetState(ja: '京都', en: 'Kyoto', error: true),
  };

  const locationStates = <String, _LocationsState>{
    'locations_a1': _LocationsState(saved: 0, plus: false),
    'locations_a2': _LocationsState(saved: 1, plus: false),
    'locations_a3': _LocationsState(saved: 4, plus: true),
    'locations_a4': _LocationsState(saved: 5, plus: true),
    'locations_a5': _LocationsState(saved: 5, plus: false),
  };

  for (final brightness in modes) {
    for (final locale in locales) {
      final tag = '${brightness.name}/${locale.languageCode}';
      final city = locale.languageCode == 'ja' ? '東京' : 'Tokyo';

      for (final entry in homeStates.entries) {
        final s = entry.value;
        testWidgets('ホーム ${entry.key} ($tag)', (tester) async {
          await _pumpShell(
            tester,
            brightness: brightness,
            locale: locale,
            overrides: [
              ...await placesBaseOverrides(
                savedCount: s.saved,
                locale: locale,
                current: s.current,
                city: city,
              ),
              ...entitlementOverrides(plus: s.plus),
              ...savedPlaceWeatherOverrides(modes: s.modes),
            ],
          );
          if (s.select != null) {
            _container(tester)
                .read(selectedPlaceIdProvider.notifier)
                .select(s.select);
            await settle(tester);
          }
          if (s.tapAdd) {
            // タブ列を終端までスクロールして「+」を押す (Figma E7)。
            await tester.drag(find.byType(PlaceTabBar), const Offset(-600, 0));
            await settle(tester);
            await tester.tap(find.byKey(kPlaceTabAddKey));
            await settle(tester);
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(goldenName(entry.key, brightness, locale)),
          );
        });
      }

      for (final entry in sheetStates.entries) {
        final s = entry.value;
        testWidgets('地点を追加 ${entry.key} ($tag)', (tester) async {
          final query = locale.languageCode == 'ja' ? s.ja : s.en;
          final kyoto = fixtureCandidate(
            kFixturePlaces[1],
            locale,
            admin1: locale.languageCode == 'ja' ? '京都府' : 'Kyoto',
          );
          await _pumpShell(
            tester,
            brightness: brightness,
            locale: locale,
            overrides: [
              ...await placesBaseOverrides(
                savedCount: 1,
                locale: locale,
                city: city,
              ),
              ...entitlementOverrides(plus: true),
              ...savedPlaceWeatherOverrides(),
              placeSearchOverride({
                if (query != null)
                  query: s.error
                      ? kPlaceNetworkError
                      : (query == 'きょうと' || query == 'kyouto')
                          ? const []
                          : [kyoto],
              }),
            ],
          );
          await tester.tap(find.byKey(kPlaceTabAddKey));
          await settle(tester);
          if (query != null) {
            await tester.enterText(find.byKey(kAddPlaceFieldKey), query);
            await settle(tester);
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(goldenName(entry.key, brightness, locale)),
          );
        });
      }

      for (final entry in locationStates.entries) {
        final s = entry.value;
        testWidgets('地点管理 ${entry.key} ($tag)', (tester) async {
          useGoldenViewport(tester);
          await tester.pumpWidget(goldenApp(
            home: const LocationsPage(),
            brightness: brightness,
            locale: locale,
            overrides: [
              ...await placesBaseOverrides(
                savedCount: s.saved,
                locale: locale,
                city: city,
              ),
              ...entitlementOverrides(plus: s.plus),
              currentLocationProvider.overrideWith(
                (ref) async => const GeoPoint(35.68, 139.77),
              ),
              savedPlaceMriOverride(),
            ],
          ));
          await settle(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(goldenName(entry.key, brightness, locale)),
          );
        });
      }
    }
  }
}
