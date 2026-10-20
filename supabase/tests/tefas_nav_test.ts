// TEFAS NAV gözlemi — saf yardımcıların testleri.
//
// `Deno.serve` gövdesi ağ ve veritabanı istediği için test edilmiyor;
// yardımcılar `_shared/tefas_nav.ts`'de bu yüzden ayrı.
//
// ## Bu dosyanın kovaladığı üç şey
// 1. **Tarih biçimi.** TEFAS `tarih` alanı ISO, Türk biçimi ya da epoch
//    gelebiliyor; yanlış ayrıştırma gözlemi YANLIŞ GÜNE yazar ve istemci
//    basamağı hiç çizmez (NAV günü çizilen günle uyuşmaz).
// 2. **Gün sınırı.** Epoch damgası TR gece yarısı = 21:00Z; UTC'ye göre gün
//    bir gün geri kayar. `trGun` Europe/Istanbul'a göre gün verir.
// 3. **Yeniden sorma kuralı.** Bugün tarihli NAV'ı görülmüş kod o gün bir
//    daha sorulmamalı (maliyet), görülmemiş olan sorulmalı; tekrar görülen
//    aynı tarih YENİ gözlem sayılmamalı (ilk görülme anı korunur).
//
// Çalıştır:
//   deno test --allow-all supabase/tests/tefas_nav_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  fonKodlari,
  gozlemYeniMi,
  oncekiKontrol,
  sonNavSatiri,
  sorulacakKodlar,
  tefasTarihToIso,
  trGun,
  fonGunlukDegisimi,
} from '../functions/_shared/tefas_nav.ts';

// ── tefasTarihToIso ─────────────────────────────────────────────────────────

Deno.test('ISO damga (saatli/saatsiz) güne indirgenir', () => {
  assertEquals(tefasTarihToIso('2026-09-10T00:00:00'), '2026-09-10');
  assertEquals(tefasTarihToIso('2026-09-10'), '2026-09-10');
});

Deno.test('Türk biçimi GG.AA.YYYY ve GG/AA/YYYY çevrilir', () => {
  assertEquals(tefasTarihToIso('10.09.2026'), '2026-09-10');
  assertEquals(tefasTarihToIso('1/9/2026'), '2026-09-01');
});

Deno.test('epoch ms TR gününe göre çevrilir (21:00Z = ertesi gün 00:00 TR)', () => {
  const ms = Date.UTC(2026, 8, 9, 21, 0, 0); // 2026-09-09T21:00Z = TR 10 Eylül 00:00
  assertEquals(tefasTarihToIso(ms), '2026-09-10');
  assertEquals(tefasTarihToIso(String(ms)), '2026-09-10');
});

Deno.test('tanınmayan biçim null — tahmin yok', () => {
  assertEquals(tefasTarihToIso('Eylül 10'), null);
  assertEquals(tefasTarihToIso(''), null);
  assertEquals(tefasTarihToIso(null), null);
});

// ── trGun ───────────────────────────────────────────────────────────────────

Deno.test('trGun gece yarısı sınırında Istanbul gününü verir', () => {
  assertEquals(trGun(new Date(Date.UTC(2026, 8, 14, 20, 59))), '2026-09-14');
  assertEquals(trGun(new Date(Date.UTC(2026, 8, 14, 21, 0))), '2026-09-15');
});

// ── sonNavSatiri ────────────────────────────────────────────────────────────

Deno.test('en yeni geçerli satır seçilir; sıraya güvenilmez', () => {
  const rows = [
    { tarih: '2026-09-10T00:00:00', fiyat: '10.5' },
    { tarih: '2026-09-08T00:00:00', fiyat: '10.1' },
    { tarih: '2026-09-09T00:00:00', fiyat: '10.3' },
  ];
  assertEquals(sonNavSatiri(rows), { tarih: '2026-09-10', fiyat: 10.5 });
});

Deno.test('sıfır/boş fiyatlı en yeni satır atlanır, bir öncekine düşülür', () => {
  const rows = [
    { tarih: '2026-09-09', fiyat: 10.3 },
    { tarih: '2026-09-10', fiyat: 0 },
    { tarih: '2026-09-11', fiyat: null },
  ];
  assertEquals(sonNavSatiri(rows), { tarih: '2026-09-09', fiyat: 10.3 });
});

Deno.test('birimPayDegeri ve virgüllü ondalık da fiyat sayılır', () => {
  assertEquals(
    sonNavSatiri([{ tarih: '2026-09-10', birimPayDegeri: '1,2345' }]),
    { tarih: '2026-09-10', fiyat: 1.2345 },
  );
});

