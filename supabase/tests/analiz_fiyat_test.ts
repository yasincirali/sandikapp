// Aylık notun fiyat paketi (2026-11-07, yasin: "tüm varlıklar yorumlansın").
//
// Kilitlenen kararlar:
//   · Aylıkta akış/hacim verisi olmayan türler (yurt dışı hisse, altın,
//     döviz, emtia, eurobond) seçilir; haftalık eski kapsamda kalır.
//   · Not anahtarı istemcinin `notAnahtari` biçimiyle aynı.
//   · Veri yoksa not yok; fiyat düzeyi ölçüm olarak gitmez (yalnız yüzde/kat).
//   · "Önemli gelişme" rozeti (`hareketli`) veriden: olağan oynaklığa göre
//     büyük değişim, oynaklık sıçraması ya da 52 haftalık uç.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  altinGramSerisi,
  fiyatPaketleri,
  lotSecimi,
  notKodu,
} from '../functions/analiz-hazirla/index.ts';
import { fiyatPaketi, kapidanGecir, kullaniciMesaji, Paket } from '../functions/_shared/analiz.ts';
import type { Seri } from '../functions/_shared/dated_history.ts';

const GUN = 24 * 60 * 60 * 1000;
const ms = (iso: string) => Date.parse(`${iso}T15:00:00Z`);
const EKIM = { baslangic: '2026-10-01', bitis: '2026-10-31' };

/// [bas]'tan [gun] günlük seri; fiyat [f](i) ile.
function seri(bas: string, gun: number, f: (i: number) => number): Seri {
  return Array.from({ length: gun }, (_, i) => [ms(bas) + i * GUN, f(i)] as [number, number]);
}

/// Sakin ve uzun bir geçmiş: ±%0,5 zikzak, 1 yıl + Ekim.
const sakinFiyat = (i: number) => 100 * (1 + (i % 2 === 0 ? 0.005 : -0.005));

Deno.test('lotSecimi: aylıkta tüm türler, haftalıkta eski kapsam', () => {
  const aylik = (type: string, ticker: string, currency?: string) =>
    lotSecimi({ type, ticker, currency }, 'aylik');
  assertEquals(aylik('hisse', 'thyao.is')?.ticker, 'THYAO.IS');
  assertEquals(aylik('hisse', 'AAPL'), {
    ticker: 'HISSE:AAPL', varlik: 'yabanci_hisse', seri: 'AAPL', para: 'USD',
  });
  // Kısa sembol `length(ticker) >= 3` kısıtına önekle sığar.
  assertEquals(aylik('hisse', 'F')?.ticker, 'HISSE:F');
  assertEquals(aylik('hisse', 'SAP.DE', 'EUR')?.para, 'EUR');
  assertEquals(aylik('altin', 'ALTIN_CEYREK')?.ticker, 'ALTIN:GRAM');
  assertEquals(aylik('altin', '')?.ticker, 'ALTIN:GRAM');
  assertEquals(aylik('doviz', 'USDTRY=X')?.varlik, 'doviz');
  assertEquals(aylik('emtia', 'GRAM:SI=F')?.ticker, 'GRAM:SI=F');
  assertEquals(aylik('emtia', 'BZ=F')?.para, 'USD');
  assertEquals(aylik('eurobond', 'EUROBOND:US900123CX66')?.varlik, 'eurobond');
  assertEquals(aylik('kripto', 'KRIPTO:BTC')?.ticker, 'KRIPTO:BTC');
  assertEquals(aylik('fon', 'TTE')?.ticker, 'TEFAS:TTE');
  // Bilerek dışarıda: mevduat, diğer, USDT, elle fiyatlı.
  assertEquals(aylik('mevduat', 'MEVDUAT:X'), null);
  assertEquals(aylik('diger', 'EV'), null);
  assertEquals(aylik('kripto', 'KRIPTO:USDT'), null);
  assertEquals(lotSecimi({ type: 'hisse', ticker: 'AAPL', is_manual_price: true }, 'aylik'), null);
  // Haftalık: yalnız akış/hacim türleri (maliyet her hafta tekrarlanır).
  const haftalik = (type: string, ticker: string) => lotSecimi({ type, ticker }, 'haftalik');
  assertEquals(haftalik('hisse', 'AAPL'), null);
  assertEquals(haftalik('altin', 'ALTIN_GRAM'), null);
  assertEquals(haftalik('hisse', 'THYAO.IS')?.ticker, 'THYAO.IS');
});

Deno.test('notKodu: modele yalnız sembol gider', () => {
  assertEquals(notKodu('HISSE:AAPL'), 'AAPL');
  assertEquals(notKodu('ALTIN:GRAM'), 'Gram altın');
  assertEquals(notKodu('USDTRY=X'), 'USD/TRY');
  assertEquals(notKodu('THYAO.IS'), 'THYAO');
  assertEquals(notKodu('EUROBOND:US900123CX66'), 'US900123CX66');
});

