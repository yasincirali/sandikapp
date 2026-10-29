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

// Ar-Ge 29 Eki #1: resmî tatil ve yarım gün sunucuda da bilinir.
import {
  bistSeansAcikMi,
  bistTatilMi,
  bistYarimGunMu,
  borsaKapaliGunMu,
} from '../functions/_shared/piyasa_takvimi.ts';

// Perşembe 29 Ekim 2026 11:00 TR (Cumhuriyet Bayramı).
const bayram = new Date('2026-10-29T08:00:00Z');

Deno.test('tatil: borsa türleri atlanır, altın/döviz/kripto koşar', () => {
  assertEquals(bistTatilMi(bayram), true);
  for (const t of ['hisse', 'fon', 'bes', 'eurobond']) {
    assertEquals(borsaKapaliGunMu(t, bayram), true, t);
  }
  for (const t of ['kripto', 'altin', 'doviz', 'emtia']) {
    assertEquals(borsaKapaliGunMu(t, bayram), false, t);
  }
  // Hafta sonu kuralı korunur.
  assertEquals(borsaKapaliGunMu('hisse', cumartesi), true);
  assertEquals(borsaKapaliGunMu('hisse', cuma), false);
});

Deno.test('seans: tatilde kapalı, 28 Ekim 12:30 sonrası kapalı, normal gün açık', () => {
  assertEquals(bistSeansAcikMi(bayram), false);
  // 28 Ekim yarım gün: 12:00 TR açık, 13:00 TR kapalı.
  assertEquals(bistYarimGunMu(new Date('2026-10-28T09:00:00Z')), true);
  assertEquals(bistSeansAcikMi(new Date('2026-10-28T09:00:00Z')), true);
  assertEquals(bistSeansAcikMi(new Date('2026-10-28T10:00:00Z')), false);
  // Cuma 23 Ekim 12:00 TR açık; 18:10 TR kapalı; 09:59 TR kapalı.
  assertEquals(bistSeansAcikMi(cuma), true);
  assertEquals(bistSeansAcikMi(new Date('2026-10-23T15:10:00Z')), false);
  assertEquals(bistSeansAcikMi(new Date('2026-10-23T06:59:00Z')), false);
  assertEquals(bistSeansAcikMi(cumartesi), false);
});

Deno.test('kapsanmayan yılda dinî bayram bilinmez (uydurma tatil yok)', () => {
  // 2027 Ramazan Bayramı listede yok → açık gün sayılır.
  assertEquals(bistTatilMi(new Date('2027-03-10T08:00:00Z')), false);
  // Sabit tatil her yıl geçerli.
  assertEquals(bistTatilMi(new Date('2027-04-23T08:00:00Z')), true);
  // TR gece yarısı: 28 Ekim 21:30 UTC = 29 Ekim 00:30 TR → tatil.
  assertEquals(bistTatilMi(new Date('2026-10-28T21:30:00Z')), true);
});
