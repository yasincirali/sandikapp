// Eurobond seri denetimi (2026-10-08) — sunucu tarafı.
//
//   deno test --allow-all supabase/tests/eurobond_seri_denetimi_test.ts
//
// Kilitlenenler:
//   · `eurobond-seri` GÜNLÜK (`1d`) penceresi SON SEANSI kapsar (Yahoo
//     `range=1d` sözleşmesi); 24 saatlik pencere Pazartesi sabahı boştu.
//   · İşlemiş faiz aritmetiği Dart eşiyle (`test/eurobond_test.dart`) AYNI
//     vektörlerle — ayrışırsa kilit ekranı ile uygulama farklı değer yazar.
//   · `EUROBOND:` sembolü canlı kotasyonda ve tarihli seride Yahoo'ya
//     DÜŞMEZ; uygulamanın ölçeğinde (kirli/100) fiyatlanır.
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  birimDeger,
  islemisFaiz,
  istanbulGunu,
  kuponAraligi,
  SON_SEANS_GERIYE_GUN,
  seriBaslangici,
  sozlesmeSatiri,
} from '../functions/_shared/eurobond.ts';
import { eurobondMu, eurobondSatiriKotasyon, kaynakAyir } from '../functions/_shared/live_prices.ts';
import { fetchDatedSeries, fetchEurobondDated } from '../functions/_shared/dated_history.ts';

const GUN = 86_400_000;

// Dart testindeki sözleşme: %6, vade 15.03.2030, ihraç 2020.
const ALTI = sozlesmeSatiri({
  isin: 'US900123DF45',
  para_birimi: 'USD',
  kupon_orani: 0.06,
  vade: '2030-03-15',
  ihrac_yili: 2020,
  kupon_sikligi: 2,
})!;

// Ölçüm örneği: Türkiye %9,875 2028 (DF45), 2026-10-08.
const DF45_SATIR = {
  isin: 'US900123DF45',
  para_birimi: 'USD',
  kupon_orani: 0.09875,
  vade: '2028-01-15',
  ihrac_yili: 2022,
  kupon_sikligi: 2,
};
const DF45 = sozlesmeSatiri(DF45_SATIR)!;

Deno.test('1d penceresi son seansı kapsar (Pazartesi sabahı boş değil)', () => {
  // Pazartesi 2026-10-12 09:00 TR = 06:00 UTC. 24 saat geri Pazar'a düşerdi.
  const pzt = Date.UTC(2026, 9, 12, 6, 0);
  const bas = seriBaslangici('1d', pzt);
  const cumaKapanis = Date.UTC(2026, 9, 9, 15, 30);
  assert(bas <= cumaKapanis, 'Cuma seansı pencerede olmalı');
  assertEquals(pzt - bas, SON_SEANS_GERIYE_GUN * GUN);
  // Öteki dönemler değişmedi.
  assertEquals(pzt - seriBaslangici('5d', pzt), 5 * GUN);
  assertEquals(pzt - seriBaslangici('5y', pzt), 1827 * GUN);
});

Deno.test('işlemiş faiz: Dart ile aynı vektörler', () => {
  // Kupon gününde sıfır.
  assertEquals(islemisFaiz(ALTI, Date.UTC(2026, 2, 15)), 0);
  // Dönemin yarısında yarım kupon: 3 × 0,5 = 1,5 puan.
  assertAlmostEquals(islemisFaiz(ALTI, Date.UTC(2026, 5, 15)), 1.5, 1e-9);
  // Vadeden sonra sıfır.
  assertEquals(islemisFaiz(ALTI, Date.UTC(2031, 0, 1)), 0);
  // DF45, 2026-10-08: önceki kupon 15.07.2026, 30/360 → 83 gün.
  // 4,9375 × 83 / 180 = 2,276736… (ölçümdeki "103,95 + 2,28").
  assertAlmostEquals(islemisFaiz(DF45, Date.UTC(2026, 9, 8)), 4.9375 * 83 / 180, 1e-9);
});

Deno.test('kupon aralığı ay sonunda kısalır (31 → 28)', () => {
  const s = sozlesmeSatiri({
    isin: 'US900123DF45', para_birimi: 'USD', kupon_orani: 0.05,
    vade: '2027-08-31', ihrac_yili: 2025, kupon_sikligi: 2,
  })!;
  const a = kuponAraligi(s, Date.UTC(2026, 3, 1))!;
  assertEquals(a.onceki, Date.UTC(2026, 1, 28));
  assertEquals(a.sonraki, Date.UTC(2026, 7, 31));
});

Deno.test('katalog satırı: bozuk satırda işlemiş faiz uydurulmaz', () => {
  assertEquals(sozlesmeSatiri({ ...DF45_SATIR, kupon_orani: null }), null);
  assertEquals(sozlesmeSatiri({ ...DF45_SATIR, isin: 'US900123DF46' }), null);
  assertEquals(sozlesmeSatiri({ ...DF45_SATIR, kupon_sikligi: 4 }), null);
  assertEquals(sozlesmeSatiri({ ...DF45_SATIR, para_birimi: 'GBP' }), null);
  assertEquals(sozlesmeSatiri({ ...DF45_SATIR, para_birimi: 'EUR' })?.gun_sayimi, 'act/act');
});

