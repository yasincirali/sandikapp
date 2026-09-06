// Fiyat alarmı — saf yardımcıların testleri.
//
// Bu testlerin varlık sebebi: alarm, kullanıcının KENDİ kurduğu tek
// bildirim. Yanlış tetiklenirse (ya da tetiklenmezse) kullanıcı bunu
// hemen fark eder — ekrandaki fiyata bakıp alarmın çalışmadığını görür.
//
// En kritik olanı `parseTruncgilNumber`: kaynak "5.412,37" biçiminde
// gönderiyor ve düz `parseFloat` bunu 5.412 okuyor — yani BİN KATI hatalı
// bir fiyat. Sessizce yanlış tetiklenmenin en kolay yolu buydu.
//
// Çalıştır:
//   deno test supabase/tests/price_alert_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  buildAlertMessage,
  formatTRY,
  isTriggered,
} from '../functions/check-price-alerts/index.ts';
import {
  extractTruncgil,
  parseTruncgilNumber,
  truncgilValue,
} from '../functions/_shared/live_prices.ts';

/// `assert.ok` karşılığı — mesajı korur.
function assertOk(v: unknown, msg?: string) {
  assertEquals(Boolean(v), true, msg);
}
 
// ── isTriggered ─────────────────────────────────────────────────────────
Deno.test('above: hedefe ULAŞMAK yeter (sınır dahil)', ()=>{
  assertEquals(isTriggered(5400, 5400, 'above'), true);
  assertEquals(isTriggered(5401, 5400, 'above'), true);
  assertEquals(isTriggered(5399, 5400, 'above'), false);
});
Deno.test('below: hedefe inmek yeter (sınır dahil)', ()=>{
  assertEquals(isTriggered(5400, 5400, 'below'), true);
  assertEquals(isTriggered(5399, 5400, 'below'), true);
  assertEquals(isTriggered(5401, 5400, 'below'), false);
});
Deno.test('geçersiz fiyat tetiklemez', ()=>{
  assertEquals(isTriggered(0, 5400, 'below'), false, 'sıfır fiyat below alarmını yakmamalı');
  assertEquals(isTriggered(NaN, 5400, 'above'), false);
  assertEquals(isTriggered(-5, 5400, 'below'), false);
});

// ── formatTRY ───────────────────────────────────────────────────────────
Deno.test('Türkçe binlik/ondalık ayıracı', ()=>{
  assertEquals(formatTRY(5412.37), '5.412,37');
  assertEquals(formatTRY(999), '999,00');
  assertEquals(formatTRY(1000), '1.000,00');
  assertEquals(formatTRY(1234567.5), '1.234.567,50');
});
Deno.test('negatif değer işareti korur', ()=>assertEquals(formatTRY(-1234.5), '-1.234,50'));

// ── buildAlertMessage ───────────────────────────────────────────────────
Deno.test('yukarı alarm metni', ()=>{
  const m = buildAlertMessage('Gram Altın', 5412.37, 5400, 'above');
  assertEquals(m.title, '▲ Gram Altın 5.400,00 seviyesine ulaştı');
  assertOk(m.body.includes('5.412,37'));
});
Deno.test('aşağı alarm metni', ()=>{
  const m = buildAlertMessage('THYAO', 298.5, 300, 'below');
  assertEquals(m.title, '▼ THYAO 300,00 seviyesinin altına indi');
});
Deno.test('SPK ibaresi her alarmda', ()=>{
  for (const d of ['above','below'])
    assertOk(buildAlertMessage('X', 1, 1, d).body.includes('Yatırım tavsiyesi değildir.'));
});
Deno.test('bildirimde sembol KODU değil etiket geçer', ()=>{
  const m = buildAlertMessage('Gram Altın', 5412, 5400, 'above');
  assertOk(!m.title.includes('ALTIN_GRAM'));
});

// ── truncgil ayrıştırma ─────────────────────────────────────────────────
Deno.test('binlik NOKTA / ondalık VİRGÜL doğru okunur', ()=>{
  // Bu testin sebebi: parseFloat("5.412,37") → 5.412, yani bin katı hata.
  assertEquals(parseTruncgilNumber('5.412,37'), 5412.37);
  assertEquals(parseTruncgilNumber('42,15'), 42.15);
  assertEquals(parseTruncgilNumber('1.234.567,89'), 1234567.89);
});
Deno.test('bozuk/boş değer null', ()=>{
  assertEquals(parseTruncgilNumber(''), null);
  assertEquals(parseTruncgilNumber('abc'), null);
  assertEquals(parseTruncgilNumber('0'), null);
  assertEquals(parseTruncgilNumber(5412.37), null, 'sayı değil string bekleniyor');
});
Deno.test('Alış yoksa Satış kullanılır', ()=>{
  assertEquals(truncgilValue({'Alış':'100,00','Satış':'101,00'}), 100);
  assertEquals(truncgilValue({'Satış':'101,00'}), 101);
  assertEquals(truncgilValue({}), null);
  assertEquals(truncgilValue(null), null);
});
Deno.test('altın ve döviz sembolleri çıkarılır', ()=>{
  const data = {'Gram Altın':{'Alış':'5.412,37'}, 'USD':{'Alış':'42,15'}, 'EUR':{'Alış':'45,90'}};
  const out = extractTruncgil(data, ['ALTIN_GRAM','USDTRY=X','EURTRY=X']);
  assertEquals(out.get('ALTIN_GRAM'), 5412.37);
  assertEquals(out.get('USDTRY=X'), 42.15);
  assertEquals(out.get('EURTRY=X'), 45.90);
});
Deno.test('kaynakta olmayan sembol atlanır, hata vermez', ()=>{
  const out = extractTruncgil({'USD':{'Alış':'42,15'}}, ['ALTIN_ATA','USDTRY=X']);
  assertEquals(out.has('ALTIN_ATA'), false);
  assertEquals(out.size, 1);
});
