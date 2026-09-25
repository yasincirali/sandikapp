// Kripto yardımcıları — saf fonksiyonlar, ağ yok.
//
//   deno test supabase/tests/kripto_test.ts
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import {
  binanceGet,
  fiyatlariHesapla,
  gunSembolParcalari,
  istanbulGunu,
  katalogKur,
  kriptoKodu,
  kriptoMu,
  mumlariCek,
  mumlariCoz,
  SAYFA_MUM,
  seriAnahtari,
  seriBaslangici,
  seriIstegiCoz,
  seriTtlMs,
  tlSerisi,
} from '../functions/_shared/kripto.ts';

Deno.test('sembol: KRIPTO: öneki çözülür, biçim dışı reddedilir', () => {
  assertEquals(kriptoKodu('KRIPTO:BTC'), 'BTC');
  assertEquals(kriptoKodu(' kripto:eth '), 'ETH');
  assertEquals(kriptoKodu('KRIPTO:1INCH'), '1INCH');
  assertEquals(kriptoKodu('BTC-USD'), null);
  assertEquals(kriptoKodu('KRIPTO:'), null);
  assertEquals(kriptoKodu("KRIPTO:BTC'; drop"), null);
  assert(kriptoMu('KRIPTO:BTC'));
  assert(!kriptoMu('TEFAS:AAK'));
});

Deno.test('istanbulGunu: UTC 21:00 İstanbul\'da ertesi gündür', () => {
  assertEquals(istanbulGunu(new Date('2026-09-25T20:59:00Z')), '2026-09-25');
  assertEquals(istanbulGunu(new Date('2026-09-25T21:00:00Z')), '2026-09-26');
});

Deno.test('katalog: TRY paritesi öncelikli, USDT yalnızca hacimde ilk N', () => {
  const binance = [
    { symbol: 'BTCTRY', baseAsset: 'BTC', quoteAsset: 'TRY', status: 'TRADING' },
    { symbol: 'BTCUSDT', baseAsset: 'BTC', quoteAsset: 'USDT', status: 'TRADING' },
    { symbol: 'SOLUSDT', baseAsset: 'SOL', quoteAsset: 'USDT', status: 'TRADING' },
    { symbol: 'XYZUSDT', baseAsset: 'XYZ', quoteAsset: 'USDT', status: 'TRADING' },
    { symbol: 'OLDTRY', baseAsset: 'OLD', quoteAsset: 'TRY', status: 'BREAK' },
    { symbol: 'USDTTRY', baseAsset: 'USDT', quoteAsset: 'TRY', status: 'TRADING' },
  ];
  const hacim = [
    { symbol: 'BTCUSDT', quoteVolume: '9000000' },
    { symbol: 'SOLUSDT', quoteVolume: '500000' },
    { symbol: 'XYZUSDT', quoteVolume: '10' },
    { symbol: 'BTCTRY', quoteVolume: '99999999999' }, // TRY hacmi sırayı etkilemez
  ];
  const varliklar = [
    { assetCode: 'BTC', assetName: 'Bitcoin', logoUrl: 'https://bin.bnbstatic.com/btc.png' },
    { assetCode: 'USDT', assetName: 'TetherUS', logoUrl: 'http://insecure' },
    { assetCode: 'SOL', assetName: 'Solana', logoUrl: null },
  ];
  const k = katalogKur(binance, hacim, varliklar, 2);
  const byKod = new Map(k.map((r) => [r.kod, r]));

  assertEquals(byKod.get('BTC')?.parite, 'TRY');
  assertEquals(byKod.get('BTC')?.binance_sembol, 'BTCTRY');
  assertEquals(byKod.get('BTC')?.ad, 'Bitcoin');
  assertEquals(byKod.get('SOL')?.parite, 'USDT');
  assertEquals(byKod.get('USDT')?.binance_sembol, 'USDTTRY');
  // http logosu kabul edilmez.
  assertEquals(byKod.get('USDT')?.logo_url, null);
  // Hacimde ilk 2'de olmayan USDT paritesi ve işlem dışı TRY paritesi girmez.
  assert(!byKod.has('XYZ'));
  assert(!byKod.has('OLD'));
  // USDT başta, sonra hacim sırası.
  assertEquals(k.map((r) => r.kod), ['USDT', 'BTC', 'SOL']);
  assertEquals(byKod.get('BTC')?.hacim_sirasi, 1);
});

