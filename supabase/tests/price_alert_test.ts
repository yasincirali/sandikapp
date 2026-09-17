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
  parseTruncgilBody,
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
  assertEquals(parseTruncgilNumber(null), null);
  assertEquals(parseTruncgilNumber(undefined), null);
  assertEquals(parseTruncgilNumber(0), null, 'sıfır fiyat geçersiz');
  assertEquals(parseTruncgilNumber(-5), null, 'negatif fiyat geçersiz');
});

// ── v4 biçimi (2026-09-15) ──────────────────────────────────────────────
//
// API sayıları artık JSON number olarak, alan adlarını da İngilizce
// döndürüyor. Bu üç test o değişikliğin regresyonunu tutar: ikisi de
// kırıldığında belirti SESSİZDİ — `check-price-alerts` HTTP 200 ile
// `{"reason":"Fiyat alinamadi.","sent":0}` dönüyor ve fiyat alarmı
// özelliği tümüyle ölüyordu.
Deno.test('v4: sayı tipi doğrudan okunur', ()=>{
  assertEquals(parseTruncgilNumber(6710.67), 6710.67);
  assertEquals(parseTruncgilNumber(48), 48);
});
Deno.test('v4: Buying/Selling alan adları okunur', ()=>{
  assertEquals(truncgilValue({'Buying':6710.67,'Selling':6711.54}), 6710.67);
  assertEquals(truncgilValue({'Selling':99.64}), 99.64);
  // Alış/Satış önce denenir — API geri dönerse çalışmaya devam etmeli.
  assertEquals(truncgilValue({'Alış':'100,00','Buying':999}), 100);
});
// ── AYAR TUTARLILIĞI — 2026-09-15 ikinci tur regresyonu ────────────────────
//
// İlk düzeltmede `ALTIN_GRAM` → `GRA` seçilmişti; `GRA`'nın adı `GRAMALTIN`
// ama içeriği 24 ayar HAS altındır. Uygulamanın `ALTIN_GRAM`'ı 22 ayardır.
// Sonuç: kullanıcı 6.270 görürken sunucu 6.710 okudu, 6.270 hedefli alarm
// ERKEN tetiklendi.
//
// Bu test "hangi anahtar" sorusunu ADLA değil, ÖLÇÜYLE cevaplar: çeyrek
// altının gram eşdeğeri (fiyat ÷ 1.75) gram fiyatıyla %2 içinde uyuşmalı.
// Aynı aile aynı ayarda kote edilir; uyuşmuyorsa yanlış ayar seçilmiştir.
Deno.test('ALTIN_GRAM 22 ayar ailesiyle tutarlı (GRA=24ayar tuzağı)', ()=>{
  // Canlı yanıttan alınmış gerçek değerler (2026-09-15 17:42).
  const data = {
    'YIA': {'Buying':6112.56,'Type':'Gold','Name':'22AYARBILEZIK'},
    'GRA': {'Buying':6687.88,'Type':'Gold','Name':'GRAMALTIN'},     // 24 ayar
    'HAS': {'Buying':6654.45,'Type':'Gold','Name':'GRAMHASALTIN'},  // 24 ayar
    'CEYREKALTIN': {'Buying':10723.78,'Type':'Gold'},
    'YARIMALTIN': {'Buying':21380.54,'Type':'Gold'},
  };
  const out = extractTruncgil(data, ['ALTIN_GRAM','ALTIN_CEYREK','ALTIN_YARIM']);
  const gram = out.get('ALTIN_GRAM')!;

  // Çeyrek 1.75 gr, yarım 3.5 gr (istemcideki `_goldWeights` ile aynı).
  const ceyrekGram = out.get('ALTIN_CEYREK')! / 1.75;
  const yarimGram = out.get('ALTIN_YARIM')! / 3.5;

  const sapma = (a: number, b: number) => Math.abs(a / b - 1);
  if (sapma(ceyrekGram, gram) > 0.02) {
    throw new Error(
      `ALTIN_GRAM (${gram}) ceyrek altinin gram esdegeriyle (${ceyrekGram.toFixed(2)}) ` +
      `uyusmuyor — yanlis AYAR secilmis olabilir (GRA=24ayar, YIA=22ayar).`,
    );
  }
  if (sapma(yarimGram, gram) > 0.02) {
    throw new Error(
      `ALTIN_GRAM (${gram}) yarim altinin gram esdegeriyle (${yarimGram.toFixed(2)}) uyusmuyor.`,
    );
  }
  // Ve 24 ayar kayıtlarına DÜŞMEMELİ.
  assertEquals(gram === 6687.88, false, 'GRA (24 ayar) secilmis — yanlis');
  assertEquals(gram === 6654.45, false, 'HAS (24 ayar) secilmis — yanlis');
});

