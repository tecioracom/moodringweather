// workers/src/webhooks/revenuecat.ts
//
// POST /webhooks/revenuecat (docs/revenuecat-integration-plan.md §3)。
// RevenueCat の Webhook を受けて Firestore の entitlement を反映する。
//
// フロー:
//   1. Authorization: Bearer <RC_WEBHOOK_AUTH_TOKEN> を検証 (fail-closed)
//   2. ボディを RevenueCatWebhookBody としてパース
//   3. イベント → entitlement 文書へ写像 (純: lib/rc.ts)
//   4. Firestore へ upsert + 監査ログ追記 (lib/firestore.ts)
//   5. 2xx を返す (RC は非 2xx でリトライするため、致命でない限り 200)

import { getGoogleAccessToken, FIRESTORE_SCOPE } from '../lib/google-auth';
import { appendBillingEvent, writeEntitlement } from '../lib/firestore';
import { isAuthorized, mapEventToEntitlement, RevenueCatWebhookBody } from '../lib/rc';

export interface RevenueCatWebhookEnv {
  RC_WEBHOOK_AUTH_TOKEN: string;
  FIRESTORE_PROJECT_ID: string;
  FIREBASE_SA_JSON: string;
}

export async function handleRevenueCatWebhook(
  req: Request,
  env: RevenueCatWebhookEnv,
): Promise<Response> {
  // 1. 認可 (RC ダッシュボードで設定した固定トークン)
  if (!isAuthorized(req.headers.get('Authorization'), env.RC_WEBHOOK_AUTH_TOKEN)) {
    return new Response('unauthorized', { status: 401 });
  }

  // 2. パース
  let body: RevenueCatWebhookBody;
  try {
    body = (await req.json()) as RevenueCatWebhookBody;
  } catch {
    return new Response('bad request', { status: 400 });
  }
  const event = body?.event;
  if (!event || !event.type || !event.app_user_id) {
    return new Response('bad request', { status: 400 });
  }

  // 3. 写像 (反映しないイベントは ok を返して終了)
  const doc = mapEventToEntitlement(event);
  if (doc === null) {
    return new Response('ignored', { status: 200 });
  }

  // 4. Firestore 反映
  try {
    const token = await getGoogleAccessToken(env.FIREBASE_SA_JSON, FIRESTORE_SCOPE);
    const updatedAtMs = event.event_timestamp_ms ?? Date.now();
    await writeEntitlement(env.FIRESTORE_PROJECT_ID, token, doc, updatedAtMs);
    // 監査ログは best-effort (失敗しても entitlement 反映は成立済み)
    try {
      await appendBillingEvent(
        env.FIRESTORE_PROJECT_ID,
        token,
        doc.uid,
        doc,
        updatedAtMs,
      );
    } catch (e) {
      console.warn(`[rc-webhook] billingEvent append failed: ${e}`);
    }
  } catch (e) {
    // 反映失敗は 500 で返し RC のリトライ (24h 指数バックオフ) に委ねる
    console.error(`[rc-webhook] entitlement write failed: ${e}`);
    return new Response('write failed', { status: 500 });
  }

  return new Response('ok', { status: 200 });
}
