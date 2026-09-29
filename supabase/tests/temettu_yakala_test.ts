// Temettü yakala — saf parçaların ve 0086 migration'ının testleri.
//
// Bildirim geri alınamaz: yanlış kullanıcıya, yanlış lot'la ya da ikinci kez
// giden bir "temettü dağıttı" push'u, kullanıcının uygulamanın bütün
// sayılarına güvenini sarsar. Bu yüzden üç şey kilitlenir:
//   1) Yahoo olayı → öneri: geçersiz tutar/tarih ÖNERİ DOĞURMAZ (uydurma yok),
//   2) hak tarihinde lot: o gün alan almaz, o gün satan alır; silinen lot yok,
//   3) tekrar önleme: defterdeki olay ikinci kez gitmez, günlük tavan tutar.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/temettu_yakala_test.ts

import { assertEquals, assertMatch } from 'jsr:@std/assert@1';
import {
  defterAnahtari,
  GUNLUK_TAVAN,
  hakTarihindekiLot,
  lotYazisi,
  onerileriKur,
  PENCERE_GUN,
  temettuKayitliMi,
  temettuleriCek,
  temettuMesaji,
  temettuOlaylari,
  temettuVerisi,
  trGunu,
  tutarYazisi,
  yakalanacakSemboller,
} from '../functions/temettu-yakala/index.ts';
import type { PozisyonLot } from '../functions/_shared/positions.ts';

// ── Kurucular ───────────────────────────────────────────────────────────────

const satir = (o: Partial<PozisyonLot> & { id: string }): PozisyonLot => ({
  user_id: 'u1',
  type: 'hisse',
  ticker: 'THYAO.IS',
  name: 'Türk Hava Yolları',
  currency: 'TRY',
  quantity: 100,
  kind: 'buy',
  added_date: '2025-06-01T09:00:00Z',
  ref_asset_id: null,
  ...o,
});

/// Yahoo `chart` gövdesi — `events.dividends` anahtar/değer haritası.
function yahooGovdesi(olaylar: Array<{ gun: string; tutar: unknown }>) {
  const dividends: Record<string, unknown> = {};
  for (const o of olaylar) {
    // BIST hak kullanımı Yahoo'da seans açılışı civarı (06:30 UTC) damgalı.
    const sn = Date.parse(`${o.gun}T06:30:00Z`) / 1000;
    dividends[String(sn)] = { date: sn, amount: o.tutar };
  }
  return { chart: { result: [{ events: { dividends } }] } };
}

const SIMDI = Date.parse('2025-06-20T16:00:00Z'); // 19:00 TR

// ── 1) Yahoo olayı → öneri ─────────────────────────────────────────────────

Deno.test('trGunu: UTC gece yarısından önceki saat TR\'de ertesi gün', () => {
  assertEquals(trGunu(Date.parse('2025-06-15T21:30:00Z')), '2025-06-16');
  assertEquals(trGunu(Date.parse('2025-06-16T06:30:00Z')), '2025-06-16');
});

Deno.test('olaylar: pencere içindeki gerçekleşmiş temettü okunur', () => {
  const o = temettuOlaylari(yahooGovdesi([{ gun: '2025-06-16', tutar: 3.442 }]), SIMDI);
  assertEquals(o, [{ hakTarihi: '2025-06-16', tutarPay: 3.442 }]);
});

Deno.test('olaylar: pencere dışı (eski) olay atılır', () => {
  const o = temettuOlaylari(
    yahooGovdesi([
      { gun: '2025-04-01', tutar: 1 },
      { gun: '2025-06-16', tutar: 3.442 },
    ]),
    SIMDI,
  );
  assertEquals(o.map((x) => x.hakTarihi), ['2025-06-16']);
  assertEquals(PENCERE_GUN, 30);
});

