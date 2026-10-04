// Fon para akışı ve büyük giriş/çıkış tespiti — saf yardımcıların testleri.
//
// `Deno.serve` gövdesi ağ ve veritabanı istediği için test edilmiyor;
// kural ve hesap `_shared/balina.ts`'te bu yüzden ayrı.
//
// ## Bu dosyanın kovaladığı dört şey
// 1. **Akış fiyat hareketini saymaz.** Pay adedi değişmediyse fon %10
//    değer kazansa da net akış SIFIRDIR.
// 2. **Uydurma yok.** Önceki gün bilinmiyorsa akış `null`; geçmiş yetersizse
//    ya da sapma sıfırsa olay YOK.
// 3. **Yanlış alarm yok.** Küçük fon, büyüklüğün %2'sinin altı ve sapmanın
//    3 katının altı olay üretmez — iki eşiğin BÜYÜĞÜ aşılmalı.
// 4. **Gün sırası ve yeniden çekme.** Günler eskiden yeniye; kesinleşmiş gün
//    sorulmaz, hafta sonu hiç sorulmaz, son iki gün her tur yeniden sorulur.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/balina_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  ASGARI_BUYUKLUK,
  ASGARI_GOZLEM,
  balinaOlayi,
  buyuklukSatirlari,
  cekilecekGunler,
  gunEkle,
  gunKesinMi,
  gunSatirlari,
  haftaSonuMu,
  netAkis,
  tefasGunParam,
  yatirimciSayisi,
} from '../functions/_shared/balina.ts';

// ── tarih yardımcıları ──────────────────────────────────────────────────────

Deno.test('tefasGunParam tireleri atar (uç YYYYMMDD ister)', () => {
  assertEquals(tefasGunParam('2026-10-02'), '20261002');
});

Deno.test('gunEkle ay ve yıl sınırını geçer', () => {
  assertEquals(gunEkle('2026-10-01', -1), '2026-09-30');
  assertEquals(gunEkle('2026-12-31', 1), '2027-01-01');
  assertEquals(gunEkle('2026-03-01', -1), '2026-02-28');
});

Deno.test('haftaSonuMu Cumartesi ve Pazar için true', () => {
  assertEquals(haftaSonuMu('2026-10-02'), false); // Cuma
  assertEquals(haftaSonuMu('2026-10-03'), true); // Cumartesi
  assertEquals(haftaSonuMu('2026-10-04'), true); // Pazar
  assertEquals(haftaSonuMu('2026-10-05'), false); // Pazartesi
});

// ── cekilecekGunler ─────────────────────────────────────────────────────────

Deno.test('günler eskiden yeniye, hafta sonu hariç', () => {
  // Pazar 4 Ekim'den 6 gün geri: 28 Eyl (Pzt) … 2 Eki (Cum).
  assertEquals(cekilecekGunler('2026-10-04', new Set(), 6, 99), [
    '2026-09-28',
    '2026-09-29',
    '2026-09-30',
    '2026-10-01',
    '2026-10-02',
  ]);
});

Deno.test('kesinleşmiş gün sorulmaz, kesin olmayan yeniden sorulur', () => {
  const kesin = new Set(['2026-09-28', '2026-09-29', '2026-09-30']);
  assertEquals(cekilecekGunler('2026-10-04', kesin, 6, 99), ['2026-10-01', '2026-10-02']);
});

Deno.test('üst sınır EN ESKİ günleri tutar (akış önceki güne bakar)', () => {
  assertEquals(cekilecekGunler('2026-10-04', new Set(), 6, 2), ['2026-09-28', '2026-09-29']);
  assertEquals(cekilecekGunler('2026-10-04', new Set(), 6, 0), []);
});

Deno.test('gunKesinMi: iki günden eski gün kesin, son iki gün değil', () => {
  assertEquals(gunKesinMi('2026-10-01', '2026-10-04'), true);
  assertEquals(gunKesinMi('2026-10-02', '2026-10-04'), false);
  assertEquals(gunKesinMi('2026-10-04', '2026-10-04'), false);
});

// ── buyuklukSatirlari ───────────────────────────────────────────────────────