Deno.test('katalog: varlık listesi gelmezse ad/logo null, fiyat paritesi yine kurulur', () => {
  const k = katalogKur(
    [{ symbol: 'ETHTRY', baseAsset: 'ETH', quoteAsset: 'TRY', status: 'TRADING' }],
    [],
    [],
  );
  assertEquals(k.length, 1);
  assertEquals(k[0].ad, null);
  assertEquals(k[0].logo_url, null);
  assertEquals(k[0].parite, 'TRY');
});

const SIMDI = new Date('2026-09-25T12:00:00Z');
const KATALOG = [
  { kod: 'BTC', parite: 'TRY' as const, binance_sembol: 'BTCTRY' },
  { kod: 'SOL', parite: 'USDT' as const, binance_sembol: 'SOLUSDT' },
];

Deno.test('fiyat: TRY paritesi doğrudan, USDT paritesi aynı borsanın kuruyla', () => {
  const rows = fiyatlariHesapla(KATALOG, [
    { symbol: 'BTCTRY', openPrice: '3900000', lastPrice: '3950000' },
    { symbol: 'SOLUSDT', openPrice: '200', lastPrice: '210' },
    { symbol: 'USDTTRY', openPrice: '41.0', lastPrice: '41.5' },
  ], SIMDI);
  const btc = rows.find((r) => r.kod === 'BTC')!;
  const sol = rows.find((r) => r.kod === 'SOL')!;
  assertEquals(btc.fiyat_try, 3950000);
  assertEquals(btc.gun_acilis_try, 3900000);
  assertEquals(btc.kaynak, 'binance_try');
  assertAlmostEquals(btc.fiyat_usd!, 3950000 / 41.5);
  assertAlmostEquals(sol.fiyat_try, 210 * 41.5);
  // Açılış, açılış anının kuruyla çevrilir — bugünkü kurla DEĞİL.
  assertAlmostEquals(sol.gun_acilis_try!, 200 * 41.0);
  assertEquals(sol.kaynak, 'binance_usdt');
  assertEquals(sol.gun, '2026-09-25');
});

Deno.test('fiyat: kur yoksa USDT paritesi YAZILMAZ (uydurma sayı yok)', () => {
  const rows = fiyatlariHesapla(KATALOG, [
    { symbol: 'BTCTRY', openPrice: '3900000', lastPrice: '3950000' },
    { symbol: 'SOLUSDT', openPrice: '200', lastPrice: '210' },
  ], SIMDI);
  assertEquals(rows.map((r) => r.kod), ['BTC']);
  assertEquals(rows[0].fiyat_usd, null);
});

Deno.test('fiyat: sıfır/bozuk fiyat atlanır, açılış yoksa null', () => {
  const rows = fiyatlariHesapla(KATALOG, [
    { symbol: 'BTCTRY', openPrice: '0', lastPrice: '3950000' },
    { symbol: 'SOLUSDT', openPrice: '200', lastPrice: 'NaN' },
    { symbol: 'USDTTRY', openPrice: '41', lastPrice: '41.5' },
  ], SIMDI);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].gun_acilis_try, null);
});

Deno.test('tradingDay parçaları: USDTTRY dahil, tekrarsız, 100\'lük', () => {
  const kat = Array.from({ length: 150 }, (_, i) => ({ binance_sembol: `C${i}TRY` }));
  kat.push({ binance_sembol: 'C0TRY' });
  const p = gunSembolParcalari(kat);
  assertEquals(p.length, 2);
  assertEquals(p[0].length, 100);
  assertEquals(p[0][0], 'USDTTRY');
  assertEquals(p.flat().length, 151);
});

