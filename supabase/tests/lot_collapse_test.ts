// Lot → pozisyon indirgemesi testleri.
//
// Kapsanan hata (2026-08-31): aynı üründen birden çok kez alım yapan
// kullanıcı, o varlık için alım sayısı kadar KOPYA push alıyordu.
// `assets` bir lot tablosu, `signal_state` PK'sı `(user_id, asset_id)` —
// iki lot iki bağımsız de-dup satırı demekti ve ikisi de diğerinden
// habersiz "bunu göndermedim" diyordu.
//
// Çalıştır:
//   deno test supabase/tests/lot_collapse_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { collapseLotsToPositions } from '../functions/analyze-signals/index.ts';

type Lot = { id: string; user_id: string; type: string; ticker: string };

/// Testlerde sembol çözümü: ticker'ı büyük harfe çevirir. Gerçek
/// `resolveSymbol` daha karmaşık (BIST soneki vb.) ama indirgeme mantığı
/// sembolün NASIL bulunduğuna değil, AYNI olup olmadığına duyarlı.
const sym = (a: Lot) => (a.ticker ? a.ticker.toUpperCase() : undefined);

Deno.test('aynı üründen üç alım → tek pozisyon', () => {
  const lots: Lot[] = [
    { id: 'a3', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
    { id: 'a2', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 1, 'üç lot tek bildirime inmeli');
  // Temsilci deterministik olmalı: en küçük id. Tur başına değişirse
  // de-dup hafızası her turda başka satıra yazılır ve çift bildirim döner.
  assertEquals(out[0].id, 'a1');
});

Deno.test('temsilci giriş sırasından bağımsız — determinizm', () => {
  const base: Lot[] = [
    { id: 'z', user_id: 'u1', type: 'hisse', ticker: 'ASELS' },
    { id: 'm', user_id: 'u1', type: 'hisse', ticker: 'ASELS' },
    { id: 'b', user_id: 'u1', type: 'hisse', ticker: 'ASELS' },
  ];
  const ileri = collapseLotsToPositions(base, sym);
  const geri = collapseLotsToPositions([...base].reverse(), sym);
  assertEquals(ileri[0].id, geri[0].id, 'sıra değişince temsilci değişmemeli');
  assertEquals(ileri[0].id, 'b');
});

Deno.test('farklı ürünler birleşmez', () => {
  const lots: Lot[] = [
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
    { id: 'a2', user_id: 'u1', type: 'hisse', ticker: 'ASELS' },
    { id: 'a3', user_id: 'u1', type: 'hisse', ticker: 'GARAN' },
  ];
  assertEquals(collapseLotsToPositions(lots, sym).length, 3);
});

Deno.test('AYNI ürün farklı kullanıcılarda birleşmez', () => {
  // En kritik senaryo: `user_id` anahtardan düşerse iki kullanıcıdan
  // yalnızca birine bildirim gider, diğeri sessizce bildirim kaybeder.
  const lots: Lot[] = [
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
    { id: 'a2', user_id: 'u2', type: 'hisse', ticker: 'THYAO' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 2, 'her kullanıcı kendi bildirimini almalı');
  assertEquals(
    new Set(out.map((a) => a.user_id)),
    new Set(['u1', 'u2']),
  );
});

Deno.test('aynı ticker farklı türde birleşmez', () => {
  const lots: Lot[] = [
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: 'XAU' },
    { id: 'a2', user_id: 'u1', type: 'emtia', ticker: 'XAU' },
  ];
  assertEquals(collapseLotsToPositions(lots, sym).length, 2);
});

Deno.test('sembolü çözülemeyen lot elenir', () => {
  // Döngü bu lot'u zaten `if (!symbol) continue` ile eliyor; burada
  // gruplamanın onu boş anahtarla tek grupta toplamadığı doğrulanır.
  const lots: Lot[] = [
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: '' },
    { id: 'a2', user_id: 'u1', type: 'hisse', ticker: '' },
    { id: 'a3', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 1);
  assertEquals(out[0].id, 'a3');
});

Deno.test('boş giriş boş çıkar', () => {
  assertEquals(collapseLotsToPositions([], sym).length, 0);
});

Deno.test('tek lot değişmeden geçer — regresyon koruması', () => {
  // Tek alımlı varlıklar bu değişiklikten ETKİLENMEMELİ; onlarda de-dup
  // zaten doğru çalışıyordu.
  const lots: Lot[] = [
    { id: 'a1', user_id: 'u1', type: 'hisse', ticker: 'THYAO' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 1);
  assertEquals(out[0].id, 'a1');
});

// ── ÜRETİM VAKASI (ölçülmüş, 2026-09-01) ──────────────────────────────────
//
// Aşağıdaki senaryo uydurma değil: `signal_notifications` sorgusundan
// çıkarıldı. Kullanıcı bu ürünler için her cron turunda lot sayısı kadar
// bildirim alıyordu.
//
//   asset_ticker  farklı_asset_id  toplam_bildirim  son_bildirim
//   TEFAS:DLY     3                28               2026-09-01 08:00
//   ALTIN_CEYREK  3                15               2026-08-25 10:00
//   EURTRY=X      2                14               2026-08-28 10:00
//   AVOD.IS       2                2                2026-08-22 07:00
//
// Desen her satırda aynıydı: AYNI dakika (tek cron turu), AYNI ticker,
// AYNI sinyal — yani üç kopya. Sebep: `signal_state` PK'sı
// `(user_id, asset_id)` olduğu için üç lot üç bağımsız de-dup satırıydı.
Deno.test('üretim vakası: TEFAS:DLY 3 lot → 1 bildirim', () => {
  const lots: Lot[] = [
    { id: 'lot-c', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
    { id: 'lot-a', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
    { id: 'lot-b', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 1, '3 lot = 3 push idi; tek bildirime inmeli');
  assertEquals(out[0].id, 'lot-a', 'temsilci deterministik olmalı (en küçük id)');
});

Deno.test('üretim vakası: dört ürün birden, her biri tek bildirim', () => {
  // Gerçek turda dördü aynı anda değerlendiriliyordu.
  const lots: Lot[] = [
    { id: 'd1', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
    { id: 'd2', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
    { id: 'd3', user_id: 'u1', type: 'fon', ticker: 'TEFAS:DLY' },
    { id: 'c1', user_id: 'u1', type: 'altin', ticker: 'ALTIN_CEYREK' },
    { id: 'c2', user_id: 'u1', type: 'altin', ticker: 'ALTIN_CEYREK' },
    { id: 'c3', user_id: 'u1', type: 'altin', ticker: 'ALTIN_CEYREK' },
    { id: 'e1', user_id: 'u1', type: 'doviz', ticker: 'EURTRY=X' },
    { id: 'e2', user_id: 'u1', type: 'doviz', ticker: 'EURTRY=X' },
    { id: 'v1', user_id: 'u1', type: 'hisse', ticker: 'AVOD.IS' },
    { id: 'v2', user_id: 'u1', type: 'hisse', ticker: 'AVOD.IS' },
  ];
  const out = collapseLotsToPositions(lots, sym);
  assertEquals(out.length, 4, '10 lot → 4 ürün → 4 bildirim');
  // Ölçülen toplam: bir turda 3+3+2+2 = 10 bildirim gidiyordu.
  assertEquals(lots.length - out.length, 6, '6 kopya bildirim engellenmeli');
});

// ── Bağlantı (wiring) koruması ────────────────────────────────────────────
//
// Yukarıdaki testler fonksiyonun DOĞRU olduğunu kanıtlar, KULLANILDIĞINI
// değil. Sabotajla ölçüldü: döngü `pozisyonlar` yerine tekrar `aktifAssets`
// üzerine alındığında — yani asıl hata birebir geri geldiğinde — sekiz
// testin sekizi de GEÇTİ. Birim testi bu regresyonu göremez çünkü hata
// fonksiyonda değil, çağrı yerinde.
//
// Bu yüzden kaynak metni doğrudan denetlenir. Kırılgan görünür ama
// koruduğu şey gerçek: sessizce kopya bildirim üreten bir regresyon.
Deno.test('döngü lot değil POZİSYON üzerinde dönüyor', async () => {
  const src = await Deno.readTextFile(
    new URL('../functions/analyze-signals/index.ts', import.meta.url),
  );

  // Ana analiz döngüsü indirgenmiş listeyi kullanmalı.
  assertEquals(
    src.includes('for (const asset of pozisyonlar)'),
    true,
    'Ana döngü `pozisyonlar` üzerinde dönmeli — `aktifAssets` üzerinde ' +
      'dönerse aynı üründen birden çok alım yapan kullanıcı KOPYA push alır.',
  );

  // Ve indirgeme fiilen çağrılmış olmalı.
  assertEquals(
    src.includes('collapseLotsToPositions('),
    true,
    '`collapseLotsToPositions` çağrılmıyor — lot birleştirme devre dışı.',
  );
});
