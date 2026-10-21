// workers/src/lib/fcm.ts
//
// FCM HTTP v1 経由でプッシュ送信する最小ラッパー。
// APNs 側は FCM が自動で APNs プロキシしてくれる前提。spec.md §12.4 の通知技術スタックに準拠。
//
// 認証: サービスアカウント JWT → OAuth2 アクセストークン (google-auth.ts, FCM_SCOPE)。
// Legacy Server Key は 2024 以降廃止のため使わない。
//
// プラットフォーム別の緊急通知の形 (docs/notification-delivery-design.md §6):
//   - Android: **data-only + priority HIGH**。background handler が端末側 l10n で表示する
//     (notification ブロックを付けると OS トレイ表示と端末表示が二重になるため付けない)。
//   - iOS    : **notification + data のハイブリッド**。APNs が OS レベルで直接表示するので
//     アプリ未起動・強制終了後でも届く。title/body はサーバー側フォールバック文言。

/** 緊急通知 (spec.md §12.2.1) */
export type EmergencyAlertKind = 'heat_stroke' | 'strong_wind' | 'heavy_snow';
/** パーソナル通知 (spec.md §12.2.3) */
export type PersonalAlertKindForFcm =
  | 'pressure_drop'
  | 'humidity_surge'
  | 'aqi_spike'
  | 'uv_high'
  | 'pollen_burst';

export type AlertKind = EmergencyAlertKind | PersonalAlertKindForFcm;

const EMERGENCY_KINDS: ReadonlySet<string> = new Set<EmergencyAlertKind>([
  'heat_stroke',
  'strong_wind',
  'heavy_snow',
]);

export function isEmergencyKind(kind: AlertKind): kind is EmergencyAlertKind {
  return EMERGENCY_KINDS.has(kind);
}

export interface Notification {
  title: string;
  body: string;
  kind: AlertKind;
  /** Time-Sensitive 対象か (iOS / 緊急 danger のみ) */
  critical?: boolean;
  /** ディープリンクや本文補強用の data payload (spec.md §12.7 パーソナル化) */
  data?: Record<string, string>;
}

export interface FcmTarget {
  fcmToken: string;
  /** iOS / android の判別。data-only / ハイブリッドと Time-Sensitive 設定の切替に使う */
  platform: 'ios' | 'android';
}

/** FCM HTTP v1 の message オブジェクトを組み立てる (純関数。テスト対象)。 */
export function buildFcmMessage(target: FcmTarget, notif: Notification): Record<string, unknown> {
  const emergency = isEmergencyKind(notif.kind);

  // spec.md §12.4「通知チャネル分離 (緊急 / 天気変化 / パーソナル / ライフスタイル)」
  const channelId = emergency
    ? 'mrw_emergency'
    : notif.critical
      ? 'mrw_emergency'
      : 'mrw_personal';

  const message: Record<string, unknown> = {
    token: target.fcmToken,
    // data は必ず全部 string (FCM v1 の制約)。kind は常に同梱する。
    data: { kind: notif.kind, ...(notif.data ?? {}) },
  };

  if (target.platform === 'android') {
    // 緊急は data-only (端末側 l10n 表示)。Doze 中も届くよう HIGH。
    // パーソナルは従来どおり notification 付き。
    if (!emergency) {
      message.notification = { title: notif.title, body: notif.body };
    }
    message.android = {
      priority: emergency || notif.critical ? 'HIGH' : 'NORMAL',
      ...(emergency ? {} : { notification: { channel_id: channelId } }),
    };
    return message;
  }

  // iOS: ハイブリッド。OS が表示するので title/body を必ず載せる。
  message.notification = { title: notif.title, body: notif.body };
  message.apns = {
    headers: {
      'apns-priority': emergency || notif.critical ? '10' : '5',
    },
    payload: {
      aps: {
        // danger 級のみ Time-Sensitive (Critical Alerts は Apple 個別申請のため使わない)
        'interruption-level': notif.critical ? 'time-sensitive' : 'active',
        ...(notif.critical ? { sound: 'default' } : {}),
      },
    },
  };
  return message;
}

/** FCM HTTP v1 へ送信。 */
export async function sendFcm(
  accessToken: string,
  projectId: string,
  target: FcmTarget,
  notif: Notification,
): Promise<{ ok: boolean; status: number; body: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ message: buildFcmMessage(target, notif) }),
  });

  return { ok: res.ok, status: res.status, body: await res.text() };
}
