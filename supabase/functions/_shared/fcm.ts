// FCM v1 gönderimi + Google servis hesabı erişim jetonu.
//
// Bu modül `analyze-signals/index.ts` içindeki aynı işi yapan yardımcıların
// paylaşılabilir hâlidir. `daily-brief` yazılırken çıkarıldı: ikinci bir
// fonksiyonun JWT imzalama kodunu kopyalaması, iki kopyanın zamanla
// ayrışması demekti.
//
// `analyze-signals` HENÜZ buraya taşınmadı — çalışan ve dağıtılmış bir
// fonksiyonu test edemeden düzenlemek riskli. Bir sonraki dokunuşta
// taşınmalı (bkz. TECHNICAL_DEBT.md).

export type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

function base64UrlEncode(input: string | Uint8Array) {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/// Servis hesabından OAuth2 erişim jetonu üretir (RS256 imzalı JWT bearer).
export async function createAccessToken(serviceAccount: ServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claimSet = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const unsignedToken = `${header}.${claimSet}`;
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );
  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(
    serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Google access token alinamadi: ${await response.text()}`);
  }
  return (await response.json()).access_token as string;
}

export type SendResult =
  | { ok: true }
  | { ok: false; rawText: string; shouldDeleteToken: boolean };

/// Tek bir cihaza görünür bildirim gönderir.
///
/// `notification` payload'ı kullanılır (data-only değil): uygulama kapalıyken
/// de sistem bildirimi gösterilsin diye. iOS'ta sessiz mesajların teslimi
/// garanti değildir.
export async function sendFcmNotification({
  accessToken,
  projectId,
  token,
  title,
  body,
  channelId,
  data,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  /// Android bildirim kanalı — istemcide aynı kimlikle kayıtlı olmalı,
  /// yoksa Android bildirimi varsayılan kanala düşürür ve kullanıcı bu
  /// tipi tek başına kapatamaz.
  channelId: string;
  data: Record<string, string>;
}): Promise<SendResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            // Brifing acil değil: `normal` öncelik pil dostu ve Android'in
            // "yüksek öncelik kötüye kullanımı" sayımına girmez.
            priority: 'normal',
            notification: {
              channel_id: channelId,
              sound: 'default',
              icon: 'ic_stat_sandik',
              color: '#F5A623',
            },
          },
          apns: {
            // apns-priority 5 = güç tasarrufu için ertelenebilir.
            // Brifing için doğrusu bu; `10` acil uyarılar içindir.
            headers: { 'apns-priority': '5', 'apns-push-type': 'alert' },
            payload: { aps: { sound: 'default' } },
          },
        },
      }),
    },
  );

  const rawText = await response.text();
  if (response.ok) return { ok: true };
  return {
    ok: false,
    rawText,
    shouldDeleteToken:
      response.status === 404 ||
      rawText.includes('UNREGISTERED') ||
      rawText.includes('INVALID_ARGUMENT'),
  };
}

/// Bildirim başlığındaki kısa varlık etiketi.
///
/// `analyze-signals` içindeki `shortLabel` ile aynı kural: kaynak ön ekleri
/// kullanıcıya hiçbir şey ifade etmez.
///   `TEFAS:AFO` → `AFO`   ·   `AGHOL.IS` → `AGHOL`   ·   `EURTRY=X` → adı
export function shortLabel(assetName: string, ticker: string): string {
  const t = (ticker ?? '').trim();
  if (t.endsWith('=X') || t === '') return assetName;
  const sade = t.includes(':') ? t.split(':').pop()! : t.replace(/\.IS$/i, '');
  return sade.length >= 2 ? sade : assetName;
}
