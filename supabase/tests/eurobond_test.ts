// Eurobond ayrıştırıcıları — saf fonksiyonlar, ağ yok.
//
//   deno test supabase/tests/eurobond_test.ts
//
// Örnek yanıtlar 2026-10-08'de GitHub koşucusundan gerçek kaynaklara
// gidilerek alındı (`tool/kaynak_ornek.py`); biçim değişirse burada kırılır.
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import {
  bfAdiniCoz,
  bfCozunurluk,
  bfFiyatiniCoz,
  bfGecmisiniCoz,
  isinGecerli,
  kuponSikligi,
  seriAnahtari,
  seriIstegiCoz,
  tahvilAdi,
  trSayi,
  trTarih,
  ziraatTablosunuCoz,
} from '../functions/_shared/eurobond.ts';

const ZIRAAT = `
<table><tr><th>Kıymet Adı</th><th>Vade</th><th>Vadeye Kalan Gün</th><th>Döviz</th>
<th>Alış Fiyatı</th><th>Alış Oranı</th><th>Satış Fiyatı</th><th>Satış Oranı</th></tr>
<tr><td>US900123CK49</td><td>09.10.2026</td><td>1</td><td>USD</td><td>102,072958</td><td>128,57</td><td>102,729500</td><td>0,00</td></tr>
<tr><td>US900123DF45</td><td>15.01.2028</td><td>464</td><td>USD</td><td>105,599736</td><td>7,07</td><td>107,200167</td><td>5,80</td></tr>
<tr><td><span>XS2361850527</span></td><td>08.07.2027</td><td>273</td><td>EUR</td><td>101,049740</td><td>4,40</td><td>103,100685</td><td>1,68</td></tr>
<tr><td>US900123DF46</td><td>15.01.2028</td><td>464</td><td>USD</td><td>1</td><td>1</td><td>2</td><td>1</td></tr>
</table>
<table><tr><th>Sıra</th><th>Taksit</th></tr><tr><td>{%= parseInt(i+1) %}</td><td>x</td></tr></table>`;

Deno.test('ISIN kontrol hanesi', () => {
  assert(isinGecerli('US900123DF45'));
  assert(isinGecerli('XS2361850527'));
  assert(!isinGecerli('US900123DF46'));
  assert(!isinGecerli('AAPL'));
});

Deno.test('Türkçe sayı ve tarih', () => {
  assertEquals(trSayi('102,072958'), 102.072958);
  assertEquals(trSayi('1.234,5'), 1234.5);
  assertEquals(trSayi('—'), null);
  assertEquals(trTarih('15.01.2028'), '2028-01-15');
  assertEquals(trTarih('31.02.2028'), null);
});

Deno.test('Ziraat tablosu: geçerli satırlar, anlamsız getiri ve hatalı ISIN elenir', () => {
  const s = ziraatTablosunuCoz(ZIRAAT);
  assertEquals(s.map((x) => x.isin), ['US900123CK49', 'US900123DF45', 'XS2361850527']);
  const df45 = s[1];
  assertEquals(df45.vade, '2028-01-15');
  assertEquals(df45.para_birimi, 'USD');
  assertEquals(df45.banka_alis, 105.599736);
  assertEquals(df45.banka_satis, 107.200167);
  assertAlmostEquals(df45.banka_alis_getiri!, 0.0707, 1e-12);
  // Vadesine bir gün kalan tahvilin "%128,57"si gösterilmez.
  assertEquals(s[0].banka_alis_getiri, null);
  assertEquals(s[2].para_birimi, 'EUR');
});

Deno.test('Ziraat tablosu: sütun sırası değişirse hiçbir şey okunmaz', () => {
  const bozuk = ZIRAAT.replace('<th>Alış Fiyatı</th><th>Alış Oranı</th>', '<th>Alış Oranı</th><th>Alış Fiyatı</th>');
  assertEquals(ziraatTablosunuCoz(bozuk), []);
});

Deno.test('Frankfurt adı → kupon ve yıllar', () => {
  assertEquals(bfAdiniCoz('Türkei, Republik 9,875% 22/28'), {
    kupon_orani: 0.09875,
    ihrac_yili: 2022,
    vade_yili: 2028,
  });
  assertEquals(bfAdiniCoz('Türkei, Republik 5,25% 20/30')?.kupon_orani, 0.0525);
  assertEquals(bfAdiniCoz('Türkei, Republik 7% 19/29')?.kupon_orani, 0.07);
  assertEquals(bfAdiniCoz('Türkei, Republik FLR'), null);
});

Deno.test('Frankfurt fiyatı', () => {
  const j = {
    changeToPrevDayAbsolute: -0.01, closingPricePrevTradingDay: 103.96, isin: 'US900123DF45',
    lastPrice: 103.95, mic: 'XFRA', minimumTradableUnit: 200000,
    timestampLastPrice: '2026-10-08T12:56:05+02:00', tradedInPercent: true,
  };
  assertEquals(bfFiyatiniCoz(j), {
    temiz_fiyat: 103.95,
    onceki_kapanis: 103.96,
    piyasa_zamani: '2026-10-08T10:56:05.000Z',
  });
  assertEquals(bfFiyatiniCoz({ ...j, tradedInPercent: false }), null);
  assertEquals(bfFiyatiniCoz({ status: 404, message: 'No data found' }), null);
});

Deno.test('Frankfurt geçmişi', () => {
  const j = { s: 'ok', t: [1759363200, 1759276800], c: [109.13, 109.56], o: [], h: [], l: [] };
  assertEquals(bfGecmisiniCoz(j), [[1759276800000, 109.56], [1759363200000, 109.13]]);
  assertEquals(bfGecmisiniCoz({ s: 'no_data' }), []);
  assertEquals(bfGecmisiniCoz({ s: 'ok', t: [1], c: [] }), []);
});

Deno.test('seri isteği ve çözünürlük', () => {
  assertEquals(seriIstegiCoz({ isin: 'us900123df45', aralik: '1d', donem: '1y' }), {
    isin: 'US900123DF45', aralik: '1d', donem: '1y',
  });
  assertEquals(seriIstegiCoz({ isin: 'US900123DF46' }), null);
  assertEquals(seriIstegiCoz({ isin: 'US900123DF45', donem: '10y' }), null);
  assertEquals(bfCozunurluk('5m'), '15');
  assertEquals(bfCozunurluk('1h'), '60');
  assertEquals(bfCozunurluk('1wk'), '1D');
  assertEquals(seriAnahtari({ isin: 'US900123DF45', aralik: '5m', donem: '1d' }), 'US900123DF45|15|1d');
});

Deno.test('katalog yardımcıları', () => {
  assertEquals(kuponSikligi('USD'), 2);
  assertEquals(kuponSikligi('EUR'), 1);
  assertEquals(tahvilAdi(0.09875, '2028-01-15'), 'Türkiye %9,875 2028');
});
