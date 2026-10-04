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
  ASGARI_PARA_HACMI,
  bistSembolu,
  hacimOlayi,
  HacimGunu,
  KAT_ESIGI,
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
