// Yurt içi kotasyon kaydı — saf satır üretimi (0101).
//
//   deno test supabase/tests/yurt_ici_kotasyon_test.ts
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import {
  tekrarDene,
  YURT_ICI_DENEME_BEKLEMELERI_MS,
  YURT_ICI_DENEME_ZAMAN_ASIMI_MS,
  YURT_ICI_SEMBOLLER,
  yurtIciKotasyonlariCek,
  yurtIciSatirlari,
} from '../functions/_shared/live_prices.ts';

const simdi = new Date('2026-10-03T09:37:42Z');

Deno.test('kova 5 dakikaya aşağı yuvarlanır (istemci slotuyla aynı)', () => {
  const r = yurtIciSatirlari({ USD: { Buying: 41.5, Change: 0.1 } }, simdi);
  assertEquals(r.length, 1);
  assertEquals(r[0].ts, '2026-10-03T09:35:00.000Z');
});

Deno.test('fiyat alanı uygulamayla aynı: Buying önce, Selling değil', () => {
  const r = yurtIciSatirlari(
    { YIA: { Buying: 5400, Selling: 5450, Change: -0.72 } },
    simdi,
  );
  assertEquals(r, [{
    sembol: 'ALTIN_GRAM',
    ts: '2026-10-03T09:35:00.000Z',
    fiyat: 5400,
    degisim_pct: -0.72,
  }]);
});

Deno.test('fiyatı okunamayan sembol satır üretmez (uydurma nokta yok)', () => {
  const r = yurtIciSatirlari(
    { USD: { Buying: 0 }, EUR: {}, GBP: { Buying: 'abc' } },
    simdi,
  );
  assertEquals(r, []);
});

Deno.test('liste tüm altın ayarlarını ve üç TL dövizini kapsar', () => {
  for (const s of ['ALTIN_GRAM', 'ALTIN_CEYREK', 'ALTIN_GRAM24', 'USDTRY=X', 'EURTRY=X', 'GBPTRY=X']) {
    assertEquals(YURT_ICI_SEMBOLLER.includes(s), true, s);
  }
});

Deno.test('kaynak bir kez düşerse aynı turda yeniden denenir', async () => {
  let n = 0;
  const beklenen: number[] = [];
  const r = await tekrarDene(
    () => (++n < 3 ? Promise.reject(new Error('yok')) : Promise.resolve('ok')),
    [1, 2],
    (ms) => { beklenen.push(ms); return Promise.resolve(); },
  );
  assertEquals(r, 'ok');
  assertEquals(n, 3);
  assertEquals(beklenen, [1, 2]);
});

Deno.test('denemeler biterse son hata atılır (sahte nokta yazılmaz)', async () => {
  let n = 0;
  await assertRejects(
    () => tekrarDene(() => { n++; return Promise.reject(new Error('yok')); },
      [1, 2], () => Promise.resolve()),
    Error,
    'yok',
  );
  assertEquals(n, 3);
});

Deno.test('deneme bütçesi pg_net 30 sn zaman aşımının altında kalır', () => {
  const toplam = YURT_ICI_DENEME_ZAMAN_ASIMI_MS *
      (YURT_ICI_DENEME_BEKLEMELERI_MS.length + 1) +
    YURT_ICI_DENEME_BEKLEMELERI_MS.reduce((a, b) => a + b, 0);
  assertEquals(toplam < 30_000, true);
});

// ── Uçtan uca: gerçek `yurtIciKotasyonlariCek`, sahte truncgil ─────────────
// `fetch` saplanır; her senaryo kaynağın gerçekte görülen bir arızasıdır.

type Yanit = () => Promise<Response>;
const tamGovde = JSON.stringify({
  USD: { Buying: 41.5, Change: 0.1 },
  YIA: { Buying: 5400, Change: -0.7 },
});
const ok: Yanit = () => Promise.resolve(new Response(tamGovde));
const http = (s: number): Yanit => () =>
  Promise.resolve(new Response('<html>hata</html>', { status: s }));
const agHatasi: Yanit = () => Promise.reject(new TypeError('connection reset'));
const zamanAsimi: Yanit = () =>
  Promise.reject(new DOMException('signal timed out', 'TimeoutError'));

async function senaryo(yanitlar: Yanit[]) {
  const asil = globalThis.fetch;
  let n = 0;
  const beklemeler: number[] = [];
  globalThis.fetch = () => yanitlar[n++]();
  try {
    const sonuc = await yurtIciKotasyonlariCek(
      simdi,
      YURT_ICI_DENEME_BEKLEMELERI_MS,
      (ms) => {
        beklemeler.push(ms);
        return Promise.resolve();
      },
    );
    return { sonuc, istek: n, beklemeler };
  } finally {
    globalThis.fetch = asil;
  }
}

Deno.test('kaynak sağlam: tek istek, bekleme yok', async () => {
  const r = await senaryo([ok]);
  assertEquals(r.istek, 1);
  assertEquals(r.beklemeler, []);
  assertEquals(r.sonuc.map((s) => s.sembol).sort(), ['ALTIN_GRAM', 'USDTRY=X']);
});

for (
  const [ad, ariza] of [
    ['ağ hatası', agHatasi],
    ['zaman aşımı', zamanAsimi],
    ['HTTP 502', http(502)],
    ['HTTP 429', http(429)],
    ['200 ama HTML sayfası', () => Promise.resolve(new Response('<html/>'))],
    ['200 ama boş gövde', () => Promise.resolve(new Response(''))],
    ['200 ama fiyatsız JSON', () => Promise.resolve(new Response('{}'))],
  ] as [string, Yanit][]
) {
  Deno.test(`${ad} bir kez → ikinci denemede yazılır`, async () => {
    const r = await senaryo([ariza, ok]);
    assertEquals(r.istek, 2);
    assertEquals(r.beklemeler, [1_500]);
    assertEquals(r.sonuc.length, 2);
  });
}

Deno.test('iki arıza üst üste → üçüncü denemede yazılır', async () => {
  const r = await senaryo([zamanAsimi, http(503), ok]);
  assertEquals(r.istek, 3);
  assertEquals(r.beklemeler, [1_500, 3_000]);
  assertEquals(r.sonuc.length, 2);
});

Deno.test('üç deneme de düşerse atar, dördüncü istek atılmaz', async () => {
  const asil = globalThis.fetch;
  let n = 0;
  globalThis.fetch = () => {
    n++;
    return agHatasi();
  };
  try {
    await assertRejects(() =>
      yurtIciKotasyonlariCek(simdi, [1, 2], () => Promise.resolve())
    );
    assertEquals(n, 3);
  } finally {
    globalThis.fetch = asil;
  }
});

Deno.test('kesik gövde: kurtarılan fiyat yazılır, yeniden denenmez', async () => {
  const kesik = '{"USD":{"Buying":41.5,"Change":0.1},"YIA":{"Buy';
  const r = await senaryo([() => Promise.resolve(new Response(kesik))]);
  assertEquals(r.istek, 1);
  assertEquals(r.sonuc.map((s) => s.sembol), ['USDTRY=X']);
});
