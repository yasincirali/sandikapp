// TypeScript TA portunun Dart implementasyonuyla BİREBİR aynı sonucu
// verdiğini doğrular.
//
// Altın standart vektörler Dart'tan üretilir:
//   GOLDEN=1 flutter test test/ta_golden_vectors_test.dart
//
// Bu test çalıştırılır:
//   deno test --allow-read supabase/functions/_shared/technical_analysis_test.ts
//
// Bir formül tek tarafta değişirse bu test kırılır — kullanıcının uygulamada
// bir sinyal, push'ta başka sinyal görmesini engelleyen güvenlik ağı budur.

import { assertEquals } from 'jsr:@std/assert@1';
import {
  adx,
  analyze,
  AssetType,
  bollingerBands,
  cci,
  macd,
  movingAverage,
  rsi,
  SignalType,
  stochastic,
  summarize,
  TechnicalIndicator,
  williamsR,
} from '../functions/_shared/technical_analysis.ts';

interface GoldenIndicator {
  id: string;
  name: string;
  value: number;
  signal: SignalType;
  description: string;
}

interface GoldenCase {
  series: string;
  type: AssetType;
  prices: number[];
  indicators: GoldenIndicator[];
  summary: {
    signal: SignalType;
    buyCount: number;
    sellCount: number;
    confidence: number;
  };
}

const golden: { cases: GoldenCase[] } = JSON.parse(
  await Deno.readTextFile(
    new URL('./ta_golden_vectors.json', import.meta.url),
  ),
);

function computeById(
  id: string,
  prices: number[],
  type: AssetType,
): TechnicalIndicator | null {
  switch (id) {
    case 'rsi': return rsi(prices, type);
    case 'macd': return macd(prices, type);
    case 'bollinger': return bollingerBands(prices, type);
    case 'ema': return movingAverage(prices, type);
    case 'stochastic': return stochastic(prices, type);
    case 'adx': return adx(prices, type);
    case 'williams_r': return williamsR(prices, type);
    case 'cci': return cci(prices, type);
    default: return null;
  }
}

/// Kayan nokta: iki dilin son-bit farkları testi kırmasın.
function round6(v: number): number {
  return Number(v.toFixed(6));
}

/// Sayısal yakınlık kontrolü.
///
/// Dart ve V8 IEEE-754 çift duyarlık kullanır ama toplama sırası ve
/// derleyici optimizasyonları son bitte ayrışabiliyor (ör. Stokastik'te
/// 49.412063 vs 49.412064). Bu bir mantık hatası değil; tolerans
/// göstergenin ölçeğine göre belirlenir.
///
/// 1e-6 GÖRECELİ tolerans: sinyal eşikleri (RSI 30/70, CCI ±100 gibi) bu
/// mertebede bir farktan etkilenmez — sinyal tipi ayrıca birebir
/// karşılaştırılıyor, asıl güvence orada.
function assertClose(actual: number, expected: number, where: string): void {
  if (actual === expected) return;

  const scale = Math.max(Math.abs(actual), Math.abs(expected), 1);
  const diff = Math.abs(actual - expected);
  if (diff / scale <= 1e-6) return;

  throw new Error(
    `${where} → değer sapması: actual=${actual} expected=${expected} ` +
      `(fark=${diff}, göreceli=${diff / scale})`,
  );
}

Deno.test('altın standart: her gösterge Dart ile aynı değeri üretir', () => {
  let checked = 0;

  for (const c of golden.cases) {
    for (const expected of c.indicators) {
      const actual = computeById(expected.id, c.prices, c.type);
      if (actual === null) {
        throw new Error(`bilinmeyen gösterge id: ${expected.id}`);
      }

      const where = `${c.series}/${c.type}/${expected.id}`;

      assertEquals(actual.name, expected.name, `${where} → isim`);
      // Sinyal tipi BİREBİR eşleşmeli — asıl davranışsal güvence bu.
      assertEquals(actual.signal, expected.signal, `${where} → sinyal`);
      assertClose(actual.value, expected.value, where);
      // Açıklama metni kullanıcıya gösteriliyor; biçim farkı da hatadır.
      assertEquals(
        actual.description,
        expected.description,
        `${where} → açıklama`,
      );
      checked++;
    }
  }

  if (checked === 0) throw new Error('hiç vektör doğrulanmadı');
  console.log(`  ${checked} gösterge çıktısı Dart ile eşleşti`);
});

Deno.test('altın standart: özet (signal/confidence) Dart ile aynı', () => {
  for (const c of golden.cases) {
    const indicators = c.indicators
      .map((g) => computeById(g.id, c.prices, c.type))
      .filter((i): i is TechnicalIndicator => i !== null);

    const s = summarize(indicators);
    const where = `${c.series}/${c.type}`;

    assertEquals(s.signal, c.summary.signal, `${where} → özet sinyal`);
    assertEquals(s.buyCount, c.summary.buyCount, `${where} → buy sayısı`);
    assertEquals(s.sellCount, c.summary.sellCount, `${where} → sell sayısı`);
    assertEquals(
      round6(s.confidence),
      round6(c.summary.confidence),
      `${where} → confidence`,
    );
  }
});

Deno.test('confidence 0-100 ölçeğinde (eşikle aynı birim)', () => {
  const allBuy: TechnicalIndicator[] = Array.from({ length: 5 }, () => ({
    name: 'x',
    value: 0,
    signal: 'buy' as SignalType,
    description: '',
  }));

  const s = summarize(allBuy);
  assertEquals(s.confidence, 100);
  assertEquals(s.signal, 'buy');
});

Deno.test('fiyat geçmişi yoksa sinyal üretilmez (simülasyona düşmez)', () => {
  // Sunucuda uydurma seri üzerinden push atmak kabul edilemez.
  const result = analyze([], 'hisse', ['rsi', 'macd'], false);
  assertEquals(result.length, 0);
});

Deno.test('premium göstergeler kilitliyken atlanır', () => {
  const prices = Array.from({ length: 120 }, (_, i) => 100 + i * 0.8);

  const locked = analyze(prices, 'hisse', ['rsi', 'adx', 'cci'], false);
  assertEquals(locked.map((i) => i.name.split(' ')[0]), ['RSI']);

  const unlocked = analyze(prices, 'hisse', ['rsi', 'adx', 'cci'], true);
  assertEquals(unlocked.length, 3);
});
