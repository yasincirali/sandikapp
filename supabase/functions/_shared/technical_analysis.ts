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
  | 'mevduat'
  | 'diger';

export interface TechnicalIndicator {
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
export function rsi(prices: number[], type: AssetType): TechnicalIndicator {
  const period = type === 'doviz' ? 9 : 14;
  const label = `RSI (${period})`;

  if (prices.length < period + 1) {
    return { name: label, value: 50, signal: 'neutral', description: 'Yetersiz veri' };
  }

  let gains = 0;
  let losses = 0;
  for (let i = prices.length - period; i < prices.length; i++) {
    const d = prices[i] - prices[i - 1];
    if (d > 0) gains += d;
    else losses -= d;
  }
  const avgG = gains / period;
  const avgL = losses / period;
  const value = avgL === 0 ? 100 : 100 - 100 / (1 + avgG / avgL);

  const overbought = type === 'hisse' ? 70 : 72;
  const oversold = type === 'hisse' ? 30 : 28;

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
export function macd(prices: number[], type: AssetType): TechnicalIndicator {
  const fast = type === 'fon' ? 8 : 12;
  const slow = type === 'fon' ? 21 : 26;
  const sig = 9;
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

  const description =
    histogram > 0
      ? `MACD çizgisi sinyal üzerinde (+${fmtNum(histogram, 2)})`
      : histogram < 0
        ? `MACD çizgisi sinyal altında (${fmtNum(histogram, 2)})`
        : 'Kesişim noktasında';

  return { name: label, value: histogram, signal, description };
}

// ── 3. Bollinger Bantları ───────────────────────────────────────────────────
export function bollingerBands(
  prices: number[],
  type: AssetType,
): TechnicalIndicator {
  const period = type === 'altin' ? 14 : 20;
  const mult = type === 'doviz' ? 1.5 : 2.0;
  // Dart `double` her zaman ondalık basar (2.0 → "2.0"); JS `Number` basmaz
  // (2.0 → "2"). Etiket kullanıcıya görünüyor, birebir eşleşmeli.
  const label = `Bollinger (${period}, ${mult.toFixed(1)}σ)`;

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
      ? 'Alt bantın altında — potansiyel dönüş'
      : current > upper
        ? 'Üst bantın üzerinde — potansiyel düzeltme'
        : `%B: ${fmtNum(pctB * 100, 0)} (bant içi)`;

  return { name: label, value: pctB * 100, signal, description };
}

// ── 4. EMA Kesişimi ─────────────────────────────────────────────────────────
export function movingAverage(
  prices: number[],
  type: AssetType,
): TechnicalIndicator {
  let shortP: number;
  let longP: number;
  if (type === 'hisse') { shortP = 20; longP = 50; }
  else if (type === 'fon') { shortP = 10; longP = 30; }
  else if (type === 'altin') { shortP = 14; longP = 40; }
  else if (type === 'doviz') { shortP = 7; longP = 21; }
  else { shortP = 20; longP = 50; }

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

  const description =
    shortEma > longEma
      ? `EMA${shortP} > EMA${longP} — yükseliş trendi`
      : shortEma < longEma
        ? `EMA${shortP} < EMA${longP} — düşüş trendi`
        : 'Ortalamalarda kesişim bölgesi';

  return { name: label, value: diff, signal, description };
}

// ── 5. Stokastik Osilatör ───────────────────────────────────────────────────
export function stochastic(
  prices: number[],
  type: AssetType,
): TechnicalIndicator {
  const period = type === 'doviz' ? 9 : 14;
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

// ── 6. ADX (proxy — Dart ile aynı basitleştirme) ────────────────────────────
export function adx(prices: number[], _type: AssetType): TechnicalIndicator {
  const period = 14;
  const label = `ADX (${period})`;

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
): TechnicalIndicator {
  const period = 14;
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
export function cci(prices: number[], _type: AssetType): TechnicalIndicator {
  const period = 20;
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
): TechnicalIndicator | null {
  switch (id) {
    case IndicatorId.rsi: return rsi(prices, type);
    case IndicatorId.macd: return macd(prices, type);
    case IndicatorId.bollinger: return bollingerBands(prices, type);
    case IndicatorId.ema: return movingAverage(prices, type);
    case IndicatorId.stochastic: return stochastic(prices, type);
    case IndicatorId.adx: return adx(prices, type);
    case IndicatorId.williamsR: return williamsR(prices, type);
    case IndicatorId.cci: return cci(prices, type);
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
): TechnicalIndicator[] {
  if (prices.length === 0) return [];

  const result: TechnicalIndicator[] = [];
  for (const id of enabledIds) {
    if (PREMIUM_INDICATORS.has(id) && !premiumUnlocked) continue;
    const ind = computeById(id, prices, type);
    if (ind) result.push(ind);
  }
  return result;
}

/**
 * Genel sinyal özeti.
 *
 * [confidence] 0-100 ölçeğindedir — kullanıcının eşiği de yüzdedir.
 * (Dart tarafında bu değer bir dönem 0..1 oranı dönüyordu ve eşik
 * karşılaştırması hiç geçmiyordu; port doğru ölçekle yazıldı.)
 */
export function summarize(indicators: TechnicalIndicator[]): {
  signal: SignalType;
  buyCount: number;
  sellCount: number;
  confidence: number;
} {
  const buy = indicators.filter((i) => i.signal === 'buy').length;
  const sell = indicators.filter((i) => i.signal === 'sell').length;
  const total = indicators.length;

  if (total === 0) {
    return { signal: 'neutral', buyCount: 0, sellCount: 0, confidence: 0 };
  }

  const buyRatio = buy / total;
  const sellRatio = sell / total;

  const signal: SignalType =
    buyRatio >= 0.6 ? 'buy' : sellRatio >= 0.6 ? 'sell' : 'neutral';

  return {
    signal,
    buyCount: buy,
    sellCount: sell,
    confidence: Math.max(buyRatio, sellRatio) * 100,
  };
}
