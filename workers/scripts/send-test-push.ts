// workers/scripts/send-test-push.ts
//
// V3 / V4 検証用: 1 台の端末へ「本番と同じ経路」で緊急プッシュを 1 通だけ送る。
// docs/fcm-activation-plan-v1.3.0.md §4 (V3: Android・アプリ終了状態で届くこと)。
//
// 本番を迂回しない部分 (= 検証の意味があるところ):
//   - 判定オブジェクトは本番の judgeForecast{Heat,Wind,Snow}() が作る (合成した気象値を入力)
//   - 文言・免責・data payload (type/kind/severity/metric/source=forecast/dedupe) は
//     本番の buildNotification() が作る
//   - 購読の読み出しは本番の iterateActiveSubscriptions() (90 日失効・解析規則も同一)
//   - 送信の形 (Android data-only / iOS ハイブリッド) は本番の sendFcm() → buildFcmMessage()
//   - 認証は本番の getGoogleAccessToken() (サービスアカウント → OAuth)
//
// 本番に触れない部分 (= 事故を起こさないところ):
//   - 本番 Worker・Cron・しきい値は一切変更しない (デプロイ不要)
//   - KV (ALERT_DEDUPE) を読まない・書かない (本番の de-dup 状態を汚さない)
//   - 送信先は --uid か --token で指定した 1 端末だけ。全購読者への一斉送信は実装しない
//
// 実行 (workers/ で):
//   FIREBASE_SA_JSON_FILE=/path/to/sa.json FIRESTORE_PROJECT_ID=<project-id> \
//     npm run push:test -- --list                      # 有効な購読を一覧 (uid を確認)
//     npm run push:test -- --uid <uid>                 # 熱中症 severe (予報 WBGT 34) を送る
//     npm run push:test -- --uid <uid> --kind strong_wind --severity danger
//     npm run push:test -- --uid <uid> --dry-run       # 送らずに message を表示
//   npx tsx を npm script 経由で呼ぶ (Node 20+)。
//
// 端末側の注意: 同じ kind×severity は 6 時間の de-dup (EmergencyAlertDeduper) で
//   2 通目が抑止される。再検証は --kind / --severity を変えるか 6 時間待つ。

import { readFileSync } from 'node:fs';

import { buildNotification } from '../src/cron/emergency-notifier';
import { buildFcmMessage, sendFcm } from '../src/lib/fcm';
import {
  judgeForecastHeat,
  judgeForecastSnow,
  judgeForecastWind,
  type ForecastJudgement,
  type ForecastSeverity,
} from '../src/lib/forecast-emergency';
import { FCM_SCOPE, FIRESTORE_SCOPE, getGoogleAccessToken } from '../src/lib/google-auth';
import { iterateActiveSubscriptions, type PushSubscription } from '../src/lib/push-subscriptions';

type Kind = 'heat_stroke' | 'strong_wind' | 'heavy_snow';

interface Args {
  list: boolean;
  dryRun: boolean;
  uid?: string;
  token?: string;
  platform?: 'ios' | 'android';
  locale?: string;
  kind: Kind;
  severity: ForecastSeverity;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { list: false, dryRun: false, kind: 'heat_stroke', severity: 'severe' };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const v = argv[i + 1];
    switch (k) {
      case '--list': a.list = true; break;
      case '--dry-run': a.dryRun = true; break;
      case '--uid': a.uid = v; i++; break;
      case '--token': a.token = v; i++; break;
      case '--platform': a.platform = v as Args['platform']; i++; break;
      case '--locale': a.locale = v; i++; break;
      case '--kind': a.kind = v as Kind; i++; break;
      case '--severity': a.severity = v as ForecastSeverity; i++; break;
      default: fail(`unknown argument: ${k}`);
    }
  }
  if (!['heat_stroke', 'strong_wind', 'heavy_snow'].includes(a.kind)) fail(`--kind must be heat_stroke|strong_wind|heavy_snow`);
  if (!['severe', 'danger'].includes(a.severity)) fail(`--severity must be severe|danger`);
  if (a.token && (a.platform !== 'ios' && a.platform !== 'android')) fail(`--token requires --platform ios|android`);
  return a;
}

function fail(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(2);
}

/**
 * 合成した気象値を本番の判定関数に通し、要求した深刻度の判定を得る。
 * しきい値そのもの (33/35, 20/30, 3/5) は forecast-emergency.ts の定数のまま。
 */
function synthesizeJudgement(kind: Kind, severity: ForecastSeverity): ForecastJudgement {
  let j: ForecastJudgement | null;
  switch (kind) {
    case 'heat_stroke':
      j = judgeForecastHeat(severity === 'danger' ? 35.5 : 34.0, 'heat_morning');
      break;
    case 'strong_wind':
      j = judgeForecastWind(severity === 'danger' ? 31 : 22);
      break;
    case 'heavy_snow':
      j = judgeForecastSnow(severity === 'danger' ? 6 : 4);
      break;
  }
  if (!j || j.severity !== severity) fail(`judgement synthesis failed for ${kind}/${severity}`);
  return j;
}

