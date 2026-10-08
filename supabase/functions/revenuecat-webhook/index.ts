// RevenueCat Webhook Edge Function — PREMIUM HAKKI (0116, 2026-10-05)
//
// RevenueCat her abonelik olayında (ilk satın alma, yenileme, iptal, iade,
// süre bitimi, aktarma) buraya POST eder. Olay yalnızca "bu kullanıcılara
// bak" sinyalidir: her kullanıcının güncel `premium` hakkı RevenueCat API'sinden
// okunup `premium_haklari`'na (kaynak `revenuecat`) yazılır. Gerekçe:
// `_shared/premium.ts` başı (sırasız/tekrarlı olay).
//
// ── Yetki ───────────────────────────────────────────────────────────────────
// RevenueCat panelinde webhook'a sabit bir Authorization değeri girilir:
// `Bearer <REVENUECAT_WEBHOOK_SECRET>`. Gateway bu değeri JWT sanıp reddetmesin
// diye fonksiyon `verify_jwt = false` ile dağıtılır (config.toml); kapı bu
// secret'tır, FAIL-CLOSED (tanımsızsa 503, emsal `cronSecretZorunlu`).
// Karşılaştırma sabit zamanlı.
//
// ── Secret'lar (iki projede function secret) ────────────────────────────────
//   REVENUECAT_WEBHOOK_SECRET  webhook kapısı (rastgele, uzun)
//   REVENUECAT_API_KEY         RevenueCat "secret API key" (sk_…), yalnız okuma
//
// Yanıt `{ ok, kullanici, yazilan }`. Hata ayrıntısı, anahtar ya da
// RevenueCat yanıtı DÖNMEZ (yalnız sunucu günlüğü). 5xx → RevenueCat yeniden
// dener; bu yüzden geçici hata 500, kalıcı "işlenecek bir şey yok" 200.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, sabitZamanliEsit } from '../_shared/cron_auth.ts';
import { etkilenenKullanicilar, revenueCatHakki } from '../_shared/premium.ts';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const RC_API = 'https://api.revenuecat.com/v1/subscribers/';

Deno.serve(async (request) => {
  if (request.method !== 'POST') return jsonResponse({ ok: false }, 405);

  try {
    const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
    const eksik = cronSecretZorunlu(secret, 'REVENUECAT_WEBHOOK_SECRET');
    if (eksik) return eksik;
    const auth = request.headers.get('Authorization') ?? '';
    if (!sabitZamanliEsit(auth, `Bearer ${secret}`)) {
      return jsonResponse({ ok: false }, 401);
    }

    const apiKey = Deno.env.get('REVENUECAT_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!apiKey || !supabaseUrl || !serviceRoleKey) {
      console.error('revenuecat-webhook: REVENUECAT_API_KEY / SUPABASE_* eksik');
      return jsonResponse({ ok: false }, 503);
    }

    let body: unknown = null;
    try { body = await request.json(); } catch (_) { /* aşağıda boş sayılır */ }
    const kullanicilar = etkilenenKullanicilar(body);
    if (kullanicilar.length === 0) {
      // Anonim satın alma ya da test olayı: yazılacak kimse yok, yeniden
      // denenmesin.
      return jsonResponse({ ok: true, kullanici: 0, yazilan: 0 });
    }

    const client: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);
    let yazilan = 0;
    for (const id of kullanicilar) {
      const r = await fetch(RC_API + encodeURIComponent(id), {
        headers: { Authorization: `Bearer ${apiKey}`, Accept: 'application/json' },
      });
      if (!r.ok) {
        console.error('revenuecat-webhook: subscribers', r.status);
        // Geçici olabilir: RevenueCat olayı yeniden göndersin.
        return jsonResponse({ ok: false }, 500);
      }
      const hak = revenueCatHakki(await r.json());
      if (hak === null) continue;

      // Silinmiş hesap: auth.users'ta yoksa FK yazmayı reddeder; kalıcı
      // durum, atla.
      const { error } = await client.from('premium_haklari').upsert({
        user_id: id,
        kaynak: 'revenuecat',
        urun: hak.urun,
        magaza: hak.magaza,
        bitis: hak.bitis,
        iptal_edildi: hak.iptal_edildi,
        sandbox: hak.sandbox,
        guncellendi: new Date().toISOString(),
      }, { onConflict: 'user_id,kaynak' });
      if (error) {
        if (error.code === '23503') continue;
        throw error;
      }
      yazilan += 1;
    }

    return jsonResponse({ ok: true, kullanici: kullanicilar.length, yazilan });
  } catch (err) {
    console.error('revenuecat-webhook', err);
    return jsonResponse({ ok: false }, 500);
  }
});
