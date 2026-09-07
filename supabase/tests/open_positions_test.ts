// Açık pozisyon netlemesi testleri.
//
// Kapsanan hata (2026-09-07, kullanıcı bildirimi): "AVOD ve AGHOL
// varlıklarımda olmamasına rağmen push'ları geliyor."
//
// Sebep: `assets` bir LOT tablosudur, satış alım satırını silmez —
// `kind='sell'` ayrı bir satır olarak yazılır. Sunucudaki push işleri
// yalnızca `kind='buy'` filtresi uyguluyor, satışları hiç okumuyordu.
// İstemci (`aggregatePositions`) net miktarı 0 olan pozisyonu portföyden
// düşürdüğü için kullanıcı "bu varlık bende yok" görüyor ama sunucu
// bildirim göndermeye devam ediyordu.
//
// Çalıştır:
//   deno test supabase/tests/open_positions_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  acikPozisyonLotlari,
  pozisyonAnahtari,
} from '../functions/_shared/positions.ts';

type Lot = {
  id: string;
  user_id: string;
  type: string;
  ticker?: string | null;
  name?: string | null;
  sub_category?: string | null;
  currency?: string | null;
  quantity?: number | null;
  kind?: string | null;
};

const alim = (o: Partial<Lot> & { id: string }): Lot => ({
  user_id: 'u1',
  type: 'hisse',
  ticker: 'AVOD',
  currency: 'TRY',
  quantity: 100,
  kind: 'buy',
  ...o,
});

const satis = (o: Partial<Lot> & { id: string }): Lot =>
  alim({ ...o, kind: 'sell' });

Deno.test('tamamen satılan pozisyon elenir — AVOD/AGHOL hatası', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 90 }),
    satis({ id: 's1', quantity: 90 }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('kısmi satış pozisyonu KAPATMAZ', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 90 }),
    satis({ id: 's1', quantity: 40 }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.length, 1);
  assertEquals(out[0].id, 'b1');
});

Deno.test('çok lotlu pozisyon: satış TOPLAM üzerinden netlenir', () => {
  // İki ayrı alım (60 + 40) ve tek satış (100) → pozisyon kapalı.
  // Lot bazlı netleme yapılsaydı ikinci alım açık kalırdı.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 60 }),
    alim({ id: 'b2', quantity: 40 }),
    satis({ id: 's1', quantity: 100 }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);

  // Satış 70 olsaydı iki alım lot'u da açık pozisyona ait olur ve
  // ikisi de dönerdi (lot → tek bildirim indirgemesi ayrı katmandır).
  const kismi: Lot[] = [
    alim({ id: 'b1', quantity: 60 }),
    alim({ id: 'b2', quantity: 40 }),
    satis({ id: 's1', quantity: 70 }),
  ];
  assertEquals(acikPozisyonLotlari(kismi).length, 2);
});

Deno.test('kayan nokta artığı pozisyonu açık göstermez', () => {
  // 0.1 × 3 = 0.30000000000000004 — ham karşılaştırma bunu "> 0" sayar
  // ve kapanmış pozisyon için bildirim gitmeye devam ederdi.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 0.1 }),
    alim({ id: 'b2', quantity: 0.1 }),
    alim({ id: 'b3', quantity: 0.1 }),
    satis({ id: 's1', quantity: 0.3 }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('başka kullanıcının satışı benim pozisyonumu kapatmaz', () => {
  // `user_id` anahtardan düşerse bir kullanıcının satışı diğerinin
  // alımından düşülür ve sahibine bildirim hiç gitmez.
  const lots: Lot[] = [
    alim({ id: 'b1', user_id: 'u1', quantity: 50 }),
    satis({ id: 's1', user_id: 'u2', quantity: 50 }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.length, 1);
  assertEquals(out[0].user_id, 'u1');
});

Deno.test('farklı ürünün satışı netlemeye girmez', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', ticker: 'AVOD', quantity: 50 }),
    satis({ id: 's1', ticker: 'AGHOL', quantity: 50 }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.length, 1);
  assertEquals(out[0].ticker, 'AVOD');
});

Deno.test('temettü ve mezar taşı satırları miktara girmez', () => {
  // `dividend` nakit hareketidir, `delete_log` mezar taşıdır. İkisi de
  // alım sayılırsa pozisyon satıldıktan sonra bile açık görünürdü.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 50 }),
    satis({ id: 's1', quantity: 50 }),
    alim({ id: 'd1', quantity: 0, kind: 'dividend' }),
    alim({ id: 'g1', quantity: 50, kind: 'delete_log' }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('satış satırı çıktıya karışmaz', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 90 }),
    satis({ id: 's1', quantity: 10 }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.map((l) => l.id), ['b1']);
});

Deno.test('altın alt kategorileri ayrı pozisyondur', () => {
  // Çeyrek satışı gram pozisyonunu kapatmamalı — Dart tarafındaki
  // `positionKey` ile aynı kural.
  const gram = alim({
    id: 'b1',
    type: 'altin',
    ticker: '',
    sub_category: 'Gram',
    quantity: 10,
  });
  const ceyrekSatis = satis({
    id: 's1',
    type: 'altin',
    ticker: '',
    sub_category: 'Çeyrek',
    quantity: 10,
  });
  assertEquals(acikPozisyonLotlari([gram, ceyrekSatis]).length, 1);
  assertEquals(
    pozisyonAnahtari(gram) === pozisyonAnahtari(ceyrekSatis),
    false,
  );
});

Deno.test('farklı para birimi ayrı pozisyondur', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', currency: 'TRY', quantity: 10 }),
    satis({ id: 's1', currency: 'USD', quantity: 10 }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 1);
});

Deno.test('kind null (migration öncesi satır) alım sayılır', () => {
  const lots: Lot[] = [alim({ id: 'b1', kind: null, quantity: 5 })];
  assertEquals(acikPozisyonLotlari(lots).length, 1);
});

Deno.test('satışsız portföy olduğu gibi geçer', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', ticker: 'THYAO' }),
    alim({ id: 'b2', ticker: 'ASELS' }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 2);
});
