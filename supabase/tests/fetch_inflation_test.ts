// TÜFE çekimi — saf yardımcıların testleri.
//
// `Deno.serve` gövdesi ağ ve veritabanı istediği için test edilmiyor;
// yardımcılar bu yüzden export edildi.
//
// ## Bu dosyanın kovaladığı üç şey
//
// 1. **EVDS biçimi.** Yanıt `{ items: [{ Tarih, TP_FG_J0 }] }` geliyor ve
//    tarih biçimi tutarsız (`AY-YIL`, `YYYY-MM`, `GG-AY-YIL` hepsi
//    görülüyor). Yanlış ayrıştırma satırı YANLIŞ AYA yazar ve reel getiri
//    sessizce kayar.
//
// 2. **Baz yılı kırılması.** TÜİK baz yılını değiştirdiğinde endeks
//    sıfırlanır; eski ve yeni satırlar karşılaştırılamaz hale gelir.
//    Böyle bir seriyi yazmak reel getiriyi anlamsız yapar — fonksiyon
//    reddetmek ZORUNDA.
//
// 3. **İçinde bulunulan ay yazılmamalı.** `InflationService` "son
//    AÇIKLANMIŞ ay"ı arıyor ve içinde bulunulan ayın tabloda OLMADIĞINI
//    varsayıyor. Geçici bir satır o varsayımı kırar.
//
// Çalıştır:
//   deno test --allow-read --allow-net supabase/tests/fetch_inflation_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  ayBasi,
  bazKirilmasiVarMi,
  evdsTarihBicimi,
  evdsTarihToPeriod,
  guncelAyiEle,
  parseEvds,
} from '../functions/fetch-inflation/index.ts';

// ── evdsTarihToPeriod ───────────────────────────────────────────────────────

Deno.test('AY-YIL biçimi ayın ilk gününe çevrilir', () => {
  assertEquals(evdsTarihToPeriod('01-2026'), '2026-01-01');
  assertEquals(evdsTarihToPeriod('12-2025'), '2025-12-01');
});

Deno.test('tek haneli ay sıfırla doldurulur', () => {
  // '3-2026' → '2026-03-01'. Doldurulmazsa '2026-3-01' olur ve Postgres
  // DATE'e çevirirken biçim hatası verir.
  assertEquals(evdsTarihToPeriod('3-2026'), '2026-03-01');
});

Deno.test('YYYY-MM biçimi de kabul edilir', () => {
  assertEquals(evdsTarihToPeriod('2026-01'), '2026-01-01');
  assertEquals(evdsTarihToPeriod('2026-9'), '2026-09-01');
});

Deno.test('GG-AY-YIL biçimi ayın ilk gününe indirgenir', () => {
  // Gün bilgisi ATILIR: tablo ayın ilk gününü anahtar tutuyor, yoksa
  // '2026-03' ile '2026-03-15' iki ayrı satır olurdu.
  assertEquals(evdsTarihToPeriod('15-03-2026'), '2026-03-01');
});

Deno.test('tanınmayan biçim null döner — tarih TAHMİN EDİLMEZ', () => {
  // Yanlış aya yazmak, hiç yazmamaktan kötü.
  assertEquals(evdsTarihToPeriod('Ocak 2026'), null);
  assertEquals(evdsTarihToPeriod(''), null);
  assertEquals(evdsTarihToPeriod('2026'), null);
});

// ── parseEvds ───────────────────────────────────────────────────────────────

/// Gerçek EVDS yanıt şekli (alan adı: serideki noktalar alt çizgiye döner).
const gercekYanit = {
  totalCount: 3,
  items: [
    { Tarih: '06-2026', TP_FG_J0: '2000.00', UNIXTIME: { $numberLong: '0' } },
    { Tarih: '07-2026', TP_FG_J0: '2040.50' },
    { Tarih: '08-2026', TP_FG_J0: '2081.31' },
  ],
};

Deno.test('gerçek EVDS yanıtı ayrıştırılır', () => {
  const out = parseEvds(gercekYanit);
  assertEquals(out.length, 3);
  assertEquals(out[0], { period: '2026-06-01', value: 2000 });
  assertEquals(out[2], { period: '2026-08-01', value: 2081.31 });
});

Deno.test('sonuç KRONOLOJİK sıralanır', () => {
  // Baz kırılması denetimi ardışık aylara bakıyor; sıra bozuksa yanlış
  // bir kırılma raporlanır.
  const out = parseEvds({
    items: [
      { Tarih: '08-2026', TP_FG_J0: '2081' },
      { Tarih: '06-2026', TP_FG_J0: '2000' },
      { Tarih: '07-2026', TP_FG_J0: '2040' },
    ],
  });
  assertEquals(out.map((r) => r.period), [
    '2026-06-01',
    '2026-07-01',
    '2026-08-01',
  ]);
});

