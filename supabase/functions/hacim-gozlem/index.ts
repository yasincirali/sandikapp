// Hacim Gözlem Edge Function — HİSSE HACİM RADARI
//
// pg_cron ile iş günleri TR 18:45 ve 22:45'te koşar (0104_hisse_hacim.sql).
// Portföylerde tutulan BIST hisselerinin günlük kapanış ve hacmini Yahoo'dan
// okur, `hisse_hacim_gunluk`'a yazar; kurala uyan günleri `balina_olay`'a
// `hisse_hacim_*` türüyle işler. Kural ve hesap `_shared/hacim.ts`'te.
//
// ── Sınır (kart da bunu yazar) ──────────────────────────────────────────────
// Hacim "kimin aldığını" söylemez; her işlemin bir alıcısı ve bir satıcısı
// vardır. Olay yönü akış değil FİYAT yönüdür. Aracı kurum dağılımı lisans
// ister (B5); o gelene kadar etiket "olağandışı hacim"dir, "balina" değil.
//
// ── Maliyet tasarımı ────────────────────────────────────────────────────────
//   · Kullanıcı başına değil SEMBOL başına istek (price_history.ts ilkesi).
//   · Tur başına en çok TUR_SEMBOL_USTU sembol, 4'lü paralel.
//   · Tek istek 3 aylık günlük seriyi verir: 20 günlük ortalama + 30 günlük
//     olay penceresi tek çağrıda dolar, geriye dönük doldurma gerekmez.
//
// ── Secret ──────────────────────────────────────────────────────────────────
// `PRICE_ALERTS_CRON_SECRET` PAYLAŞILIR (emsal: yurt-ici-kotasyon, 0101).
//
// Yanıt `{ ok, sembol, satir, olay, bos }`. Gövde `{ "dry_run": true }` →
// okur, yazmaz. Hata mesajı, token, ham Yahoo yanıtı DÖNMEZ.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import { gunEkle } from '../_shared/balina.ts';
import {
  bistSembolu,
  HACIM_OLAY_PENCERE_GUN,
  HacimGunu,
  hacimOlayi,
  paraHacmi,
  tamamlananGunler,
  yahooGunleri,
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

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Tur başına en fazla sembol; üstü sıralı kesilir (sonraki tur aynı kesim —
/// 200'den çok farklı hisse tutulursa burası büyütülür, sessizce dönmez).
const TUR_SEMBOL_USTU = 200;
const SAKLAMA_GUN = 400;
/// Yazılan geriye dönük gün (takvim): 20 işlem günü ortalama + olay penceresi.
const YAZMA_PENCERE_GUN = 75;

/// Bir hissenin 3 aylık günlük serisi. Hata/boşta `null` — tek sembolün
/// başarısızlığı turu düşürmez.
async function yahooSerisi(sembol: string): Promise<HacimGunu[] | null> {
  try {
    const url =
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sembol)}` +
      `?interval=1d&range=3mo&includePrePost=false`;
    const res = await fetch(url, {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return null;
    const body = await res.json();
    const gunler = yahooGunleri(body?.chart?.result?.[0]);
    return gunler.length > 0 ? gunler : null;
  } catch (_) {
    return null;
  }
}

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

    // 1) Portföylerdeki BIST hisseleri — sembol başına tek istek.
    const { data: assetRows, error: assetErr } = await client
      .from('assets')
      .select('ticker')
      .eq('type', 'hisse')
      .like('ticker', '%.IS')
      .is('deleted_at', null);
    if (assetErr) throw assetErr;
    const semboller = [
      ...new Set(
        (assetRows ?? []).map((r) => bistSembolu(String(r.ticker ?? ''))).filter((s) => s !== null),
      ),
    ].sort().slice(0, TUR_SEMBOL_USTU) as string[];

    if (semboller.length === 0) {
      return jsonResponse({ ok: true, sembol: 0, satir: 0, olay: 0, bos: 0 });
    }

    const yazmaBasi = gunEkle(bugun, -YAZMA_PENCERE_GUN);
    const olayBasi = gunEkle(bugun, -HACIM_OLAY_PENCERE_GUN);
    const satirlar: Array<Record<string, unknown>> = [];
    const olaylar: Array<Record<string, unknown>> = [];
    const okunan: string[] = [];
    let bos = 0;

    const CONCURRENCY = 4;
    for (let i = 0; i < semboller.length; i += CONCURRENCY) {
      const batch = semboller.slice(i, i + CONCURRENCY);
      const sonuclar = await Promise.all(
        batch.map(async (s) => ({ s, ham: await yahooSerisi(s) })),
      );
      for (const { s, ham } of sonuclar) {
        if (ham === null) { bos += 1; continue; }
        const gunler = tamamlananGunler(ham, simdi);
        okunan.push(s);
        for (let k = 0; k < gunler.length; k++) {
          const g = gunler[k];
          if (g.tarih >= yazmaBasi) {
            satirlar.push({
              ticker: s,
              tarih: g.tarih,
              kapanis: g.kapanis,
              hacim: g.hacim,
              para_hacmi: paraHacmi(g),
            });
          }
          if (g.tarih >= olayBasi) {
            const o = hacimOlayi(gunler, k);
            if (o !== null) {
              olaylar.push({ ticker: s, tarih: g.tarih, bildirime_deger: false, ...o });
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
        .from('hisse_hacim_gunluk')
        .upsert(satirlar.slice(i, i + 500), { onConflict: 'ticker,tarih' });
      if (error) throw error;
    }

    // Okunan hisselerin penceredeki hisse olayları silinip yeniden yazılır:
    // Yahoo'nun sonradan düzelttiği bar artık kurala uymuyorsa asılı kalmasın.
    // Okunamayan hissenin eski olaylarına DOKUNULMAZ.
    for (let i = 0; i < okunan.length; i += 100) {
      const { error } = await client
        .from('balina_olay')
        .delete()
        .in('ticker', okunan.slice(i, i + 100))
        .in('tur', ['hisse_hacim_yukselis', 'hisse_hacim_dusus'])
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
      .from('hisse_hacim_gunluk')
      .delete()
      .lt('tarih', gunEkle(bugun, -SAKLAMA_GUN));
    if (silErr) throw silErr;

    return jsonResponse({
      ok: true,
      sembol: okunan.length,
      satir: satirlar.length,
      olay: olaylar.length,
      // Yahoo'nun yanıt vermediği sembol sayısı; yüksekse kaynak sorunludur.
      bos,
    });
  } catch (err) {
    console.error('hacim-gozlem', err);
    return jsonResponse({ ok: false }, 500);
  }
});
