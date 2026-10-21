// workers/test/emergency-notifier.test.ts
//
// 緊急通知の配信経路 (計画 S7 / S11): payload 契約・4 言語免責文・de-dup・
// ページング走査・無効トークン掃除・不変条件 (課金/静音を見ない)。
// Open-Meteo / Firestore / FCM は global fetch を URL で振り分けてモックする。

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../src/lib/google-auth', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../src/lib/google-auth')>();
  return {
    ...mod,
    getGoogleAccessToken: vi.fn(async (_sa: string, scope: string) =>
      scope === mod.FCM_SCOPE ? 'fcm-token' : 'fs-token',
    ),
  };
});

import {
  buildNotification,
  disclaimerFor,
  evaluateStrongWind,
  fallbackLangOf,
  runEmergencyCheck,
  type Env,
} from '../src/cron/emergency-notifier';
import { buildFcmMessage } from '../src/lib/fcm';
import type { ForecastJudgement } from '../src/lib/forecast-emergency';
import { subscriptionDocumentName } from '../src/lib/push-subscriptions';

const PROJECT = 'mrw-test';

// ──────────────────────────────────────────────────────────────────
// 純関数: 文言・payload 契約
// ──────────────────────────────────────────────────────────────────

const DISCLAIMER_MARK: Record<string, RegExp> = {
  ja: /独自推定.*公式警報ではありません/,
  en: /Independent estimate.*not an official government warning/,
  es: /Estimación independiente.*no es un aviso oficial/,
  zh: /独立估算.*并非政府部门发布的官方预警/,
};

describe('fallbackLangOf / disclaimerFor (spec §12.10.4)', () => {
  it('BCP 47 の地域付きも言語で解決、未対応は en', () => {
    expect(fallbackLangOf('ja-JP')).toBe('ja');
    expect(fallbackLangOf('zh_Hans_CN')).toBe('zh');
    expect(fallbackLangOf('es-MX')).toBe('es');
    expect(fallbackLangOf('fr')).toBe('en');
    expect(fallbackLangOf('')).toBe('en');
  });

  it('4 言語すべてで免責文が独自判定である旨を含む', () => {
    for (const l of ['ja', 'en', 'es', 'zh']) {
      expect(disclaimerFor(l)).toMatch(DISCLAIMER_MARK[l]);
    }
  });
});

describe('buildNotification (payload 契約 §4.1 + 免責併記)', () => {
  const heatDanger: ForecastJudgement = {
    kind: 'heat_stroke',
    severity: 'danger',
    metricValue: 35.2,
    special: true,
  };
  const windSevere: ForecastJudgement = {
    kind: 'strong_wind',
    severity: 'severe',
    metricValue: 22.4,
    special: false,
  };

  it('data に type/kind/severity/metric(/special) + dedupe を同梱', () => {
    const n = buildNotification(heatDanger, 'ja');
    expect(n.data).toEqual({
      type: 'emergency',
      kind: 'heat_stroke',
      severity: 'danger',
      metric: '35.2',
      source: 'forecast',
      special: '1',
      dedupe: 'heat_stroke:danger',
    });
    expect(n.critical).toBe(true);
    // data の値はすべて string (FCM v1 制約)
    for (const v of Object.values(n.data!)) expect(typeof v).toBe('string');
  });

  it('severe は critical=false、special 無し', () => {
    const n = buildNotification(windSevere, 'en');
    expect(n.critical).toBe(false);
    expect(n.data!.special).toBeUndefined();
    expect(n.data!.dedupe).toBe('strong_wind:severe');
  });

  it('全種別 × 4 言語で本文末尾に免責文が併記される', () => {
    const judgements: ForecastJudgement[] = [
      heatDanger,
      { ...heatDanger, severity: 'severe', special: false },
      windSevere,
      { kind: 'heavy_snow', severity: 'danger', metricValue: 6, special: false },
    ];
    for (const j of judgements) {
      for (const l of ['ja', 'en', 'es', 'zh']) {
        const n = buildNotification(j, l);
        expect(n.body.endsWith(disclaimerFor(l))).toBe(true);
        expect(n.body).toMatch(DISCLAIMER_MARK[l]);
        expect(n.title.length).toBeGreaterThan(0);
      }
    }
  });

  it('本文の計測値は Dart 側と同じ整数丸め (35.2→35 / 22.4→22)', () => {
    expect(buildNotification(heatDanger, 'en').body).toContain('around 35°C');
    expect(buildNotification(windSevere, 'en').body).toContain('22\u00A0m/s');
    expect(buildNotification({ ...heatDanger, metricValue: 34.6 }, 'ja').body).toContain('約35°C');
  });

  it('data.source は forecast (端末側は予報文言を選ぶ)', () => {
    expect(buildNotification(heatDanger, 'ja').data!.source).toBe('forecast');
  });
});

