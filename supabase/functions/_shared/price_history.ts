// Fiyat geçmişi çekimi + paylaşımlı cache.
//
// MALİYET/PERFORMANS TASARIMI
// ---------------------------
// Naif yaklaşım (her kullanıcı için ayrı çekim) kabul edilemez:
//   1000 kullanıcı × 10 varlık = 10.000 Yahoo isteği/tur → rate-limit + uzun
//   function süresi (Supabase faturası saniye üzerinden).
//
// Bunun yerine SEMBOL BAŞINA TEK ÇEKİM yapılır:
//   - Tüm kullanıcıların varlıkları birleştirilip benzersiz sembol kümesi
//     çıkarılır (1000 kullanıcı olsa da BIST'te ~500 sembol vardır).
//   - Sembol `price_history_cache` tablosunda tazeyse ağa hiç çıkılmaz.
//   - Çekilen seri tabloya yazılır; aynı turdaki diğer kullanıcılar okur.
//
// Böylece istek sayısı kullanıcı sayısıyla değil, PORTFÖY ÇEŞİTLİLİĞİYLE
// ölçeklenir — ücretsiz katmanda kalmanın anahtarı bu.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/// Teknik göstergeler için gereken minimum nokta sayısı.
/// En uzun pencere EMA(50) — güvenli tarafta 60 istiyoruz.
export const MIN_POINTS = 60;

/// Cache tazelik süresi. Günlük kapanış verisi gün içinde değişmez;
/// 12 saat aynı gün içindeki iki cron turunun (11:00 / 15:00) ikinci
/// turunda ağa çıkmamasını sağlar.
const CACHE_TTL_MS = 12 * 60 * 60 * 1000;

const TEFAS_PREFIX = 'TEFAS:';

/// Altın iç sembolleri → gram22k çarpanı.
/// `PriceService._goldWeights` ile birebir aynı olmalı.
const GOLD_WEIGHTS: Record<string, number> = {
  ALTIN_GRAM: 1.0,
  ALTIN_CEYREK: 1.75,
  ALTIN_YARIM: 3.5,
  ALTIN_CUMHURIYET: 7.216,
  ALTIN_ATA: 7.216,
  ALTIN_RESAT: 7.216,
};

export function isGoldSymbol(symbol: string): boolean {
  return symbol in GOLD_WEIGHTS;
}

