// test/widget/paywall_page_test.dart
//
// Paywall の製品版前の必須事項 (docs/release-plan-billing.md §5 Step 8 #3〜#6)。
//   - 自動更新の開示が CTA 直上に常時表示される (トライアル有無を問わない)
//   - 既定選択は月額
//   - 免責文は特典リストより前 (ヘッドライン直下)
//   - Android では独自規約が未公開の間、規約行 (Apple 標準 EULA) を出さない
//   - 「あとで」で閉じられる

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_ring_weather/core/constants/app_links.dart';
import 'package:mood_ring_weather/data/billing/billing_gateway.dart';
import 'package:mood_ring_weather/data/billing/billing_models.dart';
import 'package:mood_ring_weather/data/models/entitlement.dart';
import 'package:mood_ring_weather/l10n/app_localizations.dart';
import 'package:mood_ring_weather/presentation/paywall/paywall_page.dart';
import 'package:mood_ring_weather/presentation/shared/quiet_controls.dart';
import 'package:mood_ring_weather/presentation/theme/app_theme.dart';
import 'package:mood_ring_weather/presentation/theme/mrw_type.dart';
import 'package:mood_ring_weather/providers/entitlement_provider.dart';

import '../golden/golden_harness.dart';

class _FakeGateway implements BillingGateway {
  _FakeGateway(this.packages);
  final List<PlusPackage> packages;
  final _controller = StreamController<EntitlementState>.broadcast();

  @override
  Future<void> configure({String? appUserId}) async {}
  @override
  Stream<EntitlementState> entitlementChanges() => _controller.stream;
  @override
  Future<EntitlementState> fetchEntitlement() async => EntitlementState.free;
  @override
  Future<List<PlusPackage>> fetchPackages() async => packages;
  @override
  Future<PurchaseResult> purchase(String packageId) async =>
      const PurchaseResult(PurchaseStatus.cancelled);
  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult(PurchaseStatus.error);
  @override
  Future<bool> openManageSubscriptions() async => true;
  @override
  Future<void> dispose() async => _controller.close();
}

const _monthly = PlusPackage(
  packageId: r'$rc_monthly',
  period: PlusBillingPeriod.monthly,
  priceString: '¥600',
  productIdentifier: 'mrw.plus.monthly',
  hasIntroOffer: true,
);
const _annual = PlusPackage(
  packageId: r'$rc_annual',
  period: PlusBillingPeriod.annual,
  priceString: '¥3,000',
  productIdentifier: 'mrw.plus.yearly',
  hasIntroOffer: true,
);

