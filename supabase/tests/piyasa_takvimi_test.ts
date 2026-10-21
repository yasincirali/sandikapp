import { assertEquals } from 'jsr:@std/assert@1';
import { haftaSonuKapaliMi } from '../functions/_shared/piyasa_takvimi.ts';

// Cumartesi 24 Ekim 2026 öğle (TR), cuma 23 Ekim öğle (TR).
const cumartesi = new Date('2026-10-24T09:00:00Z');
const cuma = new Date('2026-10-23T09:00:00Z');

Deno.test('hafta sonu: borsa türleri atlanır, kripto/altın/döviz/emtia koşar', () => {
  for (const t of ['hisse', 'fon', 'bes', 'eurobond']) {
    assertEquals(haftaSonuKapaliMi(t, cumartesi), true, t);
  }
  for (const t of ['kripto', 'altin', 'doviz', 'emtia']) {
    assertEquals(haftaSonuKapaliMi(t, cumartesi), false, t);
  }
});

Deno.test('hafta içi hiçbir tür atlanmaz', () => {
  for (const t of ['hisse', 'fon', 'bes', 'eurobond', 'kripto', 'altin']) {
    assertEquals(haftaSonuKapaliMi(t, cuma), false, t);
  }
});

Deno.test('gün Türkiye saatiyle: cuma 22:30 UTC = cumartesi 01:30 TR', () => {
  assertEquals(haftaSonuKapaliMi('hisse', new Date('2026-10-23T22:30:00Z')), true);
  // Pazar 21:30 UTC = pazartesi 00:30 TR → açık gün.
  assertEquals(haftaSonuKapaliMi('hisse', new Date('2026-10-25T21:30:00Z')), false);
});
