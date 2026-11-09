// Çizgi alarmının adı ve "bildirime dokununca çizgiyi aç" verisi
// (yasin 2026-10-29: "Çizgi alarmında isim verebilelim. Ve bildirime ve
// alarma tıkladığımızda çizgiyi izleyebilelim").
//
// İstemci adı `label`'a "varlık · ad" olarak yazar (`cizgiAlarmEtiketi`,
// lib/services/cizim_alarmi.dart); sunucu başlığı buna göre kurar. Push ve
// çan verisine `cizim_id` EKLENİR — var olan anahtarlar değişmez ki eski
// build'ler aynı davranışı sürdürsün.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  cizgiEtiketiniAyir,
  cizimMesaji,
  cizimVerisi,
} from '../functions/_shared/seviye_alarmi.ts';

Deno.test('etiket: adsız (eski) satır yalnız varlık', () => {
  assertEquals(cizgiEtiketiniAyir('THYAO'), { varlik: 'THYAO', isim: null });
  assertEquals(cizgiEtiketiniAyir('THYAO · '), { varlik: 'THYAO', isim: null });
});

Deno.test('etiket: "varlık · ad" ilk ayraçtan bölünür', () => {
  assertEquals(cizgiEtiketiniAyir('THYAO · Destek 245'), {
    varlik: 'THYAO',
    isim: 'Destek 245',
  });
  assertEquals(cizgiEtiketiniAyir('ASELS · Kırılım · üst'), {
    varlik: 'ASELS',
    isim: 'Kırılım · üst',
  });
});

Deno.test('mesaj: adsız çizgide başlık birebir eskisi', () => {
  const m = cizimMesaji('Bitcoin', 'alt', 3000000, 3010000, '₺');
  assertEquals(m.title, '▼ Bitcoin çizdiğin çizginin altına indi · ₺3.000.000,00');
});

Deno.test('mesaj: adlı çizgi başlıkta adıyla okunur', () => {
  const m = cizimMesaji('THYAO · Destek 245', 'ust', 312.4, 310, '₺');
  assertEquals(m.title, '▲ THYAO «Destek 245» çizgisinin üstüne çıktı · ₺312,40');
  assert(m.body.includes('Çizginin şu anki değeri ₺310,00'));
  assert(m.body.includes('Yatırım tavsiyesi değildir'));
});

Deno.test('veri: cizim_id eklenir, eski anahtarlar aynen kalır', () => {
  assertEquals(cizimVerisi({ id: 'c1', symbol: 'THYAO.IS', cizim_id: 'z9' }), {
    symbol: 'THYAO.IS',
    cizim_alarm_id: 'c1',
    cizim_id: 'z9',
  });
  // Kimliksiz satır (eski sorgu): anahtar hiç yazılmaz, boş dize değil.
  assertEquals(cizimVerisi({ id: 'c1', symbol: 'THYAO.IS' }), {
    symbol: 'THYAO.IS',
    cizim_alarm_id: 'c1',
  });
  assertEquals(cizimVerisi({ id: 'c1', symbol: 'THYAO.IS', cizim_id: '' }), {
    symbol: 'THYAO.IS',
    cizim_alarm_id: 'c1',
  });
});

const TUR = await Deno.readTextFile(
  new URL('../functions/_shared/seviye_alarmi.ts', import.meta.url),
);

Deno.test('tur: çizim sorgusu cizim_id okur, push ve çan aynı veriyi taşır', () => {
  assert(TUR.includes(".select('id, user_id, symbol, label, cizim_id, t1,"));
  assert(TUR.includes('veri: cizimVerisi(a),'));
  // Çan kaydı ve push aynı `veri`; push türü eski build için `price_alert`.
  assert(TUR.includes('data: x.veri,'));
  assert(TUR.includes("data: { type: 'price_alert', ...x.veri },"));
});
