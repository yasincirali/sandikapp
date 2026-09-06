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
  buildBriefMessage,
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

Deno.test('tek hisse varken "diğer" cümlesi kurulmaz', () => {
  const m = buildBriefMessage('ASELS', 3.0, 0);
  assertEquals(m.body.includes('diğer'), false, m.body);
});

Deno.test('birden çok hisse varken kalan sayısı verilir', () => {
  const m = buildBriefMessage('ASELS', 3.0, 4);
  assertEquals(m.body.includes('diğer 4 hisse'), true, m.body);
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