// ──────────────────────────────────────────────────────────────────
// ARB との同一性: サーバー側フォールバック本文 = lib/l10n の *Forecast キー (予報表現)。
// 予報の数値を現在値の文言 (emergencyHeatBodySevere 等) で出していないことも検証する。
// ──────────────────────────────────────────────────────────────────

const ARB_DIR = resolve(__dirname, '../../lib/l10n');
const arbOf = (lang: string) =>
  JSON.parse(readFileSync(resolve(ARB_DIR, `app_${lang}.arb`), 'utf8')) as Record<string, string>;
const fill = (tpl: string, ph: string, v: string) => tpl.replace(`{${ph}}`, v);

describe('サーバー側フォールバック本文は ARB の *Forecast キーと同一文字列', () => {
  const cases: Array<{ j: ForecastJudgement; key: string; ph: string; title: string }> = [
    {
      j: { kind: 'heat_stroke', severity: 'severe', metricValue: 33.4, special: false },
      key: 'emergencyHeatBodySevereForecast', ph: 'wbgt', title: 'emergencyHeatTitle',
    },
    {
      j: { kind: 'heat_stroke', severity: 'danger', metricValue: 35.2, special: true },
      key: 'emergencyHeatBodyDangerForecast', ph: 'wbgt', title: 'emergencyHeatTitle',
    },
    {
      j: { kind: 'strong_wind', severity: 'severe', metricValue: 22.4, special: false },
      key: 'emergencyStormBodyForecast', ph: 'wind', title: 'emergencyStormTitle',
    },
    {
      j: { kind: 'heavy_snow', severity: 'danger', metricValue: 6, special: false },
      key: 'emergencySnowBodyForecast', ph: 'snow', title: 'emergencySnowTitle',
    },
  ];

  for (const lang of ['ja', 'en', 'es', 'zh']) {
    it(`${lang}: 全種別で title/body/免責が ARB と一致し、現在値キーの文言を含まない`, () => {
      const arb = arbOf(lang);
      for (const c of cases) {
        const n = buildNotification(c.j, lang);
        const rounded = Math.round(c.j.metricValue).toString();
        // 暴風の {wind} は単位込み (アプリの m/s の設定と同じ「22\u00A0m/s」)。
        const v = c.ph === 'wind' ? `${rounded}\u00A0m/s` : rounded;
        expect(n.title).toBe(arb[c.title]);
        expect(n.body).toBe(`${fill(arb[c.key], c.ph, v)}\n${arb.emergencyDisclaimer}`);
        // 現在値用キー (現在形) の本文をそのまま使っていないこと
        const currentKey = c.key.replace(/Forecast$/, '');
        expect(n.body).not.toBe(`${fill(arb[currentKey], c.ph, v)}\n${arb.emergencyDisclaimer}`);
      }
      expect(disclaimerFor(lang)).toBe(arb.emergencyDisclaimer);
    });
  }

  it('ja 本文は公式アラート名 (熱中症警戒アラート等) を含まない (spec §12.10.4 / mri-spec §5.4)', () => {
    for (const c of cases) {
      const body = buildNotification(c.j, 'ja').body.split('\n')[0];
      expect(body).not.toMatch(/警戒アラート|特別警戒/);
    }
  });

  it('4 言語の *Forecast キーが ARB に揃っている (翻訳漏れなし)', () => {
    for (const lang of ['ja', 'en', 'es', 'zh']) {
      const arb = arbOf(lang);
      for (const k of [
        'emergencyHeatBodySevereForecast',
        'emergencyHeatBodyDangerForecast',
        'emergencyStormBodyForecast',
        'emergencySnowBodyForecast',
      ]) {
        expect(arb[k], `${lang}.${k}`).toBeTruthy();
        expect(arb[k]).not.toBe(arb[k.replace(/Forecast$/, '')]);
      }
    }
  });
});

