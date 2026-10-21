// test/widget/settings_v13_test.dart
//
// v1.3「Quiet Instrument」で作り直した設定系 (S5) の回帰テスト。
//   - 設定 Top: Figma の 8 行 + 副題が出る
//   - 通知: 緊急通知の配信範囲の説明が **プラットフォームで分岐** する
//     (Android = FCM でアプリ終了時も届く / iOS = 利用中のみ)。
//     どちらも「必ず届く」と読める表現にしない。
//   - About MRI: 5 帯 1 表 + 注記 2 行。**帯ドットだけが状態色** (5 個 ≤ 上限 6)
//   - Privacy: 全面ニュートラル (状態色 0 個)
//   - Plus: 特典ドットは commerce/plus。状態色 0 個
//   - 文字倍率 2.0 で溢れない

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/data/datasources/location_datasource.dart';
import 'package:mood_ring_weather/presentation/settings/about_app_page.dart';
import 'package:mood_ring_weather/presentation/settings/about_mri_page.dart';
import 'package:mood_ring_weather/presentation/settings/general_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/locations_page.dart';
import 'package:mood_ring_weather/presentation/settings/notification_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/plus_settings_page.dart';
import 'package:mood_ring_weather/presentation/settings/privacy_page.dart';
import 'package:mood_ring_weather/presentation/settings/settings_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_tokens.dart';
import 'package:mood_ring_weather/providers/comfort_twin_provider.dart';
import 'package:mood_ring_weather/providers/weather_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/saved_places_fixtures.dart' show savedPlaceMriOverride;

