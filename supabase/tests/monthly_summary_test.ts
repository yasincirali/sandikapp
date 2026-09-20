// Aylık özet — pencere ve mesaj kuralları (`weekly-summary`, period=month).
//
// Haftalık testler `weekly_summary_test.ts`'te; burada yalnızca aylığa özgü
// iki saf fonksiyon: geçen takvim ayının TR penceresi ve sayısız/sayılı
// mesaj. Ton kuralları haftalıkla aynı (uyarı yok, emoji yok, tutar yok).
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  ayPenceresi,
  buildMonthlyMessage,
} from '../functions/weekly-summary/index.ts';

// ── ayPenceresi ─────────────────────────────────────────────────────────────

Deno.test('1 Eylül 06:30 UTC → Ağustos penceresi (TR gece yarıları)', () => {
  const p = ayPenceresi(new Date('2026-09-01T06:30:00Z'));
  assertEquals(p.ayAdi, 'Ağustos');
  // 1 Ağustos 00:00 TR = 31 Temmuz 21:00 UTC
  assertEquals(new Date(p.fromMs).toISOString(), '2026-07-31T21:00:00.000Z');
  // 1 Eylül 00:00 TR = 31 Ağustos 21:00 UTC
  assertEquals(new Date(p.toMs).toISOString(), '2026-08-31T21:00:00.000Z');
});

Deno.test('Ocak\'ta geçen ay Aralık — yıl geri sarar', () => {
  const p = ayPenceresi(new Date('2027-01-01T06:30:00Z'));
  assertEquals(p.ayAdi, 'Aralık');
  assertEquals(new Date(p.fromMs).toISOString(), '2026-11-30T21:00:00.000Z');
  assertEquals(new Date(p.toMs).toISOString(), '2026-12-31T21:00:00.000Z');
});

Deno.test('gecikmeli koşu (ayın 3\'ü) yine geçen ayı verir', () => {
  const p = ayPenceresi(new Date('2026-10-03T12:00:00Z'));
  assertEquals(p.ayAdi, 'Eylül');
});

Deno.test('UTC ile TR gün farkı: 30 Eylül 22:00 UTC TR\'de 1 Ekim → Eylül', () => {
  const p = ayPenceresi(new Date('2026-09-30T22:00:00Z'));
  assertEquals(p.ayAdi, 'Eylül');
});

// ── buildMonthlyMessage ─────────────────────────────────────────────────────

Deno.test('akışlı ay: sayı YOK, "hazır" mesajı', () => {
  const m = buildMonthlyMessage('Ağustos', null, null);
  assertEquals(m.title, 'Ağustos özetin hazır');
  assertEquals(/%/.test(m.title + m.body), false);
  assertStringIncludes(m.body, 'Yatırım tavsiyesi değildir');
});

Deno.test('yükseliş: ay adı ve yön oku başlıkta', () => {
  const m = buildMonthlyMessage('Ağustos', 3.46, null);
  assertEquals(m.title, '▲ Ağustos: piyasadan %3,5');
});

Deno.test('düşüş + uzun pencere pozitif → bağlam cümlesi, uyarı tonu yok', () => {
  const m = buildMonthlyMessage('Eylül', -2.1, 18.04);
  assertEquals(m.title, '▼ Eylül: piyasadan −%2,1');
  assertStringIncludes(m.body, '+%18,0');
  assertEquals(/dikkat|uyarı|acil/i.test(m.body), false);
});

Deno.test('düşüş, uzun pencere yok → sade gövde', () => {
  const m = buildMonthlyMessage('Eylül', -2.1, null);
  assertStringIncludes(m.body, 'Özet');
  assertEquals(/hâlâ/.test(m.body), false);
});

Deno.test('tutar sızmaz: yalnızca yüzde', () => {
  const m = buildMonthlyMessage('Temmuz', 12.3, null);
  assertEquals(/₺|TL\b/.test(m.title + m.body), false);
});
