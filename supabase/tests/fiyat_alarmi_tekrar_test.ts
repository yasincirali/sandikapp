// Fiyat alarmı "Her geçişte haber ver" (0171) — saf kararın ve damga
// yazımlarının testleri.
//
// Varlık sebebi: tekrarlı alarm yanlış karar verirse iki yönde de kişiyi
// kaybettirir — gereğinden sık çalarsa (tampon/tavan çalışmıyor) bildirim
// gürültüsü, hiç dönmezse "alarm bir kez çaldı, sonra susmuş" şikâyeti.
// Tek atış alarmın dalı burada değil (`alarm_hizli_tur_test`,
// `price_alert_test`); onun metni ve söndürmesi birebir korunur.
//
// Çalıştır:
//   deno test supabase/tests/fiyat_alarmi_tekrar_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  bugunkuSayi,
  GUNLUK_TAVAN,
  KRIPTO_TEKRAR_TAMPONU,
  tampondanGecti,
  tekrarKarari,
  tekrarTamponu,
  TEKRAR_TAMPONU,
  trGunuTekrar,
} from '../functions/_shared/fiyat_alarmi_tekrar.ts';
import {
  buildAlertMessage,
  nobeteDondur,
  tekrarliCalisiYaz,
} from '../functions/check-price-alerts/index.ts';

// TR 2026-10-29 12:00 (UTC+3).
const OGLE = new Date('2026-10-29T09:00:00Z');

const yukari = (o: Partial<Parameters<typeof tekrarKarari>[0]> = {}) => ({
  target_price: 42,
  direction: 'above',
  triggered_at: null,
  gunluk_tetik_sayisi: 0,
  gunluk_tetik_gunu: null,
  ...o,
});

// ── Nöbette ────────────────────────────────────────────────────────────────
Deno.test('nöbette: hedefe ulaşınca çalar (sınır dahil), sayaç 1', () => {
  assertEquals(tekrarKarari(yukari(), 42, OGLE), { tur: 'cal', sayi: 1, gun: '2026-10-29' });
  assertEquals(tekrarKarari(yukari(), 42.3, OGLE).tur, 'cal');
  assertEquals(tekrarKarari(yukari(), 41.99, OGLE).tur, 'bekle');
});

Deno.test('nöbette: aşağı alarm hedefin altında çalar', () => {
  const a = yukari({ direction: 'below', target_price: 4300 });
  assertEquals(tekrarKarari(a, 4300, OGLE).tur, 'cal');
  assertEquals(tekrarKarari(a, 4301, OGLE).tur, 'bekle');
});

Deno.test('geçersiz fiyat ya da hedef karar vermez (uydurma yok)', () => {
  assertEquals(tekrarKarari(yukari(), 0, OGLE).tur, 'bekle');
  assertEquals(tekrarKarari(yukari(), NaN, OGLE).tur, 'bekle');
  assertEquals(tekrarKarari(yukari({ triggered_at: 'x' }), -1, OGLE).tur, 'bekle');
  assertEquals(tekrarKarari(yukari({ target_price: 0 }), 5, OGLE).tur, 'bekle');
});

// ── Nöbete dönüş (tampon) ──────────────────────────────────────────────────
Deno.test('çalmış: %0,5 tampon geçilmeden nöbete dönmez', () => {
  const a = yukari({ triggered_at: '2026-10-29T08:00:00Z' });
  // 42 × 0,995 = 41,79
  assertEquals(tekrarKarari(a, 41.9, OGLE).tur, 'bekle', 'seviyenin etrafında oynama');
  assertEquals(tekrarKarari(a, 42.5, OGLE).tur, 'bekle', 'hâlâ hedefin ötesinde');
  assertEquals(tekrarKarari(a, 41.79, OGLE).tur, 'nobete_don', 'tampon sınırı dahil');
  assertEquals(tekrarKarari(a, 40, OGLE).tur, 'nobete_don');
});

Deno.test('çalmış aşağı alarm: hedefin %0,5 üstünde nöbete döner', () => {
  const a = yukari({ direction: 'below', target_price: 4000, triggered_at: 'x' });
  assertEquals(tekrarKarari(a, 4019, OGLE).tur, 'bekle');
  assertEquals(tekrarKarari(a, 4020, OGLE).tur, 'nobete_don');
  assertEquals(tampondanGecti(4020, 4000, 'below'), true);
  assertEquals(tampondanGecti(3990, 4000, 'below'), false);
});

