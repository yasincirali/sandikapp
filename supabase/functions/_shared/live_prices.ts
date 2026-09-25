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

import { sonNavSatiri } from './tefas_nav.ts';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Altın iç sembolü → truncgil anahtarı.
/// `PriceService._truncgilGoldKeys` ile BİREBİR aynı olmalı.
///
/// ⚠️ 2026-09-15: truncgil v4 anahtarları DEĞİŞTİ. Eski adlar boşluklu ve
/// Türkçe'ydi ('Gram Altın'); yenileri boşluksuz ve ASCII.
/// Eski adların hiçbiri yanıtta artık YOK — `data[key]` her sembol için
/// `undefined` dönüyordu ve `fetchLivePrices` boş map veriyordu. Belirtisi:
/// `check-price-alerts` her turda `{"reason":"Fiyat alinamadi.","sent":0}`
/// (2026-09-15'te 30 dakikada bir, istisnasız — yani fiyat alarmı özelliği
/// tümüyle ölüydü ve hata hiçbir yerde görünmüyordu: HTTP 200).
///
/// ⚠️⚠️ `ALTIN_GRAM` → `YIA`, **`GRA` DEĞİL** (2026-09-15, ikinci tur).
///
/// İlk düzeltmede `GRA` seçilmişti ve bu YANLIŞTI: adı `GRAMALTIN` ama
/// içeriği **24 ayar has** altındır (`HAS`/`GRAMHASALTIN` ile arasında
/// yalnızca %0,5 fark var). Uygulamanın `ALTIN_GRAM`'ı ise **22 ayar**dır —
/// kategori adı bunu açıkça söylüyor (`asset_categories.dart`:
/// '22 Ayar Gram Altın') ve `_goldWeights` ağırlıkları da 22 ayar cinsinden.
///
/// Sonuç: kullanıcı 6.270 (22 ayar) görürken sunucu 6.710 (24 ayar) okudu ve
/// 6.270 hedefli alarm ERKEN tetiklendi — kullanıcı bildirdi.
///
/// Doğrulama (çapraz kontrol, canlı veri 2026-09-15 17:42): çeyrek/yarım/tam
/// altının gram eşdeğeri (`fiyat ÷ _goldWeights`) 6.109–6.158 çıkıyor; `YIA`
/// 6.112 ile %1 içinde uyumlu, `GRA` %8 sapıyor. Ailenin geri kalanı zaten
/// 22 ayar kote edildiği için TEK tutarlı seçim `YIA`'dır.
///
/// Bir dahaki sefere: anahtarın ADINA değil, aynı ailedeki başka bir ürünle
/// GRAM EŞDEĞERİNE bak. 'GRAMALTIN' adı 22 ayar sanmaya davet ediyor.
const GOLD_KEYS: Record<string, string> = {
  // 22AYARBILEZIK — uygulamadaki '22 Ayar Gram Altın' ile aynı ayar.
  ALTIN_GRAM: 'YIA',
  ALTIN_CEYREK: 'CEYREKALTIN',
  ALTIN_YARIM: 'YARIMALTIN',
  ALTIN_CUMHURIYET: 'CUMHURIYETALTINI',
  ALTIN_ATA: 'ATAALTIN',
  ALTIN_RESAT: 'RESATALTIN',
  // 2026-09-25 genişlemesi — `ALTIN_GRAM24` bilerek 24 ayar, `GRA` doğru.
  ALTIN_GRAM24: 'GRA',
  ALTIN_HAS: 'HAS',
  ALTIN_18AYAR: '18AYARALTIN',
  ALTIN_14AYAR: '14AYARALTIN',
  ALTIN_TAM: 'TAMALTIN',
  ALTIN_HAMIT: 'HAMITALTIN',
  ALTIN_IKIBUCUK: 'IKIBUCUKALTIN',
  ALTIN_GREMSE: 'GREMSEALTIN',
  ALTIN_BESLI: 'BESLIALTIN',
};

const FX_SYMBOLS = new Set(['USDTRY=X', 'EURTRY=X', 'GBPTRY=X']);

/// truncgil sayı değeri → number.
///
/// İKİ biçim de desteklenir ve bu bilinçli:
///
///   · **number** (v4, 2026-09 sonrası): `6710.67` — API artık JSON sayısı
///     döndürüyor, string değil.
///   · **string** (eski biçim): `"5.412,37"` — binlik ayıracı NOKTA,
///     ondalık ayıracı VİRGÜL. Doğrudan `Number()` bunu 5.412 okur, yani
///     BİN KATI hatalı bir fiyat. Alarmların sessizce yanlış tetiklenmesinin
///     en kolay yolu buydu.
///
/// Eski dal KORUNUYOR: API biçimi bir kez değiştiyse geri de dönebilir ve
/// iki biçimi de kabul etmenin maliyeti üç satır.
export function parseTruncgilNumber(raw: unknown): number | null {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) && raw > 0 ? raw : null;
  }
  if (typeof raw !== 'string') return null;
  const temiz = raw.replaceAll('.', '').replace(',', '.').trim();
  const n = Number(temiz);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/// truncgil kaydından fiyat: alış yoksa satış.
