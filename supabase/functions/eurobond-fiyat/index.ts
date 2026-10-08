// Eurobond Fiyat Edge Function — katalog + fiyat, hafta içi 20 dakikada bir
//
// pg_cron ile koşar (0124_eurobond.sql). Bir turda:
//   1. Ziraat eurobond tablosu → hangi ISIN'ler var, vade, döviz, banka
//      alış/satış (KİRLİ fiyat; bkz. `_shared/eurobond.ts` başı).
//   2. Katalogda olmayan ISIN için Frankfurt sembol adı → kupon oranı.
//      Kupon okunamazsa tahvil kataloğa GİRMEZ: kuponsuz işlemiş faiz
//      hesaplanamaz ve uydurulmaz.
//   3. Aktif katalogdaki her ISIN için Frankfurt son temiz fiyat.
//   4. `eurobond_fiyat` upsert.
//
// Kısmi başarı yazılır: Ziraat düşerse yalnız piyasa fiyatı, Frankfurt
// düşerse yalnız banka fiyatı güncellenir; düşen tarafın sütunları önceki
// ölçümle kalır (üzerine NULL yazılmaz). İstemci `guncellendi` /
// `banka_guncellendi`'ye bakıp "gecikmeli" gösterir.
//
// Yanıt `{ ok, katalog, banka, piyasa }`. Gövde `{ "dry_run": true }` →
// hesaplar, yazmaz. Hata gövdesine sağlayıcı yanıtı konmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  BF_API,
  bfAdiniCoz,
  bfFiyatiniCoz,
  type BankaSatiri,
  kuponSikligi,
  tahvilAdi,
  TARAYICI_UA,
  ZIRAAT_URL,
  ziraatTablosunuCoz,
} from '../_shared/eurobond.ts';

const ZAMAN_ASIMI_MS = 10_000;
const PARALEL = 6;

const corsHeaders = {
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function getir(url: string, json: boolean): Promise<unknown | string | null> {
  try {
    const r = await fetch(url, {
      headers: { 'User-Agent': TARAYICI_UA, Accept: json ? 'application/json' : 'text/html' },
      signal: AbortSignal.timeout(ZAMAN_ASIMI_MS),
    });
    if (!r.ok) return null;
    return json ? await r.json() : await r.text();
  } catch (_) {
    return null;
  }
}

async function paralel<T, R>(girdi: T[], n: number, f: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(girdi.length);
  let i = 0;
  await Promise.all(
    Array.from({ length: Math.min(n, girdi.length) }, async () => {
      while (i < girdi.length) {
        const k = i++;
        out[k] = await f(girdi[k]);
      }
    }),
  );
  return out;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    // Ayrı secret açılmadı (0124 notu): piyasa verisi işi kripto ile aynı
    // secret'ı kullanır.
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

    const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const simdi = new Date().toISOString();

    // 1) Banka tablosu
    const html = await getir(ZIRAAT_URL, false);
    const banka: BankaSatiri[] = typeof html === 'string' ? ziraatTablosunuCoz(html) : [];

    // 2) Katalog: eksik ISIN'ler için kupon
    const { data: katRows, error: katErr } = await client
      .from('eurobond_katalog')
      .select('isin, aktif');
    if (katErr) throw katErr;
    const bilinen = new Set((katRows ?? []).map((r) => String(r.isin)));
    const yeniler = banka.filter((b) => !bilinen.has(b.isin));
    const yeniKatalog = (await paralel(yeniler, PARALEL, async (b) => {
      const j = await getir(`${BF_API}/tradingview/symbols?symbol=XFRA:${b.isin}`, true);
      const ad = j && typeof j === 'object' ? (j as Record<string, unknown>).description : null;
      const c = typeof ad === 'string' ? bfAdiniCoz(ad) : null;
      // Ad içindeki vade yılı tablodaki vadeyle tutmuyorsa başka bir
      // tahvilin adı okunmuştur; yazılmaz.
      if (!c || String(c.vade_yili) !== b.vade.slice(0, 4)) return null;
      return {
        isin: b.isin,
        ad: tahvilAdi(c.kupon_orani, b.vade),
        para_birimi: b.para_birimi,
        kupon_orani: c.kupon_orani,
        vade: b.vade,
        ihrac_yili: c.ihrac_yili,
        kupon_sikligi: kuponSikligi(b.para_birimi),
        ihracci: 'hazine',
        aktif: true,
        guncellendi: simdi,
      };
    })).filter((x) => x !== null);

    if (!dryRun && yeniKatalog.length > 0) {
      const { error } = await client.from('eurobond_katalog').upsert(yeniKatalog, { onConflict: 'isin' });
      if (error) throw error;
    }
    const aktifIsinler = [
      ...(katRows ?? []).filter((r) => r.aktif).map((r) => String(r.isin)),
      ...yeniKatalog.map((k) => k!.isin),
    ];

    // 3) Piyasa fiyatı
    const piyasa = await paralel(aktifIsinler, PARALEL, async (isin) => {
      const j = await getir(`${BF_API}/data/price_information/single?isin=${isin}&mic=XFRA`, true);
      return { isin, f: bfFiyatiniCoz(j) };
    });

    // 4) Upsert — yalnız ölçülen sütunlar (düşen kaynak eski değerle kalır)
    const bankaHaritasi = new Map(banka.map((b) => [b.isin, b]));
    const satirlar = aktifIsinler.map((isin) => {
      const p = piyasa.find((x) => x.isin === isin)?.f ?? null;
      const b = bankaHaritasi.get(isin);
      const satir: Record<string, unknown> = { isin, guncellendi: simdi };
      if (p) Object.assign(satir, p);
      if (b) {
        Object.assign(satir, {
          banka_alis: b.banka_alis,
          banka_satis: b.banka_satis,
          banka_alis_getiri: b.banka_alis_getiri,
          banka_satis_getiri: b.banka_satis_getiri,
          banka_guncellendi: simdi,
        });
      }
      return { satir, olculdu: p !== null || b !== undefined };
    }).filter((x) => x.olculdu).map((x) => x.satir);

    if (!dryRun && satirlar.length > 0) {
      // Sütun kümesi satırdan satıra değişebilir; upsert gönderilen
      // sütunları yazar, eksik olanlara dokunmaz — her satır ayrı grup.
      const gruplar = new Map<string, Record<string, unknown>[]>();
      for (const s of satirlar) {
        const k = Object.keys(s).sort().join(',');
        gruplar.set(k, [...(gruplar.get(k) ?? []), s]);
      }
      for (const g of gruplar.values()) {
        const { error } = await client.from('eurobond_fiyat').upsert(g, { onConflict: 'isin' });
        if (error) throw error;
      }
    }

    const piyasaSayisi = piyasa.filter((x) => x.f !== null).length;
    if (banka.length === 0 && piyasaSayisi === 0) {
      return jsonResponse({ ok: false, reason: 'kaynaklar_yanitsiz' }, 502);
    }
    return jsonResponse({
      ok: true,
      dry_run: dryRun,
      katalog: aktifIsinler.length,
      yeni: yeniKatalog.length,
      banka: banka.length,
      piyasa: piyasaSayisi,
    });
  } catch (e) {
    console.error('eurobond-fiyat hatasi', e instanceof Error ? e.name : '');
    return jsonResponse({ ok: false }, 500);
  }
});
