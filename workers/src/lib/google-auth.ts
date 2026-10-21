// workers/src/lib/google-auth.ts
//
// サービスアカウント JWT -> OAuth2 アクセストークン交換 (Web Crypto / RS256)。
// Firestore REST と FCM HTTP v1 で共用する (fcm.ts の TODO を解消)。
//
// 入力はサービスアカウント JSON 文字列 (wrangler secret put FIREBASE_SA_JSON)。
// 取得トークンは scope 単位でメモリキャッシュ (有効期限の 60 秒前まで再利用)。

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface CachedToken {
  token: string;
  expiresAtMs: number;
}

const _cache = new Map<string, CachedToken>();

/** Firestore 読み書きに必要な OAuth スコープ。 */
export const FIRESTORE_SCOPE = 'https://www.googleapis.com/auth/datastore';
/** FCM HTTP v1 (messages:send) に必要な OAuth スコープ。 */
export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/** サービスアカウントでアクセストークンを取得 (scope 単位でキャッシュ)。 */
export async function getGoogleAccessToken(
  serviceAccountJson: string,
  scope: string,
): Promise<string> {
  const cached = _cache.get(scope);
  if (cached && cached.expiresAtMs - 60_000 > Date.now()) {
    return cached.token;
  }

  const sa = JSON.parse(serviceAccountJson) as ServiceAccount;
  const tokenUri = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
  const nowSec = Math.floor(Date.now() / 1000);
  const claims = {
    iss: sa.client_email,
    scope,
    aud: tokenUri,
    iat: nowSec,
    exp: nowSec + 3600,
  };

  const jwt = await signJwtRs256(claims, sa.private_key);

  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = (await res.json()) as { access_token: string; expires_in: number };
  _cache.set(scope, {
    token: json.access_token,
    expiresAtMs: Date.now() + json.expires_in * 1000,
  });
  return json.access_token;
}

/** テスト用にトークンキャッシュを消去。 */
export function _clearTokenCache(): void {
  _cache.clear();
}

async function signJwtRs256(
  claims: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' };
  const encoder = new TextEncoder();
  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(
    JSON.stringify(claims),
  )}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64UrlFromBytes(new Uint8Array(signature))}`;
}

function base64UrlEncode(str: string): string {
  return base64UrlFromBytes(new TextEncoder().encode(str));
}

function base64UrlFromBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
