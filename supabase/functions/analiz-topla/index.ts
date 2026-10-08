// Analiz Topla Edge Function — BATCH SONUÇLARINI YAYINA ALIR (Balina F2, 0117)
//
// pg_cron saatte bir (:25) çağırır. `analiz_batch`'te `gonderildi` durumunda
// bekleyen her batch'i Anthropic'e sorar; bitmişse her sonucu kapıdan geçirip
// (`kapidanGecir`: yapı + sayı + dil) `varlik_analizi`'ne yazar.
//
// ── Ne yayına çıkmaz ────────────────────────────────────────────────────────
//   · Model reddetti (`stop_reason: refusal`) ya da çıktı kesildi
//     (`max_tokens`): `reddedildi`. Batch'te sunucu taraflı yedek model yok;
//     not o hafta çıkmaz, uydurma bir yedek de yazılmaz.
//   · Kapıdan geçmedi: `reddedildi` + `red_nedeni` (oran izlenir, N-08).
//   · İstek hata verdi / süresi doldu: `hata`.
// Üçü de RLS'te görünmez (yalnız `yayinda` okunur). Kart o varlık için "bu
// hafta not yok" der; eski not 21 gün tazelik penceresi içinde kalır.
//
// ── Yeniden deneme ──────────────────────────────────────────────────────────
// 26 saati geçip hâlâ bitmeyen batch `hata` olur (Anthropic üst sınırı 24
// saat). `hata` dönemi `analiz-hazirla`'nın tekrar göndermesine izin verir.
//
// Yanıtta anahtar, ham Anthropic yanıtı, model metni DÖNMEZ.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { Paket, sonucSatiri, tickerdan } from '../_shared/analiz.ts';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const ZAMAN_ASIMI_SAAT = 26;

type BatchSatiri = {
  id: string;
  tur: string;
  donem: string;
  model: string;
  girdiler: Record<string, Paket>;
  olusturuldu: string;
};

async function batchTopla(client: SupabaseClient, anthropic: Anthropic, b: BatchSatiri) {
  const durum = await anthropic.messages.batches.retrieve(b.id);
  if (durum.processing_status !== 'ended') {
    const yas = (Date.now() - Date.parse(b.olusturuldu)) / 3_600_000;
    if (yas > ZAMAN_ASIMI_SAAT) {
      await anthropic.messages.batches.cancel(b.id).catch(() => {});
      await client.from('analiz_batch').update({ durum: 'hata', bitti: new Date().toISOString() }).eq('id', b.id);
      return { id: b.id, durum: 'zaman_asimi' };
    }
    return { id: b.id, durum: 'bekliyor' };
  }

  const satirlar: Record<string, unknown>[] = [];
  for await (const r of await anthropic.messages.batches.results(b.id)) {
    const paket = b.girdiler[r.custom_id];
    if (!paket || tickerdan(r.custom_id) !== paket.ticker) continue;
    // deno-lint-ignore no-explicit-any
    satirlar.push(sonucSatiri(b, paket, r.result as any));
  }
  for (let i = 0; i < satirlar.length; i += 100) {
    const { error } = await client.from('varlik_analizi')
      .upsert(satirlar.slice(i, i + 100), { onConflict: 'ticker,tur,donem' });
    if (error) throw error;
  }
  await client.from('analiz_batch').update({ durum: 'bitti', bitti: new Date().toISOString() }).eq('id', b.id);
  const say = (d: string) => satirlar.filter((s) => s.durum === d).length;
  return { id: b.id, durum: 'bitti', yayinda: say('yayinda'), reddedildi: say('reddedildi'), hata: say('hata') };
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return jsonResponse({ ok: false }, 405);
  try {
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');
    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }
    const client: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);
    const { data, error } = await client.from('analiz_batch')
      .select('id, tur, donem, model, girdiler, olusturuldu')
      .eq('durum', 'gonderildi').order('olusturuldu').limit(5);
    if (error) throw error;
    const bekleyen = (data ?? []) as BatchSatiri[];
    if (bekleyen.length === 0) return jsonResponse({ ok: true, batch: [] });

    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!apiKey) {
      console.error('analiz-topla: ANTHROPIC_API_KEY tanimli degil.');
      return jsonResponse({ ok: false, neden: 'anahtar_yok' }, 503);
    }
    const anthropic = new Anthropic({ apiKey });
    const sonuc = [];
    for (const b of bekleyen) sonuc.push(await batchTopla(client, anthropic, b));
    return jsonResponse({ ok: true, batch: sonuc });
  } catch (err) {
    console.error('analiz-topla', err);
    return jsonResponse({ ok: false }, 500);
  }
});
