// workers/test/revenuecat-webhook.test.ts
//
// RevenueCat Webhook の純ロジック検証 (docs/revenuecat-integration-plan.md §3.4)。
// 8 イベント型の写像・認可・ティア継承・store 正規化を網羅 (受け入れ条件 §7)。

import { describe, expect, it } from 'vitest';
import {
  isAuthorized,
  mapEventToEntitlement,
  normalizeStore,
  tierFromEntitlements,
  type RevenueCatEvent,
} from '../src/lib/rc';
import { entitlementToFirestoreFields } from '../src/lib/firestore';

function ev(over: Partial<RevenueCatEvent>): RevenueCatEvent {
  return {
    type: 'INITIAL_PURCHASE',
    app_user_id: 'uid_1',
    product_id: 'mrw.plus.monthly',
    entitlement_ids: ['plus'],
    expiration_at_ms: 1_900_000_000_000,
    store: 'APP_STORE',
    ...over,
  };
}

describe('isAuthorized (§3.2 fail-closed)', () => {
  it('一致する Bearer トークンを許可', () => {
    expect(isAuthorized('Bearer secret123', 'secret123')).toBe(true);
  });
  it('不一致は拒否', () => {
    expect(isAuthorized('Bearer wrong', 'secret123')).toBe(false);
  });
  it('ヘッダ無しは拒否', () => {
    expect(isAuthorized(null, 'secret123')).toBe(false);
  });
  it('期待トークン未設定なら常に拒否 (fail-closed)', () => {
    expect(isAuthorized('Bearer anything', '')).toBe(false);
  });
});

describe('tierFromEntitlements (継承 pro > plus)', () => {
  it('pro は plus に優先', () => {
    expect(tierFromEntitlements(['plus', 'pro'])).toBe('pro');
  });
  it('plus のみ', () => {
    expect(tierFromEntitlements(['plus'])).toBe('plus');
  });
  it('空は free', () => {
    expect(tierFromEntitlements([])).toBe('free');
  });
});

describe('normalizeStore', () => {
  it('APP_STORE / MAC_APP_STORE → app_store', () => {
    expect(normalizeStore('APP_STORE')).toBe('app_store');
    expect(normalizeStore('MAC_APP_STORE')).toBe('app_store');
  });
  it('PLAY_STORE → play_store', () => {
    expect(normalizeStore('PLAY_STORE')).toBe('play_store');
  });
  it('未知/未指定 → null', () => {
    expect(normalizeStore('STRIPE')).toBeNull();
    expect(normalizeStore(undefined)).toBeNull();
  });
});

describe('mapEventToEntitlement (§3.4)', () => {
  it('INITIAL_PURCHASE: 解放 + willRenew', () => {
    const doc = mapEventToEntitlement(ev({ type: 'INITIAL_PURCHASE' }))!;
    expect(doc).toMatchObject({
      uid: 'uid_1',
      tier: 'plus',
      activeEntitlements: ['plus'],
      willRenew: true,
      isInGracePeriod: false,
      store: 'app_store',
      lastEventType: 'INITIAL_PURCHASE',
    });
  });

  it('RENEWAL: 有効維持', () => {
    const doc = mapEventToEntitlement(ev({ type: 'RENEWAL' }))!;
    expect(doc.tier).toBe('plus');
    expect(doc.willRenew).toBe(true);
  });

  it('CANCELLATION: 期限まで有効・willRenew=false', () => {
    const doc = mapEventToEntitlement(ev({ type: 'CANCELLATION' }))!;
    expect(doc.activeEntitlements).toEqual(['plus']);
    expect(doc.willRenew).toBe(false);
    expect(doc.isInGracePeriod).toBe(false);
  });

  it('BILLING_ISSUE: 有効維持 + grace', () => {
    const doc = mapEventToEntitlement(ev({ type: 'BILLING_ISSUE' }))!;
    expect(doc.tier).toBe('plus');
    expect(doc.isInGracePeriod).toBe(true);
  });

  it('EXPIRATION: 全剥奪 free', () => {
    const doc = mapEventToEntitlement(ev({ type: 'EXPIRATION', entitlement_ids: [] }))!;
    expect(doc.activeEntitlements).toEqual([]);
    expect(doc.tier).toBe('free');
    expect(doc.willRenew).toBe(false);
  });

  it('PRODUCT_CHANGE: 新 entitlement へ', () => {
    const doc = mapEventToEntitlement(
      ev({ type: 'PRODUCT_CHANGE', entitlement_ids: ['plus', 'pro'], product_id: 'mrw.pro.yearly' }),
    )!;
    expect(doc.tier).toBe('pro');
    expect(doc.productId).toBe('mrw.pro.yearly');
  });

  it('NON_RENEWING_PURCHASE: 解放・willRenew=false', () => {
    const doc = mapEventToEntitlement(
      ev({
        type: 'NON_RENEWING_PURCHASE',
        entitlement_ids: ['plus'],
        product_id: 'mrw.plus.nonrenewing',
        expiration_at_ms: null,
      }),
    )!;
    expect(doc.tier).toBe('plus');
    expect(doc.willRenew).toBe(false);
    expect(doc.expiresAtMs).toBeNull();
  });

  it('TRANSFER: 旧 uid を失効', () => {
    const doc = mapEventToEntitlement(ev({ type: 'TRANSFER' }))!;
    expect(doc.tier).toBe('free');
    expect(doc.activeEntitlements).toEqual([]);
  });

  it('SUBSCRIBER_ALIAS / TEST は写像しない (null)', () => {
    expect(mapEventToEntitlement(ev({ type: 'SUBSCRIBER_ALIAS' }))).toBeNull();
    expect(mapEventToEntitlement(ev({ type: 'TEST' }))).toBeNull();
  });
});

describe('entitlementToFirestoreFields', () => {
  it('typed value へ変換 (expiresAt=null は nullValue)', () => {
    const doc = mapEventToEntitlement(
      ev({ type: 'NON_RENEWING_PURCHASE', entitlement_ids: ['plus'], expiration_at_ms: null }),
    )!;
    const fields = entitlementToFirestoreFields(doc, 1_800_000_000_000) as Record<string, any>;
    expect(fields.tier).toEqual({ stringValue: 'plus' });
    expect(fields.expiresAt).toEqual({ nullValue: null });
    expect(fields.willRenew).toEqual({ booleanValue: false });
    expect(fields.activeEntitlements.arrayValue.values).toEqual([
      { stringValue: 'plus' },
    ]);
    expect(fields.updatedAt.timestampValue).toBe(new Date(1_800_000_000_000).toISOString());
  });
});
