// Teknik analiz motoru — `lib/services/technical_analysis_service.dart`
// dosyasının BİREBİR portu.
//
// ⚠️ Bu dosya Dart karşılığıyla senkron kalmalıdır. Formül değişirse ikisi de
// güncellenmeli; aksi halde kullanıcı uygulamada bir sinyal, push'ta başka bir
// sinyal görür. Doğruluk `supabase/functions/_shared/technical_analysis_test.ts`
// içinde Dart çıktısından alınmış altın-standart vektörlerle doğrulanır.
//
// Kapsam notu: mevcut Dart implementasyonu yalnızca KAPANIŞ fiyatı kullanır
// (OHLC yok). Port da öyle — ADX gibi normalde OHLC isteyen göstergeler
// Dart'taki proxy hesabı aynen tekrarlar.

export type SignalType = 'buy' | 'sell' | 'neutral';

export type AssetType =
  | 'hisse'
  | 'fon'
  | 'altin'
  | 'doviz'
  | 'emtia'
  | 'kripto'
  | 'eurobond'
  | 'diger';

export interface TechnicalIndicator {
  /// Gösterge kimliği (`IndicatorId`). Özetin grup kararı ve W%R/Stokastik
  /// çift sayımı için; `computeById` doldurur. Dart `TechnicalIndicator.id`.
  id?: string;
  name: string;
  value: number;
  signal: SignalType;
  description: string;
}

export const IndicatorId = {
  rsi: 'rsi',
  macd: 'macd',
  bollinger: 'bollinger',
  ema: 'ema',
  stochastic: 'stochastic',
  adx: 'adx',
  williamsR: 'williams_r',
  cci: 'cci',
} as const;

/// İleri göstergeler (ADX, W%R, CCI): Dart `IndicatorId.ileri`. Kapı
/// kapalıyken hesaplanmaz (birebir eski davranış); kapı açıkken push yalnız
/// Premium'a gittiği için sekizi de hesaplanır.
export const PREMIUM_INDICATORS = new Set<string>([
  IndicatorId.adx,
  IndicatorId.williamsR,
  IndicatorId.cci,
]);

export const DEFAULT_INDICATORS = [
  IndicatorId.rsi,
  IndicatorId.macd,
  IndicatorId.bollinger,
  IndicatorId.ema,
  IndicatorId.stochastic,
];

/// Bir göstergenin kullanıcı ayarı (0142 `signal_preferences.parametreler`):
/// anahtar → tam sayı. Dart `GostergeAyari` + `GostergeParametreleri`.
export type GostergeAyari = Record<string, number>;

const PARAMETRE_TANIMLARI: Record<string, [string, number, number][]> = {
  rsi: [['periyot', 2, 50]],
  macd: [['hizli', 2, 50], ['yavas', 3, 80], ['sinyal', 2, 30]],
  bollinger: [['periyot', 5, 60]],
  ema: [['kisa', 2, 60], ['uzun', 3, 100]],
  stochastic: [['periyot', 3, 50]],
  adx: [['periyot', 3, 50]],
  williams_r: [['periyot', 3, 50]],
  cci: [['periyot', 5, 60]],
};

/// Dart `GostergeParametreleri.dogrula` ile birebir: bilinmeyen anahtar
/// atılır, değer sınıra kırpılır, kısa ≥ uzun çiftinde ayarın tümü yok
/// sayılır. Boş sonuç undefined.
export function parametreDogrula(
  id: string,
  ham: unknown,
): GostergeAyari | undefined {
  if (!ham || typeof ham !== 'object') return undefined;
  const tanim = PARAMETRE_TANIMLARI[id];
  if (!tanim) return undefined;
  const out: GostergeAyari = {};
  for (const [k, enAz, enCok] of tanim) {
    const v = (ham as Record<string, unknown>)[k];
    if (typeof v !== 'number' || !Number.isFinite(v)) continue;
    out[k] = Math.min(enCok, Math.max(enAz, Math.round(v)));
  }
  if (Object.keys(out).length === 0) return undefined;
  const ters = (a: string, b: string) =>
    out[a] !== undefined && out[b] !== undefined && out[a] >= out[b];
  if (ters('hizli', 'yavas') || ters('kisa', 'uzun')) return undefined;
  return out;
}

