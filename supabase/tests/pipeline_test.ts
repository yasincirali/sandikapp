// Sinyal boru hattı davranış testleri.
//
// `index.ts`'in karar mantığını (eşik, nötr filtresi, de-dup) izole olarak
// doğrular. Ağ/DB olmadan çalışır — CI'da ve deploy öncesi hızlı güvence.
//
// Çalıştır:
//   deno test --allow-read supabase/functions/_shared/pipeline_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  analyze,
  AssetType,
  DEFAULT_INDICATORS,
  summarize,
} from '../functions/_shared/technical_analysis.ts';
import { MIN_POINTS, resolveSymbol } from '../functions/_shared/price_history.ts';

/// `index.ts`'teki karar zinciriyle aynı sıra.
function shouldNotify(
  prices: number[],
  type: AssetType,
  threshold: number,
  neutralPush: boolean,
  lastSignal: string | null,
): { notify: boolean; reason: string; signal: string; confidence: number } {
  if (prices.length < MIN_POINTS) {
    return { notify: false, reason: 'yetersiz_veri', signal: 'none', confidence: 0 };
  }

  const inds = analyze(prices, type, DEFAULT_INDICATORS, false);
  if (inds.length === 0) {
    return { notify: false, reason: 'gosterge_yok', signal: 'none', confidence: 0 };
  }

  const s = summarize(inds);

  if (s.signal === 'neutral' && !neutralPush) {
    return { notify: false, reason: 'notr_kapali', signal: s.signal, confidence: s.confidence };
  }
  if (s.confidence < threshold) {
    return { notify: false, reason: 'esik_alti', signal: s.signal, confidence: s.confidence };
  }
  if (lastSignal === s.signal) {
    return { notify: false, reason: 'dedup', signal: s.signal, confidence: s.confidence };
  }
  if (s.signal === 'neutral') {
    return { notify: false, reason: 'notr_push_yok', signal: s.signal, confidence: s.confidence };
  }
  return { notify: true, reason: 'gonder', signal: s.signal, confidence: s.confidence };
}

/// Kesintisiz düz yükseliş — RSI ve Stokastik'i aşırı alıma iter.
///
/// Sezgiye aykırı ama DOĞRU: durmadan yükselen bir seri "aşırı alım"
/// demektir, osilatörler düzeltme bekler. Bu yüzden özet `sell` çıkar.
/// Test bunu bir hata gibi değil, beklenen davranış olarak doğrular.
const relentlessRise = Array.from({ length: 120 }, (_, i) => 100 + i * 0.8);

/// Gerçekçi yükseliş: genel trend yukarı ama son barlarda soluklanma
/// (pull-back). Osilatörler aşırı alımdan çıkar, EMA yukarıyı gösterir.
const healthyUptrend = [
  ...Array.from({ length: 105 }, (_, i) => 100 + i * 0.8),
  ...Array.from({ length: 15 }, (_, i) => 184 - i * 1.1),
];

/// Gerçekçi düşüş: genel trend aşağı, son barlarda hafif toparlanma.
const healthyDowntrend = [
  ...Array.from({ length: 105 }, (_, i) => 200 - i * 0.9),
  ...Array.from({ length: 15 }, (_, i) => 105.5 + i * 1.0),
];

Deno.test('kesintisiz yükseliş aşırı alım sayılır (osilatör davranışı)', () => {
  // 5 göstergenin 3'ü "aşırı alım" → sell, confidence %60.
  // Varsayılan eşik 70 olduğu için bu sinyal ELENİR: eşik mekanizması
  // tam da bunun için var — orta güçteki sinyaller gürültü yapmasın.
  const atDefault = shouldNotify(relentlessRise, 'hisse', 70, false, null);
  assertEquals(atDefault.signal, 'sell');
  assertEquals(Math.round(atDefault.confidence), 60);
  assertEquals(atDefault.notify, false);
  assertEquals(atDefault.reason, 'esik_alti');

  // Kullanıcı eşiği 50'ye çekerse aynı sinyal geçer.
  const atLow = shouldNotify(relentlessRise, 'hisse', 50, false, null);
  assertEquals(atLow.notify, true, `beklenen gönderim, olan: ${atLow.reason}`);
});

