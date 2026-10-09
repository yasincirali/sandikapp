// Mevduat faiz ortalaması — TCMB EVDS'den haftalık çekim (0129).
//
// pg_cron cuma TR 10:15 (yedek pazartesi) `trigger_mevduat_faiz()` ile
// çağırır. `mevduat_faiz_ortalama` tablosundaki her vade diliminin
// `seri_kodu`nu EVDS'den okur, son geçerli haftayı yazar.
//
// ── Neden sunucuda ──────────────────────────────────────────────────────────
// yasin (2026-10-09): "performansı etkilemeyecek şekilde". İstemci EVDS'ye
// hiç gitmez (anahtar zaten yalnız sunucuda); formu açınca 5 satırlık
// tabloyu okur.
//
// ── Neden sektör ortalaması ─────────────────────────────────────────────────
// Bankaya özel tabela faizini yasal + ücretsiz veren kaynak yok; TCMB'nin
// banka bazlı tek serisi "fiilen uygulanan AZAMİ" (ayın en yüksek oranı,
// bir ay gecikmeli) ve varsayılan olarak şişkin olur. Ayrıntı 0129 başlığı.
//
// ── Uydurma sayı yok ────────────────────────────────────────────────────────
// Seri boş/aralık dışı/45 günden bayatsa o dilimin `yillik_faiz`i NULL'a
// çekilir ve `durum` nedeni söyler; istemci o dilimde varsayılan YAZMAZ.
//
// ── Modlar ──────────────────────────────────────────────────────────────────
// * gövdesiz / `source: cron` → çek ve yaz.
// * `dry_run: true` → çek, YAZMA; dilim başına sonucu döndür (seri kodu
//   denemesi için).
// * `catalog: "<grup kodu>"` (+ `q`) → EVDS seri listesini döndürür, hiçbir
//   şey yazmaz. TCMB kodu değiştirirse yeni kodu tahmin etmek yerine
//   katalogdan okumak için (fetch-inflation'daki aynı ders).

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { bayatMi, EVDS_BASE, seriAdresi, sonFaiz } from '../_shared/mevduat_faiz.ts';

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

type Dilim = { vade_dilimi: string; seri_kodu: string };
type Sonuc = {
  vade_dilimi: string;
  seri_kodu: string;
  yillik_faiz: number | null;
  veri_tarihi: string | null;
  durum: string;
};

