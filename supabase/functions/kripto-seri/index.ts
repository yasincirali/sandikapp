// Kripto Seri Edge Function — grafik mumları, paylaşılan önbellekle
//
// Uygulama bir kripto grafiği açtığında çağırır (oturumlu kullanıcı).
// Gövde: `{ kod: 'BTC', aralik: '1h', donem: '1mo' }` — aralık ve dönem
// adları Yahoo'nunkiyle aynı, böylece `HistoryService`'in çözünürlük
// katmanı kriptoda da değişmeden çalışır.
//
// ── Neden cron değil de istek üzerine ───────────────────────────────────────
// Anlık fiyat herkes için aynı ve sürekli gerekli: cron'a uygun. Grafik ise
// yalnızca açıldığında gerekir ve altı çözünürlük × dokuz dönem × yüzlerce
// coin'in hepsini önden doldurmak boşa iş. Onun yerine sonuç
// `kripto_seri_onbellek`'e yazılır ve AYNI isteği yapan herkes bir bar
// boyunca (en az 60 sn, en çok 1 saat) aynı satırı okur. BTC'nin 1G
// grafiğini bin kişi açsa Binance'e dakikada en çok bir istek gider.
//
// ── Güvenlik ────────────────────────────────────────────────────────────────
// Gateway anon anahtarını da geçerli JWT sayar; burada gerçek oturum
// (`auth.getUser`) istenir. Kod katalogda yoksa sağlayıcıya hiç gidilmez —
// fonksiyon rastgele sembol için açık proxy değildir.
//
// Yanıt `{ noktalar: [[ms, fiyat_try], …], bayat? }`. Sağlayıcı hatası,
// ham yanıt DÖNMEZ.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  mumlariCek,
  seriAnahtari,
  seriBaslangici,
  seriIstegiCoz,
  seriTtlMs,
  tlSerisi,
} from '../_shared/kripto.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-region',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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
  if (request.method !== 'POST') return jsonResponse({ error: 'method' }, 405);

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error('Supabase ortam değişkenleri runtime tarafından sağlanmadı.');
    }

    const authHeader = request.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
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

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const anahtar = seriAnahtari(istek);
    const simdi = Date.now();

    const { data: onbellek } = await admin
      .from('kripto_seri_onbellek')
      .select('noktalar, guncellendi')
      .eq('anahtar', anahtar)
      .maybeSingle();
    if (
      onbellek &&
      simdi - new Date(onbellek.guncellendi as string).getTime() < seriTtlMs(istek.aralik)
    ) {
      return jsonResponse({ noktalar: onbellek.noktalar });
    }

    const { data: coin } = await admin
      .from('kripto_varlik')
      .select('parite, binance_sembol')
      .eq('kod', istek.kod)
      .maybeSingle();
    if (!coin) return jsonResponse({ error: 'bilinmeyen_kod' }, 404);

    const baslangic = seriBaslangici(istek.donem, simdi);
    const [ham, kur] = await Promise.all([
      mumlariCek(String(coin.binance_sembol), istek.aralik, baslangic, simdi),
      coin.parite === 'USDT'
        ? mumlariCek('USDTTRY', istek.aralik, baslangic, simdi)
        : Promise.resolve(null),
    ]);

    const noktalar = ham === null
      ? null
      : coin.parite === 'USDT'
      ? (kur === null ? null : tlSerisi(ham, kur))
      : ham;

    if (noktalar === null) {
      // Sağlayıcı yanıtsız: bayat önbellek varsa o (ölçülmüş veri), yoksa boş.
      if (onbellek) return jsonResponse({ noktalar: onbellek.noktalar, bayat: true });
      return jsonResponse({ noktalar: [] }, 503);
    }

    const { error: upErr } = await admin
      .from('kripto_seri_onbellek')
      .upsert({ anahtar, noktalar, guncellendi: new Date(simdi).toISOString() });
    if (upErr) console.error('kripto-seri onbellek yazilamadi', upErr.code);

    return jsonResponse({ noktalar });
  } catch (e) {
    console.error('kripto-seri hatasi', e);
    return jsonResponse({ error: 'sunucu' }, 500);
  }
});