/// Teknik gösterge açısından altın türleri aynı eğriyi izler (hepsi ons
/// altına bağlı). Çarpan eğrinin ŞEKLİNİ değiştirmediği için — RSI, MACD,
/// Bollinger hepsi orana duyarlı — tek bir GC=F serisi yeterli.
export function resolveSymbol(rawTicker: string, assetType: string): string | null {
  const t = rawTicker.trim();
  if (assetType === 'altin') return 'GC=F';
  if (t.length === 0) return null;
  return t;
}

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Yahoo Finance günlük kapanış serisi (6 ay).
async function fetchYahoo(symbol: string): Promise<number[]> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}` +
    `?interval=1d&range=6mo&includePrePost=false`;

  const res = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) return [];

  const body = await res.json();
  const result = body?.chart?.result?.[0];
  if (!result) return [];

  const closes: (number | null)[] =
    result?.indicators?.quote?.[0]?.close ?? [];

  // null kapanışlar (tatil/eksik bar) atlanır — Dart tarafı da böyle yapıyor.
  return closes.filter((c): c is number => typeof c === 'number' && c > 0);
}

/// TEFAS fon NAV serisi (6 ay).
async function fetchTefas(code: string): Promise<number[]> {
  const res = await fetch(
    'https://www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/plain, */*',
        'User-Agent': USER_AGENT,
      },
      body: JSON.stringify({ fonKodu: code, dil: 'TR', periyod: 6 }),
      signal: AbortSignal.timeout(15_000),
    },
  );
  if (!res.ok) return [];

  const data = await res.json();
  const rows: Array<Record<string, unknown>> = data?.resultList ?? [];

  const points: Array<[number, number]> = [];
  for (const row of rows) {
    const price = Number(row?.fiyat);
    const dateStr = String(row?.tarih ?? '');
    const ts = Date.parse(dateStr);
    if (!Number.isFinite(price) || price <= 0 || Number.isNaN(ts)) continue;
    points.push([ts, price]);
  }
  points.sort((a, b) => a[0] - b[0]);
  return points.map((p) => p[1]);
}

async function fetchFromSource(symbol: string): Promise<number[]> {
  try {
    if (symbol.startsWith(TEFAS_PREFIX)) {
      return await fetchTefas(symbol.slice(TEFAS_PREFIX.length));
    }
    return await fetchYahoo(symbol);
  } catch (_) {
    // Tek sembolün başarısızlığı tüm turu düşürmemeli.
    return [];
  }
}

/**
 * Verilen sembol kümesi için kapanış serilerini döner.
 *
 * Önce cache okunur; yalnızca eksik/bayat semboller ağdan çekilir ve
 * cache'e yazılır. Dönen map yalnızca YETERLİ veri (>= [MIN_POINTS])
 * içeren sembolleri barındırır — yetersiz veriyle sinyal üretilmemeli.
 */
export async function loadPriceHistories(
  client: SupabaseClient,
  symbols: Set<string>,
): Promise<Map<string, number[]>> {
  const out = new Map<string, number[]>();
  if (symbols.size === 0) return out;

  const wanted = [...symbols];

  // 1) Cache oku.
  const { data: cached } = await client
    .from('price_history_cache')
    .select('symbol, closes, fetched_at')
    .in('symbol', wanted);

  const now = Date.now();
  const stale: string[] = [];
  const cachedMap = new Map<string, { closes: number[]; fetchedAt: number }>();

  for (const row of cached ?? []) {
    cachedMap.set(row.symbol as string, {
      closes: (row.closes as number[]) ?? [],
      fetchedAt: Date.parse(row.fetched_at as string),
    });
  }

  for (const symbol of wanted) {
    const hit = cachedMap.get(symbol);
    if (hit && now - hit.fetchedAt < CACHE_TTL_MS && hit.closes.length >= MIN_POINTS) {
      out.set(symbol, hit.closes);
    } else {
      stale.push(symbol);
    }
  }

  if (stale.length === 0) return out;

  // 2) Eksikleri çek — sınırlı paralellikle (kaynak API'leri boğmamak için).
  const CONCURRENCY = 8;
  const fresh: Array<{ symbol: string; closes: number[] }> = [];

  for (let i = 0; i < stale.length; i += CONCURRENCY) {
    const batch = stale.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map(async (symbol) => ({
        symbol,
        closes: await fetchFromSource(symbol),
      })),
    );
    fresh.push(...results);
  }

  // 3) Cache'e yaz (yalnızca anlamlı seriler) + sonuca ekle.
  const rows = fresh
    .filter((f) => f.closes.length > 0)
    .map((f) => ({
      symbol: f.symbol,
      closes: f.closes,
      fetched_at: new Date().toISOString(),
    }));

  if (rows.length > 0) {
    try {
      await client.from('price_history_cache').upsert(rows, {
        onConflict: 'symbol',
      });
    } catch (_) {
      // Cache yazımı başarısız olsa da analiz sürsün.
    }
  }

  for (const f of fresh) {
    if (f.closes.length >= MIN_POINTS) out.set(f.symbol, f.closes);
    else if (f.closes.length === 0) {
      // Ağdan da gelmediyse bayat cache'i son çare olarak kullan:
      // eski veri, hiç veri olmamasından iyidir (sinyal biraz gecikir).
      const hit = cachedMap.get(f.symbol);
      if (hit && hit.closes.length >= MIN_POINTS) out.set(f.symbol, hit.closes);
    }
  }

  return out;
}

/// Test/CLI kolaylığı için — edge function kendi client'ını kurar.
export function createServiceClient(url: string, serviceRoleKey: string) {
  return createClient(url, serviceRoleKey);
}