Deno.test('TEFAS satırından kod, pay ve değer okunur (son* alanları)', () => {
  const satirlar = buyuklukSatirlari([
    {
      fonKodu: 'tte ',
      ilkPortfoyDegeri: 1,
      sonPortfoyDegeri: 2385068751.83,
      ilkPayAdedi: 1,
      sonPayAdedi: 2013904583,
    },
  ]);
  assertEquals(satirlar, [{ kod: 'TTE', pay: 2013904583, deger: 2385068751.83 }]);
});

Deno.test('bozuk satır atılır: sıfır pay, eksik değer, geçersiz kod', () => {
  assertEquals(
    buyuklukSatirlari([
      { fonKodu: 'AAA', sonPayAdedi: 0, sonPortfoyDegeri: 100 },
      { fonKodu: 'BBB', sonPayAdedi: 10, sonPortfoyDegeri: null },
      { fonKodu: 'CCC', sonPayAdedi: 10, sonPortfoyDegeri: -5 },
      { fonKodu: 'ÇOK UZUN KOD', sonPayAdedi: 10, sonPortfoyDegeri: 100 },
      { fonKodu: 'DDD', sonPayAdedi: 'abc', sonPortfoyDegeri: 100 },
      null,
      'metin',
    ]),
    [],
  );
  assertEquals(buyuklukSatirlari(null), []);
  assertEquals(buyuklukSatirlari({}), []);
});

Deno.test('emeklilik fonunun kesirli payı korunur', () => {
  assertEquals(
    buyuklukSatirlari([{ fonKodu: 'AH5', sonPayAdedi: 8732336930.353, sonPortfoyDegeri: 23005415532.74 }]),
    [{ kod: 'AH5', pay: 8732336930.353, deger: 23005415532.74 }],
  );
});

// ── netAkis ─────────────────────────────────────────────────────────────────

Deno.test('net akış = pay farkı × günün birim fiyatı', () => {
  // 1.000 pay, 2.000 TL → fiyat 2. Önceki gün 900 pay → +100 pay × 2 = +200.
  assertEquals(netAkis(1000, 2000, 900), 200);
  // Pay azaldı → çıkış.
  assertEquals(netAkis(1000, 2000, 1100), -200);
});

Deno.test('pay değişmediyse fiyat ne olursa olsun akış sıfır', () => {
  // Fon değeri 2.000 → 2.200 (fiyat %10 arttı) ama pay aynı: para girmedi.
  assertEquals(netAkis(1000, 2200, 1000), 0);
});

Deno.test('önceki gün bilinmiyorsa akış null (sıfır DEĞİL)', () => {
  assertEquals(netAkis(1000, 2000, undefined), null);
  assertEquals(netAkis(1000, 2000, 0), null);
});

Deno.test('gerçek TEFAS örneği: TTE 1→2 Ekim 2026', () => {
  // 2.023.067.154 → 2.013.904.583 pay; değer 2.385.068.751,83.
  const akis = netAkis(2013904583, 2385068751.83, 2023067154)!;
  // −9.162.571 pay × 1,184301 ≈ −10,85 mn TL.
  assertEquals(Math.round(akis / 1000), -10851);
});

// ── gunSatirlari ────────────────────────────────────────────────────────────

Deno.test('gunSatirlari akışı önceki paya göre yazar ve haritayı ilerletir', () => {
  const onceki = new Map<string, number>([['AAA', 900]]);
  const g1 = gunSatirlari('2026-10-01', 'YAT', [
    { kod: 'AAA', pay: 1000, deger: 2000 },
    { kod: 'YENI', pay: 50, deger: 500 },
  ], onceki);
  assertEquals(g1.map((s) => [s.fon_kodu, s.net_akis]), [['AAA', 200], ['YENI', null]]);
  assertEquals(g1[0].tarih, '2026-10-01');
  assertEquals(g1[0].fon_tipi, 'YAT');

  // İkinci gün: harita ilk günün paylarını taşıyor.
  const g2 = gunSatirlari('2026-10-02', 'YAT', [
    { kod: 'AAA', pay: 1000, deger: 2100 },
    { kod: 'YENI', pay: 60, deger: 600 },
  ], onceki);
  assertEquals(g2.map((s) => [s.fon_kodu, s.net_akis]), [['AAA', 0], ['YENI', 100]]);
});