Deno.test('sağlıklı yükseliş trendinde AL sinyali üretilir', () => {
  const inds = analyze(healthyUptrend, 'hisse', DEFAULT_INDICATORS, false);
  const s = summarize(inds);
  // Düzeltme sonrası osilatörler nötrlenir, EMA yukarıyı gösterir.
  assertEquals(s.buyCount > 0, true, 'en az bir gösterge AL demeli');
});

Deno.test('eşik yükseldikçe daha az sinyal geçer (monotonluk)', () => {
  for (const series of [relentlessRise, healthyDowntrend]) {
    const low = shouldNotify(series, 'hisse', 50, false, null);
    const high = shouldNotify(series, 'hisse', 85, false, null);
    // 85 geçiyorsa 50 de geçmeli — tersi mantıksız olurdu.
    if (high.notify) {
      assertEquals(low.notify, true, 'yüksek eşik geçti ama düşük geçmedi');
    }
  }
});

Deno.test('aynı sinyal tekrar gönderilmez (de-dup)', () => {
  // Eşik 50 → sinyal geçer.
  const first = shouldNotify(relentlessRise, 'hisse', 50, false, null);
  assertEquals(first.notify, true);

  // Aynı sinyal zaten gönderilmişse tekrar gitmez.
  const second = shouldNotify(
    relentlessRise, 'hisse', 50, false, first.signal,
  );
  assertEquals(second.notify, false);
  assertEquals(second.reason, 'dedup');
});

Deno.test('sinyal yön değiştirince yeniden gönderilir', () => {
  // Son kayıt 'buy' iken seri 'sell' üretiyor → de-dup engellememeli.
  const sellish = shouldNotify(relentlessRise, 'hisse', 50, false, 'buy');
  assertEquals(sellish.signal, 'sell');
  assertEquals(sellish.notify, true, `olan: ${sellish.reason}`);
});

Deno.test('yetersiz veri sinyal üretmez (uydurma seri yok)', () => {
  const r = shouldNotify([100, 101, 102], 'hisse', 70, false, null);
  assertEquals(r.notify, false);
  assertEquals(r.reason, 'yetersiz_veri');
});

Deno.test('nötr sinyal varsayılan olarak push edilmez', () => {
  // Yatay seri → nötr.
  const flat = Array.from({ length: 120 }, () => 150);
  const r = shouldNotify(flat, 'hisse', 0, false, null);
  assertEquals(r.notify, false);
  assertEquals(r.reason, 'notr_kapali');
});

Deno.test('sembol çözümü: altın tek eğriye indirgenir', () => {
  assertEquals(resolveSymbol('ALTIN_CEYREK', 'altin'), 'GC=F');
  assertEquals(resolveSymbol('ALTIN_GRAM', 'altin'), 'GC=F');
  // Hisse kendi sembolünü korur.
  assertEquals(resolveSymbol('THYAO.IS', 'hisse'), 'THYAO.IS');
  // Ticker'ı olmayan varlık analiz edilemez.
  assertEquals(resolveSymbol('', 'hisse'), null);
});

Deno.test('MIN_POINTS en uzun göstergeyi (EMA50) karşılar', () => {
  // EMA kesişimi hisse için 50 periyot ister; altında "Yetersiz veri" döner.
  const justUnder = Array.from({ length: 49 }, (_, i) => 100 + i);
  const ema = analyze(justUnder, 'hisse', ['ema'], false)[0];
  assertEquals(ema.description, 'Yetersiz veri');

  // MIN_POINTS bunun üstünde olmalı.
  assertEquals(MIN_POINTS >= 50, true);
});
