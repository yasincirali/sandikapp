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
  DefterSatiri,
  donemTwr,
  GUN_MS,
  ilkEdinmeAni,
  Lot,
  lotSembolleri,
  lotTryFiyati,
  netLotlar,
  portfoyDegeri,
  seriSembolu,
  tekKullanici,
  fonDetayi,
  varlikSayisi,
  yazimPlani,
  yarisAni,
  yedekTryFiyati,
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

// ── Seçimlerinin getirisi (TWR, 0095) ─────────────────────────────────────
//
// "Yarış Ölçüsü Kıyası" senaryosu (2026-10-01): X dalgalı (100 → dip 80 →
// 120), Y sakin (100 → 110 → 105). Ay = 30 gün; Ay 0 bugünden 360 gün önce.
// Beklenen sayılar o sayfanın TWR sütunu. İstemci eşi aynı senaryoyu
// `test/secim_getirisi_test.dart`'ta koşar — iki motor ayrışırsa biri kırılır.

const AY = 30;
const X_AY = [100, 104, 107, 110, 100, 90, 80, 88, 96, 104, 110, 118, 120];
const Y_AY = [100, 101, 102, 103, 104, 106, 110, 109, 107, 106, 105, 105, 105];
const ayAni = (ay: number) => NOW - (360 - ay * AY) * G;
const ayIso = (ay: number) => new Date(ayAni(ay)).toISOString();
const aySerisi = (f: number[]): Seri => f.map((v, ay) => [ayAni(ay), v] as [number, number]);
const PIYASA = new Map<string, Seri>([
  ['X.IS', aySerisi(X_AY)],
  ['Y.IS', aySerisi(Y_AY)],
]);

let _no = 0;
function hareket(
  ticker: string,
  ay: number,
  tutar: number,
  p: { satis?: boolean; girisAyi?: number; fiyat?: number } = {},
): DefterSatiri {
  const fiyat = p.fiyat ?? (ticker === 'X.IS' ? X_AY : Y_AY)[ay];
  return {
    id: `r${++_no}`,
    user_id: 'u1',
    type: 'hisse',
    ticker,
    kind: p.satis ? 'sell' : 'buy',
    quantity: tutar / fiyat,
    currency: 'TRY',
    added_date: ayIso(ay),
    created_at: ayIso(p.girisAyi ?? ay),
  };
}

const twr = (defter: DefterSatiri[]) => donemTwr(defter, PIYASA, NOW, 365);

Deno.test('TWR senaryo: Ayşe, Burak, Cem — para zamanlaması sonucu değiştirmez (%20)', () => {
  assertAlmostEquals(twr([hareket('X.IS', 0, 100_000)])!, 20, 1e-9);
  assertAlmostEquals(twr([hareket('X.IS', 0, 100_000), hareket('X.IS', 6, 100_000)])!, 20, 1e-9);
  assertAlmostEquals(twr([hareket('X.IS', 0, 100_000), hareket('X.IS', 3, 100_000)])!, 20, 1e-9);
});

Deno.test('TWR senaryo: Deniz — Y\'yi satıp X alan kararıyla ölçülür (%65)', () => {
  const y = hareket('Y.IS', 0, 100_000);
  const satis = { ...hareket('Y.IS', 6, 0, { satis: true }), quantity: y.quantity };
  const x = hareket('X.IS', 6, 110_000);
  assertAlmostEquals(twr([y, satis, x])!, 65, 1e-9);
});

Deno.test('TWR senaryo: Hakan — girilen fiyat (1 TL) kullanılmaz, piyasa fiyatı (%50)', () => {
  const h = { ...hareket('X.IS', 6, 100_000), quantity: 1250, purchase_price: 1 };
  assertAlmostEquals(twr([h])!, 50, 1e-9);
});

Deno.test('TWR senaryo: Ege — yalnız tuttuğu ay ölçülür (%1,69)', () => {
  assertAlmostEquals(twr([hareket('X.IS', 11, 1_000)])!, (120 / 118 - 1) * 100, 1e-9);
});

