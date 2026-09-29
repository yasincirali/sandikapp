// Sabah brifingi — saf yardımcıların testleri.
//
// Bu üç fonksiyon test edilebilir olsun diye export edildi; `Deno.serve`
// gövdesi ağ ve veritabanı istediği için ayrıca test edilmiyor.
//
// Neden bu testler var: brifing GÜNDE BİR kez, kullanıcının bildirim
// bütçesinden harcayarak gider (haftalık tavan 5, sinyaller dahil). Yanlış
// bir yüzde ya da çift gönderim, hiç göndermemekten daha maliyetlidir —
// kullanıcı sayıyı uygulamadakiyle karşılaştırır ve güvenini kaybeder.
//
// Çalıştır:
//   deno test supabase/tests/daily_brief_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  briefAdayiSec,
  briefVerisi,
  buildBriefMessage,
  buildPartnerMessage,
  collapseTokens,
  lastChangePct,
} from '../functions/daily-brief/index.ts';

// ── lastChangePct ───────────────────────────────────────────────────────────

Deno.test('son iki kapanıştan yüzde değişim', () => {
  assertEquals(lastChangePct([100, 110]), 10);
  assertEquals(lastChangePct([100, 90]), -10);
});

Deno.test('yalnızca SON iki nokta sayılır, serinin başı değil', () => {
  // Uzun seri: 6 aylık veri gelir ama brifing günlük hareketi anlatır.
  assertEquals(lastChangePct([10, 50, 200, 100, 101]), 1);
});

Deno.test('yetersiz veri null döner — uydurma yüzde üretilmez', () => {
  assertEquals(lastChangePct([]), null);
  assertEquals(lastChangePct([42]), null);
});

Deno.test('sıfır önceki kapanış null döner (sonsuza bölünme yok)', () => {
  assertEquals(lastChangePct([0, 5]), null);
});

Deno.test('bozuk sayı null döner', () => {
  assertEquals(lastChangePct([Number.NaN, 5]), null);
  assertEquals(lastChangePct([5, Number.POSITIVE_INFINITY]), null);
});

// ── buildBriefMessage ───────────────────────────────────────────────────────

Deno.test('yükseliş: yön oku başlıkta en solda', () => {
  const m = buildBriefMessage('ASELS', 4.23, 0);
  assertEquals(m.title, '▲ ASELS son kapanışta %4,2 yükseldi');
});

Deno.test('düşüş: işaret gövdeye değil yöne çevrilir', () => {
  const m = buildBriefMessage('THYAO', -2.51, 0);
  // Yüzde MUTLAK değerdir; "%-2,5 düştü" çift olumsuzlama olurdu.
  assertEquals(m.title, '▼ THYAO son kapanışta %2,5 düştü');
});

Deno.test('ondalık ayırıcı Türkçe virgüldür', () => {
  const m = buildBriefMessage('KCHOL', 1.85, 0);
  assertEquals(m.title.includes('%1,9'), true, m.title);
  assertEquals(m.title.includes('.'), false, 'nokta kullanılmamalı');
});

Deno.test('SPK ibaresi her mesajda bulunur', () => {
  for (const pct of [5.5, -5.5, 1.5]) {
    const m = buildBriefMessage('X', pct, 3);
    assertEquals(
      m.body.includes('Yatırım tavsiyesi değildir.'),
      true,
      `eksik ibare: ${m.body}`,
    );
  }
});

Deno.test('mesaj EYLEM önermez — yalnızca durum bildirir', () => {
  // RETENTION_STRATEJISI.md §9: "durum bildir, eylem önerme".
  const m = buildBriefMessage('ASELS', 6.0, 2);
  const metin = `${m.title} ${m.body}`.toLowerCase();
  for (const yasak of [' al ', ' sat ', 'alın', 'satın', 'öneri', 'tavsiye ederiz']) {
    assertEquals(metin.includes(yasak), false, `yasaklı ifade: ${yasak}`);
  }
});

Deno.test('başka hareketli hisse yokken ek cümle kurulmaz', () => {
  const m = buildBriefMessage('ASELS', 3.0, 0);
  assertEquals(m.body.includes('daha'), false, m.body);
});

Deno.test('eşiği geçen başka hisse varsa NE olduğu açıkça söylenir (#16)', () => {
  // Eski metin "Portföyündeki diğer 4 hisse daha var." ne demek istediği
  // belli olmayan bir cümleydi (emülatör testi #16, 2026-09-29).
  const m = buildBriefMessage('ASELS', 3.0, 4);
  assertEquals(m.body.includes('Portföyündeki 4 hisse daha hareketli.'), true, m.body);
  assertEquals(m.body.includes('daha var'), false, m.body);
});

// ── briefAdayiSec ───────────────────────────────────────────────────────────

Deno.test('en çok hareket eden hisse (mutlak değer) seçilir', () => {
  const s = briefAdayiSec([
    { label: 'A', sembol: 'A.IS', changePct: 2 },
    { label: 'B', sembol: 'B.IS', changePct: -5.8 },
    { label: 'C', sembol: 'C.IS', changePct: 3 },
  ], 1.5)!;
  assertEquals(s.en.sembol, 'B.IS');
  assertEquals(s.digerHareketli, 2);
});