Deno.test('olaylar: okunamayan / sıfır / negatif tutar ÖNERİ DOĞURMAZ', () => {
  // Uydurma sayı yasağı: "yaklaşık" bir tutarla bildirim gitmez.
  const o = temettuOlaylari(
    yahooGovdesi([
      { gun: '2025-06-10', tutar: 'abc' },
      { gun: '2025-06-11', tutar: 0 },
      { gun: '2025-06-12', tutar: -1 },
      { gun: '2025-06-13', tutar: null },
    ]),
    SIMDI,
  );
  assertEquals(o, []);
});

Deno.test('olaylar: gövde bozuk ya da temettüsüz → boş liste', () => {
  assertEquals(temettuOlaylari(null, SIMDI), []);
  assertEquals(temettuOlaylari({}, SIMDI), []);
  assertEquals(temettuOlaylari({ chart: { result: [{}] } }, SIMDI), []);
});

Deno.test('olaylar: tarihe göre sıralı', () => {
  const o = temettuOlaylari(
    yahooGovdesi([
      { gun: '2025-06-18', tutar: 2 },
      { gun: '2025-06-02', tutar: 1 },
    ]),
    SIMDI,
  );
  assertEquals(o.map((x) => x.hakTarihi), ['2025-06-02', '2025-06-18']);
});

Deno.test('temettuleriCek: sembol başına TEK istek, events=div, hata → boş', async () => {
  const cagrilar: string[] = [];
  const sahte = ((url: string) => {
    cagrilar.push(url);
    return Promise.resolve(
      new Response(JSON.stringify(yahooGovdesi([{ gun: '2025-06-16', tutar: 3.442 }]))),
    );
  }) as unknown as typeof fetch;
  const o = await temettuleriCek('THYAO.IS', SIMDI, sahte);
  assertEquals(cagrilar.length, 1);
  assertMatch(cagrilar[0], /THYAO\.IS\?.*events=div/);
  assertEquals(o.length, 1);

  const hatali = (() => Promise.resolve(new Response('x', { status: 500 }))) as unknown as typeof fetch;
  assertEquals(await temettuleriCek('THYAO.IS', SIMDI, hatali), []);
  const atan = (() => Promise.reject(new Error('ag'))) as unknown as typeof fetch;
  assertEquals(await temettuleriCek('THYAO.IS', SIMDI, atan), []);
});

// ── 2) Hak tarihinde lot ────────────────────────────────────────────────────

Deno.test('lot: hak tarihinden ÖNCE alınan lot sayılır', () => {
  assertEquals(hakTarihindekiLot([satir({ id: 'a' })], '2025-06-16'), 100);
});

Deno.test('lot: hak GÜNÜ ve sonrası alım hak kazandırmaz', () => {
  const s = [
    satir({ id: 'a', quantity: 100 }),
    satir({ id: 'b', quantity: 50, added_date: '2025-06-16T08:00:00Z' }),
    satir({ id: 'c', quantity: 25, added_date: '2025-06-18T08:00:00Z' }),
  ];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 100);
});

Deno.test('lot: hak günü satış hakkı düşürmez, öncesindeki satış düşürür', () => {
  const s = [
    satir({ id: 'a', quantity: 100 }),
    satir({ id: 's1', kind: 'sell', quantity: 30, added_date: '2025-06-10T08:00:00Z' }),
    satir({ id: 's2', kind: 'sell', quantity: 70, added_date: '2025-06-16T08:00:00Z' }),
  ];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 70);
});

Deno.test('lot: TR gece yarısı sınırı — 15 Haziran 23:30 TR alımı hak kazandırır', () => {
  // 2025-06-15T20:30Z = 23:30 TR → 15 Haziran; hak günü 16'sı.
  const s = [satir({ id: 'a', added_date: '2025-06-15T20:30:00Z' })];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 100);
  // 2025-06-15T21:30Z = 00:30 TR → 16 Haziran: hak yok.
  const s2 = [satir({ id: 'a', added_date: '2025-06-15T21:30:00Z' })];
  assertEquals(hakTarihindekiLot(s2, '2025-06-16'), 0);
});

