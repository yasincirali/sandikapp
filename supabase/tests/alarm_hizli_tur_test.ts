// 0168 — altın/döviz/kripto alarmları 5 dakikada.
//
// Kilitlenen üç şey:
//   1) Tür filtresi: hızlı tur yalnız altın/döviz/kripto alarmını alır;
//      gövdesiz (eski) çağrı ve tanınmayan değer HER türü değerlendirir.
//   2) Tek atış: tetiklenmiş alarm sonraki 5 dakikalık turda yeniden çalmaz
//      (sorgu `triggered_at is null` + `enabled`; damga atamayan tur push
//      göndermez).
//   3) Migration: iki iş ayrık dakikalarda, aynı pencerede.
//
// Çalıştır:
//   deno test supabase/tests/alarm_hizli_tur_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  alarmiSondur,
  alarmTuru,
  turaGirenAlarmlar,
  turFiltresi,
} from '../functions/check-price-alerts/index.ts';

const HIZLI = ['altin', 'doviz', 'kripto'];

Deno.test('alarmTuru: kaynak ayrımıyla aynı', () => {
  assertEquals(alarmTuru('ALTIN_GRAM'), 'altin');
  assertEquals(alarmTuru('ALTIN_CEYREK'), 'altin');
  assertEquals(alarmTuru('USDTRY=X'), 'doviz');
  assertEquals(alarmTuru('EURTRY=X'), 'doviz');
  assertEquals(alarmTuru('KRIPTO:BTC'), 'kripto');
  assertEquals(alarmTuru('THYAO.IS'), 'diger');
  assertEquals(alarmTuru('GC=F'), 'diger', 'emtia 30 dakikada kalır');
});

Deno.test('turFiltresi: gövdesiz / bozuk değer = her tür (eski davranış)', () => {
  assertEquals(turFiltresi(undefined), null);
  assertEquals(turFiltresi(null), null);
  assertEquals(turFiltresi('altin'), null, 'dizi değil');
  assertEquals(turFiltresi([]), null, 'boş dizi hiçbir alarmı susturmaz');
  assertEquals(turFiltresi(['hisse', 42]), null, 'tanınmayan ad');
});

Deno.test('turFiltresi: hızlı türler tanınır, yabancı ad atılır', () => {
  assertEquals([...turFiltresi(HIZLI)!].sort(), [...HIZLI].sort());
  assertEquals([...turFiltresi(['altin', 'diger', 'hisse'])!], ['altin']);
});

const ALARMLAR = [
  { id: '1', symbol: 'ALTIN_GRAM' },
  { id: '2', symbol: 'USDTRY=X' },
  { id: '3', symbol: 'KRIPTO:BTC' },
  { id: '4', symbol: 'THYAO.IS' },
  { id: '5', symbol: 'TEFAS:AFT' },
];

Deno.test('hızlı tur BIST ve fonu değerlendirmez', () => {
  const giren = turaGirenAlarmlar(ALARMLAR, turFiltresi(HIZLI));
  assertEquals(giren.map((a) => a.id), ['1', '2', '3']);
});

Deno.test('eski (parametresiz) tur her alarmı değerlendirir', () => {
  assertEquals(turaGirenAlarmlar(ALARMLAR, turFiltresi(undefined)), ALARMLAR);
});

/// `price_alerts` tablosunun sahtesi: Supabase sorgu zincirini taklit eder,
/// `triggered_at is null` koşulunu gerçekten uygular.
function sahteDb(satirlar: Map<string, { triggered_at: string | null; enabled: boolean }>) {
  return {
    from(_t: string) {
      let yama: Record<string, unknown> = {};
      let id = '';
      let yalnizBos = false;
      const zincir = {
        update(p: Record<string, unknown>) { yama = p; return zincir; },
        eq(_k: string, v: string) { id = v; return zincir; },
        is(k: string, v: null) { if (k === 'triggered_at' && v === null) yalnizBos = true; return zincir; },
        select(_s: string) {
          const r = satirlar.get(id);
          if (!r || (yalnizBos && r.triggered_at !== null)) {
            return Promise.resolve({ data: [], error: null });
          }
          Object.assign(r, yama);
          return Promise.resolve({ data: [{ id }], error: null });
        },
      };
      return zincir;
    },
  };
}