Deno.test('TWR senaryo: Fikret — küçük taban + büyük geç para şişirmez (%6,69)', () => {
  const v = twr([hareket('Y.IS', 0, 10_000), hareket('X.IS', 11, 200_000)])!;
  const bekl = (1.05 * ((100 * 105 + (200_000 / 118) * 120) / (100 * 105 + 200_000)) - 1) * 100;
  assertAlmostEquals(v, bekl, 1e-9);
  assertAlmostEquals(v, 6.69, 0.01);
});

Deno.test('TWR senaryo: Gül — Ay 12\'de girilen "Ay 6" alımı girildiği an sayılır', () => {
  // Giriş bugün → ilk alım bugün → 30 günlük asgari ölçüm yok → sıralamada yok.
  assertEquals(twr([hareket('X.IS', 6, 100_000, { girisAyi: 12 })]), null);
  // Aynı hile eski bir hesapta: Ayşe'nin defterine eklenen geriye tarihli
  // dip alımı sonucu değiştirmez (bugün alınmış sayılır, getirisi ~0).
  const ayse = hareket('X.IS', 0, 100_000);
  assertAlmostEquals(twr([ayse, hareket('X.IS', 6, 100_000, { girisAyi: 12 })])!, 20, 1e-9);
});

Deno.test('yarisAni: 3 gün pay; fazlası giriş anı; giriş anı yoksa tarih', () => {
  const r = (eklenmeGun: number, girisGun: number | null): DefterSatiri => ({
    id: 'a', user_id: 'u1', type: 'hisse',
    added_date: new Date(NOW - eklenmeGun * G).toISOString(),
    created_at: girisGun === null ? null : new Date(NOW - girisGun * G).toISOString(),
  });
  assertEquals(yarisAni(r(2, 0)), NOW - 2 * G); // dün/önceki gün alındı
  assertEquals(yarisAni(r(3, 0)), NOW - 3 * G); // sınırda pay içinde
  assertEquals(yarisAni(r(4, 0)), NOW); // geriye tarih → giriş anı
  assertEquals(yarisAni(r(40, null)), NOW - 40 * G);
});

Deno.test('TWR: asgari 30 gün ölçüm; dönemden bağımsız', () => {
  const genc = [hareket('X.IS', 12, 1_000)];
  genc[0].added_date = new Date(NOW - 20 * G).toISOString();
  genc[0].created_at = genc[0].added_date;
  assertEquals(donemTwr(genc, PIYASA, NOW, 7), null);
  const yetiskin = [{ ...genc[0], added_date: new Date(NOW - 31 * G).toISOString(), created_at: new Date(NOW - 31 * G).toISOString() }];
  // 31 gün önce alındı: 7 günlük dönemde yalnız son 7 gün ölçülür
  // (X 118 → bugün 120); 31 günün tamamı değil.
  assertAlmostEquals(donemTwr(yetiskin, PIYASA, NOW, 7)!, (120 / 118 - 1) * 100, 1e-9);
});

Deno.test('TWR: asgari süre edinme tarihinden; getiri giriş anından (2026-10-09)', () => {
  // 40 gün önce alınmış, 10 gün önce uygulamaya girilmiş (içe aktarım).
  // Eskiden giriş anından sayılırdı → null. Şimdi kapı açık; getiri yalnız
  // girildiği günden beri ölçülür (geriye tarih kuralı korunur).
  const r: DefterSatiri = {
    id: 'ia', user_id: 'u1', type: 'hisse', ticker: 'X.IS', kind: 'buy',
    quantity: 10, currency: 'TRY',
    added_date: new Date(NOW - 40 * G).toISOString(),
    created_at: new Date(NOW - 10 * G).toISOString(),
  };
  assertEquals(ilkEdinmeAni([r]), NOW - 40 * G);
  // X son 10 günde 118 → 120 (Ay 11 → Ay 12 arası doğrusal değil; seri
  // basamaklı: 10 gün önce 118). 40 gün öncesinin 110'u getiriye girmez.
  assertAlmostEquals(donemTwr([r], PIYASA, NOW, 30)!, (120 / 118 - 1) * 100, 1e-9);
  // Edinme 20 gün önce → 30 günlük kapı kapalı; ayar 14 ise açık.
  const genc = { ...r, added_date: new Date(NOW - 20 * G).toISOString() };
  assertEquals(donemTwr([genc], PIYASA, NOW, 30), null);
  assertEquals(donemTwr([genc], PIYASA, NOW, 30, 14) !== null, true);
});