Deno.test('çalmış alarm aynı tarafta yeniden ÇALMAZ (tek geçiş = tek bildirim)', () => {
  const a = yukari({ triggered_at: 'x', gunluk_tetik_sayisi: 1, gunluk_tetik_gunu: '2026-10-29' });
  for (const p of [42, 43, 50]) assert(tekrarKarari(a, p, OGLE).tur !== 'cal');
});

// ── Günlük tavan ───────────────────────────────────────────────────────────
Deno.test('günde en çok 3 çalış: 3. çalış izinli, 4. değil', () => {
  assertEquals(GUNLUK_TAVAN, 3);
  const iki = yukari({ gunluk_tetik_sayisi: 2, gunluk_tetik_gunu: '2026-10-29' });
  assertEquals(tekrarKarari(iki, 42, OGLE), { tur: 'cal', sayi: 3, gun: '2026-10-29' });
  const uc = yukari({ gunluk_tetik_sayisi: 3, gunluk_tetik_gunu: '2026-10-29' });
  assertEquals(tekrarKarari(uc, 42, OGLE).tur, 'tavan');
});

Deno.test('tavan dolunca o gün nöbete dönmez; ertesi gün döner', () => {
  const a = yukari({
    triggered_at: '2026-10-29T08:00:00Z',
    gunluk_tetik_sayisi: 3,
    gunluk_tetik_gunu: '2026-10-29',
  });
  assertEquals(tekrarKarari(a, 40, OGLE).tur, 'tavan');
  const yarin = new Date('2026-10-30T06:00:00Z');
  assertEquals(tekrarKarari(a, 40, yarin).tur, 'nobete_don');
});

Deno.test('dünkü sayaç bugün sıfırdan sayılır', () => {
  const a = yukari({ gunluk_tetik_sayisi: 3, gunluk_tetik_gunu: '2026-10-28' });
  assertEquals(tekrarKarari(a, 42, OGLE), { tur: 'cal', sayi: 1, gun: '2026-10-29' });
  assertEquals(bugunkuSayi(a, '2026-10-29'), 0);
  assertEquals(bugunkuSayi({ ...a, gunluk_tetik_gunu: '2026-10-29' }, '2026-10-29'), 3);
});

Deno.test('gün TR saatine göre: UTC 21:30 = TR ertesi gün 00:30', () => {
  assertEquals(trGunuTekrar(new Date('2026-10-29T21:30:00Z')), '2026-10-30');
  assertEquals(trGunuTekrar(new Date('2026-10-29T20:59:00Z')), '2026-10-29');
});

// ── Senaryo: seviyenin etrafında bir gün ───────────────────────────────────
Deno.test('senaryo: oynayan fiyat günde en çok 3 bildirim üretir', () => {
  type S = Parameters<typeof tekrarKarari>[0];
  let a: S = yukari();
  let calis = 0;
  // 5 dakikada bir: hedefin üstü / tamponun altı arasında gidip gelir.
  const fiyatlar = [42.1, 41.5, 42.2, 41.6, 42.3, 41.7, 42.4, 41.5, 42.5];
  for (const p of fiyatlar) {
    const k = tekrarKarari(a, p, OGLE);
    if (k.tur === 'cal') {
      calis += 1;
      a = { ...a, triggered_at: 'x', gunluk_tetik_sayisi: k.sayi, gunluk_tetik_gunu: k.gun };
    } else if (k.tur === 'nobete_don') {
      a = { ...a, triggered_at: null };
    }
  }
  assertEquals(calis, 3);
});

// ── Damga yazımları ────────────────────────────────────────────────────────
type Satir = Record<string, unknown> & { triggered_at: string | null; enabled: boolean };

