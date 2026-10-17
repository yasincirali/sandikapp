// Takip listesi hareketi — saf kurallar (sembol, eşik/sıralama, mesaj).
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  EN_COK_VARLIK,
  FON_HAREKET_ESIGI_PCT,
  HAREKET_ESIGI_PCT,
  hareketleriSec,
  hareketKarti,
  hareketMesaji,
  takipSembolu,
} from '../functions/_shared/watchlist_moves.ts';

Deno.test('sembol kuralı istemcideki alarmSembolu ile aynı', () => {
  assertEquals(takipSembolu('THYAO', null), 'THYAO');
  assertEquals(takipSembolu(' GARAN ', ''), 'GARAN');
  assertEquals(takipSembolu('', 'ALTIN_GRAM'), 'ALTIN_GRAM');
  assertEquals(takipSembolu('X', 'ALTIN_CEYREK'), 'ALTIN_CEYREK');
  assertEquals(takipSembolu('', null), null);
});

Deno.test('eşik altı elenir, mutlak harekete göre sıralanır, en çok üç', () => {
  const secili = hareketleriSec([
    { ad: 'A', pct: 5.2 },
    { ad: 'B', pct: -7.9 },
    { ad: 'C', pct: 4.9 },
    { ad: 'D', pct: 12.0 },
    { ad: 'E', pct: -6.0 },
  ]);
  assertEquals(secili.map((h) => h.ad), ['D', 'B', 'E']);
  assertEquals(secili.length, EN_COK_VARLIK);
  assertEquals(HAREKET_ESIGI_PCT, 5);
});

Deno.test('bozuk yüzde (NaN) elenir', () => {
  assertEquals(hareketleriSec([{ ad: 'A', pct: Number.NaN }]), []);
});

Deno.test('tek hareket: başlıkta yön oku, ad ve yüzde; Türkçe virgül', () => {
  const m = hareketMesaji([{ ad: 'THYAO', pct: 6.14 }]);
  assertEquals(m.title, '▲ Takip listende: THYAO +%6,1');
  assertStringIncludes(m.body, 'Yatırım tavsiyesi değildir');
});

Deno.test('çoklu hareket: sayı başlıkta, liste gövdede, eksi işareti', () => {
  const m = hareketMesaji([
    { ad: 'ASELS', pct: -5.5 },
    { ad: 'KCHOL', pct: 5.1 },
  ]);
  assertEquals(m.title, 'Takip listende 2 büyük hareket');
  assertStringIncludes(m.body, 'ASELS −%5,5 · KCHOL +%5,1');
});

Deno.test('tutar sızmaz', () => {
  const m = hareketMesaji([{ ad: 'X', pct: 9 }]);
  assertEquals(/₺|\bTL\b/.test(m.title + m.body), false);
});

// 0092: kart yalnız TEK hareketli bildirimde (birden çok hareketi tek halka
// anlatamaz).
Deno.test('hareket kartı: tek hareket → kart, çok hareket → yok', () => {
  const k = hareketKarti([{ ad: 'KCHOL', pct: -3.1 }])!;
  assertEquals(k.e, 'KCHOL');
  assertEquals(k.b, '%3,1');
  assertEquals(k.y, 'd');
  assertEquals(hareketKarti([{ ad: 'A', pct: 3 }, { ad: 'B', pct: -4 }]), null);
});

// ── Fon (TEFAS) hareketi (2026-10-17) ─────────────────────────────────────
Deno.test('fon kendi eşiğiyle (%2) süzülür; hisse %5 eşiğinde kalır', () => {
  assertEquals(FON_HAREKET_ESIGI_PCT, 2);
  const secili = hareketleriSec([
    { ad: 'FON-A', pct: 2.4, fon: true },
    { ad: 'FON-B', pct: -1.9, fon: true },
    { ad: 'HISSE', pct: 2.4 },
  ]);
  assertEquals(secili.map((h) => h.ad), ['FON-A']);
});

Deno.test('fon ve hisse aynı listede mutlak harekete göre sıralanır', () => {
  const secili = hareketleriSec([
    { ad: 'FON', pct: -3.1, fon: true },
    { ad: 'HISSE', pct: 6.0 },
  ]);
  assertEquals(secili.map((h) => h.ad), ['HISSE', 'FON']);
});

Deno.test('eşik görünen değerle: kayan noktada %1,9999… olan −%2,0 fon seçilir', () => {
  const pct = (9.8 / 10 - 1) * 100; // −1,9999999999999927
  const secili = hareketleriSec([{ ad: 'BES', pct, fon: true }]);
  assertEquals(secili.length, 1);
  // %1,94 mesajda "%1,9" yazar → eşiğin altında kalır.
  assertEquals(hareketleriSec([{ ad: 'F', pct: 1.94, fon: true }]), []);
});

Deno.test('tek fon hareketi: gövde "fon fiyatı", kapanış değil', () => {
  const m = hareketMesaji([{ ad: 'AAA Fonu', pct: 2.5, fon: true }]);
  assertStringIncludes(m.body, 'Bugünkü fon fiyatı');
  assertEquals(m.body.includes('kapanış'), false);
});
