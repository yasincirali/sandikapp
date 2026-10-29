// 0170 — gösterge ve çizgi alarmı ("EMA50'yi keserse", "trend çizgime
// değerse"), yasin 2026-10-29.
//
// Kilitlenenler:
//   1) Kapsam: altın ve TL döviz YOK (canlı truncgil, seri Yahoo: farklı
//      ölçek); BIST, ABD, kripto, fon, emtia var.
//   2) EMA tam geçmişten, istemci `emaSeries` ile birebir (aynı altın
//      vektörler `test/seviye_alarmi_test.dart`'ta Dart'a karşı).
//   3) Bugünün yarım çubuğu atılır, canlı fiyat son nokta; bayat/canlısız
//      seri hesaba girmez.
//   4) Taraf değişimi: ilk tur yalnız yazar; yön uyarsa çalar; eşitlik
//      geçiş değildir.
//   5) Çizgi: doğrusal ara değer, parça bitince susar, ışın uzar.
//   6) Tur: ilk turda taraf yazılır, çalmaz; sonraki turda geçiş çalar;
//      fiyat alarmı turu bozulmadı (seviye turu önce ve try içinde).
//
//   deno test --allow-all supabase/tests/seviye_alarmi_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  bollingerSon,
  canliIleKapanislar,
  emaSon,
  gostergeAlarmKapsamindaMi,
  gostergeSeviyesi,
  onbellekTaze,
  smaSon,
} from '../functions/_shared/gosterge_alarmi.ts';
import { cizgiDegeri, SAAT_PAYI_MS } from '../functions/_shared/cizim_alarmi.ts';
import {
  cizimMesaji,
  gostergeMesaji,
  seviyeAlarmTuruKos,
  seviyeKarari,
  seviyeYaz,
  tarafi,
} from '../functions/_shared/seviye_alarmi.ts';

const yakin = (a: number | null, b: number, eps = 1e-9) =>
  a !== null && Math.abs(a - b) < eps;

Deno.test('kapsam: altın ve TL döviz yok; BIST/ABD/kripto/fon/emtia var', () => {
  for (const s of ['ALTIN_GRAM', 'ALTIN_CEYREK', 'USDTRY=X', 'EURTRY=X', 'GBPTRY=X', '',
    'EUROBOND:XS1234567890']) {
    assertEquals(gostergeAlarmKapsamindaMi(s), false, s);
  }
  for (const s of ['THYAO.IS', 'AAPL', 'KRIPTO:BTC', 'TEFAS:AFT', 'GC=F', 'GRAM:SI=F',
    'EURUSD=X', 'XU100.IS']) {
    assertEquals(gostergeAlarmKapsamindaMi(s), true, s);
  }
});

// İstemciyle ORTAK altın seri: 100 + 15·sin(iπ/23) + 0,05·i, 260 nokta.
// Aynı sayılar `test/seviye_alarmi_test.dart`'ta
// `TechnicalAnalysisService.emaSeries/smaSeries`'e karşı doğrulanır.
const ALTIN = Array.from({ length: 260 }, (_, i) => 100 + 15 * Math.sin(i * Math.PI / 23) + 0.05 * i);
const BEKLENEN = {
  ema20: 112.93387852363564,
  ema50: 113.36301012372883,
  ema200: 108.7112825901731,
  sma20: 117.42546631045802,
  bb_ust: 134.58200938142005,
  bb_alt: 100.26892323949599,
};

Deno.test('EMA/SMA/Bollinger: istemciyle aynı altın vektörler', () => {
  for (const [k, v] of Object.entries(BEKLENEN)) {
    assert(yakin(gostergeSeviyesi(k, ALTIN), v, 1e-9), `${k}: ${gostergeSeviyesi(k, ALTIN)}`);
  }
  assert(yakin(emaSon(ALTIN, 50), BEKLENEN.ema50));
  assert(yakin(smaSon(ALTIN, 20), BEKLENEN.sma20));
  const b = bollingerSon(ALTIN)!;
  assert(b.ust > b.orta && b.orta > b.alt);
});

Deno.test('EMA tam geçmişten: son periyot×3 kesmesi kullanılmaz', () => {
  // 400 noktalık yükseliş, sonra 300 nokta 100: tohum (ilk 200'ün
  // ortalaması) farklı yerde olunca son değer de farklı çıkar.
  const s = Array.from({ length: 700 }, (_, i) => (i < 400 ? 50 + 10 * Math.sin(i / 7) + (i % 13) : 100));
  const tam = emaSon(s, 200)!;
  const kesik = emaSon(s.slice(s.length - 600), 200)!;
  assert(Math.abs(tam - kesik) > 1e-6, 'tohum yeri sonucu değiştirmeli');
});

