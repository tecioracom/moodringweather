// lib/main.dart
//
// i18n を成立させるための最小エントリ (spec.md §21)。
//   - OS 言語に追従しつつ、言語セレクタの選択を優先
//   - AppLocalizations を MaterialApp に接続
// 画面の本実装 (Home/Detail/Calibration/Settings の全要素) は別タスクで積み増す。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/billing/billing_initializer.dart';
import 'data/models/mood_ring_index.dart';
import 'data/push/firebase_push_runtime.dart';
import 'l10n/app_localizations.dart';
import 'presentation/locale/locale_controller.dart';
import 'presentation/shell/main_shell.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/font_licenses.dart';
import 'presentation/wallpaper/wallpaper_overlay_host.dart';
import 'providers/emergency_alert_provider.dart';
import 'providers/entitlement_provider.dart';
import 'providers/mri_provider.dart';
import 'providers/place_selection_provider.dart';
import 'providers/push_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/wallpaper_provider.dart';
import 'providers/weather_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 同梱フォント (OFL) のライセンス本文をアプリ内ライセンス画面へ登録。
  registerBundledFontLicenses();
  // 課金基盤 (RevenueCat + Firebase Anonymous Auth) を起動時に 1 回初期化。
  // 鍵未設定 / Firebase 失敗でも内部で握りつぶし、必ず BillingRuntime を返す
  // (課金無効モードで通常起動する。billing_initializer.dart 参照)。
  final billingRuntime = await initBilling();
  // 緊急プッシュ (FCM) の基盤。Firebase 不在 / Anonymous Auth 無効 / 対象外 OS では
  // disabled になり、ローカル通知経路 (現在値) はそのまま動く (計画 S8 / S10)。
  final pushRuntime = await initPushRuntime();
  registerPushBackgroundHandler(pushRuntime);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        billingRuntimeProvider.overrideWithValue(billingRuntime),
        pushRuntimeProvider.overrideWithValue(pushRuntime),
      ],
      child: const MoodRingApp(),
    ),
  );
}

class MoodRingApp extends ConsumerStatefulWidget {
  const MoodRingApp({super.key});
  @override
  ConsumerState<MoodRingApp> createState() => _MoodRingAppState();
}

class _MoodRingAppState extends ConsumerState<MoodRingApp>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<MoodRingIndex>>? _wallpaperSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Android のライブ壁紙へ現在地の MRI を渡す (値が確定するたび。失敗は無視)。
    // 保存地点の表示を切り替えても壁紙は現在地のまま (mriProvider は現在地専用)。
    _wallpaperSub = ref.listenManual<AsyncValue<MoodRingIndex>>(
      mriProvider,
      (_, next) =>
          ref.read(wallpaperMriSyncProvider).onMri(next.valueOrNull?.value),
      fireImmediately: true,
    );
    // 緊急通知 (熱中症/暴風/大雪) のローカル通知初期化 + 権限リクエスト
    // (iOS alert/badge/sound、Android 13+ POST_NOTIFICATIONS)。
    // 拒否・失敗してもアプリ本体は通常動作する (通知が出ないだけ)。
    // 初回起動は位置情報の許可を先に聞く (体感を出すのが先)。現在地の取得
    // (許可ダイアログへの回答を含む) が終わってから通知の許可を求める。
    // 同時に要求すると後の要求が Android に取り消され、位置情報のダイアログが
    // 出ないまま現在地の取得が止まっていた (permission_request_queue.dart)。
    Future<void>(() async {
      try {
        await ref.read(currentLocationProvider.future);
      } catch (_) {
        // 現在地の失敗は既定地点で表示する。通知の初期化は続ける。
      }
      await ref.read(notificationGatewayProvider).initialize();
    }).catchError((_) {});
    // FCM 前景受信 → onPushData、トークン更新 → 購読再登録 (Firebase 不在なら no-op)。
    try {
      ref.read(pushSubscriptionCoordinatorProvider).start();
    } catch (_) {}
  }

  @override
  void dispose() {
    _wallpaperSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// OS の言語設定がアプリ起動中に変わったら再解決 (端末追従中のみ)。
  /// 地域が変わったときに備えて、単位の初期値の地域も読み直す (保存済みの
  /// 単位はそのまま。まだ選んでいない人の初期値だけが変わる)。
  @override
  void didChangeLocales(List<Locale>? locales) {
    ref.read(localeControllerProvider.notifier).onSystemLocalesChanged();
    ref.invalidate(unitRegionProvider);
  }

  /// 保存地点を表示中にバックグラウンドへ 30 分以上いたら、戻ったとき現在地の
  /// 表示へ戻す (保存地点の出荷条件 G3。place_selection_provider.dart)。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      ref.read(selectedPlaceIdProvider.notifier).onAppLifecycleChanged(state);
    } catch (_) {
      // 表示の切り替えは付帯機能。ライフサイクル処理を巻き込まない。
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    // 設定 > 一般のテーマ選択 (system/light/dark) を実反映する。
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      locale: locale,
      supportedLocales: supportedFlutterLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // テーマは presentation/theme/app_theme.dart (ゴールデンテストと共用)。
      theme: buildAppTheme(Brightness.light, locale: locale),
      darkTheme: buildAppTheme(Brightness.dark, locale: locale),
      themeMode: themeMode,
      // ホーム / 詳細 / 設定 をタブで束ねるシェル (Figma v1.0 準拠)。
      home: const MainShell(),
      // Android のライブ壁紙の重ね描き (天気・気温・区分名 · 時刻) を最新に保つ。
      // 言語・12/24 時間制・文字の倍率を読むため、Localizations と MediaQuery の下に置く。
      builder: (context, child) =>
          WallpaperOverlayHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
