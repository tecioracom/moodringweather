// workers/src/lib/firestore.ts
//
// Firestore REST 書き込み (docs/revenuecat-integration-plan.md §3.3)。
// Webhook が users/{uid}/entitlement/current を upsert し、監査用に
// billingEvents を追記する。クライアントは read-only (Security Rules §6)。

import { EntitlementDoc } from './rc';

/** Firestore の typed value へ変換するヘルパー群。 */
function strVal(v: string) {
  return { stringValue: v };
}
function boolVal(v: boolean) {
  return { booleanValue: v };
}
function tsVal(ms: number) {
  return { timestampValue: new Date(ms).toISOString() };
}
function arrVal(items: string[]) {
  return { arrayValue: { values: items.map(strVal) } };
}
function nullVal() {
  return { nullValue: null };
}

/** entitlement 文書のフィールド表現を組み立てる。 */
export function entitlementToFirestoreFields(
  doc: EntitlementDoc,
  updatedAtMs: number,
): Record<string, unknown> {
  return {
    activeEntitlements: arrVal(doc.activeEntitlements),
    tier: strVal(doc.tier),
    productId: doc.productId ? strVal(doc.productId) : nullVal(),
    expiresAt: doc.expiresAtMs ? tsVal(doc.expiresAtMs) : nullVal(),
    willRenew: boolVal(doc.willRenew),
    isInGracePeriod: boolVal(doc.isInGracePeriod),
    store: doc.store ? strVal(doc.store) : nullVal(),
    lastEventType: strVal(doc.lastEventType),
    updatedAt: tsVal(updatedAtMs),
  };
}

/** users/{uid}/entitlement/current を upsert (REST PATCH = create or update)。 */
export async function writeEntitlement(
  projectId: string,
  accessToken: string,
  doc: EntitlementDoc,
  updatedAtMs: number,
): Promise<void> {
  const path = `users/${doc.uid}/entitlement/current`;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: entitlementToFirestoreFields(doc, updatedAtMs) }),
  });
  if (!res.ok) {
    throw new Error(`Firestore write failed: ${res.status} ${await res.text()}`);
  }
}

/** 監査ログ: users/{uid}/billingEvents/{auto} に追記 (TTL は Firestore 側で設定)。 */
export async function appendBillingEvent(
  projectId: string,
  accessToken: string,
  uid: string,
  doc: EntitlementDoc,
  occurredAtMs: number,
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}/billingEvents`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fields: {
        type: strVal(doc.lastEventType),
        productId: doc.productId ? strVal(doc.productId) : nullVal(),
        tier: strVal(doc.tier),
        occurredAt: tsVal(occurredAtMs),
      },
    }),
  });
  // 監査ログ失敗は致命ではない (本処理はエンタイトルメント反映)。呼び出し側で握る。
  if (!res.ok) {
    throw new Error(`Firestore billingEvent append failed: ${res.status}`);
  }
}