Deno.test('TWR kapsama: serisi olmayan lot bugünkü değerin %20\'sini aşarsa null', () => {
  const x = hareket('X.IS', 0, 100_000); // bugün 120.000
  const yok = (fiyat: number): DefterSatiri => ({
    id: 'z', user_id: 'u1', type: 'hisse', ticker: 'YOK.IS', kind: 'buy',
    quantity: 100, currency: 'TRY', current_price: fiyat,
    added_date: ayIso(0), created_at: ayIso(0),
  });
  assertEquals(twr([x, yok(500)]), null); // 50.000 karanlıkta
  assertAlmostEquals(twr([x, yok(50)])!, 20, 1e-9); // 5.000 → yazılır, seri dışı
});

Deno.test('TWR: fiyatı hiç olmayan defter null; sonuç CHECK aralığına kırpılır', () => {
  assertEquals(donemTwr([hareket('X.IS', 0, 100)], new Map(), NOW, 365), null);
  const uc = new Map<string, Seri>([['X.IS', [[ayAni(0), 0.0001], [ayAni(6), 1_000_000]]]]);
  assertEquals(donemTwr([hareket('X.IS', 0, 1)], uc, NOW, 365), 100000);
});

Deno.test('fon kodu öneksizse TEFAS: eklenir; diğer türler dokunulmaz', () => {
  assertEquals(seriSembolu(lot({ id: 'f', type: 'fon', ticker: 'AFT' })), 'TEFAS:AFT');
  assertEquals(seriSembolu(lot({ id: 'f', type: 'fon', ticker: 'TEFAS:AFT' })), 'TEFAS:AFT');
  assertEquals(seriSembolu(lot({ id: 'h', type: 'hisse', ticker: 'AFT.IS' })), 'AFT.IS');
  assertEquals(lotSembolleri(lot({ id: 'f', type: 'fon', ticker: 'aft' })), ['TEFAS:AFT']);
});