async function evdsGetir(url: string, key: string): Promise<unknown> {
  const res = await fetch(url, {
    // Anahtar header'da: sorgu dizesinde günlüklere sızardı.
    headers: { key, Accept: 'application/json' },
    signal: AbortSignal.timeout(20_000),
  });
  const ham = await res.text();
  const ct = res.headers.get('content-type') ?? '';
  // EVDS adres değişince 200 + HTML döndürüyor (2026-09 dersi).
  if (!res.ok || !ct.includes('json') || ham.trimStart().startsWith('<')) {
    throw new Error(`evds ${res.status} ${ct}`);
  }
  return JSON.parse(ham);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const evdsApiKey = Deno.env.get('EVDS_API_KEY');
    // Ayrı secret açılmadı (0129 notu): EVDS işi TÜFE çekimiyle aynı secret.
    const cronSecret = Deno.env.get('INFLATION_FETCH_CRON_SECRET');

    const eksik = cronSecretZorunlu(cronSecret, 'INFLATION_FETCH_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }
    if (!evdsApiKey) {
      // Yarım entegrasyonla tabloyu bozmaktansa hiçbir şey yazma.
      return jsonResponse({ ok: false, reason: 'no_api_key', written: 0 });
    }

    let dryRun = false;
    let katalog: string | null = null;
    let filtre = '';
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.catalog === 'string' && /^[A-Za-z0-9._:-]{2,64}$/.test(body.catalog)) {
        katalog = body.catalog;
      }
      if (typeof body?.q === 'string' && body.q.length <= 40) filtre = body.q;
    } catch (_) { /* gövde opsiyonel */ }

    // ── Katalog (yalnız okur) ─────────────────────────────────────────────
    if (katalog) {
      const url = katalog === 'categories'
        ? `${EVDS_BASE}categories/type=json`
        : katalog.startsWith('groups:')
        ? `${EVDS_BASE}datagroups/mode=2&code=${katalog.slice(7)}&type=json`
        : `${EVDS_BASE}serieList/type=json&code=${katalog}`;
      try {
        const dizi = await evdsGetir(url, evdsApiKey) as Record<string, unknown>[];
        const q = filtre.toLocaleUpperCase('tr');
        const items = (Array.isArray(dizi) ? dizi : [])
          .filter((k) =>
            q.length === 0 ||
            [k['SERIE_CODE'], k['SERIE_NAME'], k['DATAGROUP_CODE'], k['DATAGROUP_NAME'],
              k['TOPIC_TITLE_TR'], k['CATEGORY_ID']].join(' ').toLocaleUpperCase('tr').includes(q)
          )
          .slice(0, 60)
          .map((k) => ({
            code: k['SERIE_CODE'] ?? k['DATAGROUP_CODE'] ?? k['CATEGORY_ID'],
            name: k['SERIE_NAME'] ?? k['DATAGROUP_NAME'] ?? k['TOPIC_TITLE_TR'],
            start: k['START_DATE'],
            end: k['END_DATE'],
          }));
        return jsonResponse({ ok: true, mode: 'catalog', items, written: 0 });
      } catch (e) {
        console.error('[mevduat-faiz] katalog istegi basarisiz:', e);
        return jsonResponse({ ok: false, mode: 'catalog', reason: 'evds_unreachable', written: 0 }, 502);
      }
    }

    // ── Çekim ──────────────────────────────────────────────────────────────
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data: dilimler, error: dErr } = await admin
      .from('mevduat_faiz_ortalama')
      .select('vade_dilimi, seri_kodu');
    if (dErr) throw dErr;

    const simdi = new Date();
    const sonuclar: Sonuc[] = [];
    // Sıralı: 5 istek, EVDS'yi paralel yüklemeye gerek yok.
    for (const d of (dilimler ?? []) as Dilim[]) {
      let s: Sonuc;
      try {
        const nokta = sonFaiz(await evdsGetir(seriAdresi(d.seri_kodu, simdi), evdsApiKey), d.seri_kodu);
        if (nokta === null) {
          s = { ...d, yillik_faiz: null, veri_tarihi: null, durum: 'seri_bos' };
        } else if (bayatMi(nokta.tarih, simdi)) {
          s = { ...d, yillik_faiz: null, veri_tarihi: nokta.tarih, durum: 'bayat' };
        } else {
          s = { ...d, yillik_faiz: nokta.faiz, veri_tarihi: nokta.tarih, durum: 'ok' };
        }
      } catch (e) {
        console.error(`[mevduat-faiz] ${d.seri_kodu} basarisiz:`, e);
        // Ağ hatasında ESKİ değer korunur (geçen haftanın ortalaması hâlâ
        // doğru bir bilgi); yalnız durum işaretlenir.
        s = { ...d, yillik_faiz: NaN, veri_tarihi: null, durum: 'evds_hata' };
      }
      sonuclar.push(s);
    }

    if (!dryRun) {
      const guncellendi = simdi.toISOString();
      for (const s of sonuclar) {
        const satir: Record<string, unknown> = { durum: s.durum, guncellendi };
        if (s.durum !== 'evds_hata') {
          satir.yillik_faiz = s.yillik_faiz;
          satir.veri_tarihi = s.veri_tarihi;
        }
        const { error } = await admin
          .from('mevduat_faiz_ortalama')
          .update(satir)
          .eq('vade_dilimi', s.vade_dilimi);
        if (error) throw error;
      }
    }

    return jsonResponse({
      ok: true,
      dry_run: dryRun,
      sonuclar: sonuclar.map((s) => ({
        ...s,
        yillik_faiz: Number.isFinite(s.yillik_faiz) ? s.yillik_faiz : null,
      })),
      written: dryRun ? 0 : sonuclar.length,
    });
  } catch (e) {
    // Ham hata metni yalnız günlüğe (2026-09-23 denetimi L2).
    console.error('[mevduat-faiz] beklenmeyen hata:', e);
    return jsonResponse({ ok: false, reason: 'internal_error' }, 500);
  }
});
