// Fon dağılımı — TEFAS varlık sınıfı yüzdeleri, günlük çekim (Fon X-Ray
// Katman B, 0131).
//
// pg_cron hafta içi TR 21:00 (yedek ertesi sabah 07:30)
// `trigger_fon_dagilim()` ile çağırır. Fon tipi başına (YAT, EMK, BYF) TEK
// istekle bütün evrenin son 5 gününü alır, fon başına en yeni satırı
// `fon_dagilimlari`'na yazar.
//
// ── Neden sunucuda ──────────────────────────────────────────────────────────
// TEFAS dakikada ~6 istek kabul ediyor; istemci her varlık ekranında
// gitseydi sınır kullanıcı sayısıyla büyürdü. Burada günde 3 istek.
//
// ── Bozulmama ───────────────────────────────────────────────────────────────
//   · Kaynak boş/hatalı dönerse (Java boş metni, WAF sayfası, zaman aşımı)
//     o fon tipi için HİÇBİR ŞEY yazılmaz ve hiçbir satır SİLİNMEZ: kart
//     dünkü dağılımı tarihiyle göstermeye devam eder.
//   · Daha yeni tarihli satırın üstüne eski tarihli yazılmaz (`yazilacaklar`).
//
// ── Yanıt ───────────────────────────────────────────────────────────────────
// `{ ok, dry_run, tipler: {YAT: {durum, fon}}, yazilan }` — `error.message`,
// ham TEFAS yanıtı dönmez (CLAUDE.md sunucu kuralı).
//
// Gövde: `{ "dry_run": true }` → TEFAS'a sorar, tabloya yazmaz.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  ayristir,
  Ayristirma,
  DagilimSatiri,
  enYeniSatirlar,
  FON_TIPLERI,
  FonTipi,
  ISTEK_BASLIKLARI,
  istekGovdesi,
  pencere,
  TEFAS_DAGILIM_URL,
  yazilacaklar,
} from '../_shared/fon_dagilim.ts';

// Testler ve okuyan için: saf çekirdek bu dosyadan da görünür.
export { ayristir, enYeniSatirlar } from '../_shared/fon_dagilim.ts';

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

/// TEFAS ~6 istek/dk: istekler arası 11 sn (tefas-fon'un ölçülmüş aralığı).
const ISTEK_ARASI_MS = 11_000;

async function tefasCek(tip: FonTipi, bas: string, bit: string): Promise<Ayristirma> {
  try {
    const res = await fetch(TEFAS_DAGILIM_URL, {
      method: 'POST',
      headers: ISTEK_BASLIKLARI,
      body: JSON.stringify(istekGovdesi(tip, bas, bit)),
      signal: AbortSignal.timeout(40_000),
    });
    const ham = await res.text();
    if (!res.ok) {
      console.error(`[fon-dagilim] ${tip} HTTP ${res.status}`);
      return { durum: 'hata', satirlar: [] };
    }
    return ayristir(ham, tip);
  } catch (e) {
    console.error(`[fon-dagilim] ${tip} istek basarisiz:`, e instanceof Error ? e.name : 'hata');
    return { durum: 'hata', satirlar: [] };
  }
}

/// Tablodaki (fon_kodu → tarih). PostgREST yanıtı 1000 satırla sınırlı.
async function mevcutTarihler(client: SupabaseClient): Promise<Map<string, string>> {
  const m = new Map<string, string>();
  for (let bas = 0; ; bas += 1000) {
    const { data, error } = await client
      .from('fon_dagilimlari')
      .select('fon_kodu, tarih')
      .order('fon_kodu')
      .range(bas, bas + 999);
    if (error) throw error;
    for (const r of data ?? []) m.set(String(r.fon_kodu), String(r.tarih));
    if (!data || data.length < 1000) return m;
  }
}

async function yaz(client: SupabaseClient, satirlar: DagilimSatiri[]): Promise<number> {
  const alindi = new Date().toISOString();
  let n = 0;
  for (let i = 0; i < satirlar.length; i += 500) {
    // Kolonlar açıkça: `fon_unvan` ayrıştırıcının yan ürünü, tabloda yok.
    const parca = satirlar.slice(i, i + 500).map((s) => ({
      fon_kodu: s.fon_kodu,
      fon_tipi: s.fon_tipi,
      tarih: s.tarih,
      dagilim: s.dagilim,
      alindi,
    }));
    const { error } = await client.from('fon_dagilimlari').upsert(parca, { onConflict: 'fon_kodu' });
    if (error) throw error;
    n += parca.length;
  }
  return n;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // Ayrı secret açılmadı (0131 notu): TEFAS gözlemiyle aynı secret.
    const cronSecret = Deno.env.get('TEFAS_NAV_CRON_SECRET');
    const eksik = cronSecretZorunlu(cronSecret, 'TEFAS_NAV_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const [bas, bit] = pencere(new Date());
    const tipler: Record<string, { durum: string; fon: number }> = {};
    const hepsi: DagilimSatiri[] = [];
    for (let i = 0; i < FON_TIPLERI.length; i++) {
      if (i > 0) await new Promise((r) => setTimeout(r, ISTEK_ARASI_MS));
      const tip = FON_TIPLERI[i];
      const a = await tefasCek(tip, bas, bit);
      const yeni = enYeniSatirlar(a.satirlar);
      tipler[tip] = { durum: a.durum, fon: yeni.length };
      hepsi.push(...yeni);
    }

    // Hiçbir tip veri vermediyse dokunma: tablo dünkü hâliyle kalır.
    if (hepsi.length === 0) {
      return jsonResponse({ ok: false, reason: 'kaynak_bos', dry_run: dryRun, tipler, yazilan: 0 }, 502);
    }

    const satirlar = enYeniSatirlar(hepsi);
    if (dryRun) {
      return jsonResponse({
        ok: true,
        dry_run: true,
        tipler,
        // Yalnız kamu verisi: ilk üç fonun satırı örnek.
        ornek: satirlar.slice(0, 3).map(({ fon_kodu, tarih, dagilim }) => ({ fon_kodu, tarih, dagilim })),
        yazilan: 0,
      });
    }

    const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const yazilacak = yazilacaklar(satirlar, await mevcutTarihler(client));
    const yazilan = await yaz(client, yazilacak);
    return jsonResponse({ ok: true, dry_run: false, tipler, yazilan });
  } catch (e) {
    // Ham hata metni yalnız günlüğe (2026-09-23 denetimi L2).
    console.error('[fon-dagilim] beklenmeyen hata:', e instanceof Error ? e.name : 'hata');
    return jsonResponse({ ok: false, reason: 'internal_error' }, 500);
  }
});
