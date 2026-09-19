// Kanarya sessizlik kuralı — saf karar fonksiyonu.
//
//   deno test supabase/tests/kanarya_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { kanaryaBildirilmeliMi, KANARYA_SESSIZLIK_SAAT } from '../functions/_shared/kanarya.ts';

const simdi = new Date('2026-09-19T10:00:00Z');
const saat = (n: number) => new Date(simdi.getTime() - n * 3600_000);

Deno.test('ilk arıza her zaman bildirilir', () => {
  assertEquals(kanaryaBildirilmeliMi(null, simdi), true);
});

Deno.test('pencere içinde susar — her yarım saatlik tur aynı push\'u yağdırmasın', () => {
  assertEquals(kanaryaBildirilmeliMi(saat(0.5), simdi), false);
  assertEquals(kanaryaBildirilmeliMi(saat(KANARYA_SESSIZLIK_SAAT - 0.01), simdi), false);
});

Deno.test('pencere dolunca yeniden bildirir — arıza sürüyorsa hatırlatır', () => {
  assertEquals(kanaryaBildirilmeliMi(saat(KANARYA_SESSIZLIK_SAAT), simdi), true);
  assertEquals(kanaryaBildirilmeliMi(saat(30), simdi), true);
});

Deno.test('gelecekten gelen kayıt (saat kayması) susturur, çökertmez', () => {
  assertEquals(kanaryaBildirilmeliMi(saat(-1), simdi), false);
});