/// Supabase zincirinin sahtesi: `eq`/`is` koşullarını gerçekten uygular.
function sahteDb(satirlar: Map<string, Satir>) {
  const yazilan: Record<string, unknown>[] = [];
  return {
    yazilan,
    from(_t: string) {
      let yama: Record<string, unknown> = {};
      const kosul: [string, unknown][] = [];
      const zincir = {
        update(p: Record<string, unknown>) { yama = p; return zincir; },
        eq(k: string, v: unknown) { kosul.push([k, v]); return zincir; },
        is(k: string, v: null) { kosul.push([k, v]); return zincir; },
        select(_s: string) {
          const id = kosul.find(([k]) => k === 'id')?.[1] as string;
          const r = satirlar.get(id);
          if (!r || kosul.some(([k, v]) => k !== 'id' && r[k] !== v)) {
            return Promise.resolve({ data: [], error: null });
          }
          Object.assign(r, yama);
          yazilan.push(yama);
          return Promise.resolve({ data: [{ id }], error: null });
        },
      };
      return zincir;
    },
  };
}

Deno.test('tekrarlı çalış alarmı SÖNDÜRMEZ, damga + sayaç yazar; ikinci tur yazamaz', async () => {
  const db = new Map<string, Satir>([['a1', { triggered_at: null, enabled: true }]]);
  const admin = sahteDb(db);
  const an = new Date('2026-10-29T09:05:00Z');
  const karar = { tur: 'cal' as const, sayi: 2, gun: '2026-10-29' };
  assertEquals(await tekrarliCalisiYaz(admin, 'a1', karar, an), 'caldi');
  const r = db.get('a1')!;
  assertEquals(r.enabled, true, 'eski build için açık kalmalı');
  assertEquals(r.triggered_at, '2026-10-29T09:05:00.000Z');
  assertEquals(r.son_tetik_at, '2026-10-29T09:05:00.000Z');
  assertEquals(r.gunluk_tetik_sayisi, 2);
  assertEquals(r.gunluk_tetik_gunu, '2026-10-29');
  assert(!('enabled' in admin.yazilan[0]), 'enabled yazılmamalı');
  assertEquals(await tekrarliCalisiYaz(admin, 'a1', karar, an), 'zaten');
});

Deno.test('nöbete dönüş triggered_at\'i temizler; son_tetik_at kalır', async () => {
  const db = new Map<string, Satir>([['a1', {
    triggered_at: 'T1', enabled: true, son_tetik_at: 'T1',
  }]]);
  const admin = sahteDb(db);
  assertEquals(await nobeteDondur(admin, 'a1', 'T1'), true);
  assertEquals(db.get('a1')!.triggered_at, null, 'eski build "bekleyen" görsün');
  assertEquals(db.get('a1')!.son_tetik_at, 'T1');
  assertEquals(db.get('a1')!.enabled, true);
});

Deno.test('nöbete dönüş: damga değiştiyse ya da alarm kapatıldıysa yazmaz', async () => {
  const db = new Map<string, Satir>([
    ['a1', { triggered_at: 'T2', enabled: true }],
    ['a2', { triggered_at: 'T1', enabled: false }],
  ]);
  const admin = sahteDb(db);
  assertEquals(await nobeteDondur(admin, 'a1', 'T1'), false);
  assertEquals(db.get('a1')!.triggered_at, 'T2');
  assertEquals(await nobeteDondur(admin, 'a2', 'T1'), false);
});

Deno.test('damga hatası push göndermez', async () => {
  const admin = {
    from: () => {
      const z = {
        update: () => z, eq: () => z, is: () => z,
        select: () => Promise.resolve({ data: null, error: { message: 'x' } }),
      };
      return z;
    },
  };
  assertEquals(
    await tekrarliCalisiYaz(admin, 'a1', { tur: 'cal', sayi: 1, gun: '2026-10-29' }),
    'hata',
  );
  assertEquals(await nobeteDondur(admin, 'a1', 'T'), false);
});

// ── Metin ──────────────────────────────────────────────────────────────────
Deno.test('tekrarlı alarm metni "kapatıldı" demez, yine haber vereceğini söyler', () => {
  const m = buildAlertMessage('Dolar', 42.1, 42, 'above', '₺', true);
  assert(!m.body.includes('kapatıldı'));
  assert(m.body.includes('yine haber vereceğiz'));
  assert(m.body.includes('Yatırım tavsiyesi değildir.'));
  // Varsayılan (tek atış) metin birebir.
  assertEquals(
    buildAlertMessage('Dolar', 42.1, 42, 'above', '₺').body,
    'Şu an ₺42,10. Tek seferlik alarmdı, kapatıldı. Yatırım tavsiyesi değildir.',
  );
});