Deno.test('boş / null / sıfır değerler ATLANIR', () => {
  // EVDS bazı aylar için boş string döndürebiliyor. Tablo CHECK'i
  // `tufe_index > 0` istiyor; sıfır yazmak upsert'i düşürürdü.
  const out = parseEvds({
    items: [
      { Tarih: '06-2026', TP_FG_J0: '' },
      { Tarih: '07-2026', TP_FG_J0: null },
      { Tarih: '08-2026', TP_FG_J0: '0' },
      { Tarih: '09-2026', TP_FG_J0: '-5' },
      { Tarih: '10-2026', TP_FG_J0: '2100' },
    ],
  });
  assertEquals(out, [{ period: '2026-10-01', value: 2100 }]);
});

Deno.test('tek bozuk ay tüm turu DÜŞÜRMEZ', () => {
  const out = parseEvds({
    items: [
      { Tarih: 'bozuk', TP_FG_J0: '2000' },
      { Tarih: '07-2026', TP_FG_J0: '2040' },
    ],
  });
  assertEquals(out.length, 1);
  assertEquals(out[0].period, '2026-07-01');
});

Deno.test('sayısal değer de kabul edilir (string olmayabilir)', () => {
  const out = parseEvds({ items: [{ Tarih: '07-2026', TP_FG_J0: 2040.5 }] });
  assertEquals(out[0].value, 2040.5);
});

Deno.test('bozuk gövde boş liste döner — çökmez', () => {
  assertEquals(parseEvds(null), []);
  assertEquals(parseEvds({}), []);
  assertEquals(parseEvds({ items: 'ne' }), []);
  assertEquals(parseEvds({ items: [] }), []);
});

// ── bazKirilmasiVarMi ───────────────────────────────────────────────────────

Deno.test('normal enflasyon serisinde kırılma YOK', () => {
  assertEquals(
    bazKirilmasiVarMi([
      { period: '2026-06-01', value: 2000 },
      { period: '2026-07-01', value: 2040 },
      { period: '2026-08-01', value: 2081 },
    ]),
    null,
  );
});

Deno.test('küçük aylık deflasyon kırılma SAYILMAZ', () => {
  // −%2 gerçek bir deflasyon olabilir; eşiğin altında kalmalı.
  assertEquals(
    bazKirilmasiVarMi([
      { period: '2026-06-01', value: 2000 },
      { period: '2026-07-01', value: 1960 },
    ]),
    null,
  );
});

Deno.test('BAZ KIRILMASI yakalanır — endeks sıfırlanmış', () => {
  // 2003=100 → 2025=100 geçişi: endeks 2100'den 100'e düşer. Bölme
  // anlamsız bir "−%95 enflasyon" verirdi.
  assertEquals(
    bazKirilmasiVarMi([
      { period: '2026-06-01', value: 2100 },
      { period: '2026-07-01', value: 100 },
    ]),
    '2026-07-01',
  );
});

Deno.test('sıfır önceki değerde bölme yapılmaz', () => {
  assertEquals(
    bazKirilmasiVarMi([
      { period: '2026-06-01', value: 0 },
      { period: '2026-07-01', value: 2100 },
    ]),
    null,
  );
});

Deno.test('tek satırda kırılma denetimi anlamsız — null', () => {
  assertEquals(bazKirilmasiVarMi([{ period: '2026-07-01', value: 2100 }]), null);
  assertEquals(bazKirilmasiVarMi([]), null);
});

// ── guncelAyiEle ────────────────────────────────────────────────────────────

Deno.test('İÇİNDE BULUNULAN ay tabloya yazılmaz', () => {
  // `InflationService.inflationForPeriod` "son AÇIKLANMIŞ ay"ı arıyor ve
  // içinde bulunulan ayın tabloda OLMADIĞINI varsayıyor. Geçici bir satır
  // o varsayımı kırardı.
  const simdi = new Date(Date.UTC(2026, 8, 14)); // 14 Eylül 2026
  const out = guncelAyiEle(
    [
      { period: '2026-07-01', value: 2040 },
      { period: '2026-08-01', value: 2081 },
      { period: '2026-09-01', value: 2100 }, // bu ay — elenmeli
    ],
    simdi,
  );
  assertEquals(out.map((r) => r.period), ['2026-07-01', '2026-08-01']);
});

