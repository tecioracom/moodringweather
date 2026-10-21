// test/widget/plus_gating_test.dart
//
// Plus ゲーティングと Paywall コンプラ要件のスモークテスト:
//   - Paywall は固定免責文 (緊急通知は全員無料) を常時表示する (spec §12.11.7)
//   - 鍵未設定 (DisabledBillingGateway) では「準備中」表示
//   - 通知設定: v1.3.0 は Plus セクション (先行アラート / ピンポイント補正) を
//     出さない (決裁 D7。配信側が未実装)

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/locale/locale_controller.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/settings/notification_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({required List<Override> overrides, required Widget home}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<SharedPreferences> _mockPrefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('Paywall: 固定免責文と準備中表示 (鍵未設定)', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _mockPrefs();
    await tester.pumpWidget(_app(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      home: const PaywallPage(),
    ));
    await tester.pumpAndSettle();

    // 緊急通知は全員無料の固定免責文 (常時表示・コンプラ必須)
    expect(find.textContaining('stay free for everyone'), findsOneWidget);
    // 鍵未設定 → Offering 無し → 準備中
    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  // 決裁 D7 (2026-09-19): 先行アラート / ピンポイント補正は配信側が未実装のため、
  // v1.3.0 では通知設定に Plus セクションを出さない (無料でも Plus でも)。
  for (final (label, initial) in [
    ('無料', const <String, Object>{}),
    ('デバッグPlus', const <String, Object>{'debug_plus_tier': 'plus'}),
  ]) {
    testWidgets('通知設定($label): 未実装の Plus 特典 (先行アラート / ピンポイント補正) を出さない',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await _mockPrefs(initial);
      await tester.pumpWidget(_app(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        home: const NotificationSettingsPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Earlier alerts'), findsNothing);
      expect(find.text('Pinpoint tuning'), findsNothing);
      expect(find.text('Plus features'), findsNothing);
      // Plus バッジも無い (ロックする対象が無い)。
      expect(find.text('Plus'), findsNothing);
    });
  }
}