Deno.test('lot: temettü satırı miktara GİRMEZ', () => {
  const s = [
    satir({ id: 'a', quantity: 100 }),
    satir({ id: 'd', kind: 'dividend', quantity: 999, added_date: '2025-05-01T08:00:00Z' }),
  ];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 100);
});

Deno.test('lot: tek lot mezar taşı o lot\'u düşürür, kardeşine dokunmaz', () => {
  const s = [
    satir({ id: 'a', quantity: 100 }),
    satir({ id: 'b', quantity: 40, added_date: '2025-06-02T08:00:00Z' }),
    satir({ id: 't', kind: 'delete_log', quantity: 0, ref_asset_id: 'b', added_date: '2025-06-25T08:00:00Z' }),
  ];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 100);
});

Deno.test('lot: pozisyon silme mezar taşından eski hareketler sayılmaz (sil → yeniden al)', () => {
  const s = [
    satir({ id: 'eski', quantity: 100, added_date: '2025-05-01T08:00:00Z' }),
    satir({ id: 't', kind: 'delete_log', quantity: 0, added_date: '2025-05-10T08:00:00Z' }),
    satir({ id: 'yeni', quantity: 20, added_date: '2025-06-01T08:00:00Z' }),
  ];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 20);
});

Deno.test('lot: tarihi okunamayan hareket hak tarihine bağlanamaz, atlanır', () => {
  const s = [satir({ id: 'a', added_date: null }), satir({ id: 'b', added_date: 'bozuk' })];
  assertEquals(hakTarihindekiLot(s, '2025-06-16'), 0);
});

// ── Kayıtlı mı ──────────────────────────────────────────────────────────────

Deno.test('kayıtlı: pencere içi temettü satırı olayı karşılar', () => {
  const d = (gun: string) =>
    satir({ id: gun, kind: 'dividend', quantity: 0, added_date: `${gun}T09:00:00Z` });
  assertEquals(temettuKayitliMi([d('2025-06-16')], '2025-06-16'), true);
  assertEquals(temettuKayitliMi([d('2025-06-10')], '2025-06-16'), true); // 6 gün önce
  assertEquals(temettuKayitliMi([d('2025-08-10')], '2025-06-16'), true); // taksit
  assertEquals(temettuKayitliMi([d('2025-05-01')], '2025-06-16'), false); // geçen olay
  assertEquals(temettuKayitliMi([satir({ id: 'a' })], '2025-06-16'), false);
});

// ── 3) Öneri kurma, tekrar önleme, tavan ────────────────────────────────────

const THYAO = new Map([['THYAO.IS', [{ hakTarihi: '2025-06-16', tutarPay: 3.442 }]]]);

Deno.test('öneri: açık BIST pozisyonu + pencere içi olay → tek öneri', () => {
  const o = onerileriKur({ satirlar: [satir({ id: 'a' })], olaylar: THYAO, gonderilmis: new Set() });
  assertEquals(o, [{
    user_id: 'u1',
    ticker: 'THYAO.IS',
    hak_tarihi: '2025-06-16',
    tutar_pay: 3.442,
    lot: 100,
  }]);
});

Deno.test('öneri: defterdeki olay İKİNCİ KEZ gitmez', () => {
  const o = onerileriKur({
    satirlar: [satir({ id: 'a' })],
    olaylar: THYAO,
    gonderilmis: new Set([defterAnahtari('u1', 'thyao.is', '2025-06-16')]),
  });
  assertEquals(o, []);
});

Deno.test('öneri: kullanıcı zaten kaydettiyse gitmez', () => {
  const o = onerileriKur({
    satirlar: [
      satir({ id: 'a' }),
      satir({ id: 'd', kind: 'dividend', quantity: 0, added_date: '2025-06-17T09:00:00Z' }),
    ],
    olaylar: THYAO,
    gonderilmis: new Set(),
  });
  assertEquals(o, []);
});