describe('buildFcmMessage (プラットフォーム別の形。設計 §6)', () => {
  const n = buildNotification(
    { kind: 'heat_stroke', severity: 'danger', metricValue: 35.2, special: true },
    'ja',
  );

  it('Android 緊急: data-only + HIGH (notification ブロック無し)', () => {
    const m = buildFcmMessage({ fcmToken: 't', platform: 'android' }, n) as any;
    expect(m.token).toBe('t');
    expect(m.notification).toBeUndefined();
    expect(m.android.priority).toBe('HIGH');
    expect(m.data).toMatchObject({ kind: 'heat_stroke', type: 'emergency', severity: 'danger' });
    expect(m.apns).toBeUndefined();
  });

  it('iOS 緊急: notification + data のハイブリッド。danger は time-sensitive', () => {
    const m = buildFcmMessage({ fcmToken: 't', platform: 'ios' }, n) as any;
    expect(m.notification).toEqual({ title: n.title, body: n.body });
    expect(m.notification.body).toMatch(DISCLAIMER_MARK.ja);
    expect(m.apns.headers['apns-priority']).toBe('10');
    expect(m.apns.payload.aps['interruption-level']).toBe('time-sensitive');
    expect(m.data.type).toBe('emergency');
  });

  it('iOS severe は active (Time-Sensitive にしない)', () => {
    const sev = buildNotification(
      { kind: 'strong_wind', severity: 'severe', metricValue: 21, special: false },
      'en',
    );
    const m = buildFcmMessage({ fcmToken: 't', platform: 'ios' }, sev) as any;
    expect(m.apns.payload.aps['interruption-level']).toBe('active');
    expect(m.apns.payload.aps.sound).toBeUndefined();
  });

  it('パーソナル通知は従来どおり notification 付き (Android)', () => {
    const m = buildFcmMessage(
      { fcmToken: 't', platform: 'android' },
      { title: 'p', body: 'b', kind: 'uv_high' },
    ) as any;
    expect(m.notification).toEqual({ title: 'p', body: 'b' });
    expect(m.android.notification.channel_id).toBe('mrw_personal');
    expect(m.android.priority).toBe('NORMAL');
  });
});

// ──────────────────────────────────────────────────────────────────
// runEmergencyCheck: 走査 → 判定 → de-dup → 送信 (fetch モック)
// ──────────────────────────────────────────────────────────────────

/** 48h ぶんの穏やかな予報。wind で上書きして暴風を作る。 */
function calmForecast(windPeak = 3) {
  const hours = 48;
  const time = Array.from({ length: hours }, (_, i) => {
    const d = new Date(Date.UTC(2026, 8, 15, 0, 0) + i * 3_600_000);
    return d.toISOString().slice(0, 16);
  });
  const z = () => Array(hours).fill(0);
  const wind = z();
  wind[5] = windPeak;
  return {
    hourly: {
      time,
      temperature_2m: Array(hours).fill(20),
      relative_humidity_2m: Array(hours).fill(50),
      shortwave_radiation: z(),
      wind_speed_10m: wind,
      wind_gusts_10m: wind,
      snowfall: z(),
      snow_depth: z(),
      pressure_msl: Array(hours).fill(1013),
      uv_index: z(),
    },
    daily: {
      time: [time[0].slice(0, 10), time[24].slice(0, 10)],
      snowfall_sum: [0, 0],
      wind_speed_10m_max: [windPeak, 0],
      wind_gusts_10m_max: [windPeak, 0],
      temperature_2m_max: [20, 20],
      uv_index_max: [0, 0],
    },
  };
}

class MemoryKv {
  store = new Map<string, string>();
  ttl = new Map<string, number>();
  async get(k: string) {
    return this.store.get(k) ?? null;
  }
  async put(k: string, v: string, opt?: { expirationTtl?: number }) {
    this.store.set(k, v);
    if (opt?.expirationTtl) this.ttl.set(k, opt.expirationTtl);
  }
}