// ── Ar-Ge 30 Eki #0: kripto tamponu ve günün son çalışı ────────────────────
Deno.test('kriptoda tampon %1, öbürlerinde %0,5', () => {
  assertEquals(tekrarTamponu('KRIPTO:BTC'), KRIPTO_TEKRAR_TAMPONU);
  assertEquals(tekrarTamponu('USDTRY=X'), TEKRAR_TAMPONU);
  assertEquals(tekrarTamponu('ALTIN_GRAM'), TEKRAR_TAMPONU);
  assertEquals(tekrarTamponu(undefined), TEKRAR_TAMPONU);
  // 100.000'de kurulan BTC 'above' alarmı: 99.400 (%0,6) yetmez, 99.000 döner.
  const a = yukari({ symbol: 'KRIPTO:BTC', target_price: 100000, triggered_at: 'x', gunluk_tetik_sayisi: 1, gunluk_tetik_gunu: '2026-10-29' });
  assertEquals(tekrarKarari(a, 99400, OGLE).tur, 'bekle');
  assertEquals(tekrarKarari(a, 99000, OGLE).tur, 'nobete_don');
  // Aynı oran dolarda yeter (%0,5 tampon).
  const d = yukari({ symbol: 'USDTRY=X', triggered_at: 'x' });
  assertEquals(tekrarKarari(d, 41.75, OGLE).tur, 'nobete_don');
});

Deno.test('günün son çalışı yarına kadar susacağını söyler', () => {
  const m = buildAlertMessage('Dolar', 42.1, 42, 'above', '₺', true, true);
  assert(m.body.includes(`Bugün ${GUNLUK_TAVAN}. kez çaldı; yarın yeniden nöbette.`), m.body);
  assert(!m.body.includes('yine haber vereceğiz'), m.body);
  assert(m.body.includes('Yatırım tavsiyesi değildir.'));
  // Tek atışta sonCalis yok sayılır.
  assert(buildAlertMessage('Dolar', 42.1, 42, 'above', '₺', false, true).body.includes('kapatıldı'));
});

Deno.test('kaynak: son çalış bayrağı tavana göre veriliyor', () => {
  assert(KAYNAK_ERKEN.includes('tekrarKarar.sayi >= GUNLUK_TAVAN'));
});

const KAYNAK_ERKEN = await Deno.readTextFile(
  new URL('../functions/check-price-alerts/index.ts', import.meta.url),
);

// ── Kaynak kilitleri ───────────────────────────────────────────────────────
const KAYNAK = await Deno.readTextFile(
  new URL('../functions/check-price-alerts/index.ts', import.meta.url),
);

Deno.test('tek atış dalı korunur: tekrarsız alarm alarmiSondur + isTriggered', () => {
  assert(KAYNAK.includes(': await alarmiSondur(admin, alarm.id);'));
  assert(KAYNAK.includes('return isTriggered(p, Number(a.target_price), a.direction);'));
  assert(KAYNAK.includes('if (a.tekrar === true) {'), 'yalnız tekrar=true yeni dala girer');
});

Deno.test('0171 kolonları yoksa eski kolonlarla yeniden sorulur', () => {
  assert(KAYNAK.includes('await aktifSorgu(ALARM_KOLONLARI)'));
  assert(KAYNAK.includes("const ALARM_KOLONLARI = 'id, user_id, symbol, label, target_price, direction';"));
});

const MIGRATION = await Deno.readTextFile(
  new URL('../migrations/0171_fiyat_alarmi_tekrar.sql', import.meta.url),
);

Deno.test('migration yalnız EKLER, varsayılan tek atış', () => {
  assert(MIGRATION.includes('add column if not exists tekrar boolean not null default false'));
  for (const k of ['son_tetik_at', 'gunluk_tetik_sayisi', 'gunluk_tetik_gunu']) {
    assert(MIGRATION.includes(`add column if not exists ${k}`), `${k} eksik`);
  }
  assert(!/drop column|rename column|alter column/i.test(MIGRATION), 'kırıcı değişiklik');
  assert(MIGRATION.includes('raise exception'), 'doğrulama bloğu yok');
});