Deno.test('öneri: bugün kapalı pozisyon ÖNERİ ALMAZ (evren açık pozisyon)', () => {
  const o = onerileriKur({
    satirlar: [
      satir({ id: 'a' }),
      satir({ id: 's', kind: 'sell', quantity: 100, added_date: '2025-06-18T08:00:00Z' }),
    ],
    olaylar: THYAO,
    gonderilmis: new Set(),
  });
  assertEquals(o, []);
});

Deno.test('öneri: hak tarihinden sonra alan açık pozisyon öneri almaz', () => {
  const o = onerileriKur({
    satirlar: [satir({ id: 'a', added_date: '2025-06-17T08:00:00Z' })],
    olaylar: THYAO,
    gonderilmis: new Set(),
  });
  assertEquals(o, []);
});

Deno.test('öneri: .IS olmayan ya da USD kote hisse dışarıda', () => {
  const satirlar = [
    satir({ id: 'a', ticker: 'AAPL' }),
    satir({ id: 'b', currency: 'USD' }),
  ];
  assertEquals(yakalanacakSemboller(satirlar), []);
  const o = onerileriKur({
    satirlar,
    olaylar: new Map([...THYAO, ['AAPL', [{ hakTarihi: '2025-06-16', tutarPay: 1 }]]]),
    gonderilmis: new Set(),
  });
  assertEquals(o, []);
});

Deno.test('öneri: kullanıcılar birbirinin lot\'una karışmaz', () => {
  const o = onerileriKur({
    satirlar: [
      satir({ id: 'a', user_id: 'u1', quantity: 100 }),
      satir({ id: 'b', user_id: 'u2', quantity: 5 }),
      // u2'nin satışı u1'in alımından düşülmemeli.
      satir({ id: 's', user_id: 'u2', kind: 'sell', quantity: 5, added_date: '2025-06-18T08:00:00Z' }),
    ],
    olaylar: THYAO,
    gonderilmis: new Set(),
  });
  assertEquals(o.map((x) => [x.user_id, x.lot]), [['u1', 100]]);
});

Deno.test('semboller: tekil ve sıralı (Yahoo\'ya sembol başına bir istek)', () => {
  assertEquals(
    yakalanacakSemboller([
      satir({ id: 'a', user_id: 'u1', ticker: 'thyao.is' }),
      satir({ id: 'b', user_id: 'u2', ticker: 'THYAO.IS' }),
      satir({ id: 'c', user_id: 'u2', ticker: 'EREGL.IS' }),
    ]),
    ['EREGL.IS', 'THYAO.IS'],
  );
});

Deno.test('tavan: kullanıcı başına günde en çok GUNLUK_TAVAN öneri, en eski olay önce', () => {
  const kodlar = ['AKBNK', 'BIMAS', 'EREGL', 'THYAO', 'TUPRS'];
  const satirlar = kodlar.map((k, i) => satir({ id: String(i), ticker: `${k}.IS` }));
  const olaylar = new Map(
    kodlar.map((k, i) => [`${k}.IS`, [{ hakTarihi: `2025-06-${10 + i}`, tutarPay: 1 }]]),
  );
  const o = onerileriKur({ satirlar, olaylar, gonderilmis: new Set() });
  assertEquals(o.length, GUNLUK_TAVAN);
  assertEquals(o.map((x) => x.ticker), ['AKBNK.IS', 'BIMAS.IS', 'EREGL.IS']);

  // Aynı gün ikinci koşu: bugün yazılmış 3 satır tavanı doldurmuş.
  const ikinci = onerileriKur({
    satirlar,
    olaylar,
    gonderilmis: new Set(o.map((x) => defterAnahtari(x.user_id, x.ticker, x.hak_tarihi))),
    bugunGonderilen: new Map([['u1', 3]]),
  });
  assertEquals(ikinci, []);

  // Ertesi gün: kalanlar sırayla gelir.
  const ertesi = onerileriKur({
    satirlar,
    olaylar,
    gonderilmis: new Set(o.map((x) => defterAnahtari(x.user_id, x.ticker, x.hak_tarihi))),
  });
  assertEquals(ertesi.map((x) => x.ticker), ['THYAO.IS', 'TUPRS.IS']);
});

