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
//
// ── Yanıt süresi sınırı (2026-10-03) ────────────────────────────────────────
// "Kripto varlık fiyatı her zaman çekilemiyor … düz çizgiye dönüyor"
// (yasin). İstemci grafik çekiminden 8 sn'de vazgeçer
// (`HistoryService._grafikCekimSuresi`). Bu fonksiyon ise Frankfurt'ta
// koşup Tokyo'daki tabloya gidiyor ve Binance'e istek başına 10 sn × iki
// taban tanıyordu: önbellek bir bar eskidiği anda Binance biraz yavaşsa
// telefon ELİNDEKİ bayat seriyi bile alamadan vazgeçiyor, varlık düz
// çiziliyordu. Şimdi: önbellekte seri VARSA tazeleme [YANIT_SURESI_MS]
// içinde bitmezse bayat seri hemen döner, tazeleme arka planda
// (`EdgeRuntime.waitUntil`) sürer ve önbelleği bir sonraki istek için
// doldurur. Önbellek yoksa beklemekten başka seçenek yok.
// Boş ya da eksik seri iyi önbelleğin ÜSTÜNE yazılmaz.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  mumlariCek,
  seriAnahtari,
  seriBaslangici,
  seriIstegiCoz,
  seriTtlMs,
  tlSerisi,
} from '../_shared/kripto.ts';

/// Önbellekte seri varken tazelemeyi bekleme sınırı — istemcinin 8 sn'lik
/// vazgeçme süresinin (soğuk başlangıç + Tokyo gidiş-dönüşü payıyla) altı.
const YANIT_SURESI_MS = 5_000;

/// Grafik isteğinde Binance istek başına zaman aşımı (cron'daki 10 sn
/// değil): iki taban × 4 sn, yanıt sınırını tek başına tüketmesin.
const SERI_ZAMAN_ASIMI_MS = 4_000;

type Seri = [number, number][];

/// Yanıt döndükten sonra işi sürdürür (Supabase Edge Runtime). Yerel
/// Deno'da yoksa söz yine koşar, yalnızca beklenmez.
function arkaPlanda(p: Promise<unknown>) {
  const er = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } })
    .EdgeRuntime;
  er?.waitUntil(p);
}

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

    const { data: kayit } = await admin
      .from('kripto_seri_onbellek')
      .select('noktalar, guncellendi')
      .eq('anahtar', anahtar)
      .maybeSingle();
    // Boş satır önbellek sayılmaz: eski sürüm boş seriyi de yazıyordu ve
    // bir saat boyunca herkese "veri yok" dağıtıyordu.
    const onbellek = kayit && Array.isArray(kayit.noktalar) && kayit.noktalar.length > 0
      ? kayit
      : null;
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
    const tazele = (async (): Promise<Seri | null> => {
      const [ham, kur] = await Promise.all([
        mumlariCek(
          String(coin.binance_sembol),
          istek.aralik,
          baslangic,
          simdi,
          fetch,
          SERI_ZAMAN_ASIMI_MS,
        ),
        coin.parite === 'USDT'
          ? mumlariCek('USDTTRY', istek.aralik, baslangic, simdi, fetch, SERI_ZAMAN_ASIMI_MS)
          : Promise.resolve(null),
      ]);
      const noktalar = ham === null
        ? null
        : coin.parite === 'USDT'
        ? (kur === null ? null : tlSerisi(ham, kur))
        : ham;
      // Boş seri (kur mumlarıyla hiç eşleşmeyen an, sağlayıcının boş
      // sayfası) ölçüm değil; iyi önbelleğin üstüne yazılmaz.
      if (noktalar === null || noktalar.length === 0) return null;
      const { error: upErr } = await admin
        .from('kripto_seri_onbellek')
        .upsert({ anahtar, noktalar, guncellendi: new Date(simdi).toISOString() });
      if (upErr) console.error('kripto-seri onbellek yazilamadi', upErr.code);
      return noktalar;
    })().catch((e) => {
      console.error('kripto-seri tazeleme hatasi', e instanceof Error ? e.name : '');
      return null;
    });

    if (!onbellek) {
      const noktalar = await tazele;
      if (noktalar === null) return jsonResponse({ noktalar: [] }, 503);
      return jsonResponse({ noktalar });
    }

    let zamanlayici: ReturnType<typeof setTimeout> | undefined;
    const sinir = new Promise<'gec'>((coz) => {
      zamanlayici = setTimeout(() => coz('gec'), YANIT_SURESI_MS);
    });
    const sonuc = await Promise.race([tazele, sinir]);
    clearTimeout(zamanlayici);
    if (sonuc === 'gec') {
      arkaPlanda(tazele);
      return jsonResponse({ noktalar: onbellek.noktalar, bayat: true });
    }
    // Sağlayıcı yanıtsız: bayat önbellek (ölçülmüş veri).
    if (sonuc === null) return jsonResponse({ noktalar: onbellek.noktalar, bayat: true });
    return jsonResponse({ noktalar: sonuc });
  } catch (e) {
    console.error('kripto-seri hatasi', e);
    return jsonResponse({ error: 'sunucu' }, 500);
  }
});
