// workers/test/push-subscriptions.test.ts
//
// push_subscriptions の runQuery 本文・ドキュメント解析・ページング (計画 S7 / S11)。
// 設計 docs/notification-delivery-design.md §4.2。

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  buildSubscriptionQuery,
  deleteSubscription,
  fetchSubscriptionPage,
  iterateActiveSubscriptions,
  parseSubscriptionDoc,
  staleCutoffIso,
  subscriptionDocumentName,
  type FirestoreDocument,
} from '../src/lib/push-subscriptions';

const PROJECT = 'mrw-test';

function doc(uid: string, over: Partial<Record<string, unknown>> = {}): FirestoreDocument {
  const fields: Record<string, unknown> = {
    fcmToken: { stringValue: `tok_${uid}` },
    platform: { stringValue: 'android' },
    locale: { stringValue: 'ja' },
    lat: { doubleValue: 35.7 },
    lon: { doubleValue: 139.7 },
    updatedAt: { timestampValue: '2026-09-10T00:00:00.000Z' },
    ...over,
  };
  for (const k of Object.keys(over)) if (over[k] === undefined) delete fields[k];
  return { name: subscriptionDocumentName(PROJECT, uid), fields: fields as never };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('buildSubscriptionQuery (runQuery 本文)', () => {
  it('updatedAt >= cutoff、updatedAt/__name__ 昇順、limit=200', () => {
    const q = buildSubscriptionQuery('2026-06-12T00:00:00.000Z', null) as any;
    const sq = q.structuredQuery;
    expect(sq.from).toEqual([{ collectionId: 'push_subscriptions' }]);
    expect(sq.where.fieldFilter).toEqual({
      field: { fieldPath: 'updatedAt' },
      op: 'GREATER_THAN_OR_EQUAL',
      value: { timestampValue: '2026-06-12T00:00:00.000Z' },
    });
    expect(sq.orderBy.map((o: any) => o.field.fieldPath)).toEqual(['updatedAt', '__name__']);
    expect(sq.limit).toBe(200);
    expect(sq.startAt).toBeUndefined();
  });

  it('カーソル指定時は startAt(before=false) に updatedAt + referenceValue を載せる', () => {
    const q = buildSubscriptionQuery(
      '2026-06-12T00:00:00.000Z',
      { updatedAt: '2026-09-01T00:00:00.000Z', documentName: subscriptionDocumentName(PROJECT, 'u9') },
      50,
    ) as any;
    expect(q.structuredQuery.limit).toBe(50);
    expect(q.structuredQuery.startAt).toEqual({
      values: [
        { timestampValue: '2026-09-01T00:00:00.000Z' },
        { referenceValue: `projects/${PROJECT}/databases/(default)/documents/push_subscriptions/u9` },
      ],
      before: false,
    });
  });

  it('opt-in/out フィールドで絞り込まない (spec §12.2.1: 常時 ON)', () => {
    const json = JSON.stringify(buildSubscriptionQuery('2026-06-12T00:00:00.000Z', null));
    expect(json).not.toMatch(/optIn|optOut|enabled|isPlus|tier/);
  });
});

describe('staleCutoffIso', () => {
  it('now − 90 日', () => {
    expect(staleCutoffIso(new Date('2026-09-15T00:00:00.000Z'))).toBe('2026-06-17T00:00:00.000Z');
  });
});

describe('parseSubscriptionDoc', () => {
  it('正常ドキュメントを PushSubscription に変換', () => {
    expect(parseSubscriptionDoc(doc('u1'))).toEqual({
      uid: 'u1',
      fcmToken: 'tok_u1',
      platform: 'android',
      locale: 'ja',
      lat: 35.7,
      lon: 139.7,
      updatedAt: '2026-09-10T00:00:00.000Z',
    });
  });

  it('integerValue の座標も読める / locale 省略は ja', () => {
    const s = parseSubscriptionDoc(
      doc('u2', { lat: { integerValue: '35' }, lon: { integerValue: 139 }, locale: undefined }),
    )!;
    expect(s.lat).toBe(35);
    expect(s.lon).toBe(139);
    expect(s.locale).toBe('ja');
  });

  it('トークン欠落 / 不正 platform / 範囲外座標は null (読み飛ばし)', () => {
    expect(parseSubscriptionDoc(doc('u3', { fcmToken: { stringValue: '' } }))).toBeNull();
    expect(parseSubscriptionDoc(doc('u4', { platform: { stringValue: 'web' } }))).toBeNull();
    expect(parseSubscriptionDoc(doc('u5', { lat: { doubleValue: 91 } }))).toBeNull();
    expect(parseSubscriptionDoc(doc('u6', { lon: undefined }))).toBeNull();
  });
});

/** runQuery 応答を作る。末尾に document 無しの readTime 行を混ぜる (実 API の挙動)。 */
function runQueryResponse(docs: FirestoreDocument[]) {
  return [
    ...docs.map((d) => ({ document: d, readTime: '2026-09-15T00:00:00Z' })),
    { readTime: '2026-09-15T00:00:00Z' },
  ];
}

describe('fetchSubscriptionPage / iterateActiveSubscriptions (ページング)', () => {
  it('pageSize 未満なら nextCursor=null、document 無し行は無視', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify(runQueryResponse([doc('a'), doc('b')])), { status: 200 }),
    );
    vi.stubGlobal('fetch', fetchMock);
    const r = await fetchSubscriptionPage(PROJECT, 'tok', '2026-06-17T00:00:00.000Z', null, 200);
    expect(r.docs.map((d) => d.name.split('/').pop())).toEqual(['a', 'b']);
    expect(r.nextCursor).toBeNull();
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(
      `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    );
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer tok');
  });

  it('pageSize ちょうどなら末尾ドキュメントをカーソルにして次ページを要求し、空ページで終了', async () => {
    const page1 = [doc('a'), doc('b', { updatedAt: { timestampValue: '2026-09-11T00:00:00.000Z' } })];
    const page2 = [doc('c', { updatedAt: { timestampValue: '2026-09-12T00:00:00.000Z' } })];
    const bodies: unknown[] = [];
    const fetchMock = vi.fn(async (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(init.body as string));
      const n = bodies.length;
      const docs = n === 1 ? page1 : n === 2 ? page2 : [];
      return new Response(JSON.stringify(runQueryResponse(docs)), { status: 200 });
    });
    vi.stubGlobal('fetch', fetchMock);

    const pages: string[][] = [];
    for await (const p of iterateActiveSubscriptions(PROJECT, 'tok', new Date('2026-09-15T00:00:00Z'), 2)) {
      pages.push(p.map((s) => s.uid));
    }
    expect(pages).toEqual([['a', 'b'], ['c']]);
    expect(fetchMock).toHaveBeenCalledTimes(2); // page2 は size 未満で終了 → 3 回目は不要

    const q2 = (bodies[1] as any).structuredQuery;
    expect(q2.startAt.values).toEqual([
      { timestampValue: '2026-09-11T00:00:00.000Z' },
      { referenceValue: subscriptionDocumentName(PROJECT, 'b') },
    ]);
    expect(q2.startAt.before).toBe(false);
    expect((bodies[0] as any).structuredQuery.startAt).toBeUndefined();
  });

  it('不正ドキュメントはページから除外され、全件不正のページは yield されない', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(
        JSON.stringify(runQueryResponse([doc('x', { platform: { stringValue: 'web' } })])),
        { status: 200 },
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    const pages: unknown[] = [];
    for await (const p of iterateActiveSubscriptions(PROJECT, 'tok', new Date(), 200)) pages.push(p);
    expect(pages).toEqual([]);
  });

  it('Firestore が非 2xx なら例外 (Cron はログして次回に委ねる)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('denied', { status: 403 })));
    await expect(
      fetchSubscriptionPage(PROJECT, 'tok', '2026-06-17T00:00:00.000Z', null),
    ).rejects.toThrow(/403/);
  });
});

describe('deleteSubscription (無効トークン掃除)', () => {
  it('DELETE を uid のドキュメントに発行。404 は成功扱い', async () => {
    const fetchMock = vi.fn(async () => new Response('', { status: 404 }));
    vi.stubGlobal('fetch', fetchMock);
    await expect(deleteSubscription(PROJECT, 'tok', 'gone')).resolves.toBeUndefined();
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(
      `https://firestore.googleapis.com/v1/${subscriptionDocumentName(PROJECT, 'gone')}`,
    );
    expect(init.method).toBe('DELETE');
  });

  it('403 は例外', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('denied', { status: 403 })));
    await expect(deleteSubscription(PROJECT, 'tok', 'u')).rejects.toThrow(/403/);
  });
});
