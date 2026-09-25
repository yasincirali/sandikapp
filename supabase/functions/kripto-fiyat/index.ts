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
// ── Yedek ───────────────────────────────────────────────────────────────────
// Binance'in HİÇBİR parçası yanıt vermezse (bölge engeli 451, kesinti)
// BtcTurk'ün tek çağrılık ticker'ı ile yalnızca TRY paritesi olan coin'ler
// güncellenir. USDT paritesindekiler o turda yazılmaz; istemci bayat görür.
//
// Yanıt `{ ok, katalog, yazilan, kaynak }`. Gövde `{ "dry_run": true }` →
// hesaplar, yazmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  btcturkFiyatlari,
  type BtcTurkTicker,
  type FiyatSatiri,
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

async function btcturkTicker(): Promise<BtcTurkTicker[] | null> {
  try {
    const res = await fetch('https://api.btcturk.com/api/v2/ticker', {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      console.error(`btcturk ticker: ${res.status}`);
      await res.body?.cancel();
      return null;
    }
    const body = await res.json();
    return Array.isArray(body?.data) ? body.data as BtcTurkTicker[] : null;
  } catch (e) {
    console.error('btcturk ticker: ag hatasi', e instanceof Error ? e.name : '');
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
      return jsonResponse({ ok: true, katalog: 0, yazilan: 0, kaynak: null });
    }

    const simdi = new Date();
    const { satirlar, basarili } = await gunSatirlariniCek(gunSembolParcalari(katalog));

    let fiyatlar: FiyatSatiri[];
    let kaynak: 'binance' | 'btcturk' | null;
    if (basarili > 0) {
      fiyatlar = fiyatlariHesapla(katalog, satirlar, simdi);
      kaynak = 'binance';
    } else {
      const ticker = await btcturkTicker();
      if (ticker === null) {
        return jsonResponse({ ok: false, reason: 'saglayici_yanitsiz' }, 502);
      }
      const { data: oncekiRows } = await client
        .from('kripto_fiyat')
        .select('kod, gun, gun_acilis_try');
      const onceki = new Map(
        (oncekiRows ?? []).map((r) => [
          String(r.kod),
          { gun: String(r.gun), acilis: r.gun_acilis_try as number | null },
        ]),
      );
      fiyatlar = btcturkFiyatlari(katalog, ticker, onceki, simdi);
      kaynak = 'btcturk';
    }

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
      kaynak,
    });
  } catch (e) {
    console.error('kripto-fiyat hatasi', e);
    return jsonResponse({ ok: false }, 500);
  }
});
