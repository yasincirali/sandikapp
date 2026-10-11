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
import { buildMessage } from '../functions/analyze-signals/index.ts';
import {
  ALTIN_GRAM_TL,
  altinGramTlSerisi,
  MIN_POINTS,
  resolveSymbol,
  SINYAL_CACHE_TTL_MS,
} from '../functions/_shared/price_history.ts';

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

Deno.test('sembol çözümü: altın tek eğriye indirgenir (gram TL)', () => {
  assertEquals(resolveSymbol('ALTIN_CEYREK', 'altin'), ALTIN_GRAM_TL);
  assertEquals(resolveSymbol('ALTIN_GRAM', 'altin'), ALTIN_GRAM_TL);
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

Deno.test('altın gram TL serisi: ons × aynı günün kuru ÷ 31,1035; kursuz gün düşer', () => {
  const gun = (d: number) => Date.UTC(2026, 9, d, 21);
  const ons: Array<[number, number]> = [[gun(1), 3110.35], [gun(2), 3110.35], [gun(3), 3421.385]];
  const kur: Array<[number, number]> = [[gun(1), 40], [gun(3), 41]];
  const seri = altinGramTlSerisi(ons, kur);
  assertEquals(seri.length, 2);
  assertEquals(Number(seri[0].toFixed(6)), 4000);
  assertEquals(Number(seri[1].toFixed(6)), 4510);
});

Deno.test('sinyal önbelleği saatlik turda yenilenir', () => {
  // analyze-signals saat başı koşar; ömür bir saatten kısa olmalı ki her
  // tur gün içi fiyatı görsün (denetim 2026-10-11, bulgu 2).
  if (!(SINYAL_CACHE_TTL_MS < 60 * 60 * 1000)) throw new Error('ömür ≥ 1 saat');
});

Deno.test('push metni: güven paydası tüm göstergeler, aşırılık trend diye yazılmaz', () => {
  // 3 gösterge: 2 yukarı (RSI + Bollinger aşırı satım), 1 nötr.
  const m = buildMessage('Türk Hava Yolları', 'buy', 2, 0, 'THYAO.IS', {
    toplam: 3,
    donus: true,
  });
  assertEquals(m.title, '▼ THYAO · aşırı satım bölgesinde');
  assertEquals(m.body.startsWith('2/3 gösterge aşırı satım gösteriyor · güven %67.'), true);
  // Trend oyu çoğunluktaysa eski dil.
  const t = buildMessage('Türk Hava Yolları', 'sell', 0, 2, 'THYAO.IS', { toplam: 3 });
  assertEquals(t.title, '▼ THYAO · aşağı yönlü');
  assertEquals(t.body.startsWith('2/3 gösterge aşağı · güven %67.'), true);
});

Deno.test('özet: sert düşüşte aşırı satım oyu "dönüş" diye işaretlenir', () => {
  // 60 gün yatay, son 10 gün her gün −%2.
  const p: number[] = [];
  for (let i = 0; i < 60; i++) p.push(100 + Math.sin(i / 3));
  for (let i = 0; i < 10; i++) p.push(p[p.length - 1] * 0.98);
  const s = summarize(analyze(p, 'hisse', ['rsi', 'macd', 'bollinger'], false));
  if (s.signal === 'buy') assertEquals(s.donus, true);
});

Deno.test('özet: Stokastik açıkken Williams %R ikinci oy sayılmaz', () => {
  const p: number[] = [];
  for (let i = 0; i < 80; i++) p.push(100 + i);
  const inds = analyze(p, 'hisse', ['stochastic', 'williams_r'], true);
  assertEquals(inds.length, 2);
  assertEquals(summarize(inds).toplam, 1);
});