function loadEnv(): { sa: string; projectId: string } {
  const file = process.env.FIREBASE_SA_JSON_FILE;
  const projectId = process.env.FIRESTORE_PROJECT_ID;
  if (!file) fail('FIREBASE_SA_JSON_FILE (サービスアカウント JSON のパス) を設定してください');
  if (!projectId) fail('FIRESTORE_PROJECT_ID を設定してください');
  const sa = readFileSync(file, 'utf8');
  try {
    const parsed = JSON.parse(sa) as { client_email?: string; private_key?: string };
    if (!parsed.client_email || !parsed.private_key) fail('サービスアカウント JSON に client_email / private_key がありません');
  } catch (e) {
    fail(`サービスアカウント JSON を読めません: ${(e as Error).message}`);
  }
  return { sa, projectId };
}

async function listSubscriptions(sa: string, projectId: string): Promise<PushSubscription[]> {
  const token = await getGoogleAccessToken(sa, FIRESTORE_SCOPE);
  const all: PushSubscription[] = [];
  for await (const page of iterateActiveSubscriptions(projectId, token, new Date())) {
    all.push(...page);
  }
  return all;
}

function maskToken(t: string): string {
  return t.length <= 12 ? '***' : `${t.slice(0, 6)}…${t.slice(-6)}`;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  // --token を明示した dry-run は認証も Firestore も不要 (payload の目視だけ)。
  let target: PushSubscription;
  let env: { sa: string; projectId: string } | null = null;

  if (args.list) {
    env = loadEnv();
    const subs = await listSubscriptions(env.sa, env.projectId);
    console.log(`active subscriptions: ${subs.length}`);
    for (const s of subs) {
      console.log(
        `  uid=${s.uid} platform=${s.platform} locale=${s.locale} lat=${s.lat} lon=${s.lon} ` +
          `updatedAt=${s.updatedAt} token=${maskToken(s.fcmToken)}`,
      );
    }
    return;
  }

  if (args.token) {
    target = {
      uid: '(manual)',
      fcmToken: args.token,
      platform: args.platform!,
      locale: args.locale ?? 'ja',
      lat: 0,
      lon: 0,
      updatedAt: new Date().toISOString(),
    };
  } else if (args.uid) {
    env = loadEnv();
    const subs = await listSubscriptions(env.sa, env.projectId);
    const found = subs.find((s) => s.uid === args.uid);
    if (!found) {
      fail(
        `uid=${args.uid} は有効な購読に見つかりません (本番 Worker も同じ条件で読むため、` +
          `このままでは配信対象外です)。原因の候補: アプリで自分の体感が表示される前 / ` +
          `位置情報が拒否されて既定地点のまま / updatedAt が 90 日超 / プロジェクト ID 違い。` +
          `--list で有効な購読を確認してください。`,
      );
    }
    target = found;
  } else {
    fail('--uid <uid> か --token <fcmToken> --platform ios|android を指定してください (--list で uid を確認)');
  }

  const locale = args.locale ?? target.locale;
  const judgement = synthesizeJudgement(args.kind, args.severity);
  const notification = buildNotification(judgement, locale);
  const message = buildFcmMessage(
    { fcmToken: target.fcmToken, platform: target.platform },
    notification,
  );

  console.log('--- target ---');
  console.log(`uid=${target.uid} platform=${target.platform} locale=${locale} token=${maskToken(target.fcmToken)}`);
  console.log('--- judgement (from production judgeForecast*) ---');
  console.log(JSON.stringify(judgement));
  console.log('--- FCM message (from production buildNotification + buildFcmMessage) ---');
  console.log(JSON.stringify({ ...message, token: maskToken(target.fcmToken) }, null, 2));
  console.log('--- expected on device ---');
  console.log(`title: ${notification.title}`);
  console.log(`body : ${notification.body.replace(/\n/g, ' / ')}`);
  if (target.platform === 'android') {
    console.log('(Android は data-only。端末側が ARB の *Forecast 文言 + 免責で表示する。上の title/body は iOS 用フォールバックで、Android では同じ意味の端末側文言になる)');
  }

  if (args.dryRun) {
    console.log('--- dry-run: 送信していません ---');
    return;
  }

  env ??= loadEnv();
  const fcmToken = await getGoogleAccessToken(env.sa, FCM_SCOPE);
  const res = await sendFcm(
    fcmToken,
    env.projectId,
    { fcmToken: target.fcmToken, platform: target.platform },
    notification,
  );
  console.log('--- FCM response ---');
  console.log(`status=${res.status} ok=${res.ok}`);
  console.log(res.body);
  if (!res.ok) {
    if (res.status === 404) {
      console.error('UNREGISTERED: この端末のトークンは失効しています (アプリ再インストール等)。アプリを起動して再登録してください。本番 Worker はこの応答で購読を削除します。');
    }
    process.exit(1);
  }
  console.log('送信済み。端末で通知を確認してください (同じ kind×severity は 6 時間 de-dup されます)。');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
