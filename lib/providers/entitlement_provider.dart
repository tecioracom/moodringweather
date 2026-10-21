// lib/providers/entitlement_provider.dart
//
// 課金エンタイトルメントの状態管理 (settings_provider.dart と同じ
// StateNotifier 流儀)。UI/ドメインはこの provider 群のみを参照する。
//
// 合議 (docs/revenuecat-integration-plan.md §3.6):
//   RevenueCat SDK ローカル (entitlementChanges/fetch) と Firestore
//   (Webhook 反映) の 2 系統を updatedAt で比較し**新しい方を採用**。
//   Firebase 未初期化なら RC 単独で動く。
//
// デバッグ上書き (kDebugMode 限定):
//   実購入なしで Plus ゲートを検証するための QA トグル。リリースビルドでは
//   kReleaseMode ガードにより常に無視される。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/billing/billing_gateway.dart';
import '../data/billing/billing_initializer.dart';
import '../data/models/entitlement.dart';
import '../presentation/locale/locale_controller.dart'
    show sharedPreferencesProvider;

/// main() で実ランタイムに override する。既定 (テスト) は課金無効。
final billingRuntimeProvider =
    Provider<BillingRuntime>((ref) => BillingRuntime.disabled);

/// 課金ゲートウェイ (Paywall/設定が purchase/restore に使う)。
final billingGatewayProvider = Provider<BillingGateway>(
    (ref) => ref.watch(billingRuntimeProvider).gateway);

/// 現在のエンタイトルメント (正本)。
final entitlementProvider =
    StateNotifierProvider<EntitlementController, EntitlementState>((ref) {
  final controller = EntitlementController(
    runtime: ref.watch(billingRuntimeProvider),
    initialDebugTier: ref.read(debugPlusTierProvider),
  );
  // QA デバッグトグルの変更を反映 (kDebugMode のみ実効)。
  ref.listen<EntitlementTier?>(
    debugPlusTierProvider,
    (_, next) => controller.setDebugTier(next),
  );
  return controller;
});

/// Plus 以上を保有しているか (機能ゲートの主判定)。
final isPlusProvider =
    Provider<bool>((ref) => ref.watch(entitlementProvider).hasPlus);

/// 指定 Plus 機能が使えるか。
final plusFeatureProvider = Provider.family<bool, PlusFeature>(
    (ref, feature) => ref.watch(entitlementProvider).can(feature));

/// 保存地点の上限 (無料 0 = Plus 限定 / Plus 5)。
final savedLocationLimitProvider =
    Provider<int>((ref) => ref.watch(entitlementProvider).savedLocationLimit);

/// RC SDK と Firestore の 2 系統を updatedAt で合議 (§3.6)。
/// 新しい方を採用。null は「情報なし」として劣後。テスト容易性のため公開。
EntitlementState mergeEntitlementsByUpdatedAt(
  EntitlementState? a,
  EntitlementState? b,
) {
  if (a == null) return b ?? EntitlementState.free;
  if (b == null) return a;
  final at = a.updatedAt;
  final bt = b.updatedAt;
  if (at == null) return b;
  if (bt == null) return a;
  return bt.isAfter(at) ? b : a;
}

class EntitlementController extends StateNotifier<EntitlementState> {
  EntitlementController({
    required BillingRuntime runtime,
    EntitlementTier? initialDebugTier,
  })  : _runtime = runtime,
        _debugTier = initialDebugTier,
        super(EntitlementState.free) {
    _init();
  }

  final BillingRuntime _runtime;
  EntitlementTier? _debugTier;

  EntitlementState? _rcState;
  EntitlementState? _fsState;

  StreamSubscription<EntitlementState>? _rcSub;
  StreamSubscription<EntitlementState>? _fsSub;

  void _init() {
    final gateway = _runtime.gateway;

    // RC: リアルタイム更新 + 初回フェッチ。
    _rcSub = gateway.entitlementChanges().listen((e) {
      _rcState = e;
      _recompute();
    });
    unawaited(_fetchRc(gateway));

    // Firestore: Webhook 反映分 (Firebase 利用可能時のみ)。
    final src = _runtime.firestoreSource;
    final uid = _runtime.uid;
    if (_runtime.firebaseAvailable && src != null && uid != null) {
      _fsSub = src.watch(uid).listen((e) {
        _fsState = e;
        _recompute();
      });
    }

    _recompute();
  }

  Future<void> _fetchRc(BillingGateway gateway) async {
    try {
      final e = await gateway.fetchEntitlement();
      _rcState = e;
      _recompute();
    } catch (_) {
      // 取得失敗時は既存状態を維持 (free のまま)。
    }
  }

  /// 明示的な再取得 (購入/復元直後に UI から呼ぶ)。
  Future<void> refresh() => _fetchRc(_runtime.gateway);

  /// QA デバッグトグル (kDebugMode のみ実効)。
  void setDebugTier(EntitlementTier? tier) {
    _debugTier = tier;
    _recompute();
  }

  void _recompute() {
    final debugTier = _debugTier;
    if (kDebugMode && debugTier != null && debugTier != EntitlementTier.free) {
      state = _debugState(debugTier);
      return;
    }
    state = mergeEntitlementsByUpdatedAt(_rcState, _fsState);
  }

  static EntitlementState _debugState(EntitlementTier tier) => EntitlementState(
        tier: tier,
        activeEntitlements: <String>{
          for (final t in EntitlementTier.values)
            if (t != EntitlementTier.free && t.rank <= tier.rank) t.name,
        },
        willRenew: true,
        updatedAt: DateTime.now(),
        source: EntitlementSource.debugOverride,
      );

  @override
  void dispose() {
    _rcSub?.cancel();
    _fsSub?.cancel();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────────
// デバッグ上書きトグル (kDebugMode 限定。永続化して再起動でも保持)
// ──────────────────────────────────────────────────────────────────

const String kPrefKeyDebugPlusTier = 'debug_plus_tier';

class DebugPlusTierController extends StateNotifier<EntitlementTier?> {
  DebugPlusTierController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  Future<void> select(EntitlementTier? tier) async {
    state = tier;
    if (tier == null || tier == EntitlementTier.free) {
      await _prefs.remove(kPrefKeyDebugPlusTier);
    } else {
      await _prefs.setString(kPrefKeyDebugPlusTier, tier.name);
    }
  }

  static EntitlementTier? _load(SharedPreferences prefs) {
    if (!kDebugMode) return null;
    final raw = prefs.getString(kPrefKeyDebugPlusTier);
    if (raw == null) return null;
    final tier = EntitlementTier.parse(raw);
    return tier == EntitlementTier.free ? null : tier;
  }
}

final debugPlusTierProvider =
    StateNotifierProvider<DebugPlusTierController, EntitlementTier?>(
        (ref) => DebugPlusTierController(ref.watch(sharedPreferencesProvider)));