Widget _app({
  required List<Override> overrides,
  required Widget home,
  TargetPlatform? platform,
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) {
  final theme = buildAppTheme(Brightness.dark, locale: locale);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      supportedLocales: supportedFlutterLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: platform == null ? theme : theme.copyWith(platform: platform),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<SharedPreferences> _mockPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void _useTallViewport(WidgetTester tester, {double height = 3600}) {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 状態色 (state/*) で塗られたドット / 数値の数を数える。
/// `codex-fixes_v1.3_unified.md` §4.1 規則 2: 1 画面 6 個まで。
int _countStateColored(WidgetTester tester, MrwTokens tokens) {
  final stateColors = <Color>{
    tokens.stateCold,
    tokens.stateCool,
    tokens.stateFresh,
    tokens.stateComfortable,
    tokens.stateWarm,
    tokens.stateHot,
    tokens.stateDanger,
  };
  var count = 0;
  for (final element in find.byType(Container).evaluate()) {
    final decoration = (element.widget as Container).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      if (stateColors.contains(decoration.color)) count++;
    }
  }
  for (final element in find.byType(Text).evaluate()) {
    final color = (element.widget as Text).style?.color;
    if (color != null && stateColors.contains(color)) count++;
  }
  return count;
}

void main() {
  const tokens = MrwTokens.dark;

  group('設定 Top', () {
    testWidgets('Figma の 8 行と副題がすべて出る', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const SettingsPage(),
      ));
      await tester.pumpAndSettle();

      for (final pair in const [
        ('General', 'Units, language, theme'),
        ('Notifications', 'Heatstroke, violent wind, heavy snow'),
        ('Calibration', 'Tune your comfort model'),
        ('Comfort-Twin', 'Find matching cities'),
        ('About MRI', 'How the score is calculated'),
        ('Locations', 'Current and saved places'),
        ('Privacy', 'On-device data and deletion'),
        ('About', 'Version, help, legal'),
      ]) {
        expect(find.text(pair.$1), findsOneWidget, reason: pair.$1);
        expect(find.text(pair.$2), findsOneWidget, reason: pair.$2);
      }
      // MRI 値を表示しない画面なので状態色は 0 個。
      expect(_countStateColored(tester, tokens), 0);
    });
  });

  group('通知: 緊急アラートの配信範囲の説明', () {
    testWidgets('Android はアプリ終了時も届く旨を出す', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const NotificationSettingsPage(),
        platform: TargetPlatform.android,
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('even when the app is closed'),
        findsOneWidget,
      );
      // 「必ず届く」と読める断定はしない (OS 都合の遅延に言及する)。
      expect(find.textContaining('may be delayed'), findsOneWidget);
      // iOS 向けの旧文言は出ない。
      expect(find.textContaining('while in use'), findsNothing);
    });

    testWidgets('iOS は利用中のみ判定・配信する旨を出す', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const NotificationSettingsPage(),
        platform: TargetPlatform.iOS,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('while in use'), findsOneWidget);
      expect(
        find.textContaining('even when the app is closed'),
        findsNothing,
      );
    });

    testWidgets('日本語でも同じ分岐になる', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const NotificationSettingsPage(),
        platform: TargetPlatform.android,
        locale: const Locale('ja'),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('アプリを閉じていても'), findsOneWidget);
      expect(find.textContaining('遅れる場合があります'), findsOneWidget);
      expect(find.textContaining('アプリの利用中に'), findsNothing);
    });
  });

  group('About MRI', () {
    testWidgets('5 帯 1 表 + 注記 2 行、状態色は帯ドット 5 個だけ', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const AboutMriPage(),
      ));
      await tester.pumpAndSettle();

      // 5 帯 (降順)。FRESH / COLD の行は存在しない。
      for (final range in const ['80–100', '60–79', '40–59', '20–39', '0–19']) {
        expect(find.text(range), findsOneWidget, reason: range);
      }
      expect(find.text('FRESH'), findsNothing);
      expect(find.text('COLD'), findsNothing);

      // 注記 2 行 (§7.1)
      expect(find.textContaining('“Optimal”'), findsOneWidget);
      expect(find.textContaining('(WBGT)'), findsOneWidget);

      // 状態色は帯ドットの 5 個のみ (上限 6 以内)。
      expect(_countStateColored(tester, tokens), 5);
    });
  });

  group('地点管理', () {
    testWidgets('状態色は保存地点の MRI 値だけ。上限 6 を超えると帯ドットに縮む', (tester) async {
      Future<void> pumpWith(WidgetTester tester, int places) async {
        _useTallViewport(tester, height: 6000);
        final prefs = await _mockPrefs({
          kPrefKeyComfortRecords: jsonEncode([
            for (var i = 0; i < places; i++)
              {
                'id': 'place-$i',
                'type': 'place',
                'mri': 60 + i,
                'savedAt': '2026-06-0${(i % 9) + 1}T10:00:00.000',
                'label': 'City $i',
              },
          ]),
        });
        await tester.pumpWidget(_app(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentLocationProvider
                .overrideWith((ref) async => const GeoPoint(35.68, 139.76)),
            cityNameProvider.overrideWith((ref) async => 'Tokyo'),
            // 行の MRI は保存地点の現在値 (実通信しないよう固定)。
            savedPlaceMriOverride(values: {
              for (var i = 0; i < places; i++) 'place-$i': 60 + i,
            }),
          ],
          home: const LocationsPage(),
        ));
        await tester.pumpAndSettle();
      }

      // 5 件 (Plus の上限) → 値そのものが帯色 = 5 個 ≤ 6。
      await pumpWith(tester, 5);
      expect(_countStateColored(tester, tokens), 5);

      // 8 件 (grandfathering) → §4.1 規則 2 で行頭の帯ドットだけに縮小する。
      // 数える対象はドット 8 個のみ (数値は主文字色に戻る)。
      await pumpWith(tester, 8);
      expect(_countStateColored(tester, tokens), 8);
      expect(
        find.byWidgetPredicate((w) =>
            w is Text && w.data == 'MRI 60' && w.style?.color == tokens.textHi),
        findsOneWidget,
      );
    });
  });

  group('Privacy', () {
    testWidgets('全面ニュートラル (状態色 0 個)', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const PrivacyPage(),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byType(QuietDotCard), findsNWidgets(5)); // 4 枚 + 「データを削除」(決裁 D3)
      expect(_countStateColored(tester, tokens), 0);
    });
  });

  group('Plus 設定', () {
    testWidgets('特典ドットは commerce/plus、状態色は 0 個', (tester) async {
      _useTallViewport(tester);
      final prefs = await _mockPrefs();
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const PlusSettingsPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('CURRENT PLAN'), findsOneWidget);
      // v1.3.0 の特典は多地点のみ (決裁 D7。先行アラート / ピンポイント補正は配信側未実装)。
      expect(find.byType(QuietDotCard), findsNWidgets(1));
      expect(_countStateColored(tester, tokens), 0);

      // 主 CTA は 1 つだけ (action/primary は 1 画面 1 つ。§2.3)。
      expect(find.byType(QuietPrimaryButton), findsOneWidget);

      // 特典ドットが commerce/plus であること。
      final dots = tester
          .widgetList<QuietDotCard>(find.byType(QuietDotCard))
          .map((c) => c.dotColor)
          .toSet();
      expect(dots, {tokens.plusBase});
    });
  });

  group('文字倍率 2.0', () {
    // ja (和文の行折り) と es (ラテン系で最長) の両方を見る。
    for (final locale in const [Locale('ja'), Locale('es')]) {
      for (final entry in <(String, Widget)>[
        ('設定 Top', const SettingsPage()),
        ('一般', const GeneralSettingsPage()),
        ('通知', const NotificationSettingsPage()),
        ('地点', const LocationsPage()),
        ('About MRI', const AboutMriPage()),
        ('About App', const AboutAppPage()),
        ('Privacy', const PrivacyPage()),
        ('Plus', const PlusSettingsPage()),
      ]) {
        testWidgets('${entry.$1}: 溢れない (${locale.languageCode})',
            (tester) async {
          // 390 幅 (Figma と同寸) のまま縦だけ伸ばし、横方向の溢れを検出する。
          // レイアウト溢れが 1 つでもあれば flutter_test が例外を積む。
          tester.view.physicalSize = const Size(390, 8000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final prefs = await _mockPrefs();
          await tester.pumpWidget(_app(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              currentLocationProvider
                  .overrideWith((ref) async => const GeoPoint(35.68, 139.76)),
              cityNameProvider.overrideWith((ref) async => 'Tokyo'),
            ],
            home: entry.$2,
            textScale: 2.0,
            locale: locale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