Deno.test('yetersiz veri: seviye yok (uydurma yok)', () => {
  assertEquals(gostergeSeviyesi('ema200', ALTIN.slice(0, 199)), null);
  assertEquals(gostergeSeviyesi('ema50', ALTIN.slice(0, 50)) !== null, true);
  assertEquals(gostergeSeviyesi('bilinmeyen', ALTIN), null);
});

const GUN = 24 * 60 * 60 * 1000;
// Perşembe 2026-10-29 14:00 TR (11:00Z).
const SIMDI = Date.parse('2026-10-29T11:00:00Z');

Deno.test('canlı ile kapanışlar: bugünün çubuğu atılır, canlı sona eklenir', () => {
  const nokta = (gunOnce: number, v: number): [number, number] =>
    [Date.parse('2026-10-29T07:00:00Z') - gunOnce * GUN, v];
  const seri = [nokta(3, 10), nokta(2, 11), nokta(1, 12), nokta(0, 99)];
  assertEquals(canliIleKapanislar(seri, 13, SIMDI), [10, 11, 12, 13]);
  assertEquals(canliIleKapanislar(seri, undefined, SIMDI), null, 'canlı yoksa karar yok');
  assertEquals(canliIleKapanislar(seri, 0, SIMDI), null);
  assertEquals(canliIleKapanislar([nokta(9, 10)], 13, SIMDI), null, 'bayat seri');
  assertEquals(canliIleKapanislar([], 13, SIMDI), null);
  // TR gece yarısı sınırı: 20:59Z dün 23:59 TR'dir, bugünün çubuğu sayılmaz.
  const gece: [number, number] = [Date.parse('2026-10-28T20:59:00Z'), 50];
  assertEquals(canliIleKapanislar([gece], 51, SIMDI), [50, 51]);
});

Deno.test('önbellek: 3 saat ve aynı TR günü', () => {
  assertEquals(onbellekTaze(SIMDI - 60 * 60_000, SIMDI), true);
  assertEquals(onbellekTaze(SIMDI - 4 * 60 * 60_000, SIMDI), false);
  // TR 00:30'da dün 23:00'te yazılmış önbellek: 1,5 saat ama gün döndü.
  const gece = Date.parse('2026-10-29T21:30:00Z');
  assertEquals(onbellekTaze(Date.parse('2026-10-29T20:00:00Z'), gece), false);
  assertEquals(onbellekTaze(NaN, SIMDI), false);
});

Deno.test('taraf değişimi: ilk tur yazar, yön uyarsa çalar', () => {
  assertEquals(tarafi(101, 100), 'ust');
  assertEquals(tarafi(99, 100), 'alt');
  assertEquals(tarafi(100, 100), null);

  assertEquals(seviyeKarari(null, 101, 100, 'yukari'), { tur: 'yaz', taraf: 'ust' },
    'ilk değerlendirme çalmaz');
  assertEquals(seviyeKarari('alt', 101, 100, 'yukari'), { tur: 'cal', taraf: 'ust' });
  assertEquals(seviyeKarari('ust', 101, 100, 'yukari'), { tur: 'yok' });
  assertEquals(seviyeKarari('ust', 99, 100, 'yukari'), { tur: 'yaz', taraf: 'alt' },
    'ters yöne geçiş yalnız yazılır');
  assertEquals(seviyeKarari('ust', 99, 100, 'asagi'), { tur: 'cal', taraf: 'alt' });
  assertEquals(seviyeKarari('ust', 99, 100, 'her_ikisi'), { tur: 'cal', taraf: 'alt' });
  assertEquals(seviyeKarari('alt', 101, 100, 'her_ikisi'), { tur: 'cal', taraf: 'ust' });
  assertEquals(seviyeKarari('alt', 100, 100, 'her_ikisi'), { tur: 'yok' }, 'eşitlik geçiş değil');
  assertEquals(seviyeKarari('alt', 101, 100, 'above'), { tur: 'yok' }, 'bilinmeyen yön susar');
  assertEquals(seviyeKarari('alt', NaN, 100, 'yukari'), { tur: 'yok' });
});

Deno.test('çizgi: doğrusal ara değer, parça biter, ışın uzar', () => {
  const t1 = SIMDI - GUN, t2 = SIMDI + GUN;
  const d = { t1, p1: 100, t2, p2: 120, uzanir: false };
  assert(yakin(cizgiDegeri(d, SIMDI), 110));
  assert(yakin(cizgiDegeri(d, t2), 120));
  assertEquals(cizgiDegeri(d, t2 + 1), null, 'parça bitti');
  assert(yakin(cizgiDegeri({ ...d, uzanir: true }, t2 + GUN), 130), 'ışın uzar');
  assertEquals(cizgiDegeri(d, t1 - SAAT_PAYI_MS - 1), null);
  assert(cizgiDegeri(d, t1 - 60_000) !== null, 'birkaç dakikalık saat farkı kabul');
  assertEquals(cizgiDegeri({ ...d, t2: t1 }, SIMDI), null, 'bozuk satır');
  assertEquals(cizgiDegeri({ t1, p1: 10, t2, p2: 1, uzanir: true }, t2 + 10 * GUN), null,
    'sıfırın altına inen ışın değerlendirilmez');
});