Deno.test('diğer sayısı yalnız EŞİĞİ geçenleri sayar', () => {
  const s = briefAdayiSec([
    { label: 'A', sembol: 'A.IS', changePct: 5.8 },
    { label: 'B', sembol: 'B.IS', changePct: 0.4 },
    { label: 'C', sembol: 'C.IS', changePct: -1.49 },
    { label: 'D', sembol: 'D.IS', changePct: 1.5 },
  ], 1.5)!;
  assertEquals(s.en.sembol, 'A.IS');
  assertEquals(s.digerHareketli, 1);
});

Deno.test('aynı hissenin iki lot\'u iki hisse sayılmaz', () => {
  const s = briefAdayiSec([
    { label: 'A', sembol: 'A.IS', changePct: 5.8 },
    { label: 'A', sembol: 'A.IS', changePct: 5.8 },
    { label: 'B', sembol: 'B.IS', changePct: 3 },
    { label: 'B', sembol: 'B.IS', changePct: 3 },
  ], 1.5)!;
  assertEquals(s.digerHareketli, 1);
});

Deno.test('boş girdi → null (uydurma konu yok)', () => {
  assertEquals(briefAdayiSec([], 1.5), null);
});

// ── briefVerisi ─────────────────────────────────────────────────────────────
//
// Push ve çan kaydı AYNI veriyi taşır; istemci iki yolda da aynı hedefe
// gider: hisse mesajı → o varlığın ekranı, ortak mesajı → Özet (#16).

Deno.test('hisse mesajı ticker taşır', () => {
  assertEquals(briefVerisi('2026-09-29', 'mover', ' ARDYZ.IS '), {
    type: 'daily_brief',
    sent_on: '2026-09-29',
    variant: 'mover',
    ticker: 'ARDYZ.IS',
  });
});

Deno.test('ortak mesajı ticker taşımaz (NE eklendiği söylenmez)', () => {
  const d = briefVerisi('2026-09-29', 'partner', 'ARDYZ.IS');
  assertEquals('ticker' in d, false);
  assertEquals(d.variant, 'partner');
});

Deno.test('FCM data yalnız string taşır', () => {
  for (const v of Object.values(briefVerisi('2026-09-29', 'mover', 'X.IS'))) {
    assertEquals(typeof v, 'string');
  }
});

// ── collapseTokens ──────────────────────────────────────────────────────────

Deno.test('aynı cihazın üç tokenı → tek gönderim, en tazesi kazanır', () => {
  const out = collapseTokens([
    { token: 'eski1', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'eski2', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-05-01T00:00:00Z' },
    { token: 'guncel', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out[0].token, 'guncel');
});

Deno.test('iki ayrı cihaz ikisi de bildirim alır', () => {
  const out = collapseTokens([
    { token: 'tel', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'tablet', user_id: 'u1', device_id: 'dev-b', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 2);
});

Deno.test('device_id yoksa platform ile gruplanır (eski istemciler)', () => {
  const out = collapseTokens([
    { token: 'eski', user_id: 'u1', device_id: null, platform: 'ios', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'yeni', user_id: 'u1', device_id: null, platform: 'ios', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out[0].token, 'yeni');
});

Deno.test('farklı kullanıcılar birbirini elemez', () => {
  const out = collapseTokens([
    { token: 'a', user_id: 'u1', device_id: null, platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'b', user_id: 'u2', device_id: null, platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 2);
});

// ── buildPartnerMessage ─────────────────────────────────────────────────────
//
// Ortak hareketi brifingin SÖZÜNÜ alır (ayrı push değil — bildirim bütçesi
// günde tek proaktif mesaja izin veriyor, bkz. RETENTION_STRATEJISI.md §7).

Deno.test('tek ekleme: sayı yazılmaz', () => {
  assertEquals(
    buildPartnerMessage('Ayşe', 1).title,
    'Ayşe portföyüne ekleme yaptı',
  );
});

Deno.test('çok ekleme: sayı yazılır', () => {
  assertEquals(
    buildPartnerMessage('Ayşe', 3).title,
    'Ayşe portföyüne 3 ekleme yaptı',
  );
});

Deno.test('ad boşsa nötr ifadeye düşer', () => {
  assertEquals(
    buildPartnerMessage('', 1).title,
    'Ortağın portföyüne ekleme yaptı',
  );
  assertEquals(
    buildPartnerMessage('   ', 2).title,
    'Ortağın portföyüne 2 ekleme yaptı',
  );
});

Deno.test('NE eklendiği söylenmez — kilit ekranı mahremiyeti', () => {
  // Varlık adı bildirimde geçseydi omzunun üstünden bakan biri ortağın ne
  // aldığını görürdü. Uygulama içinde görünen bir bilgi, kilit ekranında
  // görünmek zorunda değil.
  const m = buildPartnerMessage('Ayşe', 2);
  const s = `${m.title} ${m.body}`.toLowerCase();
  for (const yasak of ['altın', 'hisse', 'dolar', 'asels', 'gram', '₺']) {
    assertEquals(s.includes(yasak), false, `sızıntı: ${yasak}`);
  }
});

Deno.test('tutar ya da miktar sızmaz', () => {
  const m = buildPartnerMessage('Ayşe', 2);
  assertEquals(/\d+[.,]\d/.test(`${m.title}${m.body}`), false);
});