///
/// ⚠️ 2026-09-15: v4 alan adları Türkçe'den İngilizce'ye döndü
/// (`Alış`→`Buying`, `Satış`→`Selling`). Eski adlar önce denenir ki API
/// geri dönerse çalışmaya devam etsin; ikisi de yoksa null.
export function truncgilValue(entry: unknown): number | null {
  if (typeof entry !== 'object' || entry === null) return null;
  const rec = entry as Record<string, unknown>;
  return parseTruncgilNumber(rec['Alış']) ??
    parseTruncgilNumber(rec['Buying']) ??
    parseTruncgilNumber(rec['Satış']) ??
    parseTruncgilNumber(rec['Selling']);
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
  return parseTruncgilBody(await res.text());
}

/// truncgil gövdesini ayrıştırır; KESİK gövdeden tam girişleri kurtarır.
///
/// `PriceService.parseTruncgilBody` ile AYNI kural — alarm, uygulamada
/// görünen sayıyla tetiklenmeli.
///
/// 2026-09-17: truncgil `v4/today.json`'u 6.805 baytta kesik gönderiyor
/// (`Content-Length` de kesik uzunlukta). `res.json()` reddediyor,
/// `fetchLivePrices` altın/döviz için boş dönüyor ve o alarmlar her turda
/// sessizce atlanıyordu (HTTP 200, hata yok). Gövde düz bir sözlük; kesim
/// noktasına kadarki `"KEY":{...}` girişleri bütündür, tek tek kurtarılır.
/// Gövde `{` ile başlamıyorsa (HTML hata sayfası) kurtarma DENENMEZ.
export function parseTruncgilBody(body: string): Record<string, unknown> {
  try {
    const decoded = JSON.parse(body);
    if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
      return decoded as Record<string, unknown>;
    }
    throw new SyntaxError('truncgil: kök nesne değil');
  } catch (e) {
    if (!body.trimStart().startsWith('{')) throw e;
    const out: Record<string, unknown> = {};
    // İç içe süslü parantez yok — `[^{}]*` bir girişi tam sınırlarıyla yakalar.
    for (const m of body.matchAll(/"([A-Za-z0-9_]+)"\s*:\s*(\{[^{}]*\})/g)) {
      try {
        const v = JSON.parse(m[2]);
        if (v && typeof v === 'object') out[m[1]] = v;
      } catch (_) {
        // Girişin kendisi bozuksa atla; komşuları hâlâ kurtarılabilir.
      }
    }
    if (Object.keys(out).length === 0) throw e;
    return out;
  }
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

/** Fiyat + günlük değişim yüzdesi (bilinmiyorsa null — uydurma yok). */
export type CanliKotasyon = { price: number; changePct: number | null };

/// Yahoo: fiyat + günlük değişim. Değişim `meta.chartPreviousClose` (dünkü
/// kapanış) üzerinden; meta yoksa yalnızca fiyat.
async function fetchYahooQuote(symbol: string): Promise<CanliKotasyon | null> {
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
    let price: number | null = null;
    const meta = result?.meta?.regularMarketPrice;
    if (typeof meta === 'number' && Number.isFinite(meta) && meta > 0) {
      price = meta;
    } else {
      const closes = result?.indicators?.quote?.[0]?.close;
      if (Array.isArray(closes)) {
        for (let i = closes.length - 1; i >= 0; i -= 1) {
          const v = closes[i];
          if (typeof v === 'number' && Number.isFinite(v) && v > 0) { price = v; break; }
        }
      }
    }
    if (price === null) return null;
    const onceki = result?.meta?.chartPreviousClose;
    const changePct = typeof onceki === 'number' && Number.isFinite(onceki) && onceki > 0
      ? (price / onceki - 1) * 100
      : null;
    return { price, changePct };
  } catch (_) {
    return null;
  }
}

