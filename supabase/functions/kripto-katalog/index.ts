// Kripto Katalog Edge Function — hangi coin'ler izlenebilir, hangi pariteden
//
// pg_cron ile saatte bir koşar (0074_kripto.sql). Binance'in işlemdeki
// sembollerini ve CoinGecko'nun piyasa değeri sıralamasını birleştirip
// `kripto_varlik` tablosunu yeniler. Uygulamadaki kripto araması bu tabloda
// çalışır: kullanıcı yazarken dışarıya istek GİTMEZ.
//
// ── Evren (kullanıcıya önerilen varsayılan, 2026-09-25) ─────────────────────
// Binance'te TRY paritesi olan her coin + piyasa değerinde ilk 250 içinde
// olup USDT paritesi olanlar. Karar `_shared/kripto.ts` `katalogKur`'da.
//
// ── Maliyet ─────────────────────────────────────────────────────────────────
// Tur başına 1 Binance (exchangeInfo, ağırlık 20) + 1 CoinGecko çağrısı.
// Ayda ~720 CoinGecko çağrısı; Demo planın 10.000 sınırının çok altında.
//
// ── Silme yok ───────────────────────────────────────────────────────────────
// Listeden düşen coin `aktif = false` olur, satırı silinmez: onu tutan
// kullanıcının varlığı hâlâ bu satırın adına/logosuna bakıyor. Fiyatı artık
// güncellenmez; istemci `guncellendi` üzerinden bayat gösterir.
//
// Yanıt `{ ok, toplam, try_paritesi, usdt_paritesi, gecko }` — hata ayrıntısı,
// ham sağlayıcı yanıtı DÖNMEZ (CLAUDE.md sunucu kuralı).
// Gövde `{ "dry_run": true }` → hesaplar, yazmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  binanceGet,
  type BinanceSembol,
  type GeckoCoin,
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

/// Piyasa değerine göre ilk 250. Demo anahtarı varsa header'da; yoksa
/// anahtarsız denenir (daha sıkı kısıtlı ama günde bir çağrıya yeter).
/// Başarısızlıkta boş liste: katalog Binance verisiyle yine kurulur.
async function geckoIlk250(): Promise<GeckoCoin[]> {
  const key = Deno.env.get('COINGECKO_DEMO_KEY');
  const url = 'https://api.coingecko.com/api/v3/coins/markets' +
    '?vs_currency=try&order=market_cap_desc&per_page=250&page=1&sparkline=false';
  try {
    const res = await fetch(url, {
      headers: {
        Accept: 'application/json',
        ...(key ? { 'x-cg-demo-api-key': key } : {}),
      },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      console.error(`coingecko markets: ${res.status}`);
      await res.body?.cancel();
      return [];
    }
    const data = await res.json();
    return Array.isArray(data) ? data as GeckoCoin[] : [];
  } catch (e) {
    console.error('coingecko markets: ag hatasi', e instanceof Error ? e.name : '');
    return [];
  }
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

    const [info, gecko] = await Promise.all([
      binanceGet('/api/v3/exchangeInfo', { symbolStatus: 'TRADING', permissions: 'SPOT' }),
      geckoIlk250(),
    ]);
    const semboller = (info as { symbols?: BinanceSembol[] } | null)?.symbols;
    if (!Array.isArray(semboller) || semboller.length === 0) {
      // Binance yanıtsızken katalogu BOŞALTMA: mevcut satırlar geçerli kalır.
      return jsonResponse({ ok: false, reason: 'binance_yanitsiz' }, 502);
    }

    const katalog = katalogKur(semboller, gecko);
    const ozet = {
      toplam: katalog.length,
      try_paritesi: katalog.filter((k) => k.parite === 'TRY').length,
      usdt_paritesi: katalog.filter((k) => k.parite === 'USDT').length,
      gecko: gecko.length,
    };
    if (dryRun || katalog.length === 0) {
      return jsonResponse({ ok: katalog.length > 0, dry_run: dryRun, ...ozet });
    }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const simdi = new Date().toISOString();

    // CoinGecko yanıt vermediyse ad/logo/sıra alanlarını EZME: dünkü değerler
    // bugünkü "ad = kod" yedeğinden daha doğru.
    const satirlar = katalog.map((k) =>
      gecko.length > 0
        ? { ...k, aktif: true, guncellendi: simdi }
        : { kod: k.kod, parite: k.parite, binance_sembol: k.binance_sembol, aktif: true, guncellendi: simdi }
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