Deno.test('yedek fiyat: current_price, TRY dışı kurla; kur yoksa 0', () => {
  const tl = lot({ id: 'a', type: 'hisse', ticker: 'X', current_price: 12 });
  assertEquals(yedekTryFiyati(tl, new Map(), NOW), 12);
  const usd = lot({ id: 'b', type: 'emtia', ticker: 'Y', currency: 'USD', current_price: 2 });
  assertEquals(yedekTryFiyati(usd, new Map(), NOW), 0);
  assertEquals(yedekTryFiyati(usd, new Map([['USDTRY=X', seri([0, 40])]]), NOW), 80);
  // Dağılıma yedekle girer.
  const d = dagilim([tl], new Map(), NOW)!;
  assertEquals(d.allocation_pct, { hisse: 100 });
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


// ── Net lot ───────────────────────────────────────────────────────────────

Deno.test('netLotlar: satış lot miktarından düşülür, pozisyon başına tek lot', () => {
  const tum = [
    lot({ id: 'k1', type: 'hisse', ticker: 'KCHOL.IS', quantity: 1000, added_date: '2023-09-13T21:00:00Z' }),
    lot({ id: 'k2', type: 'hisse', ticker: 'KCHOL.IS', quantity: 620, added_date: '2025-09-25T21:00:00Z', current_price: 216.5 }),
    lot({ id: 'k3', type: 'hisse', ticker: 'KCHOL.IS', quantity: 620, added_date: '2025-09-25T21:00:00Z' }),
    lot({ id: 's1', type: 'hisse', ticker: 'KCHOL.IS', quantity: 1620, kind: 'sell', added_date: '2026-09-16T13:40:00Z' }),
    lot({ id: 'm1', type: 'hisse', ticker: 'KCHOL.IS', quantity: 500, kind: 'delete_log' }),
    lot({ id: 'a1', type: 'hisse', ticker: 'AVOD.IS', quantity: 1000 }),
    lot({ id: 'a2', type: 'hisse', ticker: 'AVOD.IS', quantity: 1000, kind: 'sell' }),
  ];
  const acik = tum.filter((l) => (l.kind ?? 'buy') === 'buy');
  const out = netLotlar(acik, tum);
  assertEquals(out.length, 1);
  assertEquals(out[0].ticker, 'KCHOL.IS');
  assertAlmostEquals(out[0].quantity as number, 620, 1e-9);
  // Şablon en yeni alım: k2/k3 aynı tarihli, ilk gelen kalır; current_price taşınır.
  assertEquals(out[0].id, 'k2');
  assertEquals(out[0].current_price, 216.5);
});

Deno.test('netLotlar: farklı para birimi / tür ayrı pozisyon, mezar taşı miktara girmez', () => {
  const tum = [
    lot({ id: 'g1', type: 'altin', sub_category: 'Çeyrek Altın', quantity: 30 }),
    lot({ id: 'g2', type: 'altin', sub_category: 'Çeyrek Altın', quantity: 25 }),
    lot({ id: 'gs', type: 'altin', sub_category: 'Çeyrek Altın', quantity: 20, kind: 'sell' }),
    lot({ id: 'gm', type: 'altin', sub_category: 'Çeyrek Altın', quantity: 55, kind: 'delete_log' }),
    lot({ id: 'u1', type: 'doviz', ticker: 'USDTRY=X', quantity: 2200 }),
  ];
  const acik = tum.filter((l) => (l.kind ?? 'buy') === 'buy');
  const out = netLotlar(acik, tum).sort((a, b) => a.type.localeCompare(b.type));
  assertEquals(out.map((l) => [l.type, l.quantity]), [['altin', 35], ['doviz', 2200]]);
});

// ── 0091: zirve yalnız açık rıza verene, yarış yalnız katılana ──────────────
Deno.test('yazimPlani: zirve yalnız rıza verenleri alır, yarış yalnız opt-in', () => {
  const roi = [
    { user_id: 'a', period_days: 30, roi_pct: 2.7 },
    { user_id: 'b', period_days: 30, roi_pct: -3.3 },
  ];
  const alloc = [
    { user_id: 'b', allocation_pct: { altin: 100 }, type_count: 1 },
    { user_id: 'c', allocation_pct: { fon: 100 }, type_count: 1 },
  ];
  const plan = yazimPlani(roi, alloc, new Set(['b', 'z']), new Set(['a', 'c']));
  // Rıza: a ve c. 'b' yarışta ama zirveye rıza vermedi → zirvede YOK.
  assertEquals(plan.zirveRoi.map((r) => r.user_id), ['a']);
  assertEquals(plan.zirveAlloc.map((r) => r.user_id), ['c']);
  // 'z' opt-in ama ölçülmedi → yazılacak satırı yok; 'a' ve 'c' opt-in değil.
  assertEquals(plan.yarisKullanicilari, ['b']);
});

Deno.test('yazimPlani: kimse yarışa katılmamışsa yarış tablosuna yazım yok', () => {
  const plan = yazimPlani(
    [{ user_id: 'a', period_days: 7, roi_pct: 1 }],
    [{ user_id: 'a', allocation_pct: { hisse: 100 }, type_count: 1 }],
    new Set<string>(),
    new Set(['a']),
  );
  assertEquals(plan.yarisKullanicilari, []);
  assertEquals(plan.zirveRoi.length, 1);
});

Deno.test('yazimPlani: rıza yoksa zirveye hiçbir satır yazılmaz', () => {
  // 0091 öncesi herkes ölçülüyordu; artık rızasız kullanıcının getirisi
  // zirve için SAKLANMAZ (veri minimizasyonu).
  const plan = yazimPlani(
    [{ user_id: 'a', period_days: 30, roi_pct: 5 }],
    [{ user_id: 'a', allocation_pct: { altin: 100 }, type_count: 1 }],
    new Set(['a']),
    new Set<string>(),
  );
  assertEquals(plan.zirveRoi, []);
  assertEquals(plan.zirveAlloc, []);
  assertEquals(plan.yarisKullanicilari, ['a']);
});

// ── 0084: fon kırılımı ──────────────────────────────────────────────────────
function fonLot(ticker: string, quantity: number, current_price: number): Lot {
  return {
    id: ticker + quantity, user_id: 'u', type: 'fon', ticker, name: 'Kullanıcının notu',
    quantity, current_price, is_manual_price: true, kind: 'buy', currency: 'TRY',
  } as unknown as Lot;
}

Deno.test('fonDetayi: kod bazında pay, toplam portföyün yüzdesi', () => {
  const lots = [
    fonLot('AFT', 100, 10), // 1000
    fonLot('TTE', 50, 10), // 500
    { ...fonLot('X', 1, 1), type: 'altin', ticker: 'ALTIN_GRAM', quantity: 1, current_price: 2500 } as Lot,
  ];
  const d = fonDetayi(lots, new Map(), NOW)!;
  assertEquals(d, { AFT: 25, TTE: 12.5 });
});

Deno.test('fonDetayi: serbest metin kod ve %1 altı "diğer"e düşer; ad taşınmaz', () => {
  const lots = [
    fonLot('AFT', 990, 1), // %99
    fonLot('babamın fonu', 5, 1), // kalıba uymaz
    fonLot('IPB', 5, 1), // %0,5 < eşik
  ];
  const d = fonDetayi(lots, new Map(), NOW)!;
  assertEquals(d.AFT, 99);
  assertEquals(d.DIGER, 1);
  assertEquals(Object.keys(d).sort(), ['AFT', 'DIGER']);
  assertEquals(JSON.stringify(d).includes('babam'), false);
});

Deno.test('fonDetayi: fon yoksa null; TEFAS: öneki kırpılır', () => {
  assertEquals(fonDetayi([
    { ...fonLot('X', 1, 1), type: 'hisse', ticker: 'THYAO', current_price: 300 } as Lot,
  ], new Map(), NOW), null);
  assertEquals(fonDetayi([fonLot('TEFAS:aft', 10, 10)], new Map(), NOW), { AFT: 100 });
});

// ── 0085: en az 2 farklı varlık ─────────────────────────────────────────────
Deno.test('varlikSayisi: aynı sembolün lotları tek, değersiz/sıfır miktar sayılmaz', () => {
  const lots = [
    fonLot('AFT', 10, 10),
    fonLot('AFT', 5, 10), // aynı fon, ikinci lot
    fonLot('TTE', 0, 10), // miktar sıfır (satılmış)
    fonLot('IPB', 3, 0), // değeri yok
  ];
  assertEquals(varlikSayisi(lots, new Map(), NOW), 1);
  assertEquals(varlikSayisi([...lots, fonLot('TTE', 2, 10)], new Map(), NOW), 2);
});

// ── Mevduat / BES (0088) ───────────────────────────────────────────────────

Deno.test('mevduat: seri istemez, current_price (istemcinin birim değeri) ile değerlenir', () => {
  const l = lot({
    id: 'mv',
    type: 'mevduat',
    ticker: 'MEVDUAT:9f1c2e7a-0000-4000-8000-000000000001',
    quantity: 250000,
    current_price: 1.0312,
  });
  assertEquals(lotSembolleri(l), []);
  assertEquals(lotTryFiyati(l, new Map(), NOW), 1.0312);
});

Deno.test('BES: TEFAS emeklilik fonu serisinden fiyatlanır', () => {
  const l = lot({ id: 'b', type: 'bes', ticker: 'TEFAS:AH5', sub_category: 'katki' });
  assertEquals(lotSembolleri(l), ['TEFAS:AH5']);
  const seriler = new Map<string, Seri>([['TEFAS:AH5', seri([1, 0.021])]]);
  assertEquals(lotTryFiyati(l, seriler, NOW), 0.021);
});

Deno.test('tekKullanici: geçerli uuid tek kullanıcı modunu açar', () => {
  assertEquals(
    tekKullanici({ user_id: 'A1B2C3D4-0000-4000-8000-00000000000F', source: 'zirve_riza' }),
    'a1b2c3d4-0000-4000-8000-00000000000f',
  );
});

Deno.test('tekKullanici: cron gövdesi, bozuk ya da boş değer tam koşu demek', () => {
  assertEquals(tekKullanici({ source: 'cron' }), null);
  assertEquals(tekKullanici({ user_id: 'herkes' }), null);
  assertEquals(tekKullanici({ user_id: "x' or 1=1" }), null);
  assertEquals(tekKullanici({ user_id: 42 }), null);
  assertEquals(tekKullanici(null), null);
});
