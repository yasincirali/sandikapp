// Observe TEFAS NAV Edge Function — FON NAV YAYIN ANI GÖZLEMİ
//
// pg_cron ile iş günleri TR 06:00–21:30 arası yarım saatte bir koşar
// (0063_tefas_nav_gozlem.sql). Portföylerde tutulan her fon kodu için
// TEFAS'ın son NAV satırını çeker; daha önce görülmemiş bir (kod, NAV
// tarihi) çifti ilk kez görüldüğünde `tefas_nav_gozlem`'e `ilk_gorulme =
// now()` ile yazar. İstemci fonun gün içi basamağını bu ana çapalar.
//
// ── Neden var ───────────────────────────────────────────────────────────────
// TEFAS yayın zaman damgası vermiyor; basamak sabit 10:00'daydı
// (TECHNICAL_DEBT.md "Fonun gün içi NAV basamağı SABİT bir saate çapalı").
// Damgayı dış kaynaktan beklemek yerine gözlemle üretiyoruz.
//
// ── Maliyet tasarımı ────────────────────────────────────────────────────────
//   · Kullanıcı başına değil KOD başına istek (bkz. price_history.ts aynı
//     ilke). 1000 kullanıcı 60 farklı fon tutuyorsa 60 istek.
//   · Bugün tarihli NAV'ı görülmüş kod o gün bir daha sorulmaz
//     (`sorulacakKodlar`). Yayın sonrası turlar ~0 istek.
//   · Tur başına en çok TUR_KOD_USTU kod, 4'lü paralel, 10 sn zaman aşımı.
//   · Tatil/hafta içi yayınsız günlerde her tur tam liste — kabul edilen
//     bedel; cron zaten hafta sonu koşmuyor.
//
// ── Yanıt ───────────────────────────────────────────────────────────────────
// `{ ok, checked, asked, sightings, skipped }` — hata mesajı, token, ham
// TEFAS yanıtı DÖNMEZ (CLAUDE.md sunucu kuralı).
//
// Gövde: `{ "dry_run": true }` → TEFAS'a sorar ama tabloya yazmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  fonKodlari,
  gozlemYeniMi,
  oncekiKontrol,
  sonNavSatiri,
  sorulacakKodlar,
  trGun,
} from '../_shared/tefas_nav.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
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

/// TEFAS'tan bir fonun son NAV satırı. Ağ/biçim hatasında `null` —
/// tek kodun başarısızlığı turu düşürmez.
async function tefasSonNav(kod: string) {
  try {
    const res = await fetch('https://www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/plain, */*',
        'User-Agent': USER_AGENT,
      },
      // periyod 1 = son 1 ay; en yeni satır yeter ama uç nokta daha kısasını
      // sunmuyor (Dart `_fetchPriceRow` ile aynı çağrı).
      body: JSON.stringify({ fonKodu: kod, dil: 'TR', periyod: 1 }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return sonNavSatiri(data?.resultList);
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
    const cronSecret = Deno.env.get('TEFAS_NAV_CRON_SECRET');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }
    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'TEFAS_NAV_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const now = new Date();
    const bugun = trGun(now);

    // 1) Portföylerdeki fon kodları — kod başına tek istek.
    const { data: assetRows, error: assetErr } = await client
      .from('assets')
      .select('ticker')
      .eq('type', 'fon')
      .like('ticker', 'TEFAS:%')
      // Silme fiziksel değil, damgalıdır (0027); silinmiş lot için sorma.
      .is('deleted_at', null);
    if (assetErr) throw assetErr;
    const kodlar = fonKodlari((assetRows ?? []).map((r) => String(r.ticker ?? '')));

    if (kodlar.length === 0) {
      return jsonResponse({ ok: true, checked: 0, asked: 0, sightings: 0, skipped: 0 });
    }

    // 2) Bilinen son NAV tarihleri (son 10 gün yeter: bir fonun NAV'ı en
    //    çok bayram tatili kadar eskir).
    const esik = new Date(now.getTime() - 10 * 24 * 60 * 60 * 1000);
    const { data: gozlemRows, error: gozlemErr } = await client
      .from('tefas_nav_gozlem')
      .select('fon_kodu, nav_tarihi')
      .in('fon_kodu', kodlar)
      .gte('nav_tarihi', trGun(esik));
    if (gozlemErr) throw gozlemErr;

    const bilinenSon = new Map<string, string>();
    for (const r of gozlemRows ?? []) {
      const kod = String(r.fon_kodu);
      const tarih = String(r.nav_tarihi);
      const eski = bilinenSon.get(kod);
      if (eski === undefined || tarih > eski) bilinenSon.set(kod, tarih);
    }
    const bugunGorulen = new Set(
      [...bilinenSon.entries()].filter(([, t]) => t >= bugun).map(([k]) => k),
    );

    // 3) Önceki tur zamanı — aralığın alt ucu.
    const { data: turRow } = await client
      .from('tefas_nav_tur')
      .select('son_tur')
      .eq('tek', true)
      .maybeSingle();
    const sonTur = turRow?.son_tur ? new Date(String(turRow.son_tur)) : null;
    const altUc = oncekiKontrol(sonTur, now);

    // 4) Sor.
    const sorulacak = sorulacakKodlar(kodlar, bugunGorulen);
    const CONCURRENCY = 4;
    const yeni: Array<{
      fon_kodu: string;
      nav_tarihi: string;
      ilk_gorulme: string;
      onceki_kontrol: string | null;
      nav: number;
    }> = [];

    for (let i = 0; i < sorulacak.length; i += CONCURRENCY) {
      const batch = sorulacak.slice(i, i + CONCURRENCY);
      const sonuclar = await Promise.all(
        batch.map(async (kod) => ({ kod, satir: await tefasSonNav(kod) })),
      );
      for (const { kod, satir } of sonuclar) {
        if (satir === null) continue;
        if (!gozlemYeniMi(satir, bilinenSon.get(kod))) continue;
        yeni.push({
          fon_kodu: kod,
          nav_tarihi: satir.tarih,
          ilk_gorulme: now.toISOString(),
          onceki_kontrol: altUc ? altUc.toISOString() : null,
          nav: satir.fiyat,
        });
      }
    }

    // 5) Yaz — bir kez; çakışmada dokunma (ilk görülme anı KORUNUR).
    if (!dryRun) {
      if (yeni.length > 0) {
        const { error: yazErr } = await client
          .from('tefas_nav_gozlem')
          .upsert(yeni, { onConflict: 'fon_kodu,nav_tarihi', ignoreDuplicates: true });
        if (yazErr) throw yazErr;
      }
      const { error: turErr } = await client
        .from('tefas_nav_tur')
        .upsert({ tek: true, son_tur: now.toISOString() }, { onConflict: 'tek' });
      if (turErr) throw turErr;
    }

    return jsonResponse({
      ok: true,
      dry_run: dryRun,
      checked: kodlar.length,
      asked: sorulacak.length,
      sightings: yeni.length,
      skipped: kodlar.length - sorulacak.length,
      bracketed: altUc !== null,
    });
  } catch (err) {
    // Hata ayrıntısı yalnızca sunucu günlüğünde; yanıt sabit.
    console.error('observe-tefas-nav', err);
    return jsonResponse({ ok: false }, 500);
  }
});
