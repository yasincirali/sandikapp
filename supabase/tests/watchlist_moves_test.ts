// Takip listesi hareketi — saf kurallar (sembol, eşik/sıralama, mesaj).
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  calanlariCikar,
  EMTIA_HAREKET_ESIGI_PCT,
  EN_COK_VARLIK,
  emtiaSembolu,
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

Deno.test('emtia vadelisi %3 eşiğinde; hisse %5 eşiğinde kalır', () => {
  assertEquals(EMTIA_HAREKET_ESIGI_PCT, 3);
  const secili = hareketleriSec([
    { ad: 'Petrol (Brent)', pct: -3.2, emtia: true },
    { ad: 'Gümüş', pct: 2.9, emtia: true },
    { ad: 'THYAO', pct: 4.0 },
  ]);
  assertEquals(secili.map((h) => h.ad), ['Petrol (Brent)']);
});

Deno.test('emtia sembolü: yalnız Yahoo vadelisi (=F)', () => {
  assertEquals(emtiaSembolu('CL=F'), true);
  assertEquals(emtiaSembolu(' si=f '), true);
  assertEquals(emtiaSembolu('THYAO.IS'), false);
  assertEquals(emtiaSembolu('ALTIN_GRAM'), false);
  assertEquals(emtiaSembolu('TEFAS:AFT'), false);
});

Deno.test('tek emtia hareketi: gövde ve kart "gün içi", kapanış değil', () => {
  const h = [{ ad: 'Petrol (WTI)', pct: 3.4, emtia: true }];
  const m = hareketMesaji(h);
  assertStringIncludes(m.body, 'Gün içi hareket');
  assertEquals(m.body.includes('kapanış'), false);
  assertStringIncludes(JSON.stringify(hareketKarti(h)), 'gün içi');
});

Deno.test('calanlariCikar: bugün yüzde alarmı çalan sembol özetten çıkar', () => {
  const satirlar = [{ sembol: 'ALTIN_GRAM', ad: 'Gram altın' }, { sembol: 'USDTRY=X', ad: 'Dolar' }];
  const calanlar = new Set(['u1|ALTIN_GRAM', 'u2|USDTRY=X']);
  assertEquals(calanlariCikar('u1', satirlar, calanlar).map((s) => s.sembol), ['USDTRY=X']);
  assertEquals(calanlariCikar('u3', satirlar, calanlar).length, 2);
  assertEquals(calanlariCikar('u1', satirlar, new Set()), satirlar);
});
