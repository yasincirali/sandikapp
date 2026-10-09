// Mevduat faiz ortalaması — saf yardımcıların testleri (0129).
//
// Kovalanan: EVDS haftalık biçimi (GG-AA-YYYY), boş/aralık dışı haftaların
// atlanması (uydurma sayı yok) ve bayat serinin "güncel" sayılmaması.
import { assertEquals } from 'jsr:@std/assert@1';
import { bayatMi, evdsGunu, seriAdresi, sonFaiz } from '../functions/_shared/mevduat_faiz.ts';

Deno.test('evdsGunu: haftalık GG-AA-YYYY ve ISO biçimi', () => {
  assertEquals(evdsGunu('03-10-2026'), '2026-10-03');
  assertEquals(evdsGunu('3-1-2026'), '2026-01-03');
  assertEquals(evdsGunu('2026-10-03'), '2026-10-03');
  assertEquals(evdsGunu('10-2026'), null);
  assertEquals(evdsGunu(''), null);
});

Deno.test('sonFaiz: en yeni geçerli haftayı alır, boşu ve aralık dışını atlar', () => {
  const json = {
    items: [
      { Tarih: '19-09-2026', TP_TRY_MT02: '38.40' },
      { Tarih: '26-09-2026', TP_TRY_MT02: 37.95 },
      { Tarih: '03-10-2026', TP_TRY_MT02: null },
      { Tarih: '10-10-2026', TP_TRY_MT02: '' },
      { Tarih: '17-10-2026', TP_TRY_MT02: '1250' }, // endeks/tutar: faiz değil
    ],
  };
  assertEquals(sonFaiz(json, 'TP.TRY.MT02'), { tarih: '2026-09-26', faiz: 37.95 });
});

Deno.test('sonFaiz: alan yoksa ya da gövde bozuksa null (uydurma yok)', () => {
  assertEquals(sonFaiz({ items: [{ Tarih: '26-09-2026', TP_TRY_MT03: '40' }] }, 'TP.TRY.MT02'), null);
  assertEquals(sonFaiz(null, 'TP.TRY.MT02'), null);
  assertEquals(sonFaiz('<html>', 'TP.TRY.MT02'), null);
});

Deno.test('sonFaiz: virgüllü ondalık', () => {
  assertEquals(sonFaiz({ items: [{ Tarih: '26-09-2026', TP_TRY_MT02: '38,5' }] }, 'TP.TRY.MT02')?.faiz, 38.5);
});

Deno.test('bayatMi: 45 günden eski son nokta bayattır', () => {
  const simdi = new Date('2026-10-09T08:00:00Z');
  assertEquals(bayatMi('2026-10-02', simdi), false);
  assertEquals(bayatMi('2026-08-01', simdi), true);
  assertEquals(bayatMi('bozuk', simdi), true);
});

Deno.test('seriAdresi: parametreler yola gömülü, soru işareti yok, frequency yok', () => {
  const u = seriAdresi('TP.TRY.MT02', new Date('2026-10-09T00:00:00Z'), 7);
  assertEquals(
    u,
    'https://evds3.tcmb.gov.tr/igmevdsms-dis/series=TP.TRY.MT02&startDate=02-10-2026&endDate=09-10-2026&type=json',
  );
});
