// 0169 — yüzde alarmı ("gram altın bugün %2 düşerse haber ver").
//
// Kilitlenenler:
//   1) Kapsam: altın/TL döviz/kripto; fon ve BIST yok (widget kapsamından).
//   2) Tetikleme: yön + eşik, sınır dahil; bilinmeyen yön susar.
//   3) Günde bir kez: bugünün damgası olan alarm değerlendirilmez; damga
//      koşullu UPDATE (çakışan tur push göndermez).
//   4) Uydurma yok: yüzdesiz, bayat ya da dünkü satır kotasyon vermez;
//      hafta sonu altın/döviz değerlendirilmez.
//   5) Fiyat alarmı turu bozulmadı: yüzde turu ondan önce ve try içinde.
//
//   deno test --allow-all supabase/tests/yuzde_alarmi_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  bugunCaldi,
  bugunDegerlendirilir,
  esikMetni,
  sonSatirlar,
  tlMetni,
  yuzdeAlarmKaynagi,
  yuzdeAlarmKarti,
  yuzdeAlarmMesaji,
  yuzdeAlarmTuru,
  yuzdeDamgala,
  yuzdeKotasyonu,
  yuzdeTetiklendiMi,
} from '../functions/_shared/yuzde_alarmi.ts';

// Salı 2026-10-27 10:00 TR (07:00Z).
const simdi = Date.parse('2026-10-27T07:00:00Z');

Deno.test('kapsam: altın, TL döviz, kripto; fon/BIST/emtia yok', () => {
  assertEquals(yuzdeAlarmKaynagi('ALTIN_GRAM'), 'yurt_ici');
  assertEquals(yuzdeAlarmKaynagi('USDTRY=X'), 'yurt_ici');
  assertEquals(yuzdeAlarmKaynagi('KRIPTO:BTC'), 'kripto');
  for (const s of ['TEFAS:AFT', 'THYAO.IS', 'GC=F', 'XU100.IS', '']) {
    assertEquals(yuzdeAlarmKaynagi(s), null, s);
  }
  assertEquals(yuzdeAlarmTuru('ALTIN_CEYREK'), 'altin');
  assertEquals(yuzdeAlarmTuru('EURTRY=X'), 'doviz');
  assertEquals(yuzdeAlarmTuru('KRIPTO:ETH'), 'kripto');
  assertEquals(yuzdeAlarmTuru('TEFAS:AFT'), null);
});

Deno.test('tetikleme: yön ve eşik, sınır dahil', () => {
  assertEquals(yuzdeTetiklendiMi(-2, 2, 'dusus'), true);
  assertEquals(yuzdeTetiklendiMi(-1.99, 2, 'dusus'), false);
  assertEquals(yuzdeTetiklendiMi(2.5, 2, 'dusus'), false, 'yükseliş düşüş alarmını çalmaz');
  assertEquals(yuzdeTetiklendiMi(3, 3, 'yukselis'), true);
  assertEquals(yuzdeTetiklendiMi(-3, 3, 'yukselis'), false);
  assertEquals(yuzdeTetiklendiMi(-1.2, 1, 'ikisi'), true);
  assertEquals(yuzdeTetiklendiMi(1.2, 1, 'ikisi'), true);
  assertEquals(yuzdeTetiklendiMi(0.9, 1, 'ikisi'), false);
  assertEquals(yuzdeTetiklendiMi(-5, 2, 'below'), false, 'bilinmeyen yön susar');
  assertEquals(yuzdeTetiklendiMi(NaN, 2, 'ikisi'), false);
  assertEquals(yuzdeTetiklendiMi(-5, 0, 'dusus'), false);
});

Deno.test('günde bir kez: bugünün damgası', () => {
  assertEquals(bugunCaldi('2026-10-27', '2026-10-27'), true);
  assertEquals(bugunCaldi('2026-10-26', '2026-10-27'), false, 'ertesi gün yeniden kurulur');
  assertEquals(bugunCaldi(null, '2026-10-27'), false);
});

