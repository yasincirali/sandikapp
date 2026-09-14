// `_shared/fcm.ts` sendFcmNotification — gövde şekli ve token silme kuralı.
//
// 2026-09-14: analyze-signals kendi `sendPush` kopyasını bırakıp buraya
// geçti. Kopyanın iki farkı seçenek oldu: `priority: 'high'` (Android high +
// APNs 10) ve `badge`. Varsayılan brifing davranışı (normal / 5 / rozetsiz)
// değişmemeli — bu test ikisini de kilitler. `fetch` sahtelenir; ağ yok.
//
//   deno test supabase/tests/fcm_send_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { sendFcmNotification } from '../functions/_shared/fcm.ts';

type Yakalanan = { url: string; body: Record<string, unknown> };

async function gonder(
  yanit: { status: number; text: string },
  ekstra: { priority?: 'high' | 'normal'; badge?: number } = {},
): Promise<{ yakalanan: Yakalanan; sonuc: Awaited<ReturnType<typeof sendFcmNotification>> }> {
  const orijinal = globalThis.fetch;
  let yakalanan: Yakalanan | undefined;
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    yakalanan = {
      url: String(url),
      body: JSON.parse(String(init?.body)) as Record<string, unknown>,
    };
    return Promise.resolve(new Response(yanit.text, { status: yanit.status }));
  }) as typeof fetch;
  try {
    const sonuc = await sendFcmNotification({
      accessToken: 'tok',
      projectId: 'proj',
      token: 'device-token',
      title: 'Başlık',
      body: 'Gövde',
      channelId: 'signal_channel',
      data: { type: 'signal_alert', asset_id: 'a1' },
      ...ekstra,
    });
    return { yakalanan: yakalanan!, sonuc };
  } finally {
    globalThis.fetch = orijinal;
  }
}

// deno-lint-ignore no-explicit-any
const mesaj = (y: Yakalanan) => (y.body as any).message;

Deno.test('varsayılan: normal öncelik, APNs 5, rozet yok (brifing davranışı)', async () => {
  const { yakalanan, sonuc } = await gonder({ status: 200, text: '{}' });
  assertEquals(sonuc.ok, true);
  assertEquals(yakalanan.url, 'https://fcm.googleapis.com/v1/projects/proj/messages:send');
  const m = mesaj(yakalanan);
  assertEquals(m.android.priority, 'normal');
  assertEquals(m.apns.headers['apns-priority'], '5');
  assertEquals(m.apns.payload.aps, { sound: 'default' });
  assertEquals(m.android.notification.channel_id, 'signal_channel');
  assertEquals(m.data, { type: 'signal_alert', asset_id: 'a1' });
});

Deno.test('sinyal: high öncelik, APNs 10, rozet sayısı', async () => {
  const { yakalanan } = await gonder({ status: 200, text: '{}' }, { priority: 'high', badge: 3 });
  const m = mesaj(yakalanan);
  assertEquals(m.android.priority, 'high');
  assertEquals(m.apns.headers['apns-priority'], '10');
  assertEquals(m.apns.payload.aps, { sound: 'default', badge: 3 });
});

Deno.test('rozet 0 da gönderilir (okunmamış kalmadı → rozet temizlenir)', async () => {
  const { yakalanan } = await gonder({ status: 200, text: '{}' }, { badge: 0 });
  assertEquals(mesaj(yakalanan).apns.payload.aps.badge, 0);
});

Deno.test('token silme kuralı iki kopyanın birleşimi', async () => {
  for (const [status, text, beklenen] of [
    [404, 'not found', true],
    [400, '{"error":{"status":"INVALID_ARGUMENT"}}', true],
    [400, 'UNREGISTERED', true],
    [400, 'registration-token-not-registered', true],
    [500, 'internal', false],
    [429, 'quota', false],
  ] as const) {
    const { sonuc } = await gonder({ status, text });
    assertEquals(sonuc.ok, false);
    if (!sonuc.ok) assertEquals(sonuc.shouldDeleteToken, beklenen, `${status} ${text}`);
  }
});