// ── balinaOlayi ─────────────────────────────────────────────────────────────

const YETERLI = { gozlem: 40, sapma: 1_000_000 };
const BUYUK_FON = 1_000_000_000; // 1 mr TL → %2'si 20 mn

Deno.test('iki eşiği de aşan giriş olaydır; kanıt alanları dolar', () => {
  const o = balinaOlayi(31_000_000, BUYUK_FON, YETERLI);
  assertEquals(o, {
    tur: 'fon_giris',
    tutar: 31_000_000,
    buyukluk_orani: 0.031,
    sapma_kati: 31,
  });
});

Deno.test('çıkış eksi tutarla ve fon_cikis türüyle gelir', () => {
  const o = balinaOlayi(-25_000_000, BUYUK_FON, YETERLI);
  assertEquals(o?.tur, 'fon_cikis');
  assertEquals(o?.tutar, -25_000_000);
  assertEquals(o?.buyukluk_orani, 0.025);
});

Deno.test('büyüklüğün %2\'sinin altı olay değil (sapmayı aşsa bile)', () => {
  // 19 mn < 20 mn (%2), sapmanın 19 katı.
  assertEquals(balinaOlayi(19_000_000, BUYUK_FON, YETERLI), null);
});

Deno.test('sapmanın 3 katının altı olay değil (%2\'yi aşsa bile)', () => {
  // Hareketli fon: sapma 10 mn → eşik 30 mn; 25 mn %2,5 ama 2,5 kat.
  assertEquals(balinaOlayi(25_000_000, BUYUK_FON, { gozlem: 40, sapma: 10_000_000 }), null);
  // Tam eşikte olaydır.
  assertEquals(balinaOlayi(30_000_000, BUYUK_FON, { gozlem: 40, sapma: 10_000_000 })?.tur, 'fon_giris');
});

Deno.test('küçük fonda olay üretilmez', () => {
  const kucuk = ASGARI_BUYUKLUK - 1;
  assertEquals(balinaOlayi(kucuk * 0.5, kucuk, { gozlem: 40, sapma: 1000 }), null);
});

Deno.test('geçmiş yetersizse ya da sapma yoksa olay üretilmez', () => {
  assertEquals(balinaOlayi(50_000_000, BUYUK_FON, { gozlem: ASGARI_GOZLEM - 1, sapma: 1_000_000 }), null);
  assertEquals(balinaOlayi(50_000_000, BUYUK_FON, { gozlem: 40, sapma: null }), null);
  assertEquals(balinaOlayi(50_000_000, BUYUK_FON, { gozlem: 40, sapma: 0 }), null);
  assertEquals(balinaOlayi(50_000_000, BUYUK_FON, undefined), null);
});

Deno.test('akış yok ya da sıfırsa olay yok', () => {
  assertEquals(balinaOlayi(null, BUYUK_FON, YETERLI), null);
  assertEquals(balinaOlayi(0, BUYUK_FON, YETERLI), null);
  assertEquals(balinaOlayi(Number.NaN, BUYUK_FON, YETERLI), null);
});

// ── yatirimciSayisi ─────────────────────────────────────────────────────────

Deno.test('yatırımcı sayısı yalnız büyüklük günün satırıyla eşleşirse alınır', () => {
  const liste = [{ fonKodu: 'TTE', portBuyukluk: 2385068751.83, yatirimciSayi: 40518 }];
  assertEquals(yatirimciSayisi(liste, 2385068751.83), 40518);
  // TEFAS yeni günü yayınlamış, bizdeki satır eski: yanlış güne yazma.
  assertEquals(yatirimciSayisi(liste, 2256779760.5), null);
});

Deno.test('yatırımcı sayısı bozuksa ya da liste boşsa null', () => {
  assertEquals(yatirimciSayisi([], 100), null);
  assertEquals(yatirimciSayisi(null, 100), null);
  assertEquals(yatirimciSayisi([{ portBuyukluk: 100, yatirimciSayi: null }], 100), null);
  assertEquals(yatirimciSayisi([{ portBuyukluk: 100, yatirimciSayi: -3 }], 100), null);
  assertEquals(yatirimciSayisi([{ portBuyukluk: 100, yatirimciSayi: 12.5 }], 100), null);
});