Deno.test('metin: dürüst ve simgeli', () => {
  const m = gostergeMesaji('THYAO', 'ema50', 'ust', 312.4, 309.8, '₺');
  assertEquals(m.title, "▲ THYAO EMA50'nin üstüne çıktı · ₺312,40");
  assertEquals(m.body,
    'EMA50 (günlük kapanışlarla) ₺309,80. Tek seferlik alarmdı, kapatıldı. ' +
      'Yatırım tavsiyesi değildir.');
  const a = gostergeMesaji('Apple', 'ema200', 'alt', 250, 251.5, '$');
  assertEquals(a.title, "▼ Apple EMA200'ün altına indi · $250,00");
  const b = gostergeMesaji('THYAO', 'bb_ust', 'ust', 1, 1, '₺');
  assert(b.body.startsWith('Bollinger üst bandı (20, 2σ; günlük kapanışlarla)'));
  const c = cizimMesaji('Bitcoin', 'alt', 3000000, 3010000, '₺');
  assertEquals(c.title, '▼ Bitcoin çizdiğin çizginin altına indi · ₺3.000.000,00');
  assert(c.body.includes('Çizginin şu anki değeri ₺3.010.000,00'));
  assert(c.body.includes('Yatırım tavsiyesi değildir'));
});

// ── Sahte veritabanı ────────────────────────────────────────────────────────

type Satir = Record<string, unknown>;

function sahteDb(tablolar: Record<string, Satir[]>) {
  const yazilar: Array<{ tablo: string; alanlar: Satir; id: unknown }> = [];
  const eklenen: Array<{ tablo: string; satir: Satir }> = [];
  function sorgu(tablo: string) {
    const filtre: Array<(r: Satir) => boolean> = [];
    let guncelle: Satir | null = null;
    const z: Record<string, unknown> = {
      select: () => z,
      update: (v: Satir) => { guncelle = v; return z; },
      insert: (r: Satir) => {
        eklenen.push({ tablo, satir: r });
        return Promise.resolve({ error: null });
      },
      upsert: () => Promise.resolve({ error: null }),
      delete: () => z,
      eq: (k: string, v: unknown) => { filtre.push((r) => r[k] === v); return z; },
      is: (k: string, v: unknown) => {
        filtre.push((r) => (r[k] ?? null) === v);
        return z;
      },
      in: (k: string, v: unknown[]) => { filtre.push((r) => v.includes(r[k])); return z; },
      then: (ok: (x: unknown) => unknown) => {
        const satirlar = (tablolar[tablo] ?? []).filter((r) => filtre.every((f) => f(r)));
        if (guncelle) {
          for (const r of satirlar) {
            Object.assign(r, guncelle);
            yazilar.push({ tablo, alanlar: guncelle, id: r.id });
          }
        }
        return Promise.resolve({ data: satirlar.map((r) => ({ ...r })), error: null }).then(ok);
      },
    };
    return z;
  }
  return {
    admin: {
      from: sorgu,
      rpc: () => Promise.resolve({ data: [], error: null }),
    },
    yazilar,
    eklenen,
  };
}

Deno.test('koşullu yazım: okunan taraf yerinde değilse yazmaz', async () => {
  const db = sahteDb({
    cizim_alarmlari: [{ id: 'c1', son_taraf: null, triggered_at: null }],
  });
  // deno-lint-ignore no-explicit-any
  const admin = db.admin as any;
  assertEquals(await seviyeYaz(admin, 'cizim_alarmlari', 'c1', 'alt', { son_taraf: 'ust' }),
    'zaten', 'istemci çizgiyi taşıdı, taraf sıfırlandı');
  assertEquals(await seviyeYaz(admin, 'cizim_alarmlari', 'c1', null, { son_taraf: 'ust' }),
    'yazildi');
});

