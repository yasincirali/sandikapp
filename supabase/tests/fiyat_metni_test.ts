// Bildirim fiyat metni — sayı biçimi ve para simgesi (2026-10-29).
import { assertEquals } from 'jsr:@std/assert@1';
import {
  endeksMi,
  fiyatMetni,
  fiyatSayisi,
  kotasyonSimgesi,
} from '../functions/_shared/fiyat_metni.ts';

Deno.test('fiyat sayısı: binlik nokta, 2 ondalık; 1 altı en çok 6 anlamlı ondalık', () => {
  assertEquals(fiyatSayisi(6281.45), '6.281,45');
  assertEquals(fiyatSayisi(1234567.5), '1.234.567,50');
  assertEquals(fiyatSayisi(0.000412), '0,000412');
  assertEquals(fiyatSayisi(0.5), '0,50');
  assertEquals(fiyatSayisi(0.1791), '0,1791');
  assertEquals(fiyatSayisi(-1234.5), '-1.234,50');
});

Deno.test('simge: TL kote olanlar ₺, vadeli ve ABD hissesi $', () => {
  for (const s of ['THYAO.IS', 'ALTIN_GRAM', 'USDTRY=X', 'TEFAS:AFT', 'KRIPTO:BTC']) {
    assertEquals(kotasyonSimgesi(s), '₺', s);
  }
  assertEquals(kotasyonSimgesi('CL=F'), '$');
  assertEquals(kotasyonSimgesi('GRAM:SI=F'), '$');
  assertEquals(kotasyonSimgesi('AAPL'), '$');
  assertEquals(kotasyonSimgesi('BRK-B'), '$');
  assertEquals(kotasyonSimgesi('EURUSD=X'), '$');
});

Deno.test('simge: kayıt yalnız belirsiz sembolde kullanılır', () => {
  // Kayıt varsayılanı 'TRY' sembolün açık söylediğini ezmez.
  assertEquals(kotasyonSimgesi('CL=F', 'TRY'), '$');
  assertEquals(kotasyonSimgesi('EUROBOND:XS1234567890', 'EUR'), '€');
  assertEquals(kotasyonSimgesi('EUROBOND:XS1234567890'), null);
  assertEquals(kotasyonSimgesi('SAP.DE'), null);
});

Deno.test('endeks puandır: simge yok', () => {
  assertEquals(endeksMi('XU100.IS'), true);
  assertEquals(endeksMi('^GSPC'), true);
  assertEquals(endeksMi('THYAO.IS'), false);
  assertEquals(kotasyonSimgesi('XU100.IS'), null);
  assertEquals(fiyatMetni(10234.5, kotasyonSimgesi('^NDX')), '10.234,50');
});
