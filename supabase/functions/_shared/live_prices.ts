// Anlık fiyat çekimi — fiyat alarmları için.
//
// **Neden `price_history.ts` yetmiyor:** o modül GÜNLÜK KAPANIŞ serisi
// tutuyor ve 12 saatlik cache'i var. Teknik analiz için doğru, alarm için
// yanlış: "gram altın 5.400 olunca haber ver" diyen kullanıcı ertesi günü
// beklemeyi kabul etmez.
//
// **Kaynaklar istemciyle AYNI seçildi** (`lib/services/price_service.dart`):
//   · altın + döviz → finans.truncgil.com
//   · geri kalan    → Yahoo chart
// Bu bir tercih değil zorunluluk: alarm uygulamada GÖRÜNEN sayı üzerinden
// tetiklenmeli. Farklı kaynak kullansaydık kullanıcı ekranda 5.401 görürken
// 5.400 alarmının çalışmadığını fark eder ve haklı olarak "bozuk" der.

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Altın iç sembolü → truncgil anahtarı.
/// `PriceService._truncgilGoldKeys` ile BİREBİR aynı olmalı.
const GOLD_KEYS: Record<string, string> = {
  ALTIN_GRAM: 'Gram Altın',
  ALTIN_CEYREK: 'Çeyrek Altın',
  ALTIN_YARIM: 'Yarım Altın',
  ALTIN_CUMHURIYET: 'Cumhuriyet Altını',
  ALTIN_ATA: 'Ata Altını',
  ALTIN_RESAT: 'Reşat Altını',
};

const FX_SYMBOLS = new Set(['USDTRY=X', 'EURTRY=X', 'GBPTRY=X']);

/// truncgil sayı biçimi: "5.412,37" → 5412.37
///
/// Binlik ayıracı NOKTA, ondalık ayıracı VİRGÜL. Doğrudan `parseFloat`
/// "5.412,37"yi 5.412 okur — yani bin katı hatalı bir fiyat. Alarmların
/// sessizce yanlış tetiklenmesinin en kolay yolu buydu.
export function parseTruncgilNumber(raw: unknown): number | null {
  if (typeof raw !== 'string') return null;
  const temiz = raw.replaceAll('.', '').replace(',', '.').trim();
  const n = Number(temiz);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/// truncgil kaydından fiyat: "Alış" yoksa "Satış".
export function truncgilValue(entry: unknown): number | null {
  if (typeof entry !== 'object' || entry === null) return null;
  const rec = entry as Record<string, unknown>;
  return parseTruncgilNumber(rec['Alış']) ?? parseTruncgilNumber(rec['Satış']);
}

export function isGoldSymbol(symbol: string): boolean {
  return symbol in GOLD_KEYS;
}

export function isFxSymbol(symbol: string): boolean {
  return FX_SYMBOLS.has(symbol);
}

/// truncgil yanıtından istenen sembollerin TRY fiyatı.
export function extractTruncgil(
  data: Record<string, unknown>,
  symbols: string[],
): Map<string, number> {
  const out = new Map<string, number>();
  for (const sym of symbols) {
    if (isGoldSymbol(sym)) {
      const v = truncgilValue(data[GOLD_KEYS[sym]]);
      if (v !== null) out.set(sym, v);
      continue;
    }
    if (isFxSymbol(sym)) {
      // 'USDTRY=X' → 'USD'
      const v = truncgilValue(data[sym.slice(0, 3)]);
      if (v !== null) out.set(sym, v);
    }
  }
  return out;
}

async function fetchTruncgil(): Promise<Record<string, unknown>> {
  const res = await fetch('https://finans.truncgil.com/v4/today.json', {
    headers: { Accept: 'application/json', 'User-Agent': USER_AGENT },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`Truncgil HTTP ${res.status}`);
  return await res.json() as Record<string, unknown>;
}

/// Yahoo chart'tan tek sembolün son fiyatı.
///
/// `interval=5m&range=1d`: gün içi mumlar. Kapanış serisi (`1d`) alarm için
/// bir gün geç kalırdı.
async function fetchYahooLast(symbol: string): Promise<number | null> {
  try {
    const url =
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}` +
      `?interval=5m&range=1d&includePrePost=false`;
    const res = await fetch(url, {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
      signal: AbortSignal.timeout(12_000),
    });
    if (!res.ok) return null;
    const json = await res.json();
    const result = json?.chart?.result?.[0];
    // Önce meta: piyasa kapalıyken `quote.close` dizisinin sonu null olur
    // ama `regularMarketPrice` son geçerli fiyatı taşır.
    const meta = result?.meta?.regularMarketPrice;
    if (typeof meta === 'number' && Number.isFinite(meta) && meta > 0) {
      return meta;
    }
    const closes = result?.indicators?.quote?.[0]?.close;
    if (!Array.isArray(closes)) return null;
    for (let i = closes.length - 1; i >= 0; i -= 1) {
      const v = closes[i];
      if (typeof v === 'number' && Number.isFinite(v) && v > 0) return v;
    }
    return null;
  } catch (_) {
    // Tek sembolün başarısızlığı tüm turu düşürmemeli.
    return null;
  }
}

/// Verilen sembollerin anlık fiyatı (TRY ya da sembolün kendi kotasyonu).
///
/// Dönen map yalnızca fiyatı ALINABİLEN sembolleri içerir; eksik sembol için
/// alarm değerlendirilmez (yanlış tetiklemektense hiç tetiklememek).
export async function fetchLivePrices(
  symbols: Set<string>,
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (symbols.size === 0) return out;

  const hepsi = [...symbols];
  const truncgilList = hepsi.filter((s) => isGoldSymbol(s) || isFxSymbol(s));
  const yahooList = hepsi.filter((s) => !isGoldSymbol(s) && !isFxSymbol(s));

  if (truncgilList.length > 0) {
    try {
      const data = await fetchTruncgil();
      for (const [k, v] of extractTruncgil(data, truncgilList)) out.set(k, v);
    } catch (_) {
      // Altın/döviz kaynağı düştü — bu turda o alarmlar atlanır.
    }
  }

  // Sınırlı paralellik: kaynak API'yi boğmamak için (price_history.ts ile
  // aynı desen).
  const CONCURRENCY = 8;
  for (let i = 0; i < yahooList.length; i += CONCURRENCY) {
    const dilim = yahooList.slice(i, i + CONCURRENCY);
    const sonuc = await Promise.all(dilim.map(fetchYahooLast));
    dilim.forEach((sym, j) => {
      const p = sonuc[j];
      if (p !== null) out.set(sym, p);
    });
  }

  return out;
}
