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

// ── Ayın 3'ü, TÜFE ile birleşik (2026-10-01) ────────────────────────────────
// Kullanıcı bildirimi: 1 Ekim'de giden Eylül özeti Özet'te Ağustos
// enflasyonuna götürüyordu. Aylık özet artık ayın KENDİ TÜFE'siyle gider;
// başka ayın enflasyonu bu aya yazılmaz.
import { ayinTufesi } from '../functions/weekly-summary/index.ts';

const endeks = (sonAy: number) =>
  Array.from({ length: sonAy }, (_, i) => ({
    period: `2026-${String(i + 1).padStart(2, '0')}-01`,
    value: 100 * Math.pow(1.02, i),
  }));

Deno.test('ayPenceresi tablo anahtarını verir (3 Ekim → 2026-09-01)', () => {
  assertEquals(ayPenceresi(new Date('2026-10-03T07:30:00Z')).donem, '2026-09-01');
  assertEquals(ayPenceresi(new Date('2027-01-03T07:30:00Z')).donem, '2026-12-01');
});

Deno.test('ayın TÜFE\'si yoksa null — Ağustos Eylül diye yazılmaz', () => {
  // Tabloda son satır Ağustos; Eylül özeti istenirse null.
  assertEquals(ayinTufesi(endeks(8), '2026-09-01'), null);
});

Deno.test('ayın TÜFE\'si varsa o ayın aylık oranı', () => {
  const t = ayinTufesi(endeks(9), '2026-09-01');
  assertEquals(t !== null, true);
  assertEquals(Math.abs(t!.aylikPct - 2) < 1e-9, true);
  // 12 ay öncesi yok → yıllık null (uydurma yok)
  assertEquals(t!.yillikPct, null);
});

Deno.test('özetlenen aydan SONRAKİ satırlar karışmaz', () => {
  const t = ayinTufesi(endeks(10), '2026-09-01');
  assertEquals(Math.abs(t!.aylikPct - 2) < 1e-9, true);
});

Deno.test('TÜFE başlıkta: getiri ve enflasyon yan yana', () => {
  const m = buildMonthlyMessage('Eylül', 3.04, null, { aylikPct: 2.05, yillikPct: 30.2 });
  assertEquals(m.title, '▲ Eylül: piyasadan %3,0 · enflasyon %2,05');
  assertStringIncludes(m.body, 'Reel getirin');
});

Deno.test('akışlı ay + TÜFE: sayısız getiri, ulusal oran var', () => {
  const m = buildMonthlyMessage('Eylül', null, null, { aylikPct: 2.05, yillikPct: 30.2 });
  assertEquals(m.title, 'Eylül özetin hazır · enflasyon %2,05');
  assertStringIncludes(m.body, 'Yıllık enflasyon %30,2');
  assertEquals(/₺|TL\b/.test(m.title + m.body), false);
});
