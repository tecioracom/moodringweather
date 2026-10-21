// lib/data/models/entitlement.dart
//
// 課金エンタイトルメントのドメインモデル (docs/pricing-decision.md /
// docs/revenuecat-integration-plan.md §2.4)。
//
// 設計方針 (notification_preferences.dart と同じ「依存ゼロの素の Dart」):
//   - RevenueCat SDK (purchases_flutter) や Firestore に**一切依存しない**。
//     SDK / Firestore の生データはデータ層 (lib/data/billing) で本モデルへ
//     正規化し、UI・ドメインはこのモデルのみを参照する。
//   - これにより flutter test (host VM) で課金状態を自由に構築できる。
//
// 重要 (spec.md §12.2.1 / §12.11.1):
//   緊急安全通知 (熱中症 WBGT / 暴風 / 大雪) は**課金状態に無関係に永久無料**。
//   本モデルが free を返しても緊急通知の配信判定には一切影響しない
//   (緊急通知は別系統。emergency_alert_provider / Workers emergency-notifier)。

/// 課金ティア。包含関係は pro > plus > free
/// (revenuecat-integration-plan.md §2.4「継承ルール」)。
enum EntitlementTier {
  free,
  plus,
  pro;

  /// 包含順位 (大きいほど上位)。Plus 機能の解放判定に使う。
  int get rank => switch (this) {
        EntitlementTier.free => 0,
        EntitlementTier.plus => 1,
        EntitlementTier.pro => 2,
      };

  /// RevenueCat / Firestore の tier 文字列からの復元 (未知値は free)。
  static EntitlementTier parse(Object? raw) {
    if (raw is String) {
      for (final t in EntitlementTier.values) {
        if (t.name == raw) return t;
      }
    }
    return EntitlementTier.free;
  }
}

/// Plus レイヤの機能 (spec.md §12.11.2)。
/// v1.1 採用は 3 種。経路アラート等は保留 (§12.11.2 表)。
enum PlusFeature {
  /// 多地点監視 (§12.11.5)。無料=現在地のみ (保存地点 0), Plus=保存地点 最大5。
  /// クライアント実装可能。
  multiLocation,

  /// リードタイム延長 (§12.11.3)。Workers Cron 高頻度化が前提 (バックエンド依存)。
  leadTime,

  /// ピンポイント補正 (§12.11.4)。Workers 補正テーブルが前提 (バックエンド依存)。
  pinpoint,
}

/// 課金状態のスナップショット。単一の正本 (single source of truth)。
///
/// RevenueCat SDK ローカル (`Purchases.getCustomerInfo`) と
/// Firestore (Webhook 反映) の二系統を `updatedAt` で合議した結果を保持する
/// (revenuecat-integration-plan.md §3.6)。
class EntitlementState {
  final EntitlementTier tier;

  /// RevenueCat の active entitlement 識別子集合 (例: {'plus'})。
  final Set<String> activeEntitlements;

  /// 失効時刻 (期限切れ判定用。null は無期限/未設定)。
  final DateTime? expiresAt;

  /// 次回自動更新の有無 (CANCELLATION で false)。
  final bool willRenew;

  /// 支払い猶予期間中か (BILLING_ISSUE)。期間中は機能維持＋警告バナー。
  final bool isInGracePeriod;

  /// 購入ストア ('app_store' / 'play_store' / null)。
  final String? store;

  /// この状態の更新時刻 (二系統合議のキー)。
  final DateTime? updatedAt;

  /// 由来 (デバッグ/監視用)。
  final EntitlementSource source;

  const EntitlementState({
    this.tier = EntitlementTier.free,
    this.activeEntitlements = const {},
    this.expiresAt,
    this.willRenew = false,
    this.isInGracePeriod = false,
    this.store,
    this.updatedAt,
    this.source = EntitlementSource.none,
  });

  /// 無料 (未購入) の既定状態。
  static const EntitlementState free = EntitlementState();

  /// Plus 以上を保有しているか (Plus 機能解放の主判定)。
  bool get hasPlus => tier.rank >= EntitlementTier.plus.rank;