Deno.test('tek atış: ikinci tur damgayı atamaz, push göndermez', async () => {
  const db = new Map([['a1', { triggered_at: null as string | null, enabled: true }]]);
  const admin = sahteDb(db);
  assertEquals(await alarmiSondur(admin, 'a1', new Date('2026-10-24T07:05:00Z')), 'sondu');
  assertEquals(db.get('a1')!.enabled, false);
  assertEquals(db.get('a1')!.triggered_at, '2026-10-24T07:05:00.000Z');
  // Çakışan / sonraki tur (5 dakika sonra) aynı alarmı yeniden söndüremez.
  assertEquals(await alarmiSondur(admin, 'a1', new Date('2026-10-24T07:10:00Z')), 'zaten');
  assertEquals(db.get('a1')!.triggered_at, '2026-10-24T07:05:00.000Z');
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
  assertEquals(await alarmiSondur(admin, 'a1'), 'hata');
});

const KAYNAK = await Deno.readTextFile(
  new URL('../functions/check-price-alerts/index.ts', import.meta.url),
);

Deno.test('aktif alarm sorgusu tetiklenmişi dışlar (yeniden kur gerekir)', () => {
  const sorgu = KAYNAK.slice(KAYNAK.indexOf(".select('id, user_id, symbol"));
  const blok = sorgu.slice(0, sorgu.indexOf(';'));
  assert(blok.includes(".eq('enabled', true)"), 'enabled filtresi yok');
  assert(blok.includes(".is('triggered_at', null)"), 'triggered_at filtresi yok');
});

Deno.test('push yalnız damgayı atan turda gider', () => {
  const i = KAYNAK.indexOf('await alarmiSondur(admin, alarm.id)');
  assert(i > 0, 'döngü alarmiSondur kullanmıyor');
  const sonrasi = KAYNAK.slice(i, KAYNAK.indexOf('sendFcmNotification({', i));
  assert(sonrasi.includes("if (damga === 'zaten') continue;"), "'zaten' turda push atlanmıyor");
  assert(sonrasi.includes("if (damga === 'hata')"), 'damga hatası ele alınmıyor');
});

Deno.test('tür filtresi fiyat çekiminden ÖNCE uygulanır', () => {
  const filtre = KAYNAK.indexOf('turaGirenAlarmlar((alertRows');
  const fiyat = KAYNAK.indexOf('await fetchLivePrices(');
  assert(filtre > 0 && fiyat > filtre, 'hızlı tur Yahoo/TEFAS çekmemeli');
});

const MIGRATION = await Deno.readTextFile(
  new URL('../migrations/0168_alarm_hizli_tur.sql', import.meta.url),
);

/// Basit cron alanı açıcı: '5-25/5,35-55/5' → dakika listesi.
function alan(ifade: string, enKucuk: number, enBuyuk: number): number[] {
  const out = new Set<number>();
  for (const parca of ifade.split(',')) {
    const [aralik, adimS] = parca.split('/');
    const adim = adimS ? Number(adimS) : 1;
    const [a, b] = aralik === '*'
      ? [enKucuk, enBuyuk]
      : aralik.includes('-')
      ? aralik.split('-').map(Number)
      : [Number(aralik), Number(aralik)];
    for (let i = a; i <= b; i += adim) out.add(i);
  }
  return [...out].sort((x, y) => x - y);
}

Deno.test('migration: hızlı iş yarım saatlerin arasında, aynı pencerede', () => {
  const m = MIGRATION.match(
    /cron\.schedule\('check-price-alerts-hizli', '([^']+)'/,
  );
  assert(m, 'hızlı iş kurulmuyor');
  const [dk, saat] = m[1].split(' ');
  const dakikalar = alan(dk, 0, 59);
  assertEquals(dakikalar, [5, 10, 15, 20, 25, 35, 40, 45, 50, 55]);
  assert(!dakikalar.includes(0) && !dakikalar.includes(30), 'eski işle çakışır');
  assertEquals(alan(saat, 0, 23), alan('5-18', 0, 23), 'pencere 0046 ile aynı');
  assert(MIGRATION.includes("time '18:30'"), 'TR 21:30 sonrası erken dönüş yok');
  assert(!/cron\.(alter_job|unschedule)\([^)]*'check-price-alerts'\)/.test(MIGRATION),
    'eski işe dokunulmamalı');
  for (const t of HIZLI) assert(MIGRATION.includes(`'${t}'`), `${t} gövdede yok`);
});
