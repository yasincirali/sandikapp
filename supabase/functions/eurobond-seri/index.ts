// Eurobond Seri Edge Function — grafik noktaları, paylaşılan önbellekle
//
// kripto-seri'nin eşi (gerekçeler orada): uygulama bir eurobond grafiği
// açınca çağırır, sonuç `eurobond_seri_onbellek`'e yazılır ve aynı isteği
// yapan herkes TTL boyunca aynı satırı okur. Gövde:
// `{ isin: 'US900123DF45', aralik: '1d', donem: '1y' }` — Yahoo adlarıyla.
//
// Noktalar TEMİZ fiyattır (Frankfurt). İstemci değer grafiği için işlemiş
// faizi kendisi ekler (`EurobondSozlesmesi.kirliFiyat`); fiyat grafiği
// temiz kalır ve ekrandaki fiyatla aynı ölçektedir.
//
// Güvenlik: gerçek oturum istenir; ISIN katalogda değilse Frankfurt'a
// gidilmez (açık proxy değil). Yanıt `{ noktalar: [[ms, fiyat], …], bayat? }`.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  BF_API,
  bfCozunurluk,
  bfGecmisiniCoz,
  seriAnahtari,
  seriBaslangici,
  seriIstegiCoz,
  seriTtlMs,
  TARAYICI_UA,
} from '../_shared/eurobond.ts';

const ZAMAN_ASIMI_MS = 5_000;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'method' }, 405);

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error('Supabase ortam değişkenleri runtime tarafından sağlanmadı.');
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: request.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jsonResponse({ error: 'oturum' }, 401);

    let body: unknown = null;
    try {
      body = await request.json();
    } catch (_) { /* aşağıda reddedilir */ }
    const istek = seriIstegiCoz(body);
    if (!istek) return jsonResponse({ error: 'istek' }, 400);

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const anahtar = seriAnahtari(istek);
    const simdi = Date.now();

    const { data: kayit } = await admin
      .from('eurobond_seri_onbellek')
      .select('noktalar, guncellendi')
      .eq('anahtar', anahtar)
      .maybeSingle();
    const onbellek = kayit && Array.isArray(kayit.noktalar) && kayit.noktalar.length > 0
      ? kayit
      : null;
    if (onbellek && simdi - new Date(onbellek.guncellendi as string).getTime() < seriTtlMs(istek.aralik)) {
      return jsonResponse({ noktalar: onbellek.noktalar });
    }

    const { data: tahvil } = await admin
      .from('eurobond_katalog')
      .select('isin')
      .eq('isin', istek.isin)
      .maybeSingle();
    if (!tahvil) return jsonResponse({ error: 'bilinmeyen_isin' }, 404);

    const from = Math.floor(seriBaslangici(istek.donem, simdi) / 1000);
    const to = Math.floor(simdi / 1000);
    let noktalar: [number, number][] = [];
    try {
      const r = await fetch(
        `${BF_API}/tradingview/history?symbol=XFRA:${istek.isin}` +
          `&resolution=${bfCozunurluk(istek.aralik)}&from=${from}&to=${to}`,
        {
          headers: { 'User-Agent': TARAYICI_UA, Accept: 'application/json' },
          signal: AbortSignal.timeout(ZAMAN_ASIMI_MS),
        },
      );
      if (r.ok) noktalar = bfGecmisiniCoz(await r.json());
    } catch (_) { /* aşağıda bayat önbellek */ }

    if (noktalar.length === 0) {
      // Sağlayıcı yanıtsız: bayat önbellek (ölçülmüş veri) ya da boş.
      if (onbellek) return jsonResponse({ noktalar: onbellek.noktalar, bayat: true });
      return jsonResponse({ noktalar: [] }, 503);
    }
    const { error: upErr } = await admin
      .from('eurobond_seri_onbellek')
      .upsert({ anahtar, noktalar, guncellendi: new Date(simdi).toISOString() });
    if (upErr) console.error('eurobond-seri onbellek yazilamadi', upErr.code);
    return jsonResponse({ noktalar });
  } catch (e) {
    console.error('eurobond-seri hatasi', e instanceof Error ? e.name : '');
    return jsonResponse({ error: 'sunucu' }, 500);
  }
});
