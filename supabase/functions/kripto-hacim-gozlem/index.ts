// Kripto Hacim Gözlem Edge Function — ALICI BASKISI VE HACİM
//
// pg_cron ile her gün TR 00:20 ve 06:20'de koşar (0108_kripto_hacim.sql).
// Portföylerde tutulan coinlerin Binance USDT paritesindeki günlük mumlarını
// okur; işlem hacmini ve alıcı payını `kripto_hacim_gunluk`'a yazar,
// olağandışı hacim günlerini `balina_olay`'a `kripto_hacim_*` türüyle işler.
// Kural ve hesap `_shared/hacim.ts`'te (hisse radarıyla aynı kural, kendi
// tabanıyla).
//
// ── Sınır ───────────────────────────────────────────────────────────────────
// Yalnız Binance'teki işlemler (kullanıcı kararı 2026-09-25); zincir üstü
// veri ve diğer borsalar yok. Alıcı payı "kimin aldığını" söylemez.
// USDT'nin kendisi (ve USDT paritesi olmayan coin) atlanır — satır uydurulmaz.
//
// ── Secret ──────────────────────────────────────────────────────────────────
// `PRICE_ALERTS_CRON_SECRET` PAYLAŞILIR (emsal 0101, 0107).
//
// Yanıt `{ ok, sembol, satir, olay, bos }`. Gövde `{ "dry_run": true }` →
// okur, yazmaz. Hata ayrıntısı DÖNMEZ.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import { gunEkle } from '../_shared/balina.ts';
import { binanceGet, KRIPTO_ONEKI, kriptoKodu } from '../_shared/kripto.ts';
import {
  ASGARI_KRIPTO_HACMI,
  binanceGunleri,
  bitenKriptoGunleri,
  HACIM_OLAY_PENCERE_GUN,
  hacimOlayi,
  paraHacmi,
} from '../_shared/hacim.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya; Allow-Origin yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const TUR_SEMBOL_USTU = 150;
const SAKLAMA_GUN = 400;
const YAZMA_PENCERE_GUN = 75;
/// İstenen günlük mum sayısı: 20 günlük ortalama + olay penceresi + pay.
const MUM_SAYISI = '90';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
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

    const client = createClient(supabaseUrl, serviceRoleKey);
    const simdi = new Date();
    const bugun = trGun(simdi);

    const { data: assetRows, error: assetErr } = await client
      .from('assets')
      .select('ticker')
      .eq('type', 'kripto')
      .like('ticker', `${KRIPTO_ONEKI}%`)
      .is('deleted_at', null);
    if (assetErr) throw assetErr;
    const kodlar = [
      ...new Set(
        (assetRows ?? [])
          .map((r) => kriptoKodu(String(r.ticker ?? '')))
          // USDT'nin USDT paritesi yoktur.
          .filter((k): k is string => k !== null && k !== 'USDT'),
      ),
    ].sort().slice(0, TUR_SEMBOL_USTU);

    if (kodlar.length === 0) {
      return jsonResponse({ ok: true, sembol: 0, satir: 0, olay: 0, bos: 0 });
    }

    const yazmaBasi = gunEkle(bugun, -YAZMA_PENCERE_GUN);
    const olayBasi = gunEkle(bugun, -HACIM_OLAY_PENCERE_GUN);
    const satirlar: Array<Record<string, unknown>> = [];
    const olaylar: Array<Record<string, unknown>> = [];
    const okunan: string[] = [];
    let bos = 0;

    // Binance ağırlık sınırı IP başına ortak; sıralı ve seyrek sor.
    const CONCURRENCY = 3;
    for (let i = 0; i < kodlar.length; i += CONCURRENCY) {
      const batch = kodlar.slice(i, i + CONCURRENCY);
      const sonuclar = await Promise.all(batch.map(async (kod) => ({
        kod,
        rows: await binanceGet('/api/v3/klines', {
          symbol: `${kod}USDT`,
          interval: '1d',
          limit: MUM_SAYISI,
          // Günlük mum İstanbul gece yarısında açılsın (kripto.ts ile aynı).
          timeZone: '3',
        }),
      })));
      for (const { kod, rows } of sonuclar) {
        const gunler = bitenKriptoGunleri(binanceGunleri(rows), simdi);
        if (gunler.length === 0) { bos += 1; continue; }
        const ticker = `${KRIPTO_ONEKI}${kod}`;
        okunan.push(ticker);
        for (let k = 0; k < gunler.length; k++) {
          const g = gunler[k];
          if (g.tarih >= yazmaBasi) {
            satirlar.push({
              ticker,
              tarih: g.tarih,
              kapanis: g.kapanis,
              para_hacmi: paraHacmi(g),
              alici_payi: g.aliciPayi,
            });
          }
          if (g.tarih >= olayBasi) {
            const o = hacimOlayi(gunler, k, 'kripto', ASGARI_KRIPTO_HACMI);
            if (o !== null) {
              olaylar.push({
                ticker,
                tarih: g.tarih,
                bildirime_deger: false,
                alici_payi: g.aliciPayi,
                ...o,
              });
            }
          }
        }
      }
    }

    if (dryRun) {
      return jsonResponse({
        ok: true, dry_run: true, sembol: okunan.length, satir: satirlar.length,
        olay: olaylar.length, bos,
      });
    }

    for (let i = 0; i < satirlar.length; i += 500) {
      const { error } = await client
        .from('kripto_hacim_gunluk')
        .upsert(satirlar.slice(i, i + 500), { onConflict: 'ticker,tarih' });
      if (error) throw error;
    }

    // Okunan coinlerin penceredeki kripto olayları silinip yeniden yazılır;
    // okunamayanın eski olaylarına dokunulmaz (hacim-gozlem ile aynı kural).
    for (let i = 0; i < okunan.length; i += 100) {
      const { error } = await client
        .from('balina_olay')
        .delete()
        .in('ticker', okunan.slice(i, i + 100))
        .in('tur', ['kripto_hacim_yukselis', 'kripto_hacim_dusus'])
        .gte('tarih', olayBasi);
      if (error) throw error;
    }
    for (let i = 0; i < olaylar.length; i += 500) {
      const { error } = await client
        .from('balina_olay')
        .upsert(olaylar.slice(i, i + 500), { onConflict: 'ticker,tarih' });
      if (error) throw error;
    }

    const { error: silErr } = await client
      .from('kripto_hacim_gunluk')
      .delete()
      .lt('tarih', gunEkle(bugun, -SAKLAMA_GUN));
    if (silErr) throw silErr;

    return jsonResponse({
      ok: true,
      sembol: okunan.length,
      satir: satirlar.length,
      olay: olaylar.length,
      // USDT paritesi olmayan ya da Binance'in yanıt vermediği coin sayısı.
      bos,
    });
  } catch (err) {
    console.error('kripto-hacim-gozlem', err);
    return jsonResponse({ ok: false }, 500);
  }
});
