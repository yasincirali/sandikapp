// Takvim kancası — saf yardımcıların testleri.
//
// Bu bildirim ULUSAL bir rakam taşıyor ve TÜİK'in açıkladığı sayıyla
// birebir tutmak zorunda: kullanıcı bildirimi gördükten dakikalar sonra
// aynı rakamı haberlerde görecek. Tutmazsa uygulamanın bütün sayılarına
// olan güven sarsılır.
//
// Çalıştır:
//   deno test supabase/tests/calendar_nudge_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  annualInflation,
  ayinSonGunu,
  birikimDonemi,
  birikimHedefleri,
  birikimMesaji,
  bugununSecimleri,
  trAyBasiUtc,
  buildInflationMessage,
  endeksAyGeri,
  formatPct,
  monthlyInflation,
} from '../functions/calendar-nudge/index.ts';

/// Kayan nokta: 102/100-1 tam olarak 0.02 değildir.
function yakin(a: number | null, b: number, eps = 1e-9) {
  assertEquals(a !== null && Math.abs(a - b) < eps, true, `${a} != ${b}`);
}

Deno.test('yüzde Türkçe virgülle yazılır', () => {
  assertEquals(formatPct(2.487), '2,49');
  assertEquals(formatPct(40), '40,00');
});

Deno.test('aylık enflasyon endeks oranından', () => {
  yakin(monthlyInflation(100, 102), 2);
  yakin(monthlyInflation(2000, 2050), 2.5);
});

Deno.test('yıllık enflasyon 12 ay öncesine göre', () => {
  yakin(annualInflation(100, 140), 40);
});

Deno.test('geçersiz endeks null döner — uydurma rakam gitmez', () => {
  assertEquals(monthlyInflation(0, 100), null);
  assertEquals(monthlyInflation(Number.NaN, 100), null);
  assertEquals(annualInflation(100, Number.NaN), null);
});

Deno.test('mesaj iki rakamı da taşır', () => {
  const m = buildInflationMessage(2.49, 40.12);
  assertEquals(m.title.includes('aylık %2,49'), true, m.title);
  assertEquals(m.title.includes('yıllık %40,12'), true, m.title);
});

Deno.test('yıllık hesaplanamıyorsa yalnız aylık yazılır', () => {
  const m = buildInflationMessage(2.49, null);
  assertEquals(m.title.includes('aylık %2,49'), true);
  assertEquals(m.title.includes('yıllık'), false);
});

Deno.test('mesaj KİŞİYE ÖZEL rakam iddia etmez', () => {
  // Bildirim ulusal rakamı taşır. "Senin portföyün %X" demek uydurma
  // olurdu: kişiye özel hesap sunucuda yok (canlı kur ve tüm geçmiş
  // gerekir). Kullanıcı uygulamayı açtığında reel getiri rozeti karşılıyor.
  const m = buildInflationMessage(2.49, 40.12);
  const s = `${m.title} ${m.body}`.toLowerCase();
  for (const yasak of ['portföyün %', 'senin getirin', 'kazandın']) {
    assertEquals(s.includes(yasak), false, `iddia: ${yasak}`);
  }
});


// ── Uçlar TARİHTEN seçilir, dizi indeksinden değil (2026-09-16) ──────────
//
// Eskiden `seri[12]` "12 ay öncesi" varsayılıyordu. `limit(13)` SATIR
// sayısıdır: seride bir ay eksikse `seri[12]` 13 ay öncesi olur ve bildirim
// yanlış bir yıllık TÜFE taşır. Bu projede tam olarak öyle bir kesinti
// yaşandı (TÜİK Ocak 2026'da baz yılını değiştirdi).

function seri(
  aylar: Array<[string, number]>,
): Array<{ period: string; tufe_index: number }> {
  // Sorgu azalan sırada geliyor; test de o şekli taklit eder.
  return aylar.map(([period, tufe_index]) => ({
    period: `${period}-01`,
    tufe_index,
  }));
}

Deno.test('endeksAyGeri tarihle bulur — tam seri', () => {
  const s = seri([
    ['2026-08', 131.51],
    ['2026-07', 129.0],
    ['2025-08', 100.0],
  ]);
  assertEquals(endeksAyGeri(s, '2026-08', 1), 129.0);
  assertEquals(endeksAyGeri(s, '2026-08', 12), 100.0);
});

Deno.test('EKSİK ay: null döner — komşu satır 12 ay sanılmaz', () => {
  // 2025-08 yok; indeks tabanlı eski kod 2025-07'yi (13 ay öncesi) alır ve
  // yıllık TÜFE'yi olduğundan YÜKSEK gösterirdi.
  const s = seri([
    ['2026-08', 131.51],
    ['2025-07', 98.0],
  ]);
  assertEquals(endeksAyGeri(s, '2026-08', 12), null);
  assertEquals(annualInflation(98.0, 131.51) !== null, true,
    'hesap kendi başına çalışıyor — kapı UÇ SEÇİMİNDE');
});

Deno.test('yıl sınırını doğru geçer — Ocak ayından 12 ay geri', () => {
  const s = seri([
    ['2026-01', 120.0],
    ['2025-01', 100.0],
  ]);
  assertEquals(endeksAyGeri(s, '2026-01', 12), 100.0);
  assertEquals(endeksAyGeri(s, '2026-01', 1), null); // 2025-12 tabloda yok
});

Deno.test('bozuk endeks değeri null sayılır', () => {
  const s = seri([['2026-08', 131.51], ['2025-08', 0]]);
  assertEquals(endeksAyGeri(s, '2026-08', 12), null);
});

// ── Maaş günü birikim hatırlatması (0119) ───────────────────────────────────

Deno.test('birikim: ayın son günü (artık yıl dahil)', () => {
  assertEquals(ayinSonGunu(2026, 2), 28);
  assertEquals(ayinSonGunu(2028, 2), 29);
  assertEquals(ayinSonGunu(2026, 10), 31);
  assertEquals(ayinSonGunu(2026, 4), 30);
});

Deno.test('birikim: ayın içinde yalnız o gün; son günde taşan seçimler de', () => {
  assertEquals(bugununSecimleri(15, 31), [15]);
  // Şubat 28: 28, 29, 30, 31 seçenlerin hepsi bugün.
  assertEquals(bugununSecimleri(28, 28), [28, 29, 30, 31]);
  assertEquals(bugununSecimleri(30, 30), [30, 31]);
  assertEquals(bugununSecimleri(31, 31), [31]);
});

Deno.test('birikim: dönem ve TR ay başı (UTC+3)', () => {
  assertEquals(birikimDonemi(2026, 3), '2026-03-01');
  // 1 Ekim 00:00 TR = 30 Eylül 21:00 UTC — ayın ilk saatlerindeki alım sayılır.
  assertEquals(trAyBasiUtc(2026, 10), '2026-09-30T21:00:00.000Z');
});

Deno.test('birikim: bu ay alımı olan ve zaten hatırlatılan hedef değil', () => {
  assertEquals(
    birikimHedefleri(['a', 'b', 'c', 'd'], new Set(['b']), new Set(['c'])),
    ['a', 'd'],
  );
});

Deno.test('birikim: mesaj rakam ve korku dili taşımaz', () => {
  const m = birikimMesaji();
  const metin = `${m.title} ${m.body}`;
  assertEquals(/\d/.test(metin), false, 'kişiye özel rakam yok');
  assertEquals(/bozul|kaybet|son şans|kaçırma/i.test(metin), false);
});