Deno.test('liste değilse ya da boşsa null', () => {
  assertEquals(sonNavSatiri(null), null);
  assertEquals(sonNavSatiri([]), null);
  assertEquals(sonNavSatiri('x'), null);
});

// ── fonKodlari ──────────────────────────────────────────────────────────────

Deno.test('TEFAS: öneki soyulur, tekilleşir, sıralanır, bozuk kod atılır', () => {
  assertEquals(
    fonKodlari(['TEFAS:aft', 'TEFAS:AFT', 'TEFAS:TTE', 'THYAO.IS', 'TEFAS:', 'TEFAS:TOO-LONG', '']),
    ['AFT', 'TTE'],
  );
});

// ── sorulacakKodlar ─────────────────────────────────────────────────────────

Deno.test('bugün görülmüş kod sorulmaz; kalan üst sınırla kesilir', () => {
  const kodlar = ['AFT', 'GAF', 'TTE', 'YAY'];
  assertEquals(sorulacakKodlar(kodlar, new Set(['GAF'])), ['AFT', 'TTE', 'YAY']);
  assertEquals(sorulacakKodlar(kodlar, new Set(), 2), ['AFT', 'GAF']);
  assertEquals(sorulacakKodlar(kodlar, new Set(kodlar)), []);
});

// ── gozlemYeniMi ────────────────────────────────────────────────────────────

Deno.test('daha yeni tarih yeni gözlem; eşit ya da eski değil', () => {
  const satir = { tarih: '2026-09-10', fiyat: 1 };
  assertEquals(gozlemYeniMi(satir, undefined), true);
  assertEquals(gozlemYeniMi(satir, '2026-09-09'), true);
  assertEquals(gozlemYeniMi(satir, '2026-09-10'), false);
  assertEquals(gozlemYeniMi(satir, '2026-09-11'), false);
});

// ── oncekiKontrol ───────────────────────────────────────────────────────────

Deno.test('önceki tur 45 dk içindeyse aralık alt ucu, değilse null', () => {
  const now = new Date(Date.UTC(2026, 8, 14, 7, 0));
  const yakin = new Date(now.getTime() - 30 * 60 * 1000);
  const uzak = new Date(now.getTime() - 3 * 60 * 60 * 1000);
  assertEquals(oncekiKontrol(yakin, now), yakin);
  assertEquals(oncekiKontrol(uzak, now), null);
  assertEquals(oncekiKontrol(null, now), null);
  // Saat geri alınmış/bozuk: gelecekte kalan tur da güvenilmez.
  assertEquals(oncekiKontrol(new Date(now.getTime() + 60_000), now), null);
});

// ── Takip listesi fon hareketi (2026-10-17) ──────────────────────────────
Deno.test('fonGunlukDegisimi: son iki NAV tarihi, sıraya güvenmeden', () => {
  const pct = fonGunlukDegisimi([
    { tarih: '2026-10-16', fiyat: 2 },
    { tarih: '2026-10-15', fiyat: 1.9 },
    { tarih: '2026-10-14', fiyat: 1.5 },
  ], '2026-10-16');
  assertEquals(Math.round(pct! * 1000) / 1000, 5.263);
});

Deno.test('fonGunlukDegisimi: bugün tarihli NAV yoksa null (tatil / yayımlanmadı)', () => {
  assertEquals(fonGunlukDegisimi([
    { tarih: '2026-10-15', fiyat: 2 },
    { tarih: '2026-10-14', fiyat: 1.9 },
  ], '2026-10-16'), null);
});

Deno.test('fonGunlukDegisimi: tek NAV, bozuk fiyat ya da liste değilse null', () => {
  assertEquals(fonGunlukDegisimi([{ tarih: '2026-10-16', fiyat: 2 }], '2026-10-16'), null);
  assertEquals(fonGunlukDegisimi([
    { tarih: '2026-10-16', fiyat: 2 },
    { tarih: '2026-10-15', fiyat: 0 },
  ], '2026-10-16'), null);
  assertEquals(fonGunlukDegisimi(null, '2026-10-16'), null);
});

Deno.test('fonGunlukDegisimi: mükerrer gün tek sayılır; Türk biçimi ve virgül', () => {
  const pct = fonGunlukDegisimi([
    { tarih: '16.10.2026', fiyat: '1,1' },
    { tarih: '16.10.2026', fiyat: '1,1' },
    { tarih: '15.10.2026', fiyat: '1,0' },
  ], '2026-10-16');
  assertEquals(Math.round(pct! * 10) / 10, 10);
});