/// truncgil günlük değişim (`Change: 0.08` = %0,08); alan yoksa null.
export function truncgilChange(entry: unknown): number | null {
  if (!entry || typeof entry !== 'object') return null;
  const raw = (entry as Record<string, unknown>)['Change'];
  if (typeof raw === 'number') return Number.isFinite(raw) ? raw : null;
  if (typeof raw === 'string') {
    const n = Number(raw.replace('%', '').replace(',', '.'));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/// Sembol → truncgil kaydı (altın anahtarı ya da 'USDTRY=X' → 'USD').
function truncgilKaydi(data: Record<string, unknown>, sym: string): unknown {
  if (isGoldSymbol(sym)) return data[GOLD_KEYS[sym]];
  if (isFxSymbol(sym)) return data[sym.slice(0, 3)];
  return undefined;
}

/// Fon sembolü öneki — `assets.ticker` ve `price_alerts.symbol` aynı biçim.
const TEFAS_PREFIX = 'TEFAS:';

export function isTefasSymbol(symbol: string): boolean {
  return symbol.startsWith(TEFAS_PREFIX);
}

/// Sembolleri kaynağına ayırır — saf, test edilebilir.
///
/// 2026-09-19'a kadar `TEFAS:` sembolleri Yahoo'ya gidiyordu ve orada hiç
/// bulunamıyordu: canlıda `checked:9, priced:3` — fon alarmları HİÇ
/// tetiklenmiyor, kullanıcı da "hedefe gelmedi" sanıyordu. Kanarya buna
/// takılmaz (map tamamen boş değil); bu yüzden ayrım burada açık yazıldı.
export function kaynakAyir(symbols: Iterable<string>): {
  truncgil: string[];
  tefas: string[];
  yahoo: string[];
} {
  const truncgil: string[] = [];
  const tefas: string[] = [];
  const yahoo: string[] = [];
  for (const s of symbols) {
    if (isGoldSymbol(s) || isFxSymbol(s)) truncgil.push(s);
    else if (isTefasSymbol(s)) tefas.push(s);
    else yahoo.push(s);
  }
  return { truncgil, tefas, yahoo };
}

/// Fonun son NAV'ı — `observe-tefas-nav` ile aynı uç nokta ve aynı süzgeç
/// (`sonNavSatiri`). Fon günde bir kez fiyatlanır; alarm için son NAV
/// "anlık fiyat"tır ve uygulamada görünen sayıyla aynıdır.
async function fetchTefasLast(symbol: string): Promise<number | null> {
  const kod = symbol.slice(TEFAS_PREFIX.length).trim().toUpperCase();
  if (!/^[A-Z0-9]{2,6}$/.test(kod)) return null;
  try {
    const res = await fetch('https://www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/plain, */*',
        'User-Agent': USER_AGENT,
      },
      body: JSON.stringify({ fonKodu: kod, dil: 'TR', periyod: 1 }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return sonNavSatiri(data?.resultList)?.fiyat ?? null;
  } catch (_) {
    // Tek fonun başarısızlığı turu düşürmemeli.
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
  for (const [k, v] of await fetchLiveQuotes(symbols)) out.set(k, v.price);
  return out;
}

/// Fiyat + günlük değişim (2026-09-20, takip listesi hareketi için).
///
/// `fetchLivePrices` bunun fiyat izdüşümü; kaynak seçimi ve sıralama aynı.
/// TEFAS'ta değişim yok (günlük NAV, tek nokta) → `changePct: null`.
export async function fetchLiveQuotes(
  symbols: Set<string>,
): Promise<Map<string, CanliKotasyon>> {
  const out = new Map<string, CanliKotasyon>();
  if (symbols.size === 0) return out;

  const { truncgil: truncgilList, tefas: tefasList, yahoo: yahooList } = kaynakAyir(symbols);

  // Fonlar: kod başına tek istek, sınırlı paralellik (TEFAS'ı boğma).
  for (let i = 0; i < tefasList.length; i += 4) {
    const dilim = tefasList.slice(i, i + 4);
    const sonuc = await Promise.all(dilim.map(fetchTefasLast));
    dilim.forEach((sym, j) => {
      const p = sonuc[j];
      if (p !== null) out.set(sym, { price: p, changePct: null });
    });
  }

  if (truncgilList.length > 0) {
    try {
      const data = await fetchTruncgil();
      for (const [k, v] of extractTruncgil(data, truncgilList)) {
        out.set(k, { price: v, changePct: truncgilChange(truncgilKaydi(data, k)) });
      }
    } catch (_) {
      // Altın/döviz kaynağı düştü — bu turda o alarmlar atlanır.
    }
  }

  // Sınırlı paralellik: kaynak API'yi boğmamak için (price_history.ts ile
  // aynı desen).
  const CONCURRENCY = 8;
  for (let i = 0; i < yahooList.length; i += CONCURRENCY) {
    const dilim = yahooList.slice(i, i + CONCURRENCY);
    const sonuc = await Promise.all(dilim.map(fetchYahooQuote));
    dilim.forEach((sym, j) => {
      const q = sonuc[j];
      if (q !== null) out.set(sym, q);
    });
  }

  return out;
}
