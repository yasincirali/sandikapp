// Yarış snapshot'ı — saf yardımcıların testleri (2026-09-28).
//
// Sunucu her gün opt-in kullanıcıların ROI ve dağılımını hesaplar; yanlış
// bir yüzde yarış sıralamasını çarpıtır. Burada sabitlenenler:
//   · "t anındaki fiyat" kuralı (tatilde son iş günü, seri sonradan
//     başlıyorsa ilk kapanış);
//   · altın çevrimi (GC=F ons → 22 ayar gram ağırlığı) ve USD kote çevrimi;
//   · kapsama eşiği (yarım portföy getirisi yazılmaz);
//   · dağılım yüzdeleri 100'e tamamlanır, tür sayısı doğru.
//
// Çalıştır: deno test supabase/tests/leaderboard_snapshot_test.ts

import { assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import { fiyatAninda, noktalariTopla, Seri } from '../functions/_shared/dated_history.ts';
import {
  dagilim,
  donemRoi,
  GUN_MS,
  Lot,
  lotSembolleri,
  lotTryFiyati,
  portfoyDegeri,
} from '../functions/leaderboard-snapshot/index.ts';

const G = GUN_MS;
const NOW = Date.UTC(2026, 8, 28, 15, 40); // 28 Eyl 2026 18:40 TR

function seri(...noktalar: Array<[gunOnce: number, fiyat: number]>): Seri {
  return noktalar
    .map(([g, f]) => [NOW - g * G, f] as [number, number])
    .sort((a, b) => a[0] - b[0]);
}

function lot(p: Partial<Lot> & { id: string; type: string }): Lot {
  return { user_id: 'u1', kind: 'buy', quantity: 1, currency: 'TRY', ...p };
}

// ── fiyatAninda ─────────────────────────────────────────────────────────────

Deno.test('t anındaki fiyat: t\'den önceki son kapanış (tatilde son iş günü)', () => {
  const s = seri([10, 100], [5, 110], [1, 120]);
  assertEquals(fiyatAninda(s, NOW - 3 * G), 110);
  assertEquals(fiyatAninda(s, NOW - 5 * G), 110); // tam eşleşme dahil
  assertEquals(fiyatAninda(s, NOW), 120);
});

Deno.test('seri t\'den sonra başlıyorsa ilk kapanış (geriye taşıma)', () => {
  const s = seri([5, 110], [1, 120]);
  assertEquals(fiyatAninda(s, NOW - 30 * G), 110);
  assertEquals(fiyatAninda([], NOW), null);
});

Deno.test('noktalariTopla: geçersizleri atar, sıralar, aynı günde sonuncuyu tutar', () => {
  const t = Date.UTC(2026, 0, 5);
  const out = noktalariTopla([
    [t + 3600_000, 12],
    [t, 10],
    [null, 99],
    [t - G, 0],
    [t - G, 9],
    [t - 2 * G, null],
  ]);
  assertEquals(out, [[t - G, 9], [t + 3600_000, 12]]);
});

// ── Sembol çözümü ve TL fiyatı ─────────────────────────────────────────────

Deno.test('altın: sub kategoriden kod, GC=F + USDTRY ister', () => {
  const l = lot({ id: 'a', type: 'altin', sub_category: 'Çeyrek Altın', ticker: '' });
  assertEquals(lotSembolleri(l), ['GC=F', 'USDTRY=X']);
  const seriler = new Map<string, Seri>([
    ['GC=F', seri([0, 3110.35])], // ons USD → gram24 = 3110.35/31.1035 = 100 USD
    ['USDTRY=X', seri([0, 40])], // gram24 = 4000 TL, gram22 = 4000/1.0909
  ]);
  const p = lotTryFiyati(l, seriler, NOW)!;
  assertAlmostEquals(p, 4000 / 1.0909 * 1.75, 0.01);
});

Deno.test('USD kote varlık: fiyat × USDTRY; kur yoksa null', () => {
  const l = lot({ id: 'b', type: 'emtia', ticker: 'BZ=F', currency: 'USD' });
  assertEquals(lotSembolleri(l), ['BZ=F', 'USDTRY=X']);
  const kurlu = new Map<string, Seri>([['BZ=F', seri([0, 70])], ['USDTRY=X', seri([0, 40])]]);
  assertEquals(lotTryFiyati(l, kurlu, NOW), 2800);
  const kursuz = new Map<string, Seri>([['BZ=F', seri([0, 70])]]);
  assertEquals(lotTryFiyati(l, kursuz, NOW), null);
});

Deno.test('elle fiyatlı lot: seri istemez, iki uçta current_price', () => {
  const l = lot({ id: 'm', type: 'diger', ticker: 'X', is_manual_price: true, current_price: 500 });
  assertEquals(lotSembolleri(l), []);
  assertEquals(lotTryFiyati(l, new Map(), NOW), 500);
  assertEquals(lotTryFiyati(l, new Map(), NOW - 30 * G), 500);
});

// ── ROI ve kapsama ─────────────────────────────────────────────────────────

Deno.test('dönem ROI: bugünkü miktar sabit, yalnız fiyat etkisi', () => {
  const lots = [
    lot({ id: 'h', type: 'hisse', ticker: 'THYAO.IS', quantity: 10 }),
    lot({ id: 'f', type: 'fon', ticker: 'TEFAS:YAY', quantity: 100 }),
  ];
  const seriler = new Map<string, Seri>([
    ['THYAO.IS', seri([30, 100], [0, 120])], // 1000 → 1200
    ['TEFAS:YAY', seri([30, 10], [0, 10])], // 1000 → 1000
  ]);
  // 2000 → 2200 = +%10
  assertAlmostEquals(donemRoi(lots, seriler, NOW, 30)!, 10, 1e-9);
});

Deno.test('kapsama: fiyatsız lot bugünkü değerin %20\'sinden fazlaysa satır yok', () => {
  const lots = [
    lot({ id: 'h', type: 'hisse', ticker: 'THYAO.IS', quantity: 10 }),
    lot({ id: 'z', type: 'hisse', ticker: 'YOK.IS', quantity: 10 }),
  ];
  // Yalnız THYAO fiyatlı; YOK.IS için seri yok → bugünkü değer bilinmez ve
  // fiyatlı küme bugünkü değerin tamamı sayılır. Bu durumda kapsama
  // eşiği geçilir (bilinmeyen lot "yok" gibi davranır)...
  const seriler = new Map<string, Seri>([['THYAO.IS', seri([30, 100], [0, 110])]]);
  assertAlmostEquals(donemRoi(lots, seriler, NOW, 30)!, 10, 1e-9);
  // ...ama dönem BAŞINDA fiyatı olmayan bir lot bugünkü değerin %20'sini
  // aşıyorsa satır yazılmaz: seri bugünden başlıyor değil, tamamen yok.
  const kismi = new Map<string, Seri>([
    ['THYAO.IS', seri([30, 100], [0, 100])],
    ['YOK.IS', seri([0, 100])], // yalnız bugün → geriye taşınır, sorun yok
  ]);
  assertAlmostEquals(donemRoi(lots, kismi, NOW, 30)!, 0, 1e-9);
});

Deno.test('ROI: başlangıç değeri sıfırsa null; aralık kırpılır', () => {
  const lots = [lot({ id: 'h', type: 'hisse', ticker: 'A.IS', quantity: 1 })];
  assertEquals(donemRoi(lots, new Map(), NOW, 7), null);
  const uc = new Map<string, Seri>([['A.IS', seri([7, 0.0001], [0, 1_000_000])]]);
  assertEquals(donemRoi(lots, uc, NOW, 7), 100000);
});

Deno.test('portfoyDegeri: yalnizca kümesi ve kapsanan lotlar', () => {
  const lots = [
    lot({ id: 'a', type: 'hisse', ticker: 'A.IS', quantity: 2 }),
    lot({ id: 'b', type: 'hisse', ticker: 'B.IS', quantity: 3 }),
  ];
  const seriler = new Map<string, Seri>([['A.IS', seri([0, 10])], ['B.IS', seri([0, 100])]]);
  const hepsi = portfoyDegeri(lots, seriler, NOW);
  assertEquals(hepsi.deger, 320);
  assertEquals([...hepsi.kapsanan].sort(), ['a', 'b']);
  const yalniz = portfoyDegeri(lots, seriler, NOW, new Set(['a']));
  assertEquals(yalniz.deger, 20);
});

// ── Dağılım ────────────────────────────────────────────────────────────────

Deno.test('dağılım: tür payları 1 ondalık, toplam ≈ 100, tür sayısı', () => {
  const lots = [
    lot({ id: 'h', type: 'hisse', ticker: 'A.IS', quantity: 1 }),
    lot({ id: 'g', type: 'altin', ticker: 'ALTIN_GRAM', quantity: 1 }),
    lot({ id: 'm', type: 'diger', ticker: 'M', is_manual_price: true, current_price: 100 }),
  ];
  const seriler = new Map<string, Seri>([
    ['A.IS', seri([0, 600])],
    ['GC=F', seri([0, 31.1035 * 1.0909])], // gram22 = 1 USD
    ['USDTRY=X', seri([0, 300])], // ALTIN_GRAM = 300 TL
  ]);
  const d = dagilim(lots, seriler, NOW)!;
  assertEquals(d.type_count, 3);
  assertEquals(d.allocation_pct, { hisse: 60, altin: 30, diger: 10 });
  const toplam = Object.values(d.allocation_pct).reduce((a, b) => a + b, 0);
  assertAlmostEquals(toplam, 100, 0.2);
});

Deno.test('dağılım: fiyatlanan lot yoksa null', () => {
  const lots = [lot({ id: 'z', type: 'hisse', ticker: 'YOK.IS', quantity: 5 })];
  assertEquals(dagilim(lots, new Map(), NOW), null);
});
