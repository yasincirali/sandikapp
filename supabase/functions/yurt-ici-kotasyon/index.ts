// Yurt İçi Kotasyon Edge Function — altın ve döviz kotasyonunun gün içi kaydı
//
// pg_cron ile beş dakikada bir koşar (0101). truncgil'den uygulamanın
// gösterdiği TÜM altın ayarlarını ve TL dövizlerini okur, 5 dakikalık
// kovaya `yurt_ici_kotasyon`'a yazar.
//
// ── Neden (kullanıcı kararı, 2026-10-03) ───────────────────────────────────
// Hafta sonu Performans › GÜNLÜK'te dolar ve altın DÜMDÜZ çiziliyordu.
// Grafiğin şekli Yahoo'dan geliyor ve uluslararası piyasa Cumartesi 00:00 –
// Pazartesi 00:00 (TR) kapalı: seri Cuma'da bitiyor, Cumartesi'nin her
// slotu Cuma kapanışını taşıyor. Yurt içi kotasyon (Kapalıçarşı/bankalar)
// ise hafta sonu da fiyat veriyor — ama uygulama onun yalnızca ANLIK
// değerini biliyordu, gün içi geçmişini değil. Kullanıcı: "Evet bunu
// yapalım ama fiyat tutarlı ve doğru şeyi göstermeli."
//
// Kayıt sunucuda, çünkü cihazda örneklemek yalnızca uygulamanın AÇIK
// olduğu anları kapsar; Cumartesi öğleden sonra açılan uygulama sabahı
// hiç görmemiş olurdu.
//
// ── Neden her gün (yalnızca hafta sonu değil) ──────────────────────────────
// Kararı istemci verir (`FiyatKaynagi.yurtIciGunIciSekli`: uluslararası
// seri susmuşsa). Kaydı takvime bağlamak resmî tatilleri ve Yahoo'nun
// hafta içi düştüğü saatleri dışarıda bırakırdı. Maliyet: tur başına TEK
// HTTP isteği, ~18 satır; 10 günden eski satırlar aynı turda silinir.
//
// ── Secret ──────────────────────────────────────────────────────────────────
// `PRICE_ALERTS_CRON_SECRET` PAYLAŞILIR (emsal: bes-parametre ↔ TÜFE
// çekimi, 0089). İkisi de aynı kaynaktan (truncgil) salt-okur fiyat çeken
// işler; yeni secret iki sunucuda elle kurulum gerektirirdi.
//
// Yanıt `{ ok, yazilan, silinen }`. Gövde `{ "dry_run": true }` → okur,
// yazmaz. Hata gövdesine ayrıntı konmaz (CLAUDE.md "Sunucu").

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { yurtIciKotasyonlariCek } from '../_shared/live_prices.ts';

const corsHeaders = {
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

/// Saklama süresi. İstemci yalnızca BUGÜNÜ ister; 10 gün, uzun bayram
/// tatilinde de "dün ne oldu" teşhisine yetecek pay.
const SAKLAMA_GUN = 10;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');

    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const simdi = new Date();
    let satirlar;
    try {
      satirlar = await yurtIciKotasyonlariCek(simdi);
    } catch (e) {
      // Kaynak düştü: bu tur YAZMAZ. Boşluk istemcide "o slotta nokta yok"
      // olarak kalır ve önceki nokta taşınır — sahte nokta üretilmez.
      console.error('yurt-ici-kotasyon: truncgil okunamadi', e);
      return jsonResponse({ ok: false, reason: 'kaynak_yanitsiz' }, 502);
    }
    if (satirlar.length === 0) {
      return jsonResponse({ ok: false, reason: 'fiyat_yok' }, 502);
    }

    if (dryRun) {
      return jsonResponse({ ok: true, dry_run: true, yazilan: satirlar.length });
    }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const { error: upErr } = await client
      .from('yurt_ici_kotasyon')
      .upsert(satirlar, { onConflict: 'sembol,ts' });
    if (upErr) throw upErr;

    const sinir = new Date(simdi.getTime() - SAKLAMA_GUN * 86_400_000).toISOString();
    const { count, error: delErr } = await client
      .from('yurt_ici_kotasyon')
      .delete({ count: 'exact' })
      .lt('ts', sinir);
    if (delErr) throw delErr;

    return jsonResponse({ ok: true, yazilan: satirlar.length, silinen: count ?? 0 });
  } catch (e) {
    console.error('yurt-ici-kotasyon hatasi', e);
    return jsonResponse({ ok: false }, 500);
  }
});
