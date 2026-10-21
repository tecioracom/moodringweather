// workers/src/index.ts
//
// Cloudflare Workers のエントリ。HTTP fetch ハンドラと scheduled (Cron) ハンドラを公開する。
// spec.md §12.4(技術スタック)/ §12.10.3(計算配置)/ §12.2.3(パーソナル通知)準拠。

import { runEmergencyCheck, type Env as EmergencyEnv } from './cron/emergency-notifier';
import { runPersonalCheck, type Env as PersonalEnv } from './cron/personal-notifier';
import {
  handleRevenueCatWebhook,
  type RevenueCatWebhookEnv,
} from './webhooks/revenuecat';

/** 緊急 + パーソナル + 課金 Webhook の bindings を兼ねた合成 Env */
export type Env = EmergencyEnv & PersonalEnv & RevenueCatWebhookEnv;

export default {
  /** HTTP エンドポイント (/health, /webhooks/revenuecat)。 */
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ ok: true, service: 'mrw-notifier' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    // RevenueCat 課金 Webhook (docs/revenuecat-integration-plan.md §3)。
    if (url.pathname === '/webhooks/revenuecat' && req.method === 'POST') {
      return handleRevenueCatWebhook(req, env);
    }
    return new Response('Not Found', { status: 404 });
  },

  /** Cron Trigger ハンドラ。wrangler.toml の cron 文字列から発火する。 */
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    const trigger = mapCronToTrigger(event.cron);

    // 緊急通知(熱中症は heat_morning/evening のみ、その他は periodic)
    ctx.waitUntil(
      runEmergencyCheck(env, trigger).then((r) => {
        console.log(
          `[emergency:${event.cron}] trigger=${trigger} scanned=${r.scanned} pushed=${r.pushed}`,
        );
      }),
    );

    // パーソナル通知は periodic 走行(spec.md §12.4 5〜10 分間隔)時のみ動かす
    if (trigger === 'periodic') {
      ctx.waitUntil(
        runPersonalCheck(env).then((r) => {
          console.log(
            `[personal:${event.cron}] scanned=${r.scanned} pushed=${r.pushed} ` +
              `suppressedQuiet=${r.suppressedQuiet} suppressedLimit=${r.suppressedLimit}`,
          );
        }),
      );
    }
  },
};

/** wrangler.toml の cron 文字列から内部トリガー名へ変換(正本: mri-spec §5.3.2) */
function mapCronToTrigger(
  cron: string,
): 'periodic' | 'heat_morning' | 'heat_evening' | 'heat_special' {
  if (cron === '0 20 * * *') return 'heat_morning';   // JST 当日 05:00(警戒 ≥ 33)
  if (cron === '0 8 * * *') return 'heat_evening';    // JST 前日 17:00(警戒 ≥ 33)
  if (cron === '0 5 * * *') return 'heat_special';    // JST 前日 14:00(特別警戒 ≥ 35)
  return 'periodic';
}
