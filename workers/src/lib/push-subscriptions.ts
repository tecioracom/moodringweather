// workers/src/lib/push-subscriptions.ts
//
// 緊急プッシュ購読ストア `push_subscriptions/{uid}` の読み出し (Firestore REST runQuery)。
// スキーマの正本: docs/notification-delivery-design.md §4.2、ルール: firestore.rules。
//
// 設計方針:
//   - 購読 = 「地点を登録している全員」。opt-in/out フィールドは存在しない (spec §12.2.1)。
//     本モジュールは課金状態を一切見ない。
//   - 90 日以上 updatedAt が更新されていない購読は無効トークン扱いで対象外 (§4.2)。
//   - ページング: updatedAt ASC, __name__ ASC で 200 件ずつカーソル走査。
//     1 ページ分を処理してから次ページを取りに行くことで、Workers の CPU / メモリを
//     一定に保つ (全件を一度に配列へ展開しない)。
//   - FCM が 404 (UNREGISTERED) を返したトークンは deleteSubscription で掃除する。

export const SUBSCRIPTION_PAGE_SIZE = 200;
export const SUBSCRIPTION_STALE_DAYS = 90;
export const SUBSCRIPTIONS_COLLECTION = 'push_subscriptions';

export interface PushSubscription {
  uid: string;
  fcmToken: string;
  platform: 'ios' | 'android';
  locale: string;
  lat: number;
  lon: number;
  /** ISO 8601。ページングカーソルに使う */
  updatedAt: string;
}

/** runQuery のページングカーソル (直前ページ末尾の updatedAt + ドキュメント名)。 */
export interface SubscriptionCursor {
  updatedAt: string;
  /** フルパス: projects/{p}/databases/(default)/documents/push_subscriptions/{uid} */
  documentName: string;
}

/** Firestore REST の typed value (必要な部分だけ)。 */
type FirestoreValue = {
  stringValue?: string;
  doubleValue?: number;
  integerValue?: string | number;
  timestampValue?: string;
  booleanValue?: boolean;
  nullValue?: null;
};

export interface FirestoreDocument {
  name: string;
  fields?: Record<string, FirestoreValue>;
  updateTime?: string;
}

export function documentsRoot(projectId: string): string {
  return `projects/${projectId}/databases/(default)/documents`;
}

export function subscriptionDocumentName(projectId: string, uid: string): string {
  return `${documentsRoot(projectId)}/${SUBSCRIPTIONS_COLLECTION}/${uid}`;
}

/** 失効判定の境界時刻 (nowUtc − 90 日) を ISO で返す。 */
export function staleCutoffIso(nowUtc: Date): string {
  return new Date(nowUtc.getTime() - SUBSCRIPTION_STALE_DAYS * 24 * 60 * 60 * 1000).toISOString();
}

/**
 * runQuery のリクエスト本文 (純関数)。
 * 範囲フィルタ (updatedAt >= cutoff) を持つため最初の orderBy は updatedAt 固定。
 * __name__ を第 2 キーにして順序を一意にし、カーソルは「直前ページの末尾の後」(before=false)。
 */
export function buildSubscriptionQuery(
  cutoffIso: string,
  cursor: SubscriptionCursor | null,
  pageSize: number = SUBSCRIPTION_PAGE_SIZE,
): Record<string, unknown> {
  const structuredQuery: Record<string, unknown> = {
    from: [{ collectionId: SUBSCRIPTIONS_COLLECTION }],
    where: {
      fieldFilter: {
        field: { fieldPath: 'updatedAt' },
        op: 'GREATER_THAN_OR_EQUAL',
        value: { timestampValue: cutoffIso },
      },
    },
    orderBy: [
      { field: { fieldPath: 'updatedAt' }, direction: 'ASCENDING' },
      { field: { fieldPath: '__name__' }, direction: 'ASCENDING' },
    ],
    limit: pageSize,
  };
  if (cursor) {
    structuredQuery.startAt = {
      values: [
        { timestampValue: cursor.updatedAt },
        { referenceValue: cursor.documentName },
      ],
      before: false,
    };
  }
  return { structuredQuery };
}

