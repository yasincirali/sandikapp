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
  added_date?: string | null;
  ref_asset_id?: string | null;
};

const GUN = (n: number) => `2026-09-${String(n).padStart(2, '0')}T10:00:00Z`;

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

// ── Mezar taşı (`delete_log`) ile susturma ─────────────────────────────────
//
// "Sildiğim varlıklar için push atılmaması gerekiyor" (kullanıcı, 2026-09-07).
//
// Silmenin ASIL mekanizması `deleted_at` damgasıdır ve çağıran sorgu onu
// zaten eliyor. Bu blok İKİNCİ savunma hattını kilitler: istemci önce mezar
// taşını yazıp sonra damgayı attığı için (`deletePositionLots`), arada
// bağlantı koparsa lot sunucuda AKTİF kalır ama kullanıcı onu silinmiş
// görür — push gelmeye devam ederdi.

const mezarTasi = (o: Partial<Lot> & { id: string }): Lot =>
  // `ref_asset_id: null` = POZİSYON silmesi (varsayılan). Tek lot silmesini
  // test etmek isteyen çağıran bunu `o` içinde ezer.
  alim({ ref_asset_id: null, ...o, kind: 'delete_log' });

Deno.test('pozisyon mezar taşı, kendisinden ESKİ alımları susturur', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', added_date: GUN(5) }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('silmeden SONRA tekrar alındıysa bildirim yine gider', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', added_date: GUN(5) }),
    alim({ id: 'b2', added_date: GUN(9) }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.map((l) => l.id), ['b2'], 'yeni alım susturulmamalı');
});

Deno.test('TEK LOT mezar taşı pozisyonu susturmaz — en kritik yanlış pozitif', () => {
  // `deleteAsset` (varlık detayından tek lot silme) `ref_asset_id` DOLU bir
  // mezar taşı yazar. Pozisyon geneline uygulanırsa iki lot'lu bir varlıkta
  // birini silmek diğerini de susturur ve kullanıcı gerçek bir varlık için
  // bildirim almayı bırakır — sessiz, fark edilmesi zor bir hata.
  const lots: Lot[] = [
    alim({ id: 'b1', added_date: GUN(1) }),
    alim({ id: 'b2', added_date: GUN(2) }),
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b3' }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 2);
});

Deno.test('mezar taşı BAŞKA pozisyonu susturmaz', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', ticker: 'AVOD', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', ticker: 'AGHOL', added_date: GUN(5) }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.map((l) => l.ticker), ['AVOD']);
});

Deno.test('mezar taşı BAŞKA kullanıcıyı susturmaz', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', user_id: 'u1', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', user_id: 'u2', added_date: GUN(5) }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 1);
});

Deno.test('mezar taşı miktara girmez — kapalı pozisyonu diriltmez', () => {
  // `delete_log` satırı silinen POZİSYONUN net miktarını taşır. Netlemede
  // alım sayılsaydı, tamamı satılmış bir pozisyon yeniden açılırdı.
  //
  // Mezar taşı burada TEK LOT silmesi (`ref_asset_id` dolu), yani susturma
  // dalı devrede değil — ölçülen tek şey miktarın sızıp sızmadığı.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 50, added_date: GUN(1) }),
    satis({ id: 's1', quantity: 50, added_date: GUN(2) }),
    mezarTasi({
      id: 'g1',
      quantity: 50,
      added_date: GUN(3),
      ref_asset_id: 'b1',
    }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('birden çok mezar taşında EN YENİSİ geçerlidir', () => {
  const lots: Lot[] = [
    mezarTasi({ id: 'g1', added_date: GUN(2) }),
    alim({ id: 'b1', added_date: GUN(4) }),
    mezarTasi({ id: 'g2', added_date: GUN(6) }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0,
    'eski mezar taşı seçilirse b1 açık kalırdı');
});

Deno.test('mezar taşı yoksa added_date hiç okunmaz', () => {
  // Sütun boş gelse bile (eski satır) normal portföy etkilenmemeli.
  const lots: Lot[] = [alim({ id: 'b1', added_date: null })];
  assertEquals(acikPozisyonLotlari(lots).length, 1);
});

// ── ref_asset_id'li mezar taşı: TEK lot'u susturur ──────────────────────────
//
// Kullanıcı bildirimi (2026-09-10): "Sildiğim varlıkların push'ları gelmeye
// devam ediyor."
//
// Sebep: `ref_asset_id` DOLU mezar taşları tamamen atlanıyordu. Eski
// gerekçe "ilgili satır zaten fiziksel silinmiştir" idi ve bu yalnızca
// `deleteAsset` için doğruydu. Normal silme yolu (`deletePositionLots`)
// YUMUŞAK siliyor ve pozisyon TEK lot'luysa mezar taşına `ref_asset_id`
// yazıyor. `deleted_at` damgası yerine ulaşmazsa lot aktif kalıyor, mezar
// taşı atlanıyor ve bildirim gitmeye devam ediyordu. Tek lot'lu pozisyon en
// yaygın durum olduğu için ikinci savunma hattı pratikte hiç çalışmıyordu.

Deno.test('ref_asset_id işaret ettiği lot\'u eler (damga ulaşmasa bile)', () => {
  const lots: Lot[] = [
    alim({ id: 'b1', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b1' }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('ref_asset_id KARDEŞ lot\'u susturmaz', () => {
  // Karşı taraf: iki lot'lu bir varlıkta birini silmek diğerini
  // sessizleştirmemeli. `ref_asset_id`'nin pozisyon geneline
  // uygulanmamasının sebebi tam olarak budur.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 40, added_date: GUN(1) }),
    alim({ id: 'b2', quantity: 60, added_date: GUN(2) }),
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b1' }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.map((l) => l.id), ['b2']);
});

Deno.test('silinen lot\'un miktarı NETTEN de düşülür', () => {
  // 40 alındı + 60 alındı, 60'ı satıldı, sonra 40'lık lot silindi.
  // Net kâğıt üzerinde 40 görünür ama o 40 silinen lot'un kendisidir —
  // pozisyon KAPALIDIR ve bildirim gitmemelidir.
  const lots: Lot[] = [
    alim({ id: 'b1', quantity: 40, added_date: GUN(1) }),
    alim({ id: 'b2', quantity: 60, added_date: GUN(2) }),
    satis({ id: 's1', quantity: 60, added_date: GUN(3) }),
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b1' }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('mezar taşı satır SIRASINDAN bağımsız çalışır', () => {
  // Mezar taşı ilgili alım satırından ÖNCE gelirse de aynı sonuç.
  // (Sorgu sırası garanti değil; tek geçişli bir çözüm burada kırılırdı.)
  const lots: Lot[] = [
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b1' }),
    alim({ id: 'b1', added_date: GUN(1) }),
  ];
  assertEquals(acikPozisyonLotlari(lots).length, 0);
});

Deno.test('silinen lot sonrası TEKRAR alım bildirim hakkı verir', () => {
  // Kullanıcı sildiği varlığı yeniden aldıysa yeni lot açıktır.
  const lots: Lot[] = [
    alim({ id: 'b1', added_date: GUN(1) }),
    mezarTasi({ id: 'g1', added_date: GUN(5), ref_asset_id: 'b1' }),
    alim({ id: 'b2', added_date: GUN(7) }),
  ];
  const out = acikPozisyonLotlari(lots);
  assertEquals(out.map((l) => l.id), ['b2']);
});