Deno.test('seri isteği: yalnızca bilinen aralık/dönem', () => {
  assertEquals(seriIstegiCoz({ kod: 'btc', aralik: '1h', donem: '1mo' }), {
    kod: 'BTC', aralik: '1h', donem: '1mo',
  });
  assertEquals(seriIstegiCoz({ kod: 'BTC', aralik: '2h', donem: '1mo' }), null);
  assertEquals(seriIstegiCoz({ kod: 'BTC', aralik: '1h', donem: '10y' }), null);
  assertEquals(seriIstegiCoz({ kod: '../x', aralik: '1h', donem: '1mo' }), null);
  assertEquals(seriIstegiCoz(null), null);
  assertEquals(seriAnahtari({ kod: 'BTC', aralik: '1h', donem: '1mo' }), 'BTC|1h|1mo');
});

Deno.test('seri: TTL bir bar, 60 sn – 1 saat arası', () => {
  assertEquals(seriTtlMs('1m'), 60_000);
  assertEquals(seriTtlMs('15m'), 15 * 60_000);
  assertEquals(seriTtlMs('1d'), 60 * 60_000);
  assertEquals(seriTtlMs('1wk'), 60 * 60_000);
});

Deno.test('seri: başlangıç Binance açılışından önce olamaz', () => {
  const simdi = Date.UTC(2026, 8, 25);
  assertEquals(seriBaslangici('1d', simdi), simdi - 86_400_000);
  assertEquals(seriBaslangici('max', simdi), Date.UTC(2017, 6, 1));
});

Deno.test('mumlar: bozuk satır atlanır; TL serisi eşleşmeyen kur noktasını düşürür', () => {
  const coin = mumlariCoz([
    [1000, '1', '1', '1', '10', '0'],
    [2000, '1', '1', '1', '0', '0'],
    [3000, '1', '1', '1', '12', '0'],
    'bozuk',
  ]);
  assertEquals(coin, [[1000, 10], [3000, 12]]);
  const kur = mumlariCoz([[1000, '', '', '', '40', ''], [2000, '', '', '', '41', '']]);
  // 3000'in kuru yok → nokta yok, en yakın kurla DOLDURULMAZ.
  assertEquals(tlSerisi(coin, kur), [[1000, 400]]);
});

function sahteFetch(yanitlar: ((url: string) => Response)[]): typeof fetch {
  let i = 0;
  return ((input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    const f = yanitlar[Math.min(i++, yanitlar.length - 1)];
    return Promise.resolve(f(url));
  }) as typeof fetch;
}

Deno.test('binanceGet: 429\'da ikinci tabana geçmez', async () => {
  const cagrilar: string[] = [];
  const f = ((u: string) => {
    cagrilar.push(u);
    return Promise.resolve(new Response('', { status: 429 }));
  }) as unknown as typeof fetch;
  assertEquals(await binanceGet('/api/v3/ping', {}, f), null);
  assertEquals(cagrilar.length, 1);
});

Deno.test('binanceGet: 451\'de ikinci tabanı dener', async () => {
  const f = sahteFetch([
    () => new Response('', { status: 451 }),
    () => new Response('{"ok":1}', { status: 200 }),
  ]);
  assertEquals(await binanceGet('/api/v3/ping', {}, f), { ok: 1 });
});

Deno.test('mumlariCek: dolu sayfadan sonra devam eder, eksik sayfada durur', async () => {
  const dakika = 60_000;
  const tamSayfa = Array.from({ length: SAYFA_MUM }, (_, i) => [i * dakika, '', '', '', '1', '']);
  const yarim = [[SAYFA_MUM * dakika, '', '', '', '2', '']];
  const istenen: string[] = [];
  const f = sahteFetch([
    (u) => { istenen.push(u); return Response.json(tamSayfa); },
    (u) => { istenen.push(u); return Response.json(yarim); },
  ]);
  const seri = await mumlariCek('BTCTRY', '1m', 0, SAYFA_MUM * dakika * 2, f);
  assertEquals(seri?.length, SAYFA_MUM + 1);
  assertEquals(istenen.length, 2);
  assert(istenen[1].includes(`startTime=${SAYFA_MUM * dakika}`));
});

Deno.test('mumlariCek: ilk sayfada sağlayıcı yanıtsızsa null (boş seriyle karışmaz)', async () => {
  const f = sahteFetch([() => new Response('', { status: 500 })]);
  assertEquals(await mumlariCek('BTCTRY', '1h', 0, 1_000_000, f), null);
});