// ── Metin ve veri ───────────────────────────────────────────────────────────

Deno.test('mesaj: BRÜT yazılır, soru sorar, sembol ön eksiz', () => {
  const m = temettuMesaji({
    user_id: 'u1',
    ticker: 'THYAO.IS',
    hak_tarihi: '2025-06-16',
    tutar_pay: 3.44,
    lot: 100,
  });
  assertEquals(m.title, 'THYAO temettü dağıttı');
  assertEquals(m.body, '100 lot × ₺3,44 (brüt). Kaydetmek ister misin?');
});

Deno.test('biçim: pay tutarı hassasiyeti kaybolmaz, lot kesirliyse korunur', () => {
  // 3,442 → 3,44'e yuvarlanırsa kullanıcı KAP'la karşılaştırınca tutmaz.
  assertEquals(tutarYazisi(3.442), '3,442');
  assertEquals(tutarYazisi(10.38), '10,38');
  assertEquals(tutarYazisi(0.0512), '0,0512');
  assertEquals(tutarYazisi(1234.5), '1.234,50');
  assertEquals(lotYazisi(100), '100');
  assertEquals(lotYazisi(1500), '1.500');
  assertEquals(lotYazisi(2.5), '2,5');
});

Deno.test('veri: istemcinin okuduğu anahtarlar, sayılar makine biçiminde', () => {
  const v = temettuVerisi({
    user_id: 'u1',
    ticker: 'THYAO.IS',
    hak_tarihi: '2025-06-16',
    tutar_pay: 3.442,
    lot: 100,
  });
  assertEquals(v, {
    type: 'temettu',
    ticker: 'THYAO.IS',
    hak_tarihi: '2025-06-16',
    tutar_pay: '3.442',
    lot: '100',
  });
  // Kullanıcı kimliği push verisine girmez.
  assertEquals('user_id' in v, false);
});

// ── Fonksiyon kaynağı: kapı ve sızıntı ─────────────────────────────────────

const kaynak = await Deno.readTextFile(
  new URL('../functions/temettu-yakala/index.ts', import.meta.url),
);

Deno.test('fonksiyon: fail-closed cron kapısı, kapıdan önce iş yok', () => {
  const kapi = kaynak.indexOf("cronSecretZorunlu(cronSecret, 'TEMETTU_YAKALA_CRON_SECRET')");
  const yetki = kaynak.indexOf('cronYetkisiVarMi(request, cronSecret)');
  const istemci = kaynak.indexOf('createClient(supabaseUrl, serviceRoleKey)');
  assertEquals(kapi > 0 && yetki > kapi && istemci > yetki, true);
});

Deno.test('fonksiyon: yanıtta error.message / ham FCM gövdesi yok', () => {
  assertEquals(/jsonResponse\([^)]*\.message/.test(kaynak), false);
  assertEquals(/failures\.push\([^)]*rawText/.test(kaynak), false);
});

Deno.test('fonksiyon: temettü KAYDI yazmaz — assets tablosuna yazma yok', () => {
  // Kayıt yalnız istemcide, addDividend yolundan ve kullanıcı onayıyla.
  assertEquals(/from\('assets'\)\s*\.(insert|update|upsert|delete)/.test(kaynak), false);
});

Deno.test('fonksiyon: sessiz saatler ve token tekilleştirme ortak yoldan', () => {
  assertEquals(kaynak.includes('sessizKullanicilar('), true);
  assertEquals(kaynak.includes("from '../_shared/push_tokens.ts'"), true);
});

// ── Migration 0086 ──────────────────────────────────────────────────────────

