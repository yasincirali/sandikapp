// Sessiz saatler — saf yardımcıların testleri (0057 / _shared/quiet_hours.ts).
import { assertEquals } from 'jsr:@std/assert@1';
import { istanbulHour, sessizSaatteMi } from '../functions/_shared/quiet_hours.ts';

Deno.test('istanbulHour UTC+3 sabit', () => {
  assertEquals(istanbulHour(new Date('2026-09-14T06:45:00Z')), 9);
  assertEquals(istanbulHour(new Date('2026-09-14T22:00:00Z')), 1);
});

Deno.test('kapalı: null / eşit / aralık dışı', () => {
  assertEquals(sessizSaatteMi(3, null, null), false);
  assertEquals(sessizSaatteMi(3, 22, null), false);
  assertEquals(sessizSaatteMi(3, 5, 5), false);
  assertEquals(sessizSaatteMi(3, -1, 5), false);
  assertEquals(sessizSaatteMi(3, 0, 24), false);
});

Deno.test('düz pencere 9–18: 9 içinde, 18 dışında', () => {
  assertEquals(sessizSaatteMi(9, 9, 18), true);
  assertEquals(sessizSaatteMi(17, 9, 18), true);
  assertEquals(sessizSaatteMi(18, 9, 18), false);
  assertEquals(sessizSaatteMi(3, 9, 18), false);
});

Deno.test('sarmalı pencere 22–7: gece içinde, gündüz dışında', () => {
  assertEquals(sessizSaatteMi(22, 22, 7), true);
  assertEquals(sessizSaatteMi(3, 22, 7), true);
  assertEquals(sessizSaatteMi(6, 22, 7), true);
  assertEquals(sessizSaatteMi(7, 22, 7), false);
  assertEquals(sessizSaatteMi(12, 22, 7), false);
});

Deno.test('dört proaktif fonksiyon yardımcıyı kullanıyor', async () => {
  for (const fn of ['daily-brief', 'weekly-summary', 'calendar-nudge', 'check-price-alerts']) {
    const src = await Deno.readTextFile(new URL(`../functions/${fn}/index.ts`, import.meta.url));
    assertEquals(src.includes('sessizKullanicilar('), true, `${fn} sessiz saatleri uygulamalı`);
  }
});