Deno.test('noktanın günü İstanbul takvimiyle (istemci cihaz saati TR)', () => {
  // 2026-10-08 22:30 UTC = 9 Ekim 01:30 TR → faiz 9 Ekim'e göre.
  const ms = Date.UTC(2026, 9, 8, 22, 30);
  assertEquals(istanbulGunu(ms), Date.UTC(2026, 9, 9));
  assertAlmostEquals(
    birimDeger(DF45, 103.95, ms),
    (103.95 + 4.9375 * 84 / 180) / 100,
    1e-12,
  );
});

Deno.test('canlı kotasyon: EUROBOND ayrı kova, Yahoo\'ya DÜŞMEZ', () => {
  const r = kaynakAyir(['EUROBOND:US900123DF45', 'AAPL', 'THYAO.IS', 'KRIPTO:BTC']);
  assertEquals(r.eurobond, ['EUROBOND:US900123DF45']);
  assertEquals(r.yahoo, ['AAPL', 'THYAO.IS']);
  assert(eurobondMu('eurobond:us900123df45'));
  assert(!eurobondMu('AAPL'));
});

Deno.test('canlı kotasyon: kirli/100 ölçeği, günlük yüzde temizden', () => {
  const simdi = Date.UTC(2026, 9, 8, 10, 0);
  const k = eurobondSatiriKotasyon(
    { ...DF45_SATIR, eurobond_fiyat: { temiz_fiyat: 103.95, onceki_kapanis: 103.96 } },
    simdi,
  )!;
  assertAlmostEquals(k.price, (103.95 + 4.9375 * 83 / 180) / 100, 1e-12);
  assertAlmostEquals(k.changePct!, (103.95 - 103.96) / 103.96 * 100, 1e-12);
  // PostgREST gömülü ilişkiyi dizi olarak da döndürebilir.
  const dizi = eurobondSatiriKotasyon(
    { ...DF45_SATIR, eurobond_fiyat: [{ temiz_fiyat: 103.95, onceki_kapanis: null }] },
    simdi,
  )!;
  assertEquals(dizi.changePct, null);
  // Temiz fiyat yoksa nokta yok (banka kotasyonu yerine konmaz).
  assertEquals(
    eurobondSatiriKotasyon({ ...DF45_SATIR, eurobond_fiyat: { temiz_fiyat: null } }, simdi),
    null,
  );
  assertEquals(eurobondSatiriKotasyon({ ...DF45_SATIR, eurobond_fiyat: null }, simdi), null);
});

/// `from('eurobond_katalog').select().eq().maybeSingle()` zinciri.
function sahteIstemci(satir: Record<string, unknown> | null): SupabaseClient {
  const zincir = {
    select: () => zincir,
    eq: () => zincir,
    maybeSingle: () => Promise.resolve({ data: satir, error: null }),
  };
  return { from: () => zincir } as unknown as SupabaseClient;
}

Deno.test('tarihli seri: Frankfurt temiz kapanışı + o günün işlemiş faizi', async () => {
  const t1 = Date.UTC(2026, 9, 7, 22, 0) / 1000; // 8 Ekim 01:00 TR
  const t2 = Date.UTC(2026, 9, 8, 22, 0) / 1000; // 9 Ekim 01:00 TR
  const istenen: string[] = [];
  const f = ((url: string) => {
    istenen.push(url);
    return Promise.resolve(
      new Response(JSON.stringify({ s: 'ok', t: [t2, t1], c: [104, 103.95] })),
    );
  }) as unknown as typeof fetch;

  const seri = await fetchEurobondDated(sahteIstemci(DF45_SATIR), 'EUROBOND:US900123DF45', f);
  assertEquals(istenen.length, 1);
  assert(istenen[0].includes('XFRA:US900123DF45'));
  assert(istenen[0].includes('resolution=1D'));
  assertEquals(seri.length, 2);
  assertAlmostEquals(seri[0][1], (103.95 + 4.9375 * 83 / 180) / 100, 1e-12);
  assertAlmostEquals(seri[1][1], (104 + 4.9375 * 84 / 180) / 100, 1e-12);

  // Kaynak seçici EUROBOND'u Yahoo'ya göndermez.
  istenen.length = 0;
  await fetchDatedSeries(sahteIstemci(DF45_SATIR), 'EUROBOND:US900123DF45', f);
  assert(istenen.every((u) => !u.includes('yahoo')));
});

Deno.test('tarihli seri: katalogda olmayan ISIN için Frankfurt\'a gidilmez', async () => {
  let cagri = 0;
  const f = (() => {
    cagri++;
    return Promise.resolve(new Response('{}'));
  }) as unknown as typeof fetch;
  assertEquals(await fetchEurobondDated(sahteIstemci(null), 'EUROBOND:US900123DF45', f), []);
  assertEquals(await fetchEurobondDated(sahteIstemci(DF45_SATIR), 'EUROBOND:US900123DF46', f), []);
  assertEquals(cagri, 0);
});
