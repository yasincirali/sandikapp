// Kripto Katalog Edge Function — hangi coin'ler izlenebilir, hangi pariteden
//
// pg_cron ile saatte bir koşar (0074_kripto.sql). Binance'in işlemdeki
// sembollerini, 24 saatlik hacmini ve varlık adlarını/logolarını birleştirip
// `kripto_varlik` tablosunu yeniler. Tek kaynak Binance (kullanıcı kararı,
// 2026-09-25). Uygulamadaki kripto araması bu tabloda
// çalışır: kullanıcı yazarken dışarıya istek GİTMEZ.
//
// ── Evren (kullanıcıya önerilen varsayılan, 2026-09-25) ─────────────────────
// Binance'te TRY paritesi olan her coin + USDT paritesinin 24 saatlik
// hacmine göre ilk 250. Karar `_shared/kripto.ts` `katalogKur`'da.
//
// ── Maliyet ─────────────────────────────────────────────────────────────────
// Tur başına üç Binance çağrısı: exchangeInfo (ağırlık 20), tüm
// sembollerin ticker/24hr'si (80) ve varlık listesi. Saatte bir; dakikalık
// 6.000 ağırlık sınırının yanında önemsiz.
//
// ── Silme yok ───────────────────────────────────────────────────────────────
// Listeden düşen coin `aktif = false` olur, satırı silinmez: onu tutan
// kullanıcının varlığı hâlâ bu satırın adına/logosuna bakıyor. Fiyatı artık
// güncellenmez; istemci `guncellendi` üzerinden bayat gösterir.
//
// Yanıt `{ ok, toplam, try_paritesi, usdt_paritesi, adli }` — hata ayrıntısı,
// ham sağlayıcı yanıtı DÖNMEZ (CLAUDE.md sunucu kuralı).
// Gövde `{ "dry_run": true }` → hesaplar, yazmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  binanceGet,
  type BinanceSembol,
  binanceVarliklari,
  type HacimSatiri,
  katalogKur,
} from '../_shared/kripto.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

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
    const cronSecret = Deno.env.get('KRIPTO_CRON_SECRET');

    const eksik = cronSecretZorunlu(cronSecret, 'KRIPTO_CRON_SECRET');
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

    const [info, hacim, varliklar] = await Promise.all([
      binanceGet('/api/v3/exchangeInfo', { symbolStatus: 'TRADING', permissions: 'SPOT' }),
      binanceGet('/api/v3/ticker/24hr', { type: 'MINI' }),
      binanceVarliklari(),
    ]);
    const semboller = (info as { symbols?: BinanceSembol[] } | null)?.symbols;
    if (!Array.isArray(semboller) || semboller.length === 0) {
      // Binance yanıtsızken katalogu BOŞALTMA: mevcut satırlar geçerli kalır.
      return jsonResponse({ ok: false, reason: 'binance_yanitsiz' }, 502);
    }

    const katalog = katalogKur(
      semboller,
      Array.isArray(hacim) ? hacim as HacimSatiri[] : [],
      varliklar,
    );
    const ozet = {
      toplam: katalog.length,
      try_paritesi: katalog.filter((k) => k.parite === 'TRY').length,
      usdt_paritesi: katalog.filter((k) => k.parite === 'USDT').length,
      adli: katalog.filter((k) => k.ad !== null).length,
    };
    if (dryRun || katalog.length === 0) {
      return jsonResponse({ ok: katalog.length > 0, dry_run: dryRun, ...ozet });
    }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const simdi = new Date().toISOString();

    // Varlık listesi (ad/logo) bu turda gelmediyse o alanları EZME: bir
    // önceki turun adları boş değerden daha doğru.
    const satirlar = katalog.map((k) =>
      varliklar.length > 0
        ? { ...k, aktif: true, guncellendi: simdi }
        : {
          kod: k.kod,
          parite: k.parite,
          binance_sembol: k.binance_sembol,
          hacim_sirasi: k.hacim_sirasi,
          aktif: true,
          guncellendi: simdi,
        }
    );
    const { error: upErr } = await client
      .from('kripto_varlik')
      .upsert(satirlar, { onConflict: 'kod' });
    if (upErr) throw upErr;

    // Bu turda görülmeyen coin'ler pasif.
    const { error: pasifErr } = await client
      .from('kripto_varlik')
      .update({ aktif: false })
      .lt('guncellendi', simdi)
      .eq('aktif', true);
    if (pasifErr) throw pasifErr;

    return jsonResponse({ ok: true, ...ozet });
  } catch (e) {
    console.error('kripto-katalog hatasi', e);
    return jsonResponse({ ok: false }, 500);
  }
});
