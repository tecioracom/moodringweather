// workers/src/lib/rc.ts
//
// RevenueCat Webhook の純ロジック (docs/revenuecat-integration-plan.md §2.4 / §3.2 / §3.4)。
// 副作用 (Firestore 書き込み / ネットワーク) は持たず、イベント→エンタイトルメント
// 文書への写像と認可判定だけを担う。ネットワークI/Oは firestore.ts に分離。

/** RevenueCat Webhook のイベント種別 (§3.4 ハンドリング対象)。 */
export type RevenueCatEventType =
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'NON_RENEWING_PURCHASE'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE'
  | 'SUBSCRIBER_ALIAS'
  | 'TRANSFER'
  | 'TEST';

/** RevenueCat Webhook ペイロード (必要フィールドのみ)。 */
export interface RevenueCatEvent {
  type: RevenueCatEventType;
  app_user_id: string;
  product_id?: string;
  entitlement_ids?: string[] | null;
  expiration_at_ms?: number | null;
  event_timestamp_ms?: number;
  store?: string; // APP_STORE / PLAY_STORE / MAC_APP_STORE ...
}

export interface RevenueCatWebhookBody {
  api_version?: string;
  event: RevenueCatEvent;
}

export type EntitlementTier = 'free' | 'plus' | 'pro';

/** Firestore `users/{uid}/entitlement/current` に書く正規化済みフィールド (§3.3)。 */
export interface EntitlementDoc {
  uid: string;
  activeEntitlements: string[];
  tier: EntitlementTier;
  productId: string | null;
  expiresAtMs: number | null; // Firestore 書き込み時に Timestamp へ変換
  willRenew: boolean;
  isInGracePeriod: boolean;
  store: 'app_store' | 'play_store' | null;
  lastEventType: RevenueCatEventType;
}

/** Authorization ヘッダが RC からの正規呼び出しか検証 (§3.2)。 */
export function isAuthorized(authHeader: string | null, expectedToken: string): boolean {
  if (!expectedToken) return false; // トークン未設定なら常に拒否 (fail-closed)
  return authHeader === `Bearer ${expectedToken}`;
}

/** entitlement_ids から最上位ティアを決定 (継承: pro > plus)。 */
export function tierFromEntitlements(ids: readonly string[]): EntitlementTier {
  if (ids.includes('pro')) return 'pro';
  if (ids.includes('plus')) return 'plus';
  return 'free';
}

/** RC の store 文字列をクライアント表現へ正規化。 */
export function normalizeStore(store?: string): 'app_store' | 'play_store' | null {
  switch (store) {
    case 'APP_STORE':
    case 'MAC_APP_STORE':
      return 'app_store';
    case 'PLAY_STORE':
      return 'play_store';
    default:
      return null;
  }
}

/**
 * イベントをエンタイトルメント文書へ写像する。
 * Firestore へ反映しないイベント (SUBSCRIBER_ALIAS / TEST) は null を返す。
 * TRANSFER は「旧 uid を失効させる」ため active=[] / free を返す
 * (新 uid 側は別途 INITIAL/RENEWAL で確立される)。
 */
export function mapEventToEntitlement(event: RevenueCatEvent): EntitlementDoc | null {
  const { type, app_user_id } = event;
  if (type === 'SUBSCRIBER_ALIAS' || type === 'TEST') return null;

  const ids = event.entitlement_ids ?? [];
  const store = normalizeStore(event.store);
  const productId = event.product_id ?? null;
  const base = {
    uid: app_user_id,
    productId,
    expiresAtMs: event.expiration_at_ms ?? null,
    store,
    lastEventType: type,
  };

  switch (type) {
    // 有効化系: entitlement を解放し自動更新 ON
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'PRODUCT_CHANGE':
    case 'NON_RENEWING_PURCHASE':
      return {
        ...base,
        activeEntitlements: ids,
        tier: tierFromEntitlements(ids),
        willRenew: type !== 'NON_RENEWING_PURCHASE',
        isInGracePeriod: false,
      };

    // 解約予約: 期限までは有効、ただし更新しない
    case 'CANCELLATION':
      return {
        ...base,
        activeEntitlements: ids,
        tier: tierFromEntitlements(ids),
        willRenew: false,
        isInGracePeriod: false,
      };

    // 支払い猶予: 有効を維持しつつ警告フラグ
    case 'BILLING_ISSUE':
      return {
        ...base,
        activeEntitlements: ids,
        tier: tierFromEntitlements(ids),
        willRenew: true,
        isInGracePeriod: true,
      };

    // 失効 / 移管(旧uid側): すべて剥奪
    case 'EXPIRATION':
    case 'TRANSFER':
      return {
        ...base,
        activeEntitlements: [],
        tier: 'free',
        willRenew: false,
        isInGracePeriod: false,
      };
  }
}