// Dart `fmtNum(value, digits: n)` — tr_TR biçimi (ondalık ayırıcı virgül).
// Açıklama metinleri kullanıcıya gösterildiği için biçim de birebir olmalı.
function fmtNum(value: number, digits: number): string {
  return value.toLocaleString('tr-TR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

// ── EMA ─────────────────────────────────────────────────────────────────────
// Dart `_ema` ile birebir: son (period*3) noktaya bakar, ilk `period` elemanın
// ortalamasıyla başlar, ardından klasik k-çarpanıyla ilerler.
function ema(prices: number[], period: number): number {
  if (prices.length === 0) return 0;
  const len = Math.min(prices.length, period * 3);
  const sub = prices.slice(prices.length - len);
  const seedCount = Math.min(period, sub.length);

  let value = sub.slice(0, seedCount).reduce((a, b) => a + b, 0) / seedCount;
  const k = 2 / (period + 1);
  for (let i = seedCount; i < sub.length; i++) {
    value = sub[i] * k + value * (1 - k);
  }
  return value;
}

// ── 1. RSI ──────────────────────────────────────────────────────────────────
export function rsi(prices: number[], type: AssetType, par?: GostergeAyari): TechnicalIndicator {
  const period = par?.periyot ?? (type === 'doviz' ? 9 : 14);
  const label = `RSI (${period})`;

  if (prices.length < period + 1) {
    return { name: label, value: 50, signal: 'neutral', description: 'Yetersiz veri' };
  }

  // Wilder RSI (TradingView `ta.rsi`): ilk [period] değişimin basit
  // ortalaması tohumdur, sonra RMA (α = 1/period) ile bütün seri boyunca
  // yumuşatılır. 2026-10-11 denetimine kadar yalnız son [period] değişimin
  // basit ortalaması alınıyordu (Cutler RSI): TradingView'den ortalama 6,5
  // puan farklıydı ve uygulamanın kendi Pine RSI şablonuyla çelişiyordu.
  let avgG = 0;
  let avgL = 0;
  for (let i = 1; i <= period; i++) {
    const d = prices[i] - prices[i - 1];
    if (d > 0) avgG += d;
    else avgL -= d;
  }
  avgG /= period;
  avgL /= period;
  for (let i = period + 1; i < prices.length; i++) {
    const d = prices[i] - prices[i - 1];
    avgG = (avgG * (period - 1) + (d > 0 ? d : 0)) / period;
    avgL = (avgL * (period - 1) + (d < 0 ? -d : 0)) / period;
  }
  const value = avgL === 0 ? 100 : avgG === 0 ? 0 : 100 - 100 / (1 + avgG / avgL);

  // Eşik her türde 70/30 (TradingView varsayılanı; RSI şablonunun
  // çizgileriyle aynı). Hisse dışı 72/28 basit RSI'ın oynaklığını
  // bastırmak içindi; Wilder RSI'da gerekmez.
  const overbought = 70;
  const oversold = 30;

  const signal: SignalType =
    value < oversold ? 'buy' : value > overbought ? 'sell' : 'neutral';

  const description =
    value < oversold
      ? `Aşırı satım bölgesi (${fmtNum(value, 1)})`
      : value > overbought
        ? `Aşırı alım bölgesi (${fmtNum(value, 1)})`
        : `Nötr bölge (${fmtNum(value, 1)})`;

  return { name: label, value, signal, description };
}

// ── 2. MACD ─────────────────────────────────────────────────────────────────
export function macd(prices: number[], type: AssetType, par?: GostergeAyari): TechnicalIndicator {
  const fast = par?.hizli ?? (type === 'fon' ? 8 : 12);
  const slow = par?.yavas ?? (type === 'fon' ? 21 : 26);
  const sig = par?.sinyal ?? 9;
  const label = `MACD (${fast},${slow},${sig})`;

  if (prices.length < slow + sig) {
    return { name: label, value: 0, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const macdLine = ema(prices, fast) - ema(prices, slow);

  // Dart ile aynı (maliyetli ama birebir) yaklaşım: her prefix için EMA farkı.
  const macdSeries: number[] = [];
  for (let i = slow; i <= prices.length; i++) {
    const sub = prices.slice(0, i);
    macdSeries.push(ema(sub, fast) - ema(sub, slow));
  }
  const signalLine = ema(macdSeries, sig);
  const histogram = macdLine - signalLine;

  const signal: SignalType =
    histogram > 0 ? 'buy' : histogram < 0 ? 'sell' : 'neutral';

  // Histogram fiyatın yüzdesiyle yazılır: ham fark ₺1'lik fonda "+0,00",
  // altında dolar/ons olurdu (denetim 2026-10-11, bulgu 12).
  const son = prices[prices.length - 1];
  const yuzde = son !== 0 ? (histogram / son) * 100 : 0;
  const description =
    histogram > 0
      ? `MACD çizgisi sinyal üzerinde (+%${fmtNum(yuzde, 2)})`
      : histogram < 0
        ? `MACD çizgisi sinyal altında (-%${fmtNum(-yuzde, 2)})`
        : 'Kesişim noktasında';

  return { name: label, value: histogram, signal, description };
}

// ── 3. Bollinger Bantları ───────────────────────────────────────────────────
export function bollingerBands(
  prices: number[],
  type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator {
  const period = par?.periyot ?? (type === 'altin' ? 14 : 20);
  const mult = type === 'doviz' ? 1.5 : 2.0;
  // Dart `double` her zaman ondalık basar (2.0 → "2.0"); JS `Number` basmaz
  // (2.0 → "2"). Etiket kullanıcıya görünüyor, birebir eşleşmeli.
  // "2σ", "1.5σ": Dart portuyla aynı ("2.0σ" gürültüydü, 2026-11-01).
  const label = `Bollinger (${period}, ${String(mult)}σ)`;

  if (prices.length < period) {
    return { name: label, value: 50, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const recent = prices.slice(prices.length - period);
  const sma = recent.reduce((a, b) => a + b, 0) / period;
  const variance =
    recent.reduce((acc, p) => acc + Math.pow(p - sma, 2), 0) / period;
  const stdDev = Math.sqrt(variance);
  const upper = sma + stdDev * mult;
  const lower = sma - stdDev * mult;
  const current = prices[prices.length - 1];

  const pctB = upper - lower > 0 ? (current - lower) / (upper - lower) : 0.5;

  const signal: SignalType =
    current < lower ? 'buy' : current > upper ? 'sell' : 'neutral';

  const description =
    current < lower
      ? 'Alt bandın altında: potansiyel dönüş'
      : current > upper
        ? 'Üst bandın üzerinde: potansiyel düzeltme'
        : `%B: ${fmtNum(pctB * 100, 0)} (bant içi)`;

  return { name: label, value: pctB * 100, signal, description };
}

// ── 4. EMA Kesişimi ─────────────────────────────────────────────────────────
export function movingAverage(
  prices: number[],
  type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator {
  let shortP: number;
  let longP: number;
  if (type === 'hisse') { shortP = 20; longP = 50; }
  else if (type === 'fon') { shortP = 10; longP = 30; }
  else if (type === 'altin') { shortP = 14; longP = 40; }
  else if (type === 'doviz') { shortP = 7; longP = 21; }
  else { shortP = 20; longP = 50; }
  shortP = par?.kisa ?? shortP;
  longP = par?.uzun ?? longP;

  const label = `EMA Kesişim (${shortP}/${longP})`;

  if (prices.length < longP) {
    return { name: label, value: 0, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const shortEma = ema(prices, shortP);
  const longEma = ema(prices, longP);
  const current = prices[prices.length - 1];
  const diff = ((shortEma - longEma) / longEma) * 100;

  const signal: SignalType =
    shortEma > longEma && current > shortEma
      ? 'buy'
      : shortEma < longEma && current < shortEma
        ? 'sell'
        : 'neutral';

  // Açıklama sinyalle aynı şeyi söylemeli (Dart ile birebir; gerekçe
  // `technical_analysis_service.dart` movingAverage notunda, emülatör
  // testi #31): teyitsiz kesişim "yükseliş trendi" diye yazılmaz.
  const description =
    signal === 'buy'
      ? `EMA${shortP} > EMA${longP}: yükseliş trendi`
      : signal === 'sell'
        ? `EMA${shortP} < EMA${longP}: düşüş trendi`
        : shortEma > longEma
          ? `EMA${shortP} > EMA${longP}, fiyat EMA${shortP} altında, teyit yok`
          : shortEma < longEma
            ? `EMA${shortP} < EMA${longP}, fiyat EMA${shortP} üstünde, teyit yok`
            : 'Ortalamalarda kesişim bölgesi';

  return { name: label, value: diff, signal, description };
}

// ── 5. Stokastik Osilatör ───────────────────────────────────────────────────
export function stochastic(
  prices: number[],
  type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator {
  const period = par?.periyot ?? (type === 'doviz' ? 9 : 14);
  const overbought = 80;
  const oversold = 20;
  const label = `Stokastik %K (${period})`;

  if (prices.length < period) {
    return { name: label, value: 50, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const recent = prices.slice(prices.length - period);
  const lowest = Math.min(...recent);
  const highest = Math.max(...recent);
  const current = prices[prices.length - 1];
  const range = highest - lowest;
  const k = range === 0 ? 50 : ((current - lowest) / range) * 100;

  const signal: SignalType =
    k < oversold ? 'buy' : k > overbought ? 'sell' : 'neutral';

  const description =
    k < oversold
      ? `Aşırı satım (%K: ${fmtNum(k, 1)})`
      : k > overbought
        ? `Aşırı alım (%K: ${fmtNum(k, 1)})`
        : `Nötr bölge (%K: ${fmtNum(k, 1)})`;

  return { name: label, value: k, signal, description };
}

// ── 6. Trend gücü (kimlik 'adx'; Dart ile aynı) ────────────────────────────
// Formül |Σyükseliş − Σdüşüş| ÷ Σ|değişim| (Kaufman verim oranı). Gerçek
// ADX yüksek/düşük ister, yön vermez; sunucu yalnız kapanış tutar. Bu yüzden
// adı "Trend Gücü" (denetim 2026-10-11, bulgu 6); kimlik ayarlar bozulmasın
// diye 'adx' kalır.
export function adx(prices: number[], _type: AssetType, par?: GostergeAyari): TechnicalIndicator {
  const period = par?.periyot ?? 14;
  const label = `Trend Gücü (${period})`;

  if (prices.length < period + 1) {
    return { name: label, value: 0, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const recent = prices.slice(prices.length - period - 1);
  let sumUp = 0;
  let sumDown = 0;
  let sumRange = 0;
  for (let i = 1; i < recent.length; i++) {
    const d = recent[i] - recent[i - 1];
    if (d > 0) sumUp += d;
    else sumDown -= d;
    sumRange += Math.abs(d);
  }
  if (sumRange === 0) {
    return { name: label, value: 0, signal: 'neutral', description: 'Yatay (trend yok)' };
  }
  const directional = (Math.abs(sumUp - sumDown) / sumRange) * 100;

  const signal: SignalType =
    directional > 25 ? (sumUp > sumDown ? 'buy' : 'sell') : 'neutral';

  const description =
    directional > 40
      ? `Güçlü trend (${fmtNum(directional, 0)})`
      : directional > 25
        ? `Trend başlıyor (${fmtNum(directional, 0)})`
        : `Zayıf trend (${fmtNum(directional, 0)})`;

  return { name: label, value: directional, signal, description };
}

// ── 7. Williams %R ──────────────────────────────────────────────────────────
export function williamsR(
  prices: number[],
  _type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator {
  const period = par?.periyot ?? 14;
  const label = `Williams %R (${period})`;

  if (prices.length < period) {
    return { name: label, value: -50, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const recent = prices.slice(prices.length - period);
  const highest = Math.max(...recent);
  const lowest = Math.min(...recent);
  const current = prices[prices.length - 1];
  const range = highest - lowest;
  const wr = range === 0 ? -50 : ((highest - current) / range) * -100;

  const signal: SignalType = wr < -80 ? 'buy' : wr > -20 ? 'sell' : 'neutral';

  const description =
    wr < -80
      ? `Aşırı satım (${fmtNum(wr, 0)})`
      : wr > -20
        ? `Aşırı alım (${fmtNum(wr, 0)})`
        : `Nötr bölge (${fmtNum(wr, 0)})`;

  return { name: label, value: wr, signal, description };
}

// ── 8. CCI ──────────────────────────────────────────────────────────────────
export function cci(prices: number[], _type: AssetType, par?: GostergeAyari): TechnicalIndicator {
  const period = par?.periyot ?? 20;
  const label = `CCI (${period})`;

  if (prices.length < period) {
    return { name: label, value: 0, signal: 'neutral', description: 'Yetersiz veri' };
  }

  const recent = prices.slice(prices.length - period);
  const sma = recent.reduce((a, b) => a + b, 0) / period;
  const meanDev =
    recent.reduce((acc, p) => acc + Math.abs(p - sma), 0) / period;
  const current = prices[prices.length - 1];
  const value = meanDev === 0 ? 0 : (current - sma) / (0.015 * meanDev);

  const signal: SignalType =
    value < -100 ? 'buy' : value > 100 ? 'sell' : 'neutral';

  const description =
    value < -100
      ? `Aşırı satım (${fmtNum(value, 0)})`
      : value > 100
        ? `Aşırı alım (${fmtNum(value, 0)})`
        : `Nötr bölge (${fmtNum(value, 0)})`;

  return { name: label, value, signal, description };
}

// ── Dispatcher ──────────────────────────────────────────────────────────────
function computeById(
  id: string,
  prices: number[],
  type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator | null {
  const ind = hesapla(id, prices, type, par);
  return ind ? { id, ...ind } : null;
}

function hesapla(
  id: string,
  prices: number[],
  type: AssetType,
  par?: GostergeAyari,
): TechnicalIndicator | null {
  switch (id) {
    case IndicatorId.rsi: return rsi(prices, type, par);
    case IndicatorId.macd: return macd(prices, type, par);
    case IndicatorId.bollinger: return bollingerBands(prices, type, par);
    case IndicatorId.ema: return movingAverage(prices, type, par);
    case IndicatorId.stochastic: return stochastic(prices, type, par);
    case IndicatorId.adx: return adx(prices, type, par);
    case IndicatorId.williamsR: return williamsR(prices, type, par);
    case IndicatorId.cci: return cci(prices, type, par);
    default: return null;
  }
}

/**
 * Verilen fiyat serisi için seçili göstergeleri hesaplar.
 *
 * Dart tarafından farkı: fiyat geçmişi YOKSA simülasyona düşmez. Sunucuda
 * uydurma seri üzerinden push atmak kabul edilemez — veri yoksa sinyal yok.
 */
export function analyze(
  prices: number[],
  type: AssetType,
  enabledIds: string[],
  premiumUnlocked: boolean,
  parametreler?: Record<string, unknown> | null,
): TechnicalIndicator[] {
  if (prices.length === 0) return [];

  const result: TechnicalIndicator[] = [];
  for (const id of enabledIds) {
    if (PREMIUM_INDICATORS.has(id) && !premiumUnlocked) continue;
    const ind = computeById(id, prices, type, parametreDogrula(id, parametreler?.[id]));
    if (ind) result.push(ind);
  }
  return result;
}

/// Ortalamaya dönüş (aşırılık) göstergeleri: "al" oyu "çok düştü" demektir,
/// "yükseliş trendi" değil. Kalanlar (MACD, EMA, trend gücü) trend
/// göstergesidir. Dart `IndicatorId.donus`.
export const DONUS_INDICATORS = new Set<string>([
  IndicatorId.rsi,
  IndicatorId.bollinger,
  IndicatorId.stochastic,
  IndicatorId.williamsR,
  IndicatorId.cci,
]);

/**
 * Genel sinyal özeti.
 *
 * [confidence] 0-100 ölçeğindedir — kullanıcının eşiği de yüzdedir.
 *
 * Williams %R, Stokastik ile birlikte açıksa sayılmaz: ikisi de kapanıştan
 * aynı pencerenin uçlarına bakar (W%R = %K − 100), aynı bilgi iki oy
 * olurdu (denetim 2026-10-11, bulgu 5).
 *
 * [donus]: kazanan yönün oylarının çoğu ortalamaya dönüş göstergelerinden
 * geliyorsa true — "al" aşırı satım, "sat" aşırı alım demektir; ekran ve
 * push bunu trend yönü diye yazmaz (bulgu 1).
 */
export function summarize(indicators: TechnicalIndicator[]): {
  signal: SignalType;
  buyCount: number;
  sellCount: number;
  confidence: number;
  donus: boolean;
  /// Oylamaya giren gösterge sayısı (W%R çift sayımı düşülmüş). Güven
  /// yüzdesinin paydası; push metni de bunu yazar.
  toplam: number;
} {
  const stokastikVar = indicators.some((i) => i.id === IndicatorId.stochastic);
  const sayilan = stokastikVar
    ? indicators.filter((i) => i.id !== IndicatorId.williamsR)
    : indicators;
  const buy = sayilan.filter((i) => i.signal === 'buy').length;
  const sell = sayilan.filter((i) => i.signal === 'sell').length;
  const total = sayilan.length;

  if (total === 0) {
    return { signal: 'neutral', buyCount: 0, sellCount: 0, confidence: 0, donus: false, toplam: 0 };
  }

  const buyRatio = buy / total;
  const sellRatio = sell / total;

  const signal: SignalType =
    buyRatio >= 0.6 ? 'buy' : sellRatio >= 0.6 ? 'sell' : 'neutral';

  let donus = false;
  if (signal !== 'neutral') {
    const lehte = sayilan.filter((i) => i.signal === signal);
    const d = lehte.filter((i) => i.id !== undefined && DONUS_INDICATORS.has(i.id)).length;
    donus = d > lehte.length - d;
  }

  return {
    signal,
    buyCount: buy,
    sellCount: sell,
    confidence: Math.max(buyRatio, sellRatio) * 100,
    donus,
    toplam: total,
  };
}
