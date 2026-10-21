// workers/src/lib/dedupe.ts
//
// 重複抑制 / レート制限(spec.md §12.3「同種類の通知は 1 時間以上の間隔」)。
// KV namespace: ALERT_DEDUPE
// key 設計: `${uid}:${key}`。key は AlertKind 単体、または緊急通知では
// 「kind:severity」(mri-spec §5.3: 深刻度エスカレーション時は即時再発火 = 別キー)。
// value: 直近送信時刻 ISO 文字列。TTL は種別ごとのクールダウン秒。

import type { AlertKind } from './fcm';

const COOLDOWN_SEC: Record<AlertKind, number> = {
  // 緊急
  heat_stroke: 6 * 60 * 60,  // 6h(spec.md §12.10: 当日/前日の 2 回想定)
  strong_wind: 1 * 60 * 60,  // 1h(§12.3 デフォルト)
  heavy_snow: 3 * 60 * 60,   // 3h(積雪は変化が遅いので長め)
  // パーソナル(spec.md §12.3「同種類の通知は 1 時間以上の間隔」を最低ラインに、特性に応じて延長)
  pressure_drop: 6 * 60 * 60,    // 気圧の波は半日単位 → 6h
  humidity_surge: 1 * 60 * 60,   // 短時間で変動するため §12.3 既定通り 1h
  aqi_spike: 3 * 60 * 60,        // PM2.5 ピークは数時間続く → 3h
  uv_high: 12 * 60 * 60,         // 1 日 1 回想定 → 12h(朝のみ送信)
  pollen_burst: 6 * 60 * 60,     // 同日内の重複を強めに抑制
};

export async function isCoolingDown(
  kv: KVNamespace,
  uid: string,
  key: string,
): Promise<boolean> {
  const v = await kv.get(`${uid}:${key}`);
  return v !== null;
}

export async function markSent(
  kv: KVNamespace,
  uid: string,
  key: string,
): Promise<void> {
  // key が「kind:severity」形式でも kind 部分でクールダウン秒を引く。
  const kind = key.split(':')[0] as AlertKind;
  await kv.put(`${uid}:${key}`, new Date().toISOString(), {
    expirationTtl: COOLDOWN_SEC[kind] ?? 60 * 60,
  });
}