Deno.test('v4: gerçek anahtarlarla altın ve döviz çıkarılır', ()=>{
  // Anahtarlar canlı yanıttan alındı (2026-09-15). Eski adlar
  // ('Gram Altın', 'Ata Altını') yanıtta ARTIK YOK.
  const data = {
    'YIA': {'Buying':6112.56,'Selling':6118.27,'Type':'Gold'},
    'ATAALTIN': {'Buying':44145.84,'Selling':45258.4,'Type':'Gold'},
    'USD': {'Buying':48.6332,'Selling':48.6464,'Type':'Currency'},
    'EUR': {'Buying':56.1795,'Selling':56.1908,'Type':'Currency'},
  };
  const out = extractTruncgil(data, ['ALTIN_GRAM','ALTIN_ATA','USDTRY=X','EURTRY=X']);
  assertEquals(out.get('ALTIN_GRAM'), 6112.56);
  assertEquals(out.get('ALTIN_ATA'), 44145.84);
  assertEquals(out.get('USDTRY=X'), 48.6332);
  assertEquals(out.get('EURTRY=X'), 56.1795);
  assertEquals(out.size, 4, 'dört sembolün dördü de çözülmeli');
});

Deno.test('Alış yoksa Satış kullanılır', ()=>{
  assertEquals(truncgilValue({'Alış':'100,00','Satış':'101,00'}), 100);
  assertEquals(truncgilValue({'Satış':'101,00'}), 101);
  assertEquals(truncgilValue({}), null);
  assertEquals(truncgilValue(null), null);
});
Deno.test('eski biçim (string + Türkçe alan) hâlâ okunur', ()=>{
  // Geriye dönük uyum kasıtlı: API biçimi bir kez değiştiyse geri dönebilir.
  const out = extractTruncgil({'USD':{'Alış':'42,15'}}, ['USDTRY=X']);
  assertEquals(out.get('USDTRY=X'), 42.15);
});
Deno.test('kaynakta olmayan sembol atlanır, hata vermez', ()=>{
  const out = extractTruncgil({'USD':{'Buying':48.63}}, ['ALTIN_ATA','USDTRY=X']);
  assertEquals(out.has('ALTIN_ATA'), false);
  assertEquals(out.size, 1);
});

// ── kesik gövde kurtarma ────────────────────────────────────────────────
// 2026-09-17: truncgil v4 gövdesi 6.805 baytta kesik geliyor; `res.json()`
// reddedince altın/döviz alarmları her turda sessizce atlanıyordu.
const TAM_GOVDE = '{"Update_Date":"2026-09-17 19:12:01",' +
  '"USD":{"Buying":48.6717,"Type":"Currency","Selling":48.6767,"Change":0.04},' +
  '"YIA":{"Buying":6212.28,"Type":"Gold","Name":"22AYARBILEZIK","Selling":6219.29,"Change":0.59},' +
  '"GRAMPALADYUM":{"Buying":2019.87,"Type":"Palladium","Name":"GRAMPALADYUM","Selling":2028.42,"Change":1.43}}';

Deno.test('parseTruncgilBody: tam gövde JSON.parse ile aynı', () => {
  assertEquals(parseTruncgilBody(TAM_GOVDE), JSON.parse(TAM_GOVDE));
});
Deno.test('parseTruncgilBody: kesik gövdeden bütün girişler kurtarılır', () => {
  const kesik = TAM_GOVDE.slice(0, TAM_GOVDE.indexOf('"Change":1.43'));
  const d = parseTruncgilBody(kesik) as Record<string, Record<string, unknown>>;
  assertEquals(d.USD.Buying, 48.6717);
  assertEquals(d.YIA.Buying, 6212.28);
  assertEquals('GRAMPALADYUM' in d, false, 'yarım giriş uydurulmamalı');
  // Alarm hattı: kurtarılan gövdeden altın fiyatı okunabilmeli.
  assertEquals(extractTruncgil(d, ['ALTIN_GRAM']).get('ALTIN_GRAM'), 6212.28);
});
Deno.test('parseTruncgilBody: HTML gövdede kurtarma denenmez', () => {
  let hata = false;
  try { parseTruncgilBody('<html>"USD":{"Buying":1}</html>'); } catch { hata = true; }
  assertEquals(hata, true);
});