Deno.test('hafta sonu altın/döviz değerlendirilmez, kripto değerlendirilir', () => {
  const cumartesi = new Date('2026-10-31T07:00:00Z');
  const pazarGeceTr = new Date('2026-11-01T20:59:00Z'); // TR pazar 23:59
  const pazartesiTr = new Date('2026-11-01T21:01:00Z'); // TR pazartesi 00:01
  assertEquals(bugunDegerlendirilir('yurt_ici', cumartesi), false);
  assertEquals(bugunDegerlendirilir('yurt_ici', pazarGeceTr), false);
  assertEquals(bugunDegerlendirilir('yurt_ici', pazartesiTr), true);
  assertEquals(bugunDegerlendirilir('kripto', cumartesi), true);
  assertEquals(bugunDegerlendirilir('yurt_ici', new Date(simdi)), true);
});

Deno.test('kotasyon: yurt içi taze satır; yüzdesiz/bayat/dünkü satır yok', () => {
  const taze = { ts: '2026-10-27T06:55:00Z', fiyat: '4212.37', degisim_pct: '-2.13' };
  assertEquals(yuzdeKotasyonu('yurt_ici', taze, simdi), {
    fiyat: 4212.37, degisim: -2.13, zaman: Date.parse(taze.ts),
  });
  assertEquals(yuzdeKotasyonu('yurt_ici', { ...taze, degisim_pct: null }, simdi), null);
  assertEquals(
    yuzdeKotasyonu('yurt_ici', { ...taze, ts: '2026-10-27T06:40:00Z' }, simdi),
    null,
    '20 dk eski satır alarm için bayat',
  );
  // TR 00:05'te, TR dün 23:58 satırı: 7 dk taze ama başka gün.
  const gece = Date.parse('2026-10-26T21:05:00Z');
  assertEquals(
    yuzdeKotasyonu('yurt_ici', { ...taze, ts: '2026-10-26T20:58:00Z' }, gece),
    null,
  );
});

Deno.test('kotasyon: kripto günün açılışına göre; açılışsız ya da bayat yok', () => {
  const satir = { fiyat_try: 98, gun_acilis_try: 100, guncellendi: '2026-10-27T06:58:00Z' };
  const k = yuzdeKotasyonu('kripto', satir, simdi)!;
  assertEquals(k.fiyat, 98);
  assert(Math.abs(k.degisim - -2) < 1e-9);
  assertEquals(yuzdeKotasyonu('kripto', { ...satir, gun_acilis_try: null }, simdi), null);
  assertEquals(
    yuzdeKotasyonu('kripto', { ...satir, guncellendi: '2026-10-27T06:45:00Z' }, simdi),
    null,
  );
});

Deno.test('son satır: sembol başına en yeni', () => {
  const m = sonSatirlar([
    { sembol: 'ALTIN_GRAM', ts: '2026-10-27T06:50:00Z', v: 1 },
    { sembol: 'ALTIN_GRAM', ts: '2026-10-27T06:55:00Z', v: 2 },
    { sembol: 'USDTRY=X', ts: '2026-10-27T06:45:00Z', v: 3 },
  ]);
  assertEquals(m.get('ALTIN_GRAM')?.v, 2);
  assertEquals(m.get('USDTRY=X')?.v, 3);
});

Deno.test('metin: Türkçe biçim, yön oku + fiil', () => {
  const d = yuzdeAlarmMesaji('Gram altın', -2.13, 4212.37, 2);
  assertEquals(d.title, '▼ Gram altın bugün %2,1 düştü · ₺4.212,37');
  assert(d.body.includes('günlük %2 alarmı'));
  assert(d.body.includes('Yatırım tavsiyesi değildir'));
  const y = yuzdeAlarmMesaji('Bitcoin', 3.04, 3456789.5, 3);
  assertEquals(y.title, '▲ Bitcoin bugün %3,0 yükseldi · ₺3.456.789,50');
  assertEquals(tlMetni(0.000123), '0,000123');
  assertEquals(esikMetni(2), '2');
  assertEquals(esikMetni(2.5), '2,5');
  const kart = yuzdeAlarmKarti('Gram altın', -2.13, 4212.37, 2)!;
  assertEquals(kart.y, 'd');
  assertEquals(kart.b, '%2,1');
  assert(kart.a.length <= 32);
});

