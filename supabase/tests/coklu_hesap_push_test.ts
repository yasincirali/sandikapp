// Çoklu hesap (0137) — cihazın PASİF hesaplarına giden bildirim.
//
// Sözleşme: (1) `hesap` verilmezse FCM gövdesi birebir eskisi (mağazadaki
// sürüm etkilenmez); (2) verilirse başlıkta hesap adı + `data.hesap_uid`;
// (3) RPC yoksa/hata verirse ek satır boş döner, birincil gönderim düşmez;
// (4) push gönderen her fonksiyon ek satırları okuyor (biri unutulursa o
// bildirim pasif hesaba hiç gitmez — sessiz arıza).
//
//   deno test supabase/tests/coklu_hesap_push_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { hesapliBaslik, sendFcmNotification } from '../functions/_shared/fcm.ts';
import { ekHesap, ekHesapSatirlari } from '../functions/_shared/push_tokens.ts';

async function yakala(hesap?: { uid: string; etiket: string }) {
  const orijinal = globalThis.fetch;
  let govde: Record<string, unknown> | undefined;
  globalThis.fetch = ((_u: string | URL | Request, init?: RequestInit) => {
    govde = JSON.parse(String(init?.body));
    return Promise.resolve(new Response('{}', { status: 200 }));
  }) as typeof fetch;
  try {
    await sendFcmNotification({
      accessToken: 't',
      projectId: 'p',
      token: 'tok',
      title: 'THYAO alım sinyali',
      body: 'Gövde',
      channelId: 'signal_channel',
      data: { type: 'signal_alert' },
      hesap,
    });
  } finally {
    globalThis.fetch = orijinal;
  }
  // deno-lint-ignore no-explicit-any
  return (govde as any).message;
}

Deno.test('hesap verilmezse gövde birebir eskisi', async () => {
  const m = await yakala();
  assertEquals(m.notification, { title: 'THYAO alım sinyali', body: 'Gövde' });
  assertEquals(m.data, { type: 'signal_alert' });
});

Deno.test('pasif hesap: başlıkta ad, veride hesap_uid', async () => {
  const m = await yakala({ uid: 'u2', etiket: 'ayse' });
  assertEquals(m.notification.title, 'ayse · THYAO alım sinyali');
  assertEquals(m.data, { type: 'signal_alert', hesap_uid: 'u2' });
});

Deno.test('uzun etiket kesilir, boş etiket başlığa dokunmaz', () => {
  assertEquals(hesapliBaslik('  ', 'X'), 'X');
  assertEquals(hesapliBaslik('a'.repeat(30), 'X'), `${'a'.repeat(23)}… · X`);
});

Deno.test('ekHesap yalnız etiketli satırda değer döner', () => {
  assertEquals(ekHesap({ user_id: 'u1' }), undefined);
  assertEquals(ekHesap({ user_id: 'u1', hesap_etiketi: null }), undefined);
  assertEquals(ekHesap({ user_id: 'u1', hesap_etiketi: 'veli' }), {
    uid: 'u1',
    etiket: 'veli',
  });
});

Deno.test('RPC hatası / eksik istemci boş liste döner', async () => {
  const hatali = {
    rpc: () => Promise.resolve({ data: null, error: { code: 'PGRST202', message: 'yok' } }),
  };
  assertEquals(await ekHesapSatirlari(hatali), []);
  const firlatan = { rpc: () => { throw new Error('ağ'); } };
  assertEquals(await ekHesapSatirlari(firlatan), []);
  // Boş kullanıcı listesi sunucuya hiç gitmez.
  let cagrildi = false;
  const izle = { rpc: () => { cagrildi = true; return Promise.resolve({ data: [], error: null }); } };
  assertEquals(await ekHesapSatirlari(izle, []), []);
  assertEquals(cagrildi, false);
});

Deno.test('RPC parametresi: kullanıcı süzgeci yalnız verilince', async () => {
  const gelen: unknown[] = [];
  const izle = {
    rpc: (fn: string, args?: Record<string, unknown>) => {
      gelen.push([fn, args]);
      return Promise.resolve({
        data: [{ token: 't', user_id: 'u', hesap_etiketi: 'ayse' }],
        error: null,
      });
    },
  };
  const s = await ekHesapSatirlari(izle, ['u']);
  assertEquals(s.length, 1);
  await ekHesapSatirlari(izle);
  assertEquals(gelen, [
    ['push_ek_hesap_hedefleri', { p_user_ids: ['u'] }],
    ['push_ek_hesap_hedefleri', {}],
  ]);
});

Deno.test('push gönderen her yüzey pasif hesap satırlarını okuyor', async () => {
  const kok = new URL('../functions/', import.meta.url);
  const dosyalar = [
    'analyze-signals/index.ts',
    'check-price-alerts/index.ts',
    'daily-brief/index.ts',
    'weekly-summary/index.ts',
    'calendar-nudge/index.ts',
    'temettu-yakala/index.ts',
    'send-partner-invite-push/index.ts',
    '_shared/watchlist_moves.ts',
    '_shared/tufe_push.ts',
  ];
  for (const d of dosyalar) {
    const kaynak = await Deno.readTextFile(new URL(d, kok));
    const gonderim = (kaynak.match(/sendFcmNotification\(\{/g) ?? []).length;
    const hesapli = (kaynak.match(/hesap: ekHesap\(/g) ?? []).length +
      (kaynak.match(/hesap: \(\(\) =>/g) ?? []).length;
    assertEquals(kaynak.includes('ekHesapSatirlari('), true, `${d}: ek satır okunmuyor`);
    assertEquals(hesapli, gonderim, `${d}: her gönderim hesap etiketini taşımalı`);
  }
});