Deno.test('ayın 1\'inde de içinde bulunulan ay elenir', () => {
  const simdi = new Date(Date.UTC(2026, 8, 1));
  const out = guncelAyiEle(
    [
      { period: '2026-08-01', value: 2081 },
      { period: '2026-09-01', value: 2100 },
    ],
    simdi,
  );
  assertEquals(out.map((r) => r.period), ['2026-08-01']);
});

// ── Tarih yardımcıları ──────────────────────────────────────────────────────

Deno.test('ayBasi ayın ilk gününe indirger (UTC)', () => {
  assertEquals(ayBasi(new Date(Date.UTC(2026, 8, 14, 23, 59))), '2026-09-01');
  assertEquals(ayBasi(new Date(Date.UTC(2026, 0, 1))), '2026-01-01');
});

Deno.test('evdsTarihBicimi GG-AA-YYYY verir', () => {
  assertEquals(evdsTarihBicimi(new Date(Date.UTC(2026, 8, 3))), '03-09-2026');
  assertEquals(evdsTarihBicimi(new Date(Date.UTC(2024, 11, 25))), '25-12-2024');
});

// ── CRON SIRASI — otomatikleştirmenin asıl kazancı ──────────────────────────
//
// `calendar-nudge` tabloda BU AYIN satırını arıyor; yoksa sessizce
// hiçbir şey göndermiyor. Çekim nudge'dan SONRA koşarsa nudge hep bayat
// veriyle karşılaşır ve o ayın kancası kaçar.
//
// Borç kaydı `0 8 3 * *` (TR 11:00) öneriyordu — nudge 07:15'te. Bu sıra
// yanlıştı ve testle kilitlendi.

const migration = Deno.readTextFileSync(
  new URL('../migrations/0053_fetch_inflation.sql', import.meta.url),
);

Deno.test('çekim, takvim kancasından ÖNCE koşuyor', () => {
  assertEquals(
    migration.includes("cron.schedule('fetch-inflation', '5 7 3 * *'"),
    true,
    'çekim 07:05 UTC olmalı (nudge 07:15)',
  );
});

Deno.test('ayın 4\'ünde ikinci tur var — veri geç gelirse', () => {
  assertEquals(
    migration.includes("cron.schedule('fetch-inflation-retry', '5 7 4 * *'"),
    true,
  );
});

Deno.test('takvim kancasının ikinci turu AÇILIYOR', () => {
  // `0048`'de yazılmış ama kapalı bırakılmıştı (defter yoktu).
  assertEquals(
    migration.includes(
      "cron.schedule('calendar-nudge-inflation-retry', '15 7 4 * *'",
    ),
    true,
  );
});

Deno.test('gönderim defteri tablosu kuruluyor ve istemciye KAPALI', () => {
  assertEquals(migration.includes('calendar_nudge_log'), true);
  assertEquals(
    migration.includes(
      'revoke all on table public.calendar_nudge_log from anon, authenticated',
    ),
    true,
  );
});

Deno.test('migration SIRA bozulmasını yakalıyor', () => {
  // Çekim ve nudge aynı saate kurulursa yüksek sesle patlamalı.
  assertEquals(
    migration.includes('nudge bayat veri gorur'),
    true,
  );
});

Deno.test('pg_net timeout AÇIKÇA veriliyor', () => {
  // EVDS turu + 24 aylık upsert 5 saniyede bitmez.
  assertEquals(migration.includes('timeout_milliseconds := 60000'), true);
});

// ── Kancanın defteri gerçekten OKUDUĞU ──────────────────────────────────────
//
// İkinci tur yalnızca defter varsa güvenli. Fonksiyon defteri okumazsa,
// `0048`'in ikinci turu kapatma sebebi (çift bildirim) geri gelir.

const nudgeSrc = Deno.readTextFileSync(
  new URL('../functions/calendar-nudge/index.ts', import.meta.url),
);

Deno.test('calendar-nudge defteri OKUYOR', () => {
  assertEquals(
    nudgeSrc.includes("from('calendar_nudge_log')"),
    true,
    'defter okunmadan ikinci tur çift bildirim gönderir',
  );
  assertEquals(nudgeSrc.includes('zaten gonderildi'), true);
});

Deno.test('calendar-nudge defteri YAZIYOR — yalnızca gönderim olduysa', () => {
  assertEquals(nudgeSrc.includes('if (sent > 0)'), true);
  assertEquals(nudgeSrc.includes("onConflict: 'occasion,period'"), true);
});
