// Kripto Fiyat Edge Function — tüm kripto fiyatları, dakikada bir, TEK turda
//
// pg_cron ile her dakika koşar (0074_kripto.sql). `kripto_varlik`'taki aktif
// coin'lerin TL fiyatını ve İstanbul gününün açılışını `kripto_fiyat`'a
// yazar. Uygulama, widget'lar ve (sonraki adımda) fiyat alarmları kripto
// fiyatını YALNIZCA bu tablodan okur.
//
// ── Neden dakikada bir ──────────────────────────────────────────────────────
// Uygulamanın fiyat nabzı 30 sn (`tazelik_ritmi.dart`). Kripto 7/24 hareket
// ediyor; bir dakikalık tazelik, nabzın her iki turundan birinde yeni sayı
// demek. Daha sıkı cron, Supabase çağrı kotasını harcar, ekranda fark
// yaratmaz.
//
// ── Maliyet ─────────────────────────────────────────────────────────────────
// Binance `ticker/tradingDay` 100 sembollük parçalar hâlinde; parça başına
// ağırlık en çok 200. ~300 coin'lik katalog ≈ 4 parça ≈ 800 / 6.000 ağırlık
// dakikada. Kullanıcı sayısı bu sayıyı DEĞİŞTİRMEZ.
//
// ── Yedek yok (kullanıcı kararı, 2026-09-25: "tamamen binanceten") ────────
// Binance'in hiçbir parçası yanıt vermezse (bölge engeli 451, kesinti) o
// tur hiçbir şey YAZMAZ; satırlar bir önceki ölçümle kalır ve istemci
// `guncellendi` 10 dakikayı geçince "gecikmeli" gösterir. Başka borsanın
// fiyatıyla sessizce karıştırmak, grafikte sahte basamak üretirdi.
//
// Yanıt `{ ok, katalog, yazilan }`. Gövde `{ "dry_run": true }` →
// hesaplar, yazmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  fiyatlariHesapla,
  gunSatirlariniCek,
  gunSembolParcalari,
  type Parite,
} from '../_shared/kripto.ts';

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

    const client = createClient(supabaseUrl, serviceRoleKey);
    const { data: katalogRows, error: katErr } = await client
      .from('kripto_varlik')
      .select('kod, parite, binance_sembol')
      .eq('aktif', true);
    if (katErr) throw katErr;
    const katalog = (katalogRows ?? []).map((r) => ({
      kod: String(r.kod),
      parite: r.parite as Parite,
      binance_sembol: String(r.binance_sembol),
    }));
    if (katalog.length === 0) {
      // Katalog henüz kurulmadı (kripto-katalog ilk turunu bekliyor).
      return jsonResponse({ ok: true, katalog: 0, yazilan: 0 });
    }

    const simdi = new Date();
    const { satirlar, basarili } = await gunSatirlariniCek(gunSembolParcalari(katalog));

    if (basarili === 0) {
      return jsonResponse({ ok: false, reason: 'binance_yanitsiz' }, 502);
    }
    const fiyatlar = fiyatlariHesapla(katalog, satirlar, simdi);

    if (!dryRun && fiyatlar.length > 0) {
      const { error: upErr } = await client
        .from('kripto_fiyat')
        .upsert(fiyatlar, { onConflict: 'kod' });
      if (upErr) throw upErr;
    }

    return jsonResponse({
      ok: true,
      dry_run: dryRun,
      katalog: katalog.length,
      yazilan: fiyatlar.length,
    });
  } catch (e) {
    console.error('kripto-fiyat hatasi', e);
    return jsonResponse({ ok: false }, 500);
  }
});
