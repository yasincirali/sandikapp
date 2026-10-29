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
  hareketDonemi,
  hareketMesaji,
  takipEtiketi,
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

Deno.test('tek hareket: başlıkta yön oku, ad, dönem, yüzde ve fiyat; Türkçe virgül', () => {
  const m = hareketMesaji([
    { ad: 'THYAO', pct: 5.34, donem: 'kapanis', fiyat: 312.4, simge: '₺' },
  ]);
  assertEquals(m.title, '▲ THYAO bugün +%5,3 · ₺312,40');
  assertStringIncludes(m.body, 'Günlük değişim, önceki kapanışa göre.');
  assertStringIncludes(m.body, 'Takip listendeki varlık');
  assertStringIncludes(m.body, 'Yatırım tavsiyesi değildir');
});

Deno.test('fiyat bilinmiyorsa başlıkta fiyat yazılmaz (uydurma yok)', () => {
  const m = hareketMesaji([{ ad: 'THYAO', pct: -6.14 }]);
  assertEquals(m.title, '▼ THYAO bugün −%6,1');
});

Deno.test('ABD hissesi gün içi ve dolarla; kripto 00:00 tabanlı', () => {
  const abd = hareketMesaji([
    { ad: 'AAPL', pct: -5.2, donem: hareketDonemi('AAPL'), fiyat: 255.1, simge: '$' },
  ]);
  assertEquals(abd.title, '▼ AAPL gün içi −%5,2 · $255,10');
  assertStringIncludes(abd.body, 'Gün içi değişim, önceki kapanışa göre.');
  assertEquals(abd.body.includes('kapanış.'), false);
  const btc = hareketMesaji([
    { ad: 'BTC', pct: 6, donem: hareketDonemi('KRIPTO:BTC'), fiyat: 4123456.7, simge: '₺' },
  ]);
  assertEquals(btc.title, '▲ BTC gün içi +%6,0 · ₺4.123.456,70');
  assertStringIncludes(btc.body, "Bugün 00:00'dan (İstanbul) bu yana.");
});

Deno.test('küçük fiyat 2 haneye yuvarlanmaz', () => {
  const m = hareketMesaji([
    { ad: 'SHIB', pct: 7, donem: 'kripto', fiyat: 0.000412, simge: '₺' },
  ]);
  assertStringIncludes(m.title, '₺0,000412');
});

Deno.test('dönem sembolden: BIST kapanış, fon, kripto, diğerleri gün içi', () => {
  assertEquals(hareketDonemi('THYAO.IS'), 'kapanis');
  assertEquals(hareketDonemi('XU100.IS'), 'kapanis');
  assertEquals(hareketDonemi('TEFAS:AFT'), 'fon');
  assertEquals(hareketDonemi('KRIPTO:BTC'), 'kripto');
  assertEquals(hareketDonemi('AAPL'), 'gun_ici');
  assertEquals(hareketDonemi('CL=F'), 'gun_ici');
  assertEquals(hareketDonemi('ALTIN_GRAM'), 'gun_ici');
  assertEquals(hareketDonemi('USDTRY=X'), 'gun_ici');
});

Deno.test('kısa etiket: kod; kodun bir şey söylemediği yerde ad', () => {
  assertEquals(takipEtiketi('THYAO.IS', 'Türk Hava Yolları A.O.'), 'THYAO');
  assertEquals(takipEtiketi('TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler Fonu'), 'AFT');
  assertEquals(takipEtiketi('KRIPTO:BTC', 'Bitcoin'), 'BTC');
  assertEquals(takipEtiketi('AAPL', 'Apple Inc.'), 'AAPL');
  assertEquals(takipEtiketi('ALTIN_GRAM', 'Gram Altın'), 'Gram Altın');
  assertEquals(takipEtiketi('USDTRY=X', 'Dolar'), 'Dolar');
  assertEquals(takipEtiketi('CL=F', 'Petrol (WTI)'), 'Petrol (WTI)');
  assertEquals(takipEtiketi('GRAM:SI=F', 'Gram Gümüş'), 'Gram Gümüş');
});

Deno.test('çoklu hareket: sayı ve "bugün" başlıkta, dönem + liste gövdede, eksi işareti', () => {
  const m = hareketMesaji([
    { ad: 'ASELS', pct: -5.5, fiyat: 150.2, simge: '₺' },
    { ad: 'KCHOL', pct: 5.1 },
  ]);
  assertEquals(m.title, 'Takip listende bugün 2 sert hareket');
  assertEquals(
    m.body,
    'Günlük değişim (önceki kapanışa göre): ASELS −%5,5 ₺150,20 · KCHOL +%5,1. ' +
      'Yatırım tavsiyesi değildir.',
  );
});

Deno.test('çoklu hareket, karışık dönem: her satır kendi dönemini söyler', () => {
  const m = hareketMesaji([
    { ad: 'THYAO', pct: 5.3, donem: 'kapanis' },
    { ad: 'BTC', pct: -6.1, donem: 'kripto' },
    { ad: 'AAPL', pct: 5.0, donem: 'gun_ici', fiyat: 255.1, simge: '$' },
  ]);
  assertEquals(
    m.body,
    "THYAO +%5,3 (günlük) · BTC −%6,1 (00:00'dan beri) · AAPL +%5,0 $255,10 (gün içi). " +
      'Yatırım tavsiyesi değildir.',
  );
});

// 0092: kart yalnız TEK hareketli bildirimde (birden çok hareketi tek halka
// anlatamaz).
Deno.test('hareket kartı: tek hareket → kart, çok hareket → yok', () => {
  const k = hareketKarti([{ ad: 'KCHOL', pct: -3.1 }])!;
  assertEquals(k.e, 'KCHOL');
  assertEquals(k.b, '%3,1');
  assertEquals(k.y, 'd');
  assertEquals(k.a, 'Takip listesi · günlük');
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
  const m = hareketMesaji([{ ad: 'AAA', pct: 2.5, fon: true }]);
  assertEquals(m.title, '▲ AAA bugün +%2,5');
  assertStringIncludes(m.body, 'Bugün açıklanan fon fiyatı, bir önceki fiyata göre.');
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
  assertStringIncludes(m.title, 'gün içi');
  assertStringIncludes(m.body, 'Gün içi değişim');
  assertStringIncludes(JSON.stringify(hareketKarti(h)), 'gün içi');
});

Deno.test('calanlariCikar: bugün yüzde alarmı çalan sembol özetten çıkar', () => {
  const satirlar = [{ sembol: 'ALTIN_GRAM', ad: 'Gram altın' }, { sembol: 'USDTRY=X', ad: 'Dolar' }];
  const calanlar = new Set(['u1|ALTIN_GRAM', 'u2|USDTRY=X']);
  assertEquals(calanlariCikar('u1', satirlar, calanlar).map((s) => s.sembol), ['USDTRY=X']);
  assertEquals(calanlariCikar('u3', satirlar, calanlar).length, 2);
  assertEquals(calanlariCikar('u1', satirlar, new Set()), satirlar);
});
