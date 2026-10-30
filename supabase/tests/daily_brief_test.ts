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
  briefKartAltYazisi,
  briefSembolu,
  briefTuru,
  briefVerisi,
  buildBriefMessage,
  fonNavGuncelMi,
  oncekiIsGunu,
  buildPartnerMessage,
  collapseTokens,
  ortakLotuGorur,
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

// Ortak portföy paylaşımı (0135): gizli portföye eklenen lot "ortağın N
// varlık ekledi" sayımına girmez. RLS eşi `ortak_portfoyu_gorur`.
Deno.test('ortakLotuGorur: satır yoksa ya da tümü ise her lot sayılır', () => {
  assertEquals(ortakLotuGorur(undefined, null), true);
  assertEquals(ortakLotuGorur(undefined, 'p1'), true);
  const tumu = { tumu: true, ana: false, portfoyIdler: [] };
  assertEquals(ortakLotuGorur(tumu, 'p1'), true);
});

Deno.test('ortakLotuGorur: seçili modda yalnız Ana ve seçilenler', () => {
  const p = { tumu: false, ana: true, portfoyIdler: ['p1'] };
  assertEquals(ortakLotuGorur(p, null), true);
  assertEquals(ortakLotuGorur(p, 'p1'), true);
  assertEquals(ortakLotuGorur(p, 'p2'), false);
  const anasiz = { tumu: false, ana: false, portfoyIdler: [] };
  assertEquals(ortakLotuGorur(anasiz, null), false);
});

// ── v2: altın, döviz, fon (Ar-Ge 2026-10-30 #1) ────────────────────────────

Deno.test('briefSembolu: altın ayarı sub_category\'den, öbürleri ticker\'dan', () => {
  assertEquals(briefSembolu('XAU', 'ALTIN_GRAM'), 'ALTIN_GRAM');
  assertEquals(briefSembolu(' USDTRY=X ', null), 'USDTRY=X');
  assertEquals(briefSembolu('TEFAS:AFT', 'hisse_senedi'), 'TEFAS:AFT');
});

Deno.test('briefTuru: kapsam widget beyaz listesiyle aynı', () => {
  assertEquals(briefTuru('hisse', 'ASELS.IS'), 'hisse');
  assertEquals(briefTuru('altin', 'ALTIN_GRAM'), 'yurt_ici');
  assertEquals(briefTuru('doviz', 'USDTRY=X'), 'yurt_ici');
  assertEquals(briefTuru('fon', 'TEFAS:AFT'), 'fon');
  // BES lotu da TEFAS: taşır ama fon değildir; kapsam dışı.
  assertEquals(briefTuru('bes', 'TEFAS:AH5'), null);
  // Listede olmayan döviz, kripto, emtia: aday olmaz (uydurma yok).
  assertEquals(briefTuru('doviz', 'CHFTRY=X'), null);
  assertEquals(briefTuru('kripto', 'KRIPTO:BTC'), null);
  assertEquals(briefTuru('emtia', 'GUMUS_GRAM'), null);
});

Deno.test('yalnız hisse tutana metin birebir eskisi', () => {
  const m = buildBriefMessage('ASELS', 3.0, 2);
  assertEquals(m.title, '▲ ASELS son kapanışta %3,0 yükseldi');
  assertEquals(
    m.body,
    'Portföyünde en çok hareket eden hisse. Portföyündeki 2 hisse daha hareketli. ' +
      'Yatırım tavsiyesi değildir.',
  );
});

Deno.test('altın/döviz "bugün", fon "son fiyatında" der', () => {
  assertEquals(
    buildBriefMessage('22 Ayar Gram Altın', 1.42, 0, 'yurt_ici', 'varlık').title,
    '▲ 22 Ayar Gram Altın bugün %1,4 yükseldi',
  );
  assertEquals(
    buildBriefMessage('AFT', -2.04, 0, 'fon', 'varlık').title,
    '▼ AFT son fiyatında %2,0 düştü',
  );
});

Deno.test('karışık portföyde gövde "varlık" der, altını hisse diye anlatmaz', () => {
  const m = buildBriefMessage('Dolar', 1.6, 1, 'yurt_ici', 'varlık');
  assertEquals(m.body.includes('hisse'), false, m.body);
  assertEquals(m.body.includes('Portföyündeki 1 varlık daha hareketli.'), true, m.body);
  assertEquals(m.body.endsWith('Yatırım tavsiyesi değildir.'), true, m.body);
});

Deno.test('kart alt yazısı başlıktaki zamanla aynı', () => {
  assertEquals(briefKartAltYazisi('hisse'), 'Son kapanış · en hareketli');
  assertEquals(briefKartAltYazisi('yurt_ici'), 'Bugün · en hareketli');
  assertEquals(briefKartAltYazisi('fon'), 'Son fon fiyatı · en hareketli');
});

Deno.test('briefAdayiSec: türler karışınca yalnizHisse false', () => {
  const s = briefAdayiSec([
    { label: 'A', sembol: 'A.IS', changePct: 0.5 },
    { label: 'Gram', sembol: 'ALTIN_GRAM', changePct: 1.8, tur: 'yurt_ici' },
  ], 1.5)!;
  assertEquals(s.en.sembol, 'ALTIN_GRAM');
  assertEquals(s.yalnizHisse, false);
  const h = briefAdayiSec([{ label: 'A', sembol: 'A.IS', changePct: 2 }], 1.5)!;
  assertEquals(h.yalnizHisse, true);
});

Deno.test('oncekiIsGunu: hafta sonunu ve resmî tatili atlar', () => {
  // Pazartesi 2026-11-02 09:45 TR → cuma 2026-10-30.
  assertEquals(oncekiIsGunu(new Date('2026-11-02T06:45:00Z')), '2026-10-30');
  // Cuma 2026-10-30 09:45 TR → 29 Ekim tatil, 28 Ekim (yarım gün işlem var).
  assertEquals(oncekiIsGunu(new Date('2026-10-30T06:45:00Z')), '2026-10-28');
  // Salı → pazartesi.
  assertEquals(oncekiIsGunu(new Date('2026-11-03T06:45:00Z')), '2026-11-02');
});

Deno.test('fonNavGuncelMi: bugünün ya da önceki iş gününün NAV\'ı; eskisi yinelenmez', () => {
  const sali = new Date('2026-11-03T06:45:00Z');
  assertEquals(fonNavGuncelMi('2026-11-02', sali), true);
  assertEquals(fonNavGuncelMi('2026-11-03', sali), true);
  // Pazartesi NAV'ı gelmediyse cumanın değişimi salı sabahı yeniden anlatılmaz.
  assertEquals(fonNavGuncelMi('2026-10-30', sali), false);
  // Pazartesi sabahı cumanın NAV'ı güncel sayılır.
  assertEquals(fonNavGuncelMi('2026-10-30', new Date('2026-11-02T06:45:00Z')), true);
});

Deno.test('altın brifingi push verisi varlığı bulacak sembolü taşır', () => {
  assertEquals(briefVerisi('2026-10-30', 'mover', 'ALTIN_GRAM').ticker, 'ALTIN_GRAM');
  assertEquals(briefVerisi('2026-10-30', 'mover', 'TEFAS:AFT').ticker, 'TEFAS:AFT');
});
