// Takip listesi hareketi — saf kurallar (sembol, eşik/sıralama, mesaj).
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  EN_COK_VARLIK,
  HAREKET_ESIGI_PCT,
  hareketleriSec,
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