Future<void> _pump(
  WidgetTester tester, {
  List<PlusPackage> packages = const [_annual, _monthly],
  TargetPlatform platform = TargetPlatform.android,
  double width = 390,
  double height = 1400,
  double textScale = 1.0,
  Locale locale = const Locale('en'),
  FakeViewPadding? safeArea,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (safeArea != null) {
    tester.view.padding = safeArea;
    tester.view.viewPadding = safeArea;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      billingGatewayProvider.overrideWithValue(_FakeGateway(packages)),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ja'),
        Locale('es'),
        Locale('zh')
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.dark, locale: locale)
          .copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showPaywall(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// CTA の見た目の塗り (ボタン内の Material)。
Finder _ctaFill(AppLocalizations t) => find
    .ancestor(of: find.text(t.paywallStartCta), matching: find.byType(Material))
    .first;

void main() {
  // 同梱書体で描画する (既定の Ahem だと文字幅が実際より広く、幅の検証にならない)。
  setUpAll(loadAppFonts);

  testWidgets('自動更新の開示が常時表示され、CTA の直上にある', (tester) async {
    await _pump(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    final notice = find.text(t.paywallAutoRenewNotice);
    expect(notice, findsOneWidget);
    final cta = find.text(t.paywallStartCta);
    expect(cta, findsOneWidget);
    expect(tester.getRect(notice).bottom,
        lessThanOrEqualTo(tester.getRect(cta).top));
  });

  testWidgets('トライアル無しでも自動更新の開示は出る', (tester) async {
    await _pump(tester, packages: const [
      PlusPackage(
        packageId: r'$rc_monthly',
        period: PlusBillingPeriod.monthly,
        priceString: '¥600',
        productIdentifier: 'mrw.plus.monthly',
      ),
    ]);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    expect(find.text(t.paywallTrialNote), findsNothing);
    expect(find.text(t.paywallAutoRenewNotice), findsOneWidget);
  });

  testWidgets('トライアル注記は選択中のプランにオファーがあるときだけ', (tester) async {
    // 年額だけにオファーが付いた構成。既定選択は月額なので注記は出ない。
    await _pump(tester, packages: const [
      _annual,
      PlusPackage(
        packageId: r'$rc_monthly',
        period: PlusBillingPeriod.monthly,
        priceString: '¥600',
        productIdentifier: 'mrw.plus.monthly',
      ),
    ]);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    expect(find.text(t.paywallTrialNote), findsNothing);
    // 年額を選ぶと出る。
    await tester.tap(find.text(t.paywallPeriodAnnual));
    await tester.pumpAndSettle();
    expect(find.text(t.paywallTrialNote), findsOneWidget);
    // 文言に期間を固定で書かない (ストア表示に委ねる)。
    expect(t.paywallTrialNote, isNot(contains('7')));
  });

  testWidgets('既定選択は月額 (年額が先に並んでいても)', (tester) async {
    await _pump(tester, packages: const [_annual, _monthly]);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    final checked = find.byIcon(Icons.radio_button_checked);
    expect(checked, findsOneWidget);
    final monthlyLabel = find.text(t.paywallPeriodMonthly);
    // 選択中のラジオと「Monthly」が同じカード (InkWell) の中にある。
    final card =
        find.ancestor(of: monthlyLabel, matching: find.byType(InkWell));
    expect(find.descendant(of: card, matching: checked), findsOneWidget);
  });

  testWidgets('免責文は特典リストより前にある', (tester) async {
    await _pump(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    final disclaimer = tester.getRect(find.text(t.paywallSafetyDisclaimer));
    final feature = tester.getRect(find.text(t.plusFeatureMultiLocationTitle));
    expect(disclaimer.bottom, lessThanOrEqualTo(feature.top));
  });

  testWidgets('規約 URL は公開済みの HTTPS 恒久 URL (2026-09-27 公開)', (tester) async {
    expect(AppLinks.termsOfUseUrl, startsWith('https://'),
        reason: 'App Store 3.1.2 / Play の定期購入要件: 規約リンクを paywall に出す');
  });

  testWidgets('Android: 独自規約が公開済みなので規約行とプライバシー行を出す', (tester) async {
    await _pump(tester, platform: TargetPlatform.android);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    expect(find.text(t.paywallTerms), findsOneWidget);
    expect(find.text(t.paywallPrivacy), findsOneWidget);
  });

  testWidgets('iOS: 独自規約を出す (Apple 標準 EULA フォールバックは使わない)', (tester) async {
    await _pump(tester, platform: TargetPlatform.iOS);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    expect(find.text(t.paywallTerms), findsOneWidget);
  });

  testWidgets('幅 320dp × 文字倍率 1.3 でも溢れず、CTA までスクロールして押せる', (tester) async {
    // 4 言語で最長の es (自動更新の開示が 333 字) で確認する。
    await _pump(tester, width: 320, textScale: 1.3, locale: const Locale('es'));
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    await tester.scrollUntilVisible(find.text(t.paywallStartCta), 200);
    expect(find.text(t.paywallStartCta), findsOneWidget);
    expect(find.text(t.paywallAutoRenewNotice), findsOneWidget);
  });

  group('初期表示で CTA が見える (390×844・safe area 上 47 / 下 34・×1.0)', () {
    // 案2 の縦の詰め (designer 2026-09-29) の受け入れ条件: スクロールせずに
    // CTA 全体が見え、表示域 (ListView) の下端まで 16px 以上空く (EN / JA)。
    // es は開示文が長く届かないことがあるので計測値だけ出す。
    const safeArea = FakeViewPadding(top: 47, bottom: 34);

    Future<({Rect cta, Rect viewport})> measure(
      WidgetTester tester,
      Locale locale,
    ) async {
      await _pump(tester, locale: locale, height: 844, safeArea: safeArea);
      final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
      // 見た目のボタン (塗りの Material)。FilledButton の箱はタップ領域の余白込みで 48。
      final cta = tester.getRect(_ctaFill(t));
      final viewport = tester.getRect(find
          .descendant(
            of: find.byType(PaywallPage),
            matching: find.byType(Scrollable),
          )
          .first);
      final headline = tester.getRect(find.text(t.paywallHeadline));
      // ignore: avoid_print
      print('PAYWALL_FOLD|${locale.languageCode}'
          '|cta=${cta.top.toStringAsFixed(1)}-${cta.bottom.toStringAsFixed(1)}'
          '|viewport=${viewport.top.toStringAsFixed(1)}'
          '-${viewport.bottom.toStringAsFixed(1)}'
          '|margin=${(viewport.bottom - cta.bottom).toStringAsFixed(1)}'
          '|headline=${headline.top.toStringAsFixed(1)}'
          '|${t.paywallHeadline}');
      return (cta: cta, viewport: viewport);
    }

    for (final locale in const [Locale('en'), Locale('ja')]) {
      testWidgets('${locale.languageCode}: CTA 全体が見え、下端まで 16px 以上',
          (tester) async {
        final m = await measure(tester, locale);
        expect(m.cta.top, greaterThanOrEqualTo(m.viewport.top));
        expect(m.viewport.bottom - m.cta.bottom, greaterThanOrEqualTo(16));
      });
    }

    testWidgets('es: 計測だけ (合否なし)', (tester) async {
      final m = await measure(tester, const Locale('es'));
      expect(m.cta.height, 46);
    });
  });

  testWidgets('CTA は Quiet の主ボタン (本文書体・高さ 46)', (tester) async {
    await _pump(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    final cta = find.ancestor(
      of: find.text(t.paywallStartCta),
      matching: find.byType(QuietPrimaryButton),
    );
    expect(cta, findsOneWidget);
    expect(tester.getSize(_ctaFill(t)).height, 46);
    // ボタン文字は quietButtonTextStyle (サイズは型スケールの body)。
    expect(
      DefaultTextStyle.of(tester.element(find.text(t.paywallStartCta)))
          .style
          .fontSize,
      MrwType.forScale(MrwTypeScale.fromEnvironment).body.fontSize(13),
    );
  });

  testWidgets('年額の BEST VALUE は Quiet のバッジ (大文字)', (tester) async {
    await _pump(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    final badge = find.byType(QuietBadge);
    expect(badge, findsOneWidget);
    expect(tester.widget<QuietBadge>(badge).label,
        t.paywallBestValue.toUpperCase());
  });

  testWidgets('「あとで」で閉じられる', (tester) async {
    await _pump(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PaywallPage)));
    await tester.tap(find.text(t.paywallNotNow));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallPage), findsNothing);
  });
}
