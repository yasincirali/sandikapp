// Tarihli kapanış serileri — yarış snapshot'ı için (2026-09-28).
//
// `price_history.ts` yalnızca kapanış DİZİSİ döner (tarihsiz): sinyal
// motoru "son N mum" ister, takvim umurunda değildir. Dönem getirisi
// ("30 gün önce portföy ne ediyordu") ise tarihe bağlıdır ve kaynaklar
// farklı takvimlerde yürür: BIST/TEFAS iş günü, kripto her gün, altın
// vadelisi ABD takvimi. Kapanış indeksinden "N gün önce"yi türetmek
// kaynaklar arasında kayar; bu yüzden burada her nokta [ms, kapanış]
// çiftidir ve "t anındaki fiyat" [fiyatAninda] ile okunur.
//
// Kaynaklar `price_history.ts` ile AYNI (Yahoo / TEFAS / Binance /
// Frankfurt eurobond) — fiyat
// kaynağı sözleşmesi (istemci `fiyat_kaynagi.dart`) sunucuda da tek
// merdiven. Menzil 1 yıl: yarışın en uzun dönemi 365 gün.
//
// Önbellek yok (bilinçli): günde bir koşu, sembol başına tek istek;
// `price_history_cache` tarihsiz olduğu için paylaşılamıyor. Sembol
// sayısı büyürse ayrı bir tarihli önbellek tablosu eklenir.

import { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { kriptoKodu, mumlariCek, tlSerisi } from './kripto.ts';
import {
  BF_API,
  bfGecmisiniCoz,
  birimDeger,
  EUROBOND_ONEKI,
  isinGecerli,
  sozlesmeSatiri,
  TARAYICI_UA,
} from './eurobond.ts';

/// [ms, kapanış] — artan zaman sırasında.
export type Seri = [number, number][];

const TEFAS_PREFIX = 'TEFAS:';
const GUN_MS = 24 * 60 * 60 * 1000;
const MENZIL_GUN = 370;

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Yahoo chart API — `timestamp[]` ile `close[]` eşleşir; null kapanışlar
/// (tatil, eksik gün) atılır.
export async function fetchYahooDated(
  symbol: string,
  f: typeof fetch = fetch,
): Promise<Seri> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}` +
    `?interval=1d&range=1y&includePrePost=false`;
  const res = await f(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) return [];
  const body = await res.json();
  const result = body?.chart?.result?.[0];
  if (!result) return [];
  const ts: (number | null)[] = result?.timestamp ?? [];
  const closes: (number | null)[] = result?.indicators?.quote?.[0]?.close ?? [];
  return noktalariTopla(ts.map((t, i) => [t === null ? null : t * 1000, closes[i] ?? null]));
}

/// TEFAS fon fiyatı — `periyod: 12` (ay).
export async function fetchTefasDated(
  code: string,
  f: typeof fetch = fetch,
): Promise<Seri> {
  const res = await f('https://www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/plain, */*',
      'User-Agent': USER_AGENT,
    },
    body: JSON.stringify({ fonKodu: code, dil: 'TR', periyod: 12 }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) return [];
  const data = await res.json();
  const rows: Array<Record<string, unknown>> = data?.resultList ?? [];
  return noktalariTopla(rows.map((row) => {
    const price = Number(row?.fiyat);
    const ts = Date.parse(String(row?.tarih ?? ''));
    return [Number.isNaN(ts) ? null : ts, Number.isFinite(price) ? price : null];
  }));
}

/// Binance günlük mumlar, TL'ye çevrilmiş (`price_history.ts › fetchKripto`
/// ile aynı kural: USDT paritesi AYNI borsanın USDTTRY'si ile çevrilir).
export async function fetchKriptoDated(
  client: SupabaseClient,
  symbol: string,
  f: typeof fetch = fetch,
): Promise<Seri> {
  const kod = kriptoKodu(symbol);
  if (!kod) return [];
  const { data: coin } = await client
    .from('kripto_varlik')
    .select('parite, binance_sembol')
    .eq('kod', kod)
    .maybeSingle();
  if (!coin) return [];
  const simdi = Date.now();
  const baslangic = simdi - MENZIL_GUN * GUN_MS;
  const [ham, kur] = await Promise.all([
    mumlariCek(String(coin.binance_sembol), '1d', baslangic, simdi, f),
    coin.parite === 'USDT'
      ? mumlariCek('USDTTRY', '1d', baslangic, simdi, f)
      : Promise.resolve(null),
  ]);
  if (ham === null) return [];
  const noktalar = coin.parite === 'USDT'
    ? (kur === null ? [] : tlSerisi(ham, kur))
    : ham;
  return noktalariTopla(noktalar);
}

/// Eurobond günlük kapanışları — uygulamanın lot fiyatıyla AYNI ölçekte:
/// her nokta o günün KİRLİ fiyatı / 100 (1 nominal birim, tahvilin para
/// biriminde).
///
/// ## Neden (seri denetimi, 2026-10-08)
/// `EUROBOND:` sembolü Yahoo'ya düşüyor, seri boş dönüyordu. Yarış
/// snapshot'ı eurobond lotunu "karanlık" sayıyor; eurobond ağırlıklı
/// portföy kapsama eşiğinin (%80) altında kalıp sıralamadan düşüyordu —
/// veri Frankfurt'ta VARKEN. Kaynak grafikle aynı (`eurobond-seri`,
/// Frankfurt `1D`); temiz kapanışa noktanın kendi gününün işlemiş faizi
/// eklenir (istemci `PriceService._eurobondSerisi` ile aynı kural).
/// Katalogda olmayan ISIN için Frankfurt'a gidilmez.
export async function fetchEurobondDated(
  client: SupabaseClient,
  symbol: string,
  f: typeof fetch = fetch,
): Promise<Seri> {
  const isin = symbol.trim().toUpperCase().slice(EUROBOND_ONEKI.length);
  if (!symbol.trim().toUpperCase().startsWith(EUROBOND_ONEKI) || !isinGecerli(isin)) return [];
  const { data: satir } = await client
    .from('eurobond_katalog')
    .select('isin, para_birimi, kupon_orani, vade, ihrac_yili, kupon_sikligi')
    .eq('isin', isin)
    .maybeSingle();
  const s = satir ? sozlesmeSatiri(satir as Record<string, unknown>) : null;
  if (!s) return [];
  const to = Math.floor(Date.now() / 1000);
  const from = to - MENZIL_GUN * 24 * 60 * 60;
  const res = await f(
    `${BF_API}/tradingview/history?symbol=XFRA:${isin}&resolution=1D&from=${from}&to=${to}`,
    {
      headers: { 'User-Agent': TARAYICI_UA, Accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    },
  );
  if (!res.ok) return [];
  return noktalariTopla(
    bfGecmisiniCoz(await res.json()).map(([t, temiz]) => [t, birimDeger(s, temiz, t)]),
  );
}

/// Sembole göre kaynak seçer; tek sembolün hatası boş seri döner, turu
/// düşürmez.
export async function fetchDatedSeries(
  client: SupabaseClient,
  symbol: string,
  f: typeof fetch = fetch,
): Promise<Seri> {
  try {
    if (kriptoKodu(symbol)) return await fetchKriptoDated(client, symbol, f);
    if (symbol.trim().toUpperCase().startsWith(EUROBOND_ONEKI)) {
      return await fetchEurobondDated(client, symbol, f);
    }
    if (symbol.startsWith(TEFAS_PREFIX)) {
      return await fetchTefasDated(symbol.slice(TEFAS_PREFIX.length), f);
    }
    return await fetchYahooDated(symbol, f);
  } catch (_) {
    return [];
  }
}

/// Sembol kümesi → seri; boş dönenler haritaya girmez.
export async function loadDatedHistories(
  client: SupabaseClient,
  symbols: Set<string>,
  f: typeof fetch = fetch,
): Promise<Map<string, Seri>> {
  const out = new Map<string, Seri>();
  const wanted = [...symbols];
  const CONCURRENCY = 8;
  for (let i = 0; i < wanted.length; i += CONCURRENCY) {
    const batch = wanted.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map(async (symbol) => ({ symbol, seri: await fetchDatedSeries(client, symbol, f) })),
    );
    for (const r of results) if (r.seri.length > 0) out.set(r.symbol, r.seri);
  }
  return out;
}

/// Geçersiz noktaları atar, zamana göre sıralar, aynı güne düşen
/// tekrarlarda SONUNCUYU tutar.
export function noktalariTopla(
  ham: Array<[number | null, number | null]>,
): Seri {
  const temiz: Seri = [];
  for (const [t, c] of ham) {
    if (t === null || c === null) continue;
    if (!Number.isFinite(t) || !Number.isFinite(c) || c <= 0) continue;
    temiz.push([t, c]);
  }
  temiz.sort((a, b) => a[0] - b[0]);
  const out: Seri = [];
  for (const p of temiz) {
    const son = out[out.length - 1];
    if (son && Math.floor(son[0] / GUN_MS) === Math.floor(p[0] / GUN_MS)) {
      out[out.length - 1] = p;
    } else {
      out.push(p);
    }
  }
  return out;
}

/// `t` anındaki fiyat: t'den önceki (≤) SON kapanış — tatilde son iş günü
/// geçerlidir. Seri t'den SONRA başlıyorsa ilk kapanış (istemci `simulate`
/// serisinin geriye taşıma kuralıyla aynı: varlık dönemden yeni olsa da
/// bugünkü miktar dönem boyunca tutulmuş sayılır). Boş seri → null.
export function fiyatAninda(seri: Seri, tMs: number): number | null {
  if (seri.length === 0) return null;
  if (seri[0][0] > tMs) return seri[0][1];
  // İkili arama: son ≤ t.
  let lo = 0, hi = seri.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (seri[mid][0] <= tMs) lo = mid;
    else hi = mid - 1;
  }
  return seri[lo][1];
}