Deno.test('fiyatPaketi: değişim, TL bazı, oynaklık; düzey yok; tarih aralığı veriden', () => {
  const s = [...seri('2025-10-01', 365, sakinFiyat), ...seri('2026-10-01', 31, (i) => 100 * (1 + 0.002 * i))];
  const kur: Seri = [[ms('2026-09-30'), 40], [ms('2026-10-31'), 42]];
  const p = fiyatPaketi({
    ticker: 'HISSE:AAPL', kod: 'AAPL', varlik: 'yabanci_hisse', tur: 'aylik', aralik: EKIM,
    seri: s, para: 'USD', kur, kaynak: 'Yahoo Finance',
  })!;
  assertEquals(p.baslangic, '2026-10-01');
  assertEquals(p.bitis, '2026-10-31');
  assertEquals(p.para, 'USD');
  const a = Object.fromEntries(p.olcumler.map((o) => [o.anahtar, o]));
  assert(a.fiyat_degisim && a.tl_degisim && a.oynaklik && a.hareket_kati && a.oynaklik_kati);
  // TL bazı = (1 + d) × kur oranı − 1.
  const d = a.fiyat_degisim.deger;
  assert(Math.abs(a.tl_degisim.deger - ((1 + d) * 42 / 40 - 1)) < 1e-9);
  // Hiçbir gösterim fiyat düzeyi değil (₺/$ yok).
  assert(p.olcumler.every((o) => !/[₺$]/.test(o.gosterim)));
});

Deno.test('fiyatPaketi: veri yoksa not yok', () => {
  const g = { ticker: 'SI=F', kod: 'SI=F', varlik: 'emtia' as const, tur: 'aylik' as const,
    aralik: EKIM, para: 'USD', kur: null, kaynak: 'Yahoo Finance' as const };
  // Dönemde 4 kapanış: yetersiz.
  assertEquals(fiyatPaketi({ ...g, seri: seri('2026-09-20', 15, () => 10) }), null);
  // Dönem öncesi kapanış yok: değişim ölçülemez.
  assertEquals(fiyatPaketi({ ...g, seri: seri('2026-10-01', 31, () => 10) }), null);
  assertEquals(fiyatPaketi({ ...g, seri: [] }), null);
});

Deno.test('fiyatPaketi rozet: sakin ay sakin, büyük hareket ve 52 hafta zirvesi hareketli', () => {
  const g = { ticker: 'USDTRY=X', kod: 'USD/TRY', varlik: 'doviz' as const, tur: 'aylik' as const,
    aralik: EKIM, para: 'TRY', kur: null, kaynak: 'Yahoo Finance' as const };
  const gecmis = seri('2025-10-01', 365, sakinFiyat);
  // Ay sonu kapanışı yılın ucunda değil (zikzakın ortası).
  const sakin = fiyatPaketi({ ...g, seri: [...gecmis, ...seri('2026-10-01', 31, (i) => (i === 30 ? 100 : sakinFiyat(i)))] })!;
  assertEquals(sakin.rozet, 'sakin');
  assertEquals(sakin.olaylar, []);
  // Her gün +%1: değişim olağan oynaklığın çok üstünde ve yılın zirvesi.
  const sert = fiyatPaketi({ ...g, seri: [...gecmis, ...seri('2026-10-01', 31, (i) => 100 * 1.01 ** (i + 1))] })!;
  assertEquals(sert.rozet, 'hareketli');
  assert(sert.olaylar[0].includes('52 haftanın en yükseği'));
  // Kısa seride 52 hafta iddiası yok.
  const kisa = fiyatPaketi({ ...g, seri: [...seri('2026-08-01', 61, sakinFiyat), ...seri('2026-10-01', 31, (i) => 100 * 1.01 ** (i + 1))] })!;
  assertEquals(kisa.olaylar, []);
});

Deno.test('fiyatPaketi: modelin gösterimleri aynen kullanan notu kapıdan geçer', () => {
  const p = fiyatPaketi({
    ticker: 'ALTIN:GRAM', kod: 'Gram altın', varlik: 'altin', tur: 'aylik', aralik: EKIM,
    seri: [...seri('2025-10-01', 365, sakinFiyat), ...seri('2026-10-01', 31, (i) => 100 * 1.01 ** (i + 1))],
    para: 'TRY', kur: null, kaynak: 'Yahoo Finance',
  }) as Paket;
  const deg = p.olcumler.find((o) => o.anahtar === 'fiyat_degisim')!;
  const not = {
    baslik: `Gram altın ${p.olaylar[0].split(' kapanışı')[0]} kapanışında son 52 haftanın en yükseğinde.`,
    maddeler: [{ metin: `Ay boyunca fiyat ${deg.gosterim} değişti.`, kanit: ['fiyat_degisim'] }],
  };
  assertEquals(kapidanGecir(not, p), { gecti: true });
  // Fiyat düzeyi uyduran not reddedilir.
  const uydurma = { ...not, maddeler: [{ metin: 'Gram fiyatı 3.150 TL oldu.', kanit: ['fiyat_degisim'] }] };
  assertEquals(kapidanGecir(uydurma, p).gecti, false);
  const m = kullaniciMesaji(p);
  assert(m.includes('altın, gram fiyatı TL'));
  assert(m.includes('fiyat serisi (TRY kote)'));
});

