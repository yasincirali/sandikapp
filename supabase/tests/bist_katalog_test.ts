// BIST hisse kataloğu — saf yardımcıların testleri (0139).
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Evren hisselerdir.** Adi hisse + kapalı uçlu yatırım ortaklığı girer;
//    BYF (ETF) ve Darphane sertifikaları (ALTIN, DMLKT) girmez.
// 2. **KAP biçimi.** Kaçışlı Next.js yükünden kod → unvan; çok kodlu şirket.
// 3. **Kısa ad.** Resmî unvan uygulamanın üslubuna iner, Türkçe büyük/küçük
//    harf doğru ("İş", "Işık"), "ve" küçük kalır.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/bist_katalog_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  ASGARI_HISSE,
  DISLANAN,
  evrenKur,
  kapUnvanlari,
  kisaAd,
  type TvSatiri,
} from '../functions/_shared/bist_katalog.ts';

Deno.test('evren: adi hisse ve yatırım ortaklığı girer, BYF ve sertifika girmez', () => {
  const satirlar: TvSatiri[] = [
    ['THYAO', 'Turk Hava Yollari A.O.', 'stock', 'common'],
    ['KUTPO', 'Kutahya Porselen Sanayi AS', 'stock', 'common'],
    ['ISYAT', 'Is Yatirim Ortakligi A.S.', 'fund', 'closedend'],
    ['GLDTR', 'GOLDIST - Istanbul Gold ETF', 'fund', 'etf'],
    ['ALTIN', 'Darphane Altin Sertifikasi', 'stock', 'common'],
    ['DMLKT', 'Darphane Gumus', 'stock', 'common'],
    ['bozuk kod', 'x', 'stock', 'common'],
  ];
  const e = evrenKur(satirlar);
  assertEquals([...e.keys()].sort(), ['ISYAT', 'KUTPO', 'THYAO']);
  assertEquals(e.get('THYAO'), 'Turk Hava Yollari A.O.');
  assertEquals(DISLANAN.has('ALTIN'), true);
});

Deno.test('asgari hisse eşiği borsanın büyüklüğüne göre makul', () => {
  // ~630 kâğıt; eşik yarım yanıtı yakalamalı ama gerçek küçülmeyi değil.
  assertEquals(ASGARI_HISSE >= 400 && ASGARI_HISSE <= 550, true);
});

Deno.test('KAP: kaçışlı JSON yükünden kod → unvan', () => {
  const html = String.raw`self.__next_f.push([1,"[{\"mkkMemberOid\":\"a\",\"kapMemberTitle\":\"TÜRK HAVA YOLLARI A.O.\",\"relatedMemberTitle\":\"PwC\",\"stockCode\":\"THYAO\",\"cityName\":\"İSTANBUL\"},{\"kapMemberTitle\":\"AYTEMİZ YATIRIM BANKASI A.Ş.\",\"stockCode\":\"AYTEM, AYTEB\"}]"])`;
  const m = kapUnvanlari(html);
  assertEquals(m.get('THYAO'), 'TÜRK HAVA YOLLARI A.O.');
  assertEquals(m.get('AYTEM'), 'AYTEMİZ YATIRIM BANKASI A.Ş.');
  assertEquals(m.get('AYTEB'), 'AYTEMİZ YATIRIM BANKASI A.Ş.');
});

Deno.test('KAP biçimi değişirse boş harita (ad TradingView\'dan gelir)', () => {
  assertEquals(kapUnvanlari('<html>yeni biçim</html>').size, 0);
});

Deno.test('kısa ad: tüzel kuyruk gider, Türkçe harfler doğru', () => {
  assertEquals(kisaAd('TÜRK HAVA YOLLARI A.O.', 'THYAO'), 'Türk Hava Yolları');
  assertEquals(kisaAd('KÜTAHYA PORSELEN SANAYİ A.Ş.', 'KUTPO'), 'Kütahya Porselen');
  assertEquals(kisaAd('İŞ GİRİŞİM SERMAYESİ YATIRIM ORTAKLIĞI A.Ş.', 'ISGSY'),
    'İş Girişim Sermayesi Yatırım Ortaklığı');
  assertEquals(kisaAd('TSKB GAYRİMENKUL YATIRIM ORTAKLIĞI A.Ş.', 'TSGYO'), 'TSKB GYO');
  assertEquals(kisaAd('GÜR-SEL TURİZM TAŞIMACILIK VE SERVİS TİCARET A.Ş.', 'GRSEL'),
    'Gür-Sel Turizm Taşımacılık ve Servis');
});

Deno.test('kısa ad: ASCII TradingView açıklaması da iner; boşsa kod', () => {
  assertEquals(kisaAd('Kutahya Porselen Sanayi AS', 'KUTPO'), 'Kutahya Porselen');
  assertEquals(kisaAd(null, 'YENIH'), 'YENIH');
  assertEquals(kisaAd('   ', 'YENIH'), 'YENIH');
});