Deno.test('tur: ilk tur yalnız taraf yazar, sonraki geçiş çalar', async () => {
  const kapanislar: Array<[number, number]> = ALTIN.map((v, i) =>
    [SIMDI - (ALTIN.length - i) * GUN, v]
  );
  const gosterge: Satir = {
    id: 'g1', user_id: 'u1', symbol: 'THYAO.IS', label: 'THYAO', gosterge: 'ema50',
    yon: 'yukari', son_taraf: null, enabled: true, triggered_at: null,
  };
  const cizim: Satir = {
    id: 'c1', user_id: 'u1', symbol: 'KRIPTO:BTC', label: 'Bitcoin',
    t1: SIMDI - GUN, p1: 100, t2: SIMDI + GUN, p2: 120, uzanir: true,
    yon: 'asagi', son_taraf: null, enabled: true, triggered_at: null,
  };
  const altin: Satir = {
    id: 'g2', user_id: 'u1', symbol: 'ALTIN_GRAM', label: 'Gram', gosterge: 'ema20',
    yon: 'her_ikisi', son_taraf: null, enabled: true, triggered_at: null,
  };
  const db = sahteDb({ gosterge_alarmlari: [gosterge, altin], cizim_alarmlari: [cizim] });
  let fiyat = new Map([['THYAO.IS', 100], ['KRIPTO:BTC', 115], ['ALTIN_GRAM', 4000]]);
  const kos = () =>
    // deno-lint-ignore no-explicit-any
    seviyeAlarmTuruKos(db.admin as any, {
      dryRun: false,
      turaGirer: () => true,
      fcm: null,
      simdi: new Date(SIMDI),
      fiyatlar: () => Promise.resolve(fiyat),
      seriler: (s) => Promise.resolve(new Map(s.map((x) => [x, kapanislar]))),
    });

  const ilk = await kos();
  assertEquals(ilk.sent, 0, 'ilk tur çalmaz');
  assertEquals(ilk.sides_written, 2);
  assertEquals(gosterge.son_taraf, 'alt', 'fiyat 100 < EMA50 ~113');
  assertEquals(cizim.son_taraf, 'ust', 'fiyat 115 > çizgi 110');
  assertEquals(altin.son_taraf, null, 'altın kapsam dışı: dokunulmaz');

  fiyat = new Map([['THYAO.IS', 130], ['KRIPTO:BTC', 105], ['ALTIN_GRAM', 4000]]);
  const ikinci = await kos();
  assertEquals(ikinci.triggered, 2, 'EMA50 yukarı kesildi, çizgi aşağı kesildi');
});

const FONKSIYON = await Deno.readTextFile(
  new URL('../functions/check-price-alerts/index.ts', import.meta.url),
);
const TUR = await Deno.readTextFile(
  new URL('../functions/_shared/seviye_alarmi.ts', import.meta.url),
);
const MIGRATION = await Deno.readTextFile(
  new URL('../migrations/0170_gosterge_cizim_alarmlari.sql', import.meta.url),
);

Deno.test('fonksiyon: seviye turu fiyat alarmından önce ve hata yutulur', () => {
  const seviye = FONKSIYON.indexOf('await seviyeAlarmTuruKos(');
  const fiyat = FONKSIYON.indexOf(".from('price_alerts')\n      .select(");
  assert(seviye > 0 && fiyat > seviye);
  const blok = FONKSIYON.slice(FONKSIYON.lastIndexOf('try {', seviye), fiyat);
  assert(blok.includes('} catch (e) {'));
});

Deno.test('tur: damga önce, push sonra; acil öncelik; sessiz saat', () => {
  const i = TUR.indexOf('enabled: false,');
  const j = TUR.indexOf('sendFcmNotification({');
  assert(i > 0 && j > i, 'damga push’tan önce');
  assert(TUR.slice(i, j).includes("if (damga === 'zaten') continue;"));
  assert(TUR.slice(j).includes("priority: 'high'"));
  assert(TUR.includes('sessizKullanicilar('));
});

Deno.test('migration: price_alerts değişmez, RLS + açık GRANT, premium yazma', () => {
  assert(!/alter table public\.price_alerts/.test(MIGRATION));
  for (const t of ['gosterge_alarmlari', 'cizim_alarmlari', 'gosterge_seri_onbellegi']) {
    assert(MIGRATION.includes(`alter table public.${t} enable row level security`), t);
    assert(MIGRATION.includes(`alter table public.${t} force row level security`), t);
    assert(!new RegExp(`grant [a-z, ]+ on table public\\.${t} to anon`).test(MIGRATION), t);
  }
  assert(!/grant [a-z, ]+ on table public\.gosterge_seri_onbellegi to authenticated/.test(MIGRATION));
  assert((MIGRATION.match(/public\.premium_icerik_gorebilir\(\)/g) ?? []).length >= 4);
  assert(MIGRATION.includes("'yuzde_alarm', 'gosterge_alarm', 'cizim_alarm'"));
  assert((MIGRATION.match(/set search_path = public, pg_temp/g) ?? []).length === 2);
});
