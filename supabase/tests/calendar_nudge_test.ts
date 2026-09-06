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
  buildInflationMessage,
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