Deno.test('fiyatPaketleri: altın GC=F × USDTRY, kur serisi istenir, boş seri not üretmez', async () => {
  let istenen = new Set<string>();
  const gecmis = (f: (i: number) => number) => [...seri('2025-10-01', 365, f), ...seri('2026-10-01', 31, f)];
  const paketler = await fiyatPaketleri([
    { ticker: 'ALTIN:GRAM', varlik: 'altin', tutan: 3, seri: 'ALTIN:GRAM', para: 'TRY' },
    { ticker: 'HISSE:AAPL', varlik: 'yabanci_hisse', tutan: 2, seri: 'AAPL', para: 'USD' },
    { ticker: 'HISSE:YOK', varlik: 'yabanci_hisse', tutan: 1, seri: 'YOK', para: 'USD' },
    { ticker: 'TEFAS:TTE', varlik: 'fon', tutan: 1 },
  ], 'aylik', EKIM, (s) => {
    istenen = s;
    const m = new Map<string, Seri>();
    m.set('GC=F', gecmis(() => 2000));
    m.set('USDTRY=X', gecmis(() => 40));
    m.set('AAPL', gecmis(sakinFiyat));
    m.set('TEFAS:TTE', gecmis(sakinFiyat));
    return Promise.resolve(m);
  });
  assertEquals([...istenen].sort(), ['AAPL', 'GC=F', 'TEFAS:TTE', 'USDTRY=X', 'YOK']);
  assertEquals(paketler.map((p) => p.ticker), ['ALTIN:GRAM', 'HISSE:AAPL', 'TEFAS:TTE']);
  assertEquals(paketler.find((p) => p.ticker === 'TEFAS:TTE')!.olcumler[0].kaynak, 'TEFAS');
  // Kur 40 sabit → TL bazı = fiyat değişimi.
  const aapl = paketler.find((p) => p.ticker === 'HISSE:AAPL')!;
  const a = Object.fromEntries(aapl.olcumler.map((o) => [o.anahtar, o.deger]));
  assert(Math.abs(a.tl_degisim - a.fiyat_degisim) < 1e-12);
});

Deno.test('altinGramSerisi: kuru olmayan gün seriye girmez', () => {
  const ons: Seri = [[ms('2026-10-01'), 3110.35], [ms('2026-10-02'), 3110.35]];
  const kur: Seri = [[ms('2026-10-01'), 40]];
  const s = altinGramSerisi(ons, kur);
  assertEquals(s.length, 1);
  assert(Math.abs(s[0][1] - 4000) < 1e-9);
});

Deno.test('kapı: teknik terim ve açıklanmamış "oynaklık" reddedilir (anlaşılır not)', () => {
  const p = fiyatPaketi({
    ticker: 'SI=F', kod: 'SI=F', varlik: 'emtia', tur: 'aylik', aralik: EKIM,
    seri: [...seri('2025-10-01', 365, sakinFiyat), ...seri('2026-10-01', 31, (i) => (i === 30 ? 100 : sakinFiyat(i)))],
    para: 'USD', kur: null, kaynak: 'Yahoo Finance',
  }) as Paket;
  const deg = p.olcumler.find((o) => o.anahtar === 'fiyat_degisim')!.gosterim;
  const madde = (metin: string) => ({ baslik: 'Gümüşte sakin bir ay geçti.', maddeler: [{ metin, kanit: ['fiyat_degisim'] }] });
  assertEquals(kapidanGecir(madde(`Fiyat ay boyunca ${deg} değişti.`), p), { gecti: true });
  assertEquals(kapidanGecir(madde('Volatilite düşük kaldı.'), p).gecti, false);
  assertEquals(kapidanGecir(madde('Oynaklık düşük kaldı.'), p).gecti, false);
  assertEquals(kapidanGecir(madde('Oynaklık, yani fiyatın günlük dalgalanması, düşük kaldı.'), p), { gecti: true });
  assertEquals(kapidanGecir(madde('fiyat_degisim ölçümü sakin.'), p).gecti, false);
});
