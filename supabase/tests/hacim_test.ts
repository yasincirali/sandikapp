// Hisse hacim radarı — saf yardımcıların testleri.
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Üç eşik birden.** z, kat ve taban; biri eksikse olay yok.
// 2. **Uydurma yok.** 20 önceki gün tam değilse ya da sapma sıfırsa olay yok;
//    boş bar atılır.
// 3. **Yarım gün sayılmaz.** Seans bitmeden bugünün barı listeye girmez.
// 4. **Yön fiyat yönüdür**, akış değil.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/hacim_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  ASGARI_KRIPTO_HACMI,
  ASGARI_PARA_HACMI,
  binanceGunleri,
  binanceSaatleri,
  bistSembolu,
  bitenKriptoGunleri,
  hacimOlayi,
  HacimGunu,
  KAT_ESIGI,
  netAlim,
  ORTALAMA_GUN,
  paraHacmi,
  tamamlananGunler,
  yahooGunleri,
  Z_ESIGI,
} from '../functions/_shared/hacim.ts';

/// 20 sakin gün (para hacmi 90–110 mn arası dalgalı) + son gün.
function seri(sonHacim: number, sonKapanis = 10, oncekiKapanis = 10): HacimGunu[] {
  const g: HacimGunu[] = [];
  for (let i = 0; i < ORTALAMA_GUN; i++) {
    const d = new Date(Date.UTC(2026, 8, 1 + i, 12));
    g.push({
      tarih: d.toISOString().slice(0, 10),
      kapanis: i === ORTALAMA_GUN - 1 ? oncekiKapanis : 10,
      hacim: (i % 2 === 0 ? 9_000_000 : 11_000_000) * (10 / (i === ORTALAMA_GUN - 1 ? oncekiKapanis : 10)),
    });
  }
  g.push({ tarih: '2026-09-21', kapanis: sonKapanis, hacim: sonHacim });
  return g;
}

Deno.test('eşik sabitleri: z 3, kat 2, taban 50 mn, 20 gün', () => {
  assertEquals([Z_ESIGI, KAT_ESIGI, ASGARI_PARA_HACMI, ORTALAMA_GUN], [3, 2, 50_000_000, 20]);
});

Deno.test('bistSembolu yalnız .IS sembolünü kabul eder', () => {
  assertEquals(bistSembolu('thyao.is'), 'THYAO.IS');
  assertEquals(bistSembolu('AAPL'), null);
  assertEquals(bistSembolu('TEFAS:TTE'), null);
  assertEquals(bistSembolu(''), null);
});

Deno.test('yahooGunleri: boş bar atılır, aynı günün son barı kalır, sıralı döner', () => {
  const t = (g: number, saat: number) => Date.UTC(2026, 8, g, saat) / 1000;
  const gunler = yahooGunleri({
    timestamp: [t(15, 7), t(16, 7), t(17, 7), t(17, 14)],
    indicators: { quote: [{ close: [10, null, 11, 12], volume: [100, 200, 300, 400] }] },
  });
  assertEquals(gunler, [
    { tarih: '2026-09-15', kapanis: 10, hacim: 100 },
    { tarih: '2026-09-17', kapanis: 12, hacim: 400 },
  ]);
  assertEquals(yahooGunleri(null), []);
  assertEquals(yahooGunleri({ timestamp: [1], indicators: {} }), []);
});

Deno.test('seans bitmeden bugünün barı sayılmaz; 18:30 TR sonrası sayılır', () => {
  const gunler = [
    { tarih: '2026-10-01', kapanis: 1, hacim: 1 },
    { tarih: '2026-10-02', kapanis: 1, hacim: 1 },
  ];
  // 2 Ekim 15:00 TR = 12:00Z.
  assertEquals(tamamlananGunler(gunler, new Date(Date.UTC(2026, 9, 2, 12))).length, 1);
  // 2 Ekim 18:45 TR = 15:45Z.
  assertEquals(tamamlananGunler(gunler, new Date(Date.UTC(2026, 9, 2, 15, 45))).length, 2);
  // Ertesi sabah ikisi de tam.
  assertEquals(tamamlananGunler(gunler, new Date(Date.UTC(2026, 9, 3, 5))).length, 2);
});

Deno.test('üç eşiği aşan gün olaydır; kat, z ve fiyat yönü dolar', () => {
  // Ortalama 100 mn; son gün 320 mn (3,2 kat), fiyat +%4.
  const g = seri(32_000_000 / 1.04, 10.4);
  const o = hacimOlayi(g, g.length - 1)!;
  assertEquals(o.tur, 'hisse_hacim_yukselis');
  assertEquals(o.tutar, paraHacmi(g[g.length - 1]));
  assertEquals(o.ortalama_kati, 3.2);
  assertEquals(o.fiyat_degisim, 0.04);
  assertEquals(o.sapma_kati > 3, true);
});

Deno.test('fiyat düştüyse tür düşüştür — yön akış değil fiyat', () => {
  const g = seri(32_000_000 / 0.95, 9.5);
  assertEquals(hacimOlayi(g, g.length - 1)?.tur, 'hisse_hacim_dusus');
});

Deno.test('ortalamanın 2 katının altı olay değil', () => {
  const g = seri(19_000_000);
  assertEquals(hacimOlayi(g, g.length - 1), null);
});