function numberOf(v: FirestoreValue | undefined): number | null {
  if (!v) return null;
  if (typeof v.doubleValue === 'number') return v.doubleValue;
  if (v.integerValue !== undefined) {
    const n = Number(v.integerValue);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/**
 * Firestore ドキュメント → PushSubscription (純関数)。
 * ルールで弾けない古いデータや壊れたデータは null にして黙って読み飛ばす
 * (1 件の不正で Cron 全体を止めない)。
 */
export function parseSubscriptionDoc(doc: FirestoreDocument): PushSubscription | null {
  const f = doc.fields ?? {};
  const uid = doc.name.split('/').pop() ?? '';
  const fcmToken = f.fcmToken?.stringValue ?? '';
  const platform = f.platform?.stringValue;
  const lat = numberOf(f.lat);
  const lon = numberOf(f.lon);
  const updatedAt = f.updatedAt?.timestampValue ?? doc.updateTime;

  if (!uid || !fcmToken) return null;
  if (platform !== 'ios' && platform !== 'android') return null;
  if (lat === null || lon === null) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  if (!updatedAt) return null;

  return {
    uid,
    fcmToken,
    platform,
    locale: f.locale?.stringValue || 'ja',
    lat,
    lon,
    updatedAt,
  };
}

/** runQuery の応答要素。最後の要素は document を持たない (readTime のみ) ことがある。 */
interface RunQueryRow {
  document?: FirestoreDocument;
  readTime?: string;
  done?: boolean;
}

/** 1 ページ分を Firestore REST から取得する。 */
export async function fetchSubscriptionPage(
  projectId: string,
  accessToken: string,
  cutoffIso: string,
  cursor: SubscriptionCursor | null,
  pageSize: number = SUBSCRIPTION_PAGE_SIZE,
): Promise<{ docs: FirestoreDocument[]; nextCursor: SubscriptionCursor | null }> {
  const url = `https://firestore.googleapis.com/v1/${documentsRoot(projectId)}:runQuery`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(buildSubscriptionQuery(cutoffIso, cursor, pageSize)),
  });
  if (!res.ok) {
    throw new Error(`Firestore runQuery failed: ${res.status} ${await res.text()}`);
  }
  const rows = (await res.json()) as RunQueryRow[];
  const docs = rows.flatMap((r) => (r.document ? [r.document] : []));

  // ページサイズ未満なら最終ページ。ちょうど pageSize の場合は次ページを試す
  // (空ページが 1 回返って終了する。余計な 1 リクエストは許容)。
  if (docs.length < pageSize) return { docs, nextCursor: null };
  const last = docs[docs.length - 1];
  const lastUpdatedAt = last.fields?.updatedAt?.timestampValue ?? last.updateTime;
  if (!lastUpdatedAt) return { docs, nextCursor: null };
  return { docs, nextCursor: { updatedAt: lastUpdatedAt, documentName: last.name } };
}

/**
 * 有効な購読を 200 件ずつページ単位で列挙する async generator。
 * 呼び出し側は 1 ページを処理し終えてから次を要求するため、同時に保持する件数は
 * 常に 1 ページ分に収まる。
 */
export async function* iterateActiveSubscriptions(
  projectId: string,
  accessToken: string,
  nowUtc: Date,
  pageSize: number = SUBSCRIPTION_PAGE_SIZE,
): AsyncGenerator<PushSubscription[], void, void> {
  const cutoff = staleCutoffIso(nowUtc);
  let cursor: SubscriptionCursor | null = null;
  // 安全弁: 無限ループ防止 (200 件 × 10,000 ページ = 200 万購読で打ち切り)。
  for (let page = 0; page < 10_000; page++) {
    const { docs, nextCursor } = await fetchSubscriptionPage(
      projectId,
      accessToken,
      cutoff,
      cursor,
      pageSize,
    );
    const subs = docs.flatMap((d) => {
      const s = parseSubscriptionDoc(d);
      return s ? [s] : [];
    });
    if (subs.length > 0) yield subs;
    if (!nextCursor) return;
    cursor = nextCursor;
  }
}

/** 無効トークン (FCM 404 UNREGISTERED) の購読を削除する (設計 §4.2)。失敗は呼び出し側で握る。 */
export async function deleteSubscription(
  projectId: string,
  accessToken: string,
  uid: string,
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/${subscriptionDocumentName(projectId, uid)}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  // 404 は既に無い = 目的達成なので成功扱い。
  if (!res.ok && res.status !== 404) {
    throw new Error(`Firestore delete failed: ${res.status} ${await res.text()}`);
  }
}