function subDoc(uid: string, over: Record<string, unknown> = {}) {
  return {
    name: subscriptionDocumentName(PROJECT, uid),
    fields: {
      fcmToken: { stringValue: `tok_${uid}` },
      platform: { stringValue: 'android' },
      locale: { stringValue: 'ja' },
      lat: { doubleValue: 35.7 },
      lon: { doubleValue: 139.7 },
      updatedAt: { timestampValue: '2026-09-10T00:00:00.000Z' },
      ...over,
    },
  };
}

interface Harness {
  env: Env;
  kv: MemoryKv;
  fcmCalls: Array<{ token: string; message: any }>;
  deletes: string[];
  forecastCalls: number;
  queryBodies: any[];
}

function setup(opts: {
  pages: Array<ReturnType<typeof subDoc>[]>;
  windPeak?: number;
  fcmStatus?: (token: string) => number;
}): Harness {
  const kv = new MemoryKv();
  const h: Harness = {
    env: {
      OPEN_METEO_BASE: 'https://api.open-meteo.test/v1/forecast',
      FIRESTORE_PROJECT_ID: PROJECT,
      FIREBASE_SA_JSON: '{"client_email":"x","private_key":"y"}',
      ALERT_DEDUPE: kv as unknown as KVNamespace,
    },
    kv,
    fcmCalls: [],
    deletes: [],
    forecastCalls: 0,
    queryBodies: [],
  };
  const pageSize = 200;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: string | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes('open-meteo.test')) {
        h.forecastCalls += 1;
        return new Response(JSON.stringify(calmForecast(opts.windPeak ?? 3)), { status: 200 });
      }
      if (url.endsWith(':runQuery')) {
        const body = JSON.parse(init!.body as string);
        h.queryBodies.push(body);
        const idx = h.queryBodies.length - 1;
        const docs = opts.pages[idx] ?? [];
        // ページを pageSize に満たない件数で返せば最終ページ扱いになる。
        // 複数ページのテストでは前ページを pageSize 件に水増しする。
        const rows = docs.map((d) => ({ document: d, readTime: 'x' }));
        if (idx < opts.pages.length - 1) {
          while (rows.length < pageSize) {
            const uid = `pad_${idx}_${rows.length}`;
            rows.push({ document: subDoc(uid), readTime: 'x' });
          }
        }
        return new Response(JSON.stringify([...rows, { readTime: 'x' }]), { status: 200 });
      }
      if (url.includes('fcm.googleapis.com')) {
        const message = JSON.parse(init!.body as string).message;
        h.fcmCalls.push({ token: message.token, message });
        const status = opts.fcmStatus?.(message.token) ?? 200;
        return new Response(status === 200 ? '{"name":"m"}' : '{"error":"x"}', { status });
      }
      if (init?.method === 'DELETE' && url.includes('/push_subscriptions/')) {
        h.deletes.push(url.split('/').pop()!);
        return new Response('{}', { status: 200 });
      }
      throw new Error(`unexpected fetch: ${url}`);
    }),
  );
  return h;
}

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  vi.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('runEmergencyCheck', () => {
  it('購読 0 件なら何も送らない (未活性状態で無害)', async () => {
    const h = setup({ pages: [[]] });
    const r = await runEmergencyCheck(h.env, 'periodic', new Date('2026-09-15T00:00:00Z'));
    expect(r).toEqual({ scanned: 0, pushed: 0, invalidated: 0 });
    expect(h.fcmCalls).toEqual([]);
  });

  it('暴風 severe を購読者全員に送り、KV に種別×深刻度キーで記録', async () => {
    const h = setup({ pages: [[subDoc('a'), subDoc('b', { platform: { stringValue: 'ios' }, locale: { stringValue: 'en' } })]], windPeak: 22 });
    const r = await runEmergencyCheck(h.env, 'periodic', new Date('2026-09-15T00:00:00Z'));
    expect(r).toEqual({ scanned: 2, pushed: 2, invalidated: 0 });
    expect(h.fcmCalls.map((c) => c.token)).toEqual(['tok_a', 'tok_b']);
    expect(h.kv.store.has('a:strong_wind:severe')).toBe(true);
    expect(h.kv.ttl.get('a:strong_wind:severe')).toBe(3600);

    // Android は data-only、iOS はハイブリッド + 英語免責
    expect(h.fcmCalls[0].message.notification).toBeUndefined();
    expect(h.fcmCalls[1].message.notification.body).toMatch(DISCLAIMER_MARK.en);
    // FCM には FCM スコープのトークンを使う
    const fcmInit = (fetch as any).mock.calls.find((c: any[]) => String(c[0]).includes('fcm.googleapis'))[1];
    expect(fcmInit.headers.Authorization).toBe('Bearer fcm-token');
  });

  it('de-dup: 同種・同深刻度の 2 回目は送らない。深刻度が上がれば即時再送', async () => {
    const h = setup({ pages: [[subDoc('a')]], windPeak: 22 });
    await runEmergencyCheck(h.env, 'periodic');
    await runEmergencyCheck(h.env, 'periodic');
    expect(h.fcmCalls).toHaveLength(1);

    // danger (>= 30 m/s) に上がると別キーで再送
    vi.unstubAllGlobals();
    const h2 = setup({ pages: [[subDoc('a')]], windPeak: 31 });
    h2.kv.store = h.kv.store; // 同じ KV を引き継ぐ
    await runEmergencyCheck(h2.env, 'periodic');
    expect(h2.fcmCalls).toHaveLength(1);
    expect(h2.fcmCalls[0].message.data.dedupe).toBe('strong_wind:danger');
    expect(h2.fcmCalls[0].message.data.severity).toBe('danger');
  });

  it('同じ粗座標の購読者は Open-Meteo 取得を 1 回で共有する', async () => {
    const h = setup({ pages: [[subDoc('a'), subDoc('b'), subDoc('c', { lat: { doubleValue: 43.1 } })]] });
    await runEmergencyCheck(h.env, 'periodic');
    expect(h.forecastCalls).toBe(2);
  });

  it('200 件ページを跨いで走査し、2 ページ目にカーソルを渡す', async () => {
    const h = setup({ pages: [[subDoc('a')], [subDoc('z')]], windPeak: 22 });
    const r = await runEmergencyCheck(h.env, 'periodic');
    expect(r.scanned).toBe(201); // 1 ページ目 200 (水増し込み) + 2 ページ目 1
    expect(h.queryBodies).toHaveLength(2);
    expect(h.queryBodies[0].structuredQuery.startAt).toBeUndefined();
    expect(h.queryBodies[1].structuredQuery.startAt.before).toBe(false);
    expect(h.fcmCalls.at(-1)!.token).toBe('tok_z');
  });

  it('FCM 404 (UNREGISTERED) は購読を削除し invalidated に数える', async () => {
    const h = setup({
      pages: [[subDoc('dead'), subDoc('alive')]],
      windPeak: 22,
      fcmStatus: (t) => (t === 'tok_dead' ? 404 : 200),
    });
    const r = await runEmergencyCheck(h.env, 'periodic');
    expect(r).toEqual({ scanned: 2, pushed: 1, invalidated: 1 });
    expect(h.deletes).toEqual(['dead']);
    expect(h.kv.store.has('dead:strong_wind:severe')).toBe(false);
  });

  it('FCM 5xx は削除せず、KV にも記録しない (次回再試行)', async () => {
    const h = setup({ pages: [[subDoc('a')]], windPeak: 22, fcmStatus: () => 503 });
    const r = await runEmergencyCheck(h.env, 'periodic');
    expect(r).toEqual({ scanned: 1, pushed: 0, invalidated: 0 });
    expect(h.deletes).toEqual([]);
    expect(h.kv.store.size).toBe(0);
  });

  it('不変条件: 購読クエリと Env に課金・静音・上限の概念が無い', () => {
    const h = setup({ pages: [[]] });
    expect(Object.keys(h.env)).not.toContain('NOTIFICATION_PREFERENCES');
    const src = runEmergencyCheck.toString();
    expect(src).not.toMatch(/quietHours|dailyLimit|isPlus\s*&&|entitlement/);
  });
});

describe('evaluateStrongWind (locale 引き回し)', () => {
  it('locale=es で本文がスペイン語 + 免責', () => {
    const n = evaluateStrongWind(calmForecast(25) as any, 'es')!;
    expect(n.title).toBe('Alerta de viento violento');
    expect(n.body).toMatch(DISCLAIMER_MARK.es);
  });
});