Deno.test('taban: küçük tahtada 5 kat bile olay değil', () => {
  // Para hacmi ortalaması 1 mn, son gün 5 mn < 50 mn.
  const g = seri(0).map((x, i, a) => ({ ...x, hacim: i === a.length - 1 ? 500_000 : x.hacim / 100 }));
  assertEquals(hacimOlayi(g, g.length - 1), null);
});

Deno.test('20 önceki gün yoksa ya da hacim hiç oynamamışsa olay yok', () => {
  const g = seri(32_000_000);
  assertEquals(hacimOlayi(g.slice(1), g.length - 2), null); // 19 önceki gün
  const duz = g.map((x, i, a) => ({ ...x, hacim: i === a.length - 1 ? 32_000_000 : 10_000_000 }));
  assertEquals(hacimOlayi(duz, duz.length - 1), null); // sapma 0
  assertEquals(hacimOlayi(g, 99), null);
});

// ── kripto ──────────────────────────────────────────────────────────────────

Deno.test('binanceGunleri: quote hacmi ve alıcı payı okunur; bozuk satır atılır', () => {
  const ac = Date.UTC(2026, 9, 1, 21); // 2 Ekim 00:00 TR
  const g = binanceGunleri([
    [ac, '1', '1', '1', '60000', '1000', ac + 1, '50000000', 10, '580', '29000000', '0'],
    [ac + 86400000, '1', '1', '1', '61000', '900', 0, '0', 1, '0', '0', '0'], // hacimsiz
    [ac + 2 * 86400000, '1', '1', '1', '62000', '900', 0, '100', 1, '0', '500', '0'], // alış > toplam
    'bozuk',
  ]);
  assertEquals(g, [{ tarih: '2026-10-02', kapanis: 60000, hacim: 1000, para: 50000000, aliciPayi: 0.58 }]);
  assertEquals(paraHacmi(g[0]), 50000000);
  assertEquals(binanceGunleri(null), []);
});

Deno.test('bitenKriptoGunleri bugünün yarım mumunu atar', () => {
  const g = [
    { tarih: '2026-10-03', kapanis: 1, hacim: 1 },
    { tarih: '2026-10-04', kapanis: 1, hacim: 1 },
  ];
  // 4 Ekim 23:00 TR = 20:00Z: gün bitmedi.
  assertEquals(bitenKriptoGunleri(g, new Date(Date.UTC(2026, 9, 4, 20))).length, 1);
  assertEquals(bitenKriptoGunleri(g, new Date(Date.UTC(2026, 9, 4, 21, 5))).length, 2);
});

Deno.test('kripto olayı kendi tabanını ve kendi tür önekini kullanır', () => {
  assertEquals(ASGARI_KRIPTO_HACMI, 10_000_000);
  // Ortalama 100 mn, son gün 320 mn: hem hisse hem kripto tabanının üstünde.
  const g = seri(32_000_000 / 1.04, 10.4);
  assertEquals(hacimOlayi(g, g.length - 1, 'kripto', ASGARI_KRIPTO_HACMI)?.tur, 'kripto_hacim_yukselis');
  assertEquals(hacimOlayi(g, g.length - 1)?.tur, 'hisse_hacim_yukselis');
  // Taban parametresi etkili: çıta günün hacminin üstündeyse olay yok.
  assertEquals(hacimOlayi(g, g.length - 1, 'kripto', 400_000_000), null);
});

// ── Saatlik alıcı baskısı (0115) ────────────────────────────────────────────

const SA = 60 * 60 * 1000;
const t0 = Date.UTC(2026, 9, 5, 10); // 10:00 UTC
const saatSatiri = (t: number, para: string, alis: string) =>
  [t, '1', '1', '1', '1', '5', t + SA - 1, para, 100, '2', alis];

Deno.test('binanceSaatleri: yalnız KAPANMIŞ saatler, eskiden yeniye', () => {
  const rows = [
    saatSatiri(t0 + SA, '2000', '500'),
    saatSatiri(t0, '1000', '600'),
    saatSatiri(t0 + 2 * SA, '3000', '1500'), // 12:00 mumu, şimdi 12:30 → yarım
  ];
  const s = binanceSaatleri(rows, new Date(t0 + 2 * SA + 30 * 60 * 1000));
  assertEquals(s.map((x) => x.saat), [
    new Date(t0).toISOString(),
    new Date(t0 + SA).toISOString(),
  ]);
  assertEquals(s[0].aliciPayi, 0.6);
  assertEquals(s[1].aliciPayi, 0.25);
});

Deno.test('binanceSaatleri: bozuk satır uydurulmaz', () => {
  const simdi = new Date(t0 + 10 * SA);
  const rows = [
    saatSatiri(t0, '0', '0'), // hacim yok
    saatSatiri(t0 + SA, '100', '150'), // alış > toplam
    saatSatiri(t0 + 2 * SA, 'x', '1'), // sayı değil
    [t0 + 3 * SA, '1'], // kısa satır
    saatSatiri(t0 + 4 * SA + 5, '100', '50'), // saat başı değil
    saatSatiri(t0 + 5 * SA, '100', '50'),
  ];
  const s = binanceSaatleri(rows, simdi);
  assertEquals(s.length, 1);
  assertEquals(s[0].saat, new Date(t0 + 5 * SA).toISOString());
  assertEquals(binanceSaatleri('bozuk', simdi), []);
});

Deno.test('netAlim = (2 × pay − 1) × hacim; %50 sıfır', () => {
  assertEquals(netAlim(1000, 0.6), 200);
  assertEquals(netAlim(1000, 0.5), 0);
  assertEquals(netAlim(1000, 0.25), -500);
});