  bool get hasPro => tier.rank >= EntitlementTier.pro.rank;

  /// 指定の Plus 機能を使えるか。現状 3 機能はすべて Plus 解放
  /// (上位ティアは継承)。将来 Pro 限定機能が出たらここで分岐する。
  bool can(PlusFeature feature) => hasPlus;

  /// 保存できる地点数の上限 (§12.11.5: 無料=0 / Plus=5)。
  int get savedLocationLimit =>
      hasPlus ? kPlusSavedLocationLimit : kFreeSavedLocationLimit;

  EntitlementState copyWith({
    EntitlementTier? tier,
    Set<String>? activeEntitlements,
    DateTime? expiresAt,
    bool? willRenew,
    bool? isInGracePeriod,
    String? store,
    DateTime? updatedAt,
    EntitlementSource? source,
  }) =>
      EntitlementState(
        tier: tier ?? this.tier,
        activeEntitlements: activeEntitlements ?? this.activeEntitlements,
        expiresAt: expiresAt ?? this.expiresAt,
        willRenew: willRenew ?? this.willRenew,
        isInGracePeriod: isInGracePeriod ?? this.isInGracePeriod,
        store: store ?? this.store,
        updatedAt: updatedAt ?? this.updatedAt,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'activeEntitlements': activeEntitlements.toList(),
        'expiresAt': expiresAt?.toIso8601String(),
        'willRenew': willRenew,
        'isInGracePeriod': isInGracePeriod,
        'store': store,
        'updatedAt': updatedAt?.toIso8601String(),
        'source': source.name,
      };

  factory EntitlementState.fromJson(Map<String, dynamic> json) =>
      EntitlementState(
        tier: EntitlementTier.parse(json['tier']),
        activeEntitlements: <String>{
          for (final e in (json['activeEntitlements'] as List? ?? const []))
            if (e is String) e,
        },
        expiresAt: _parseDate(json['expiresAt']),
        willRenew: json['willRenew'] as bool? ?? false,
        isInGracePeriod: json['isInGracePeriod'] as bool? ?? false,
        store: json['store'] as String?,
        updatedAt: _parseDate(json['updatedAt']),
        source: _parseSource(json['source']),
      );

  static DateTime? _parseDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static EntitlementSource _parseSource(Object? raw) {
    if (raw is String) {
      for (final s in EntitlementSource.values) {
        if (s.name == raw) return s;
      }
    }
    return EntitlementSource.none;
  }

  @override
  bool operator ==(Object other) =>
      other is EntitlementState &&
      other.tier == tier &&
      _setEquals(other.activeEntitlements, activeEntitlements) &&
      other.expiresAt == expiresAt &&
      other.willRenew == willRenew &&
      other.isInGracePeriod == isInGracePeriod &&
      other.store == store &&
      other.updatedAt == updatedAt &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
        tier,
        Object.hashAllUnordered(activeEntitlements),
        expiresAt,
        willRenew,
        isInGracePeriod,
        store,
        updatedAt,
        source,
      );

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

/// エンタイトルメントの由来。二系統合議 (§3.6) のどちらを採用したか。
enum EntitlementSource {
  /// まだ確定していない (初期化前/キー未設定/課金無効)。
  none,

  /// RevenueCat SDK ローカルキャッシュ (`getCustomerInfo`)。
  revenueCat,

  /// Firestore (Webhook 反映)。
  firestore,

  /// 開発用デバッグ上書き (kDebugMode 限定)。
  debugOverride,
}

/// 地点保存上限 (spec.md §12.11.5)。
///
/// 保存地点は Plus 限定 (無料は現在地のみ = 0 件。2026-09-30 ユーザー決裁、
/// 1.3.0 (12) から。それまでは無料 1 件)。上限は**新規追加**だけを止める:
/// 無料で既に保存している地点 (Plus 解約後・無料 1 件の時期に保存したもの) は
/// 消さない (grandfathering。domain/places/saved_place_rules.dart)。
const int kFreeSavedLocationLimit = 0;
const int kPlusSavedLocationLimit = 5;