/// Sahte admin: update zincirini kaydeder, sonucu verir.
function sahteAdmin(sonuc: { data: unknown; error: unknown }) {
  const cagri: Record<string, unknown> = {};
  const z: Record<string, unknown> = {
    update: (v: unknown) => { cagri.update = v; return z; },
    eq: (k: string, v: unknown) => { cagri.eq = [k, v]; return z; },
    or: (f: string) => { cagri.or = f; return z; },
    select: () => Promise.resolve(sonuc),
  };
  return { admin: { from: (t: string) => { cagri.tablo = t; return z; } }, cagri };
}

Deno.test('damga: koşullu; satır dönmezse push yok', async () => {
  const k = { fiyat: 4212.37, degisim: -2.13 };
  const a = sahteAdmin({ data: [{ id: 'y1' }], error: null });
  assertEquals(await yuzdeDamgala(a.admin, 'y1', '2026-10-27', k), 'damgalandi');
  assertEquals(a.cagri.tablo, 'yuzde_alarmlari');
  assertEquals(a.cagri.or, 'son_tetik_gunu.is.null,son_tetik_gunu.lt.2026-10-27');
  assertEquals((a.cagri.update as Record<string, unknown>).son_tetik_gunu, '2026-10-27');
  const b = sahteAdmin({ data: [], error: null });
  assertEquals(await yuzdeDamgala(b.admin, 'y1', '2026-10-27', k), 'zaten');
  const c = sahteAdmin({ data: null, error: { message: 'x' } });
  assertEquals(await yuzdeDamgala(c.admin, 'y1', '2026-10-27', k), 'hata');
});

const TUR = await Deno.readTextFile(
  new URL('../functions/_shared/yuzde_alarmi.ts', import.meta.url),
);
const FONKSIYON = await Deno.readTextFile(
  new URL('../functions/check-price-alerts/index.ts', import.meta.url),
);

Deno.test('tur: push yalnız damgayı atan turda, acil öncelik, alarm kanalı', () => {
  const i = TUR.indexOf('await yuzdeDamgala(admin, alarm.id');
  assert(i > 0, 'döngü yuzdeDamgala kullanmıyor');
  const sonrasi = TUR.slice(i, TUR.indexOf('sendFcmNotification({', i));
  assert(sonrasi.includes("if (damga === 'zaten') continue;"));
  assert(sonrasi.includes("if (damga === 'hata')"));
  const gonderim = TUR.slice(TUR.indexOf('sendFcmNotification({', i));
  assert(gonderim.includes("priority: 'high'"), 'fiyat alarmıyla aynı acil öncelik (#252)');
  assert(gonderim.includes('channelId: YUZDE_KANAL'));
  assert(TUR.includes("export const YUZDE_KANAL = 'alert_channel'"));
  assert(TUR.includes('sessizKullanicilar('), 'sessiz saatler uygulanmalı');
});

Deno.test('fonksiyon: yüzde turu fiyat alarmı sorgusundan önce ve hata yutulur', () => {
  const yuzde = FONKSIYON.indexOf('await yuzdeAlarmTuruKos(');
  const fiyat = FONKSIYON.indexOf(".from('price_alerts')\n      .select(");
  assert(yuzde > 0 && fiyat > yuzde, 'yüzde turu fiyat alarmından önce koşmalı');
  const blok = FONKSIYON.slice(FONKSIYON.lastIndexOf('try {', yuzde), fiyat);
  assert(blok.includes('} catch (e) {'), 'yüzde turu hatası fiyat alarmını düşürmemeli');
});

const MIGRATION = await Deno.readTextFile(
  new URL('../migrations/0169_yuzde_alarmlari.sql', import.meta.url),
);

Deno.test('migration: price_alerts yön kısıtına dokunulmaz, çan türü genişler', () => {
  assert(!/alter table public\.price_alerts/.test(MIGRATION), 'price_alerts değişmemeli');
  assert(MIGRATION.includes("'temettu',\n    'yuzde_alarm'"), 'eski türler korunmalı');
  assert(MIGRATION.includes('force row level security'));
  assert(!/grant [a-z, ]+ on table public\.yuzde_alarmlari to anon/.test(MIGRATION));
});