const sql = (await Deno.readTextFile(
  new URL('../migrations/0086_temettu_bildirimleri.sql', import.meta.url),
)).split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');

Deno.test('0086: PK tekrar önleme anahtarı', () => {
  assertEquals(sql.includes('primary key (user_id, ticker, hak_tarihi)'), true);
  assertEquals(sql.includes('references auth.users(id) on delete cascade'), true);
});

Deno.test('0086: RLS açık + zorlanmış, yalnız kendi satırını SELECT', () => {
  assertEquals(sql.includes('enable row level security'), true);
  assertEquals(sql.includes('force row level security'), true);
  assertMatch(sql, /for select to authenticated\s+using \(\(select auth\.uid\(\)\) = user_id\)/);
  // Yazma politikası yok.
  assertEquals(/for (insert|update|delete|all)/.test(sql), false);
});

Deno.test('0086: GRANT — istemci yalnız okur, yazma service_role', () => {
  assertEquals(
    sql.includes('revoke all on table public.temettu_bildirimleri from public, anon, authenticated;'),
    true,
  );
  assertEquals(sql.includes('grant select on table public.temettu_bildirimleri to authenticated;'), true);
  assertEquals(/grant [^;]*insert[^;]* to authenticated/.test(sql), false);
});

Deno.test('0086: kendini raise exception ile doğruluyor (GRANT ve RLS ayrı)', () => {
  assertEquals(sql.includes("has_table_privilege('authenticated', 'public.temettu_bildirimleri', 'INSERT')"), true);
  assertEquals(sql.includes('relforcerowsecurity'), true);
  assertEquals((sql.match(/raise exception/g) ?? []).length >= 8, true);
});

Deno.test('0086: tetikleyici 0054/0076 deseni — secret x-cron-secret\'ta, adres Vault\'ta', () => {
  assertEquals(sql.includes("url := public.edge_function_url('temettu-yakala')"), true);
  assertEquals(sql.includes("headers := public.cron_headers('temettu_yakala_cron_secret')"), true);
  assertEquals(sql.includes("'Authorization'"), false);
  assertMatch(sql, /security definer\s+set search_path = public, vault, net/);
  assertEquals(sql.includes('timeout_milliseconds := 120000'), true);
  assertEquals(
    sql.includes('revoke all on function public.trigger_temettu_yakala() from public, anon, authenticated;'),
    true,
  );
  // Yer tutucu secret EKİLMEZ (0076 gerekçesi).
  assertEquals(sql.includes('vault.create_secret'), false);
});

Deno.test('0086: cron 19:00 TR (16:00 UTC) her gün; önce unschedule', () => {
  const un = sql.indexOf("cron.unschedule(jobid) from cron.job where jobname = 'temettu-yakala'");
  const sc = sql.indexOf("cron.schedule('temettu-yakala', '0 16 * * *'");
  assertEquals(un > 0 && sc > un, true);
});

Deno.test('0086: Frankfurt kipi — tüm işler kapalıysa yeni iş de kapalı kurulur', () => {
  // İki sunucu kuralı: tek bilinçli fark cron `active`; proje ref'i sabit yazılmaz.
  assertEquals(sql.includes('cron.alter_job(job_id := jobid, active := false)'), true);
  assertEquals(/[a-z0-9]{20}\.supabase\.co/.test(sql), false);
  assertEquals(/ybdb|ynwy/.test(sql), false);
});

Deno.test('0086: çan türü CHECK genişler, var olan türlerin hiçbiri düşmez', () => {
  for (const t of [
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge', 'temettu',
  ]) {
    assertEquals(sql.includes(`'${t}'`), true, t);
  }
});

Deno.test('0086: yalnız ekleme — var olan tablo/fonksiyon düşürülmez', () => {
  assertEquals(/drop (table|function|policy if exists (?!temettu_bildirimleri_own_select))/.test(sql), false);
});
