// BIST Hisse Kataloğu Edge Function — borsada işlem gören tüm hisseler (0139)
//
// pg_cron her sabah çağırır (`trigger_bist_hisse_katalog()`). TradingView
// tarayıcısından evreni, KAP'tan Türkçe unvanları okur ve `bist_hisse`
// tablosunu yeniler. Uygulamanın hisse seçicisi ve araması bu tabloyu okur
// (gömülü listeye düşer). Gerekçe ve kaynak ölçümü `_shared/bist_katalog.ts`.
//
// ── Yazma kuralları ─────────────────────────────────────────────────────────
// · Yeni kod (halka arz) eklenir; adı KAP unvanından kısaltılır.
// · Var olan satırın ADI EZİLMEZ: kullanıcı o adı gördü; elle düzeltilmiş
//   adlar (seed) korunur.
// · Bu turda görülmeyen kod silinmez, `aktif = false` olur (kod değişti ya
//   da borsadan çıktı). Onu tutan kullanıcının kaydı etkilenmez; yalnız
//   seçicide/aramada çıkmaz.
// · Yanıt `ASGARI_HISSE`'den azsa tablo DEĞİŞMEZ (bozuk yanıt yüzlerce
//   hisseyi pasifleştirmesin).
//
// Secret: `INFLATION_FETCH_CRON_SECRET` paylaşılır (0129 emsali — kamu
// verisi okuyan cron; yeni secret yasin'in iki sunucuda elle kurmasını
// beklerdi). Fail-closed.
//
// Yanıt `{ ok, toplam, yeni, pasif, kapli, xu100 }` — hata ayrıntısı, ham
// sağlayıcı yanıtı DÖNMEZ (CLAUDE.md sunucu kuralı).
// Gövde `{ "dry_run": true }` → hesaplar, yazmaz; yeni kodları da döndürür.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  ASGARI_HISSE,
  evrenKur,
  kapUnvanlari,
  kisaAd,
  type TvSatiri,
} from '../_shared/bist_katalog.ts';

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

const UA = { 'User-Agent': 'Mozilla/5.0 (sandik bist-hisse-katalog)' };

async function tvTara(ek: Record<string, unknown>): Promise<TvSatiri[]> {
  const res = await fetch('https://scanner.tradingview.com/turkey/scan', {
    method: 'POST',
    headers: { ...UA, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      filter: [{ left: 'exchange', operation: 'equal', right: 'BIST' }],
      columns: ['name', 'description', 'type', 'subtype'],
      range: [0, 2000],
      ...ek,
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) return [];
  const j = await res.json() as { data?: { d?: unknown[] }[] };
  return (j.data ?? [])
    .map((x) => x.d)
    .filter((d): d is unknown[] => Array.isArray(d) && typeof d[0] === 'string')
    .map((d) => [d[0], d[1] ?? null, d[2] ?? null, d[3] ?? null] as TvSatiri);
}

async function kapGetir(): Promise<Map<string, string>> {
  try {
    const res = await fetch('https://www.kap.org.tr/tr/bist-sirketler', {
      headers: UA,
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) return new Map();
    return kapUnvanlari(await res.text());
  } catch (_) {
    return new Map();
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('INFLATION_FETCH_CRON_SECRET');

    const eksik = cronSecretZorunlu(cronSecret, 'INFLATION_FETCH_CRON_SECRET');
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

    const [hepsi, x100Satir, kap] = await Promise.all([
      tvTara({}).catch(() => [] as TvSatiri[]),
      tvTara({ symbols: { symbolset: ['SYML:BIST;XU100'] } }).catch(() => [] as TvSatiri[]),
      kapGetir(),
    ]);
    const evren = evrenKur(hepsi);
    if (evren.size < ASGARI_HISSE) {
      // Kaynak yanıtsız/yarım: katalogu DEĞİŞTİRME, mevcut satırlar geçerli.
      return jsonResponse({ ok: false, reason: 'kaynak_yetersiz', toplam: evren.size }, 502);
    }
    // XU100 kümesi 100 değilse (yarım yanıt) üyelik bilgisi bu tur yazılmaz.
    const x100 = new Set(x100Satir.map((r) => r[0]));
    const x100Gecerli = x100.size >= 90;

    const client = createClient(supabaseUrl, serviceRoleKey);
    const { data: mevcutSatir, error: okuErr } = await client
      .from('bist_hisse')
      .select('kod, ad, aktif');
    if (okuErr) throw okuErr;
    const mevcut = new Map(
      (mevcutSatir ?? []).map((r) => [String(r.kod), r as { ad: string; aktif: boolean }]),
    );

    const simdi = new Date().toISOString();
    const yeniKodlar: string[] = [];
    const satirlar = [...evren].map(([kod, tvAd]) => {
      const eski = mevcut.get(kod);
      if (!eski) yeniKodlar.push(kod);
      return {
        kod,
        ad: eski?.ad ?? kisaAd(kap.get(kod) ?? tvAd, kod),
        aktif: true,
        ...(x100Gecerli ? { xu100: x100.has(kod) } : {}),
        guncellendi: simdi,
      };
    });
    const pasiflesecek = [...mevcut].filter(([kod, r]) => r.aktif && !evren.has(kod))
      .map(([kod]) => kod);
    const ozet = {
      toplam: evren.size,
      yeni: yeniKodlar.length,
      pasif: pasiflesecek.length,
      kapli: [...evren.keys()].filter((k) => kap.has(k)).length,
      xu100: x100Gecerli ? x100.size : 0,
    };
    if (dryRun) {
      return jsonResponse({
        ok: true,
        dry_run: true,
        ...ozet,
        yeni_kodlar: yeniKodlar.slice(0, 50),
        pasif_kodlar: pasiflesecek.slice(0, 50),
      });
    }

    for (let i = 0; i < satirlar.length; i += 500) {
      const { error } = await client
        .from('bist_hisse')
        .upsert(satirlar.slice(i, i + 500), { onConflict: 'kod' });
      if (error) throw error;
    }
    if (pasiflesecek.length > 0) {
      const { error } = await client
        .from('bist_hisse')
        .update({ aktif: false, guncellendi: simdi })
        .in('kod', pasiflesecek);
      if (error) throw error;
    }

    return jsonResponse({ ok: true, ...ozet });
  } catch (e) {
    console.error('bist-hisse-katalog hatasi', e);
    return jsonResponse({ ok: false }, 500);
  }
});
