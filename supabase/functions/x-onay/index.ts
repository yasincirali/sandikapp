// x-onay — Telegram onay düğmesinin webhook'u (0146, 2026-10-13).
//
// Telegram oturumsuz çağırır; JWT doğrulaması KAPALI
// (`config.toml` → `[functions.x-onay] verify_jwt = false`). Kapıyı iki
// katman tutar:
//   1. `X-Telegram-Bot-Api-Secret-Token` başlığı = TELEGRAM_WEBHOOK_SECRET
//      (setWebhook'ta verilen; sabit zamanlı karşılaştırma).
//   2. Düğmeye basan kişi TELEGRAM_ADMIN_CHAT_ID (yalnız yasin).
// İkisinden biri tutmazsa 200 ve sessizlik: Telegram'a hata dönmek yeniden
// denemeye yol açar, saldırgana da bilgi vermez.
//
// Tek gönderim: satır `taslak → gonderiliyor` koşullu güncellemeyle
// kilitlenir; çift basış ya da Telegram'ın yeniden denemesi ikinci kez
// atamaz. X hata verirse `hata` olur, yeniden basılamaz (elle yeni taslak).

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sabitZamanliEsit } from '../_shared/cron_auth.ts';
import { hataOzeti } from '../_shared/ekstre_esleme.ts';
import { botModu, geriCagriCoz, type Kart, kartSvg, onaySuresiGectiMi, xeGonderir } from '../_shared/x_paylasim.ts';
import {
  telegramAyari,
  telegramCevapla,
  telegramSonucYaz,
  xKartliGonder,
  XHatasi,
  xKimligi,
} from '../_shared/x_istemci.ts';
import { pngCiz } from '../bildirim-karti/cizici.ts';

const TAMAM = () => new Response('ok', { status: 200 });

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response(null, { status: 405 });
  const tg = telegramAyari();
  if (!tg) return TAMAM();
  const baslik = req.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '';
  if (!sabitZamanliEsit(baslik, tg.gizli)) {
    console.warn('[x-onay] gizli baslik tutmadi');
    return TAMAM();
  }

  let guncelleme: Record<string, unknown>;
  try {
    guncelleme = await req.json();
  } catch {
    return TAMAM();
  }
  const cq = guncelleme?.callback_query as {
    id?: string;
    from?: { id?: number };
    data?: unknown;
    message?: { message_id?: number; caption?: string; text?: string; chat?: { id?: number } };
  } | undefined;
  if (!cq?.id) return TAMAM();
  if (String(cq.from?.id ?? '') !== tg.sohbet) {
    console.warn('[x-onay] yetkisiz kullanici');
    return TAMAM();
  }
  const istek = geriCagriCoz(cq.data);
  if (!istek) {
    await telegramCevapla(tg, cq.id, 'Tanınmayan işlem.');
    return TAMAM();
  }
  const eskiBaslik = cq.message?.caption ?? cq.message?.text ?? '';
  const mesajId = cq.message?.message_id;
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const sonucYaz = async (s: string) => {
    await telegramCevapla(tg, cq.id!, s);
    if (mesajId) await telegramSonucYaz(tg, mesajId, eskiBaslik, s);
  };

  try {
    const { data: g, error } = await db.from('x_gonderileri')
      .select('id, durum, metin, kart, olusturuldu').eq('id', istek.id).maybeSingle();
    if (error) throw error;
    if (!g) {
      await sonucYaz('Taslak bulunamadı.');
      return TAMAM();
    }
    if (g.durum !== 'taslak') {
      await telegramCevapla(tg, cq.id, `Bu taslak zaten işlendi (${g.durum}).`);
      return TAMAM();
    }

    if (istek.islem === 'reddet') {
      await db.from('x_gonderileri').update({ durum: 'reddedildi', karar_at: new Date().toISOString() })
        .eq('id', g.id).eq('durum', 'taslak');
      await sonucYaz('Reddedildi.');
      return TAMAM();
    }

    if (onaySuresiGectiMi(g.olusturuldu, new Date())) {
      await db.from('x_gonderileri').update({ durum: 'suresi_doldu', karar_at: new Date().toISOString() })
        .eq('id', g.id).eq('durum', 'taslak');
      await sonucYaz('Süresi geçti, veri bayat. Gönderilmedi.');
      return TAMAM();
    }

    // `otomatik` modda yeni taslaklar düğmesiz gelir; düğmesi olan eski bir
    // taslağa basılırsa onaylı gibi gönderilir.
    const mod = botModu(Deno.env.get('X_BOT_MODU') ?? 'kapali');
    if (!xeGonderir(mod)) {
      await db.from('x_gonderileri').update({ durum: 'onaylandi', karar_at: new Date().toISOString() })
        .eq('id', g.id).eq('durum', 'taslak');
      await sonucYaz('Onaylandı (taslak modu: X\'e gönderilmedi).');
      return TAMAM();
    }
    const kimlik = xKimligi();
    if (!kimlik) {
      await sonucYaz('X anahtarları tanımlı değil. Gönderilmedi.');
      return TAMAM();
    }

    // Kilit: yalnız bir istek `gonderiliyor`a geçirebilir.
    const { data: kilit, error: ke } = await db.from('x_gonderileri')
      .update({ durum: 'gonderiliyor', karar_at: new Date().toISOString() })
      .eq('id', g.id).eq('durum', 'taslak').select('id');
    if (ke) throw ke;
    if (!kilit?.length) {
      await telegramCevapla(tg, cq.id, 'Bu taslak zaten işleniyor.');
      return TAMAM();
    }

    try {
      let png: Uint8Array<ArrayBuffer> | null = null;
      try {
        png = await pngCiz(kartSvg(g.kart as Kart));
      } catch (e) {
        console.error('[x-onay] kart', hataOzeti(e));
      }
      const xId = await xKartliGonder(kimlik, g.metin, png);
      await db.from('x_gonderileri').update({ durum: 'gonderildi', x_id: xId, gonderildi_at: new Date().toISOString() })
        .eq('id', g.id);
      await sonucYaz(`Yayınlandı: https://x.com/i/status/${xId}`);
    } catch (e) {
      const neden = e instanceof XHatasi ? e.message : hataOzeti(e);
      console.error('[x-onay] gonderim', neden);
      await db.from('x_gonderileri').update({ durum: 'hata', hata: neden.slice(0, 200) }).eq('id', g.id);
      await sonucYaz(`Gönderilemedi (${neden}).`);
    }
    return TAMAM();
  } catch (e) {
    console.error('[x-onay]', hataOzeti(e));
    return TAMAM();
  }
});
