// SANDIK X hesabı (0146) — içerik kuralları, kapı, kart, OAuth imzası.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/x_paylasim_test.ts

import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import {
  botModu,
  xeGonderir,
  abdTufeGuncelMi,
  abdTufeOzeti,
  abdTufeTaslagi,
  akisOzeti,
  fedKarariBul,
  fedTaslagi,
  ASGARI_FON,
  bugununFonGonderisi,
  type FonAkisSatiri,
  fonAkisiTaslagi,
  fonKategorisi,
  geriCagriCoz,
  haftalikTaslak,
  imzaTabani,
  kartSvg,
  kisaTutar,
  kurDegisimleri,
  metinKapisi,
  oauthBasligi,
  onaySuresiGectiMi,
  tufeOzeti,
  tufeTaslagi,
  tufeYeniMi,
  tutarYazisi,
  yuzde,
} from '../functions/_shared/x_paylasim.ts';
import { pngCiz } from '../functions/bildirim-karti/cizici.ts';

function gun(tarih: string, dagilim: [string, number, number][]): FonAkisSatiri[] {
  // dagilim: [fon_turu, fon sayısı, fon başına net akış]
  const out: FonAkisSatiri[] = [];
  let n = 0;
  for (const [tur, adet, net] of dagilim) {
    for (let i = 0; i < adet; i++) {
      out.push({ fon_kodu: `F${n++}`, tarih, fon_tipi: 'YAT', fon_turu: tur, net_akis: net });
    }
  }
  return out;
}

const ORNEK = gun('2026-10-13', [
  ['Para Piyasası Şemsiye Fonu', 100, 24e6],
  ['Borçlanma Araçları Şemsiye Fonu', 100, 9.1e6],
  ['Kıymetli Madenler Şemsiye Fonu', 50, 10.1e6],
  ['Hisse Senedi Şemsiye Fonu', 100, -5.2e6],
  ['Değişken Şemsiye Fonu', 50, -1.9e6],
]);

Deno.test('kategori: katılım para piyasası para piyasasıdır, bilinmeyen Diğer', () => {
  assertEquals(fonKategorisi('Katılım Para Piyasası Şemsiye Fonu'), 'Para piyasası');
  assertEquals(fonKategorisi('Hisse Senedi Şemsiye Fonu'), 'Hisse senedi');
  assertEquals(fonKategorisi('Hisse Senedi Serbest Şemsiye Fonu'), 'Serbest');
  assertEquals(fonKategorisi('Kıymetli Madenler Şemsiye Fonu'), 'Altın ve kıymetli maden');
  assertEquals(fonKategorisi(null), 'Diğer');
});

Deno.test('biçim: Türkçe tutar ve yüzde', () => {
  assertEquals(tutarYazisi(3.24e9), '3,2 milyar TL');
  assertEquals(tutarYazisi(-520e6), '520 milyon TL');
  assertEquals(kisaTutar(-520e6), '−520 mn');
  assertEquals(kisaTutar(2.4e9), '+2,4 mr');
  assertEquals(yuzde(1.83, true), '+%1,8');
  assertEquals(yuzde(-0.3, true), '−%0,3');
});

Deno.test('akış özeti: BES ve akışı bilinmeyen fon sayılmaz, eksik gün paylaşılmaz', () => {
  const o = akisOzeti([
    ...ORNEK,
    { fon_kodu: 'B1', tarih: '2026-10-13', fon_tipi: 'EMK', fon_turu: 'Hisse', net_akis: 9e12 },
    { fon_kodu: 'N1', tarih: '2026-10-13', fon_tipi: 'YAT', fon_turu: 'Hisse', net_akis: null },
  ], '2026-10-13', '2026-10-13')!;
  assertEquals(o.fon_sayisi, 400);
  assertEquals(Math.round(o.toplam / 1e6), 2400 + 910 + 505 - 520 - 95);
  assertEquals(o.kategoriler[0].kategori, 'Para piyasası');
  assertEquals(o.kategoriler.at(-1)!.kategori, 'Hisse senedi');
  assertEquals(akisOzeti(ORNEK.slice(0, ASGARI_FON - 1), '2026-10-13', '2026-10-13'), null);
});

Deno.test('fon akışı taslağı: şablon kendi kapısından geçer, kart 5 satır', () => {
  const t = fonAkisiTaslagi(akisOzeti(ORNEK, '2026-10-13', '2026-10-13')!);
  assertEquals(t.sablon_metin, 'Fonlara bugün net 3,2 milyar TL girdi. En çok giriş para piyasası fonlarına oldu: 2,4 milyar TL. Hisse senedi fonlarından 520 milyon TL çıktı.');
  assertEquals(metinKapisi({ metin: t.sablon_metin }, t).gecti, true);
  assert(t.kart.bicim === 'liste');
  if (t.kart.bicim === 'liste') {
    assertEquals(t.kart.satirlar.length, 5);
    assertEquals(t.kart.satirlar[0].oran, 1);
    assertEquals(t.kart.satirlar.at(-1)!.yon, 'd');
  }
});

Deno.test('kapı: uydurma sayı, yönlendirme, gelecek dili, link, emoji reddedilir', () => {
  const t = fonAkisiTaslagi(akisOzeti(ORNEK, '2026-10-13', '2026-10-13')!);
  const red = (m: string) => metinKapisi({ metin: m }, t).gecti;
  assertEquals(red('Fonlara bugün net 3,5 milyar TL girdi, bu bir artış.'), false);
  assertEquals(red('Fonlara bugün net 3,2 milyar TL girdi. Para piyasası fonlarını almalısın.'), false);
  assertEquals(red('Fonlara bugün net 3,2 milyar TL girdi; bu ilgi yarın da sürebilir.'), false);
  assertEquals(red('Fonlara bugün net 3,2 milyar TL girdi. Ayrıntı sandik.app adresinde.'), false);
  assertEquals(red('Fonlara bugün net 3,2 milyar TL girdi 🚀 güzel bir gün.'), false);
  assertEquals(red('Fonlara bugün net 3,2 milyar TL girdi! Kaçırmayın.'), false);
  assertEquals(red('Bugün fonlara net 3,2 milyar TL girdi; paranın çoğu yine para piyasası fonlarına gitti.'), true);
  assertEquals(metinKapisi({}, t).gecti, false);
  assertEquals(metinKapisi({ metin: 'x'.repeat(300) }, t).gecti, false);
});

Deno.test('TÜFE: aylık ve yıllık endeks oranından, 13 ay yoksa null', () => {
  const satirlar = [];
  let e = 100;
  for (let i = 0; i < 13; i++) {
    const y = 2025 + Math.floor((8 + i) / 12);
    const a = ((8 + i) % 12) + 1;
    satirlar.push({ period: `${y}-${String(a).padStart(2, '0')}-01`, tufe_index: e });
    e *= 1.02;
  }
  const t = tufeOzeti(satirlar)!;
  assertEquals(t.donem, '2026-09-01');
  assertEquals(Math.round(t.aylik * 100) / 100, 2);
  assertEquals(Math.round(t.yillik * 10) / 10, 26.8);
  assertEquals(t.son_aylar.length, 6);
  assertEquals(tufeOzeti(satirlar.slice(1)), null);
  const ts = tufeTaslagi(t);
  assertEquals(ts.sablon_metin, 'Eylül enflasyonu %2,0 geldi; yıllık enflasyon %26,8 oldu.');
  assertEquals(metinKapisi({ metin: ts.sablon_metin }, ts).gecti, true);
});

Deno.test('kur: iki uçta da veri yoksa sembol atlanır, gram altın 24 ayar', () => {
  const k = kurDegisimleri([
    { sembol: 'ALTIN_GRAM24', ts: '2026-10-03T15:00:00Z', fiyat: 4825 },
    { sembol: 'ALTIN_GRAM24', ts: '2026-10-10T14:55:00Z', fiyat: 4912 },
    { sembol: 'ALTIN_GRAM', ts: '2026-10-10T14:55:00Z', fiyat: 4500 },
    { sembol: 'USDTRY=X', ts: '2026-10-10T14:55:00Z', fiyat: 42.31 },
  ], '2026-10-03T15:00:00Z', '2026-10-10T15:00:00Z');
  assertEquals(k.length, 1);
  assertEquals(k[0].ad, 'Gram altın');
  assertEquals(k[0].son, '4.912 ₺');
  assertEquals(yuzde(k[0].degisim), '%1,8');
});

Deno.test('haftalık: kur kapalıyken yalnız fon satırları; şablon kapıdan geçer', () => {
  const o = akisOzeti(ORNEK, '2026-10-13', '2026-10-13')!;
  const t = haftalikTaslak({ ...o, baslangic: '2026-10-06', bitis: '2026-10-10' }, []);
  assertEquals(t.donem, '2026-10-10');
  assertEquals(metinKapisi({ metin: t.sablon_metin }, t).gecti, true);
  if (t.kart.bicim === 'liste') assertEquals(t.kart.satirlar.every((s) => !/altın|dolar/i.test(s.ad)), true);
});

Deno.test('takvim: hafta içi günlük, Cuma haftalık, hafta sonu yok', () => {
  assertEquals(bugununFonGonderisi('2026-10-13')?.tur, 'fon_akisi');
  assertEquals(bugununFonGonderisi('2026-10-16'), { tur: 'haftalik', baslangic: '2026-10-12', bitis: '2026-10-16' });
  assertEquals(bugununFonGonderisi('2026-10-17'), null);
  assertEquals(tufeYeniMi('2026-10-03T07:05:00Z', new Date('2026-10-05T16:40:00Z')), true);
  assertEquals(tufeYeniMi('2026-09-03T07:05:00Z', new Date('2026-10-05T16:40:00Z')), false);
});

Deno.test('onay: düğme verisi katı biçimde, 36 saat sonra bayat', () => {
  assertEquals(geriCagriCoz('o:42'), { islem: 'onayla', id: 42 });
  assertEquals(geriCagriCoz('r:7'), { islem: 'reddet', id: 7 });
  assertEquals(geriCagriCoz('o:42;drop'), null);
  assertEquals(geriCagriCoz(42), null);
  assertEquals(onaySuresiGectiMi('2026-10-13T16:40:00Z', new Date('2026-10-14T16:40:00Z')), false);
  assertEquals(onaySuresiGectiMi('2026-10-13T16:40:00Z', new Date('2026-10-15T05:00:00Z')), true);
});

// X'in (Twitter) kendi belgesindeki örnek imza: "Creating a signature".
Deno.test('OAuth 1.0a imzası X belgesindeki örnekle aynı', async () => {
  const url = 'https://api.twitter.com/1.1/statuses/update.json';
  const ek = { include_entities: 'true', status: 'Hello Ladies + Gentlemen, a signed OAuth request!' };
  const baslik = await oauthBasligi('POST', url, {
    consumerKey: 'xvz1evFS4wEEPTGEFPHBog',
    consumerSecret: 'kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw',
    token: '370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb',
    tokenSecret: 'LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE',
  }, ek, 'kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg', 1318622958);
  assertMatch(baslik, /oauth_signature="hCtSmYh%2BiHYCEqBWrE7C7hYmtUk%3D"/);
  assert(imzaTabani('post', url, { a: '!' }).startsWith('POST&https%3A%2F%2F'));
});

Deno.test('kart SVG: metin kaçırılır, "Yatırım tavsiyesi değildir" her kartta', () => {
  const t = fonAkisiTaslagi(akisOzeti(ORNEK, '2026-10-13', '2026-10-13')!);
  const svg = kartSvg({ ...t.kart, baslik: '<b>&"' } as typeof t.kart);
  assert(svg.includes('&lt;b&gt;&amp;&quot;'));
  assert(svg.includes('Yatırım tavsiyesi değildir'));
});

Deno.test('kart PNG çizilir (üç biçim)', async () => {
  const o = akisOzeti(ORNEK, '2026-10-13', '2026-10-13')!;
  const satirlar = [];
  let e = 100;
  for (let i = 0; i < 13; i++) {
    satirlar.push({ period: `${2025 + Math.floor((8 + i) / 12)}-${String(((8 + i) % 12) + 1).padStart(2, '0')}-01`, tufe_index: e });
    e *= 1.025;
  }
  const kartlar = [
    fonAkisiTaslagi(o).kart,
    haftalikTaslak({ ...o, baslangic: '2026-10-06', bitis: '2026-10-10' }, [{ ad: 'Gram altın', son: '4.912 ₺', degisim: 1.8 }]).kart,
    tufeTaslagi(tufeOzeti(satirlar)!).kart,
    abdTufeTaslagi(abdTufeOzeti(bls([320, 320.5, 320.2, 320.9, 321.6, 322.0, 322.96], Array.from({ length: 13 }, (_, i) => 300 + i * 0.7)))!).kart,
    fedTaslagi({ tarih: '2026-10-30', eski: [4, 4.25], yeni: [3.75, 4] }).kart,
  ];
  for (const k of kartlar) {
    const png = await pngCiz(kartSvg(k));
    assertEquals([...png.slice(1, 4)].map((c) => String.fromCharCode(c)).join(''), 'PNG');
    const dosya = Deno.env.get('X_KART_CIKTI');
    if (dosya) await Deno.writeFile(`${dosya}/kart_${kartlar.indexOf(k)}.png`, png);
  }
});

// ── ABD (Türkçe) ─────────────────────────────────────────────────────────────

function bls(sa: number[], ham: number[], sonYil = 2026, sonAy = 9) {
  const seri = (id: string, v: number[]) => ({
    seriesID: id,
    data: v.map((d, i) => {
      const geri = v.length - 1 - i;
      const toplam = sonYil * 12 + sonAy - 1 - geri;
      return { year: String(Math.floor(toplam / 12)), period: `M${String((toplam % 12) + 1).padStart(2, '0')}`, value: String(d) };
    }).reverse(), // BLS en yeniyi önce verir
  });
  return { status: 'REQUEST_SUCCEEDED', Results: { series: [seri('CUSR0000SA0', sa), seri('CUUR0000SA0', ham)] } };
}

Deno.test('ABD TÜFE: aylık arındırılmış seriden, yıllık ham seriden', () => {
  const ham = Array.from({ length: 13 }, (_, i) => 300 * (1 + 0.029 * i / 12));
  const t = abdTufeOzeti(bls([320, 320.96], ham))!;
  assertEquals(t.donem, '2026-09-01');
  assertEquals(yuzde(t.aylik), '%0,3');
  assertEquals(yuzde(t.yillik), '%2,9');
  const ts = abdTufeTaslagi(t);
  assertEquals(ts.sablon_metin, "ABD'de eylül ayı enflasyonu aylık %0,3, yıllık %2,9 oldu.");
  assertEquals(metinKapisi({ metin: ts.sablon_metin }, ts).gecti, true);
  assertEquals(abdTufeOzeti({ Results: { series: [] } }), null);
  assertEquals(abdTufeOzeti(null), null);
});

Deno.test('ABD TÜFE yalnız geçen ayın verisi ve ayın ilk 20 gününde', () => {
  assertEquals(abdTufeGuncelMi('2026-09-01', '2026-10-15'), true);
  assertEquals(abdTufeGuncelMi('2026-09-01', '2026-10-24'), false);
  assertEquals(abdTufeGuncelMi('2026-08-01', '2026-10-05'), false);
  assertEquals(abdTufeGuncelMi('2025-12-01', '2026-01-13'), true);
});

Deno.test('Fed: hedef aralık değişimi bulunur, değişmediyse null', () => {
  const r = (d: string, a: number, b: number) => ({ effectiveDate: d, type: 'EFFR', percentRate: a + 0.08, targetRateFrom: a, targetRateTo: b });
  const k = fedKarariBul({ refRates: [r('2026-10-30', 3.75, 4), r('2026-10-29', 4, 4.25), r('2026-10-28', 4, 4.25)] })!;
  assertEquals(k, { tarih: '2026-10-30', eski: [4, 4.25], yeni: [3.75, 4] });
  const t = fedTaslagi(k);
  assertEquals(t.sablon_metin, 'Fed politika faizini 25 baz puan indirdi. Yeni hedef aralık %3,75–4,00, önceki aralık %4,00–4,25 idi.');
  assertEquals(metinKapisi({ metin: t.sablon_metin }, t).gecti, true);
  assertEquals(fedKarariBul({ refRates: [r('2026-10-29', 4, 4.25), r('2026-10-28', 4, 4.25)] }), null);
  assertEquals(fedKarariBul({}), null);
});

// ── Sunucu tarafı kilitler ───────────────────────────────────────────────────

const migration = await Deno.readTextFile(new URL('../migrations/0146_x_paylasim.sql', import.meta.url));
const config = await Deno.readTextFile(new URL('../config.toml', import.meta.url));
const onay = await Deno.readTextFile(new URL('../functions/x-onay/index.ts', import.meta.url));
const paylas = await Deno.readTextFile(new URL('../functions/x-paylas/index.ts', import.meta.url));

Deno.test('0146: istemciye kapalı tablo, tür+dönem benzersiz, hafta içi cron', () => {
  assert(migration.includes('force row level security'));
  assert(migration.includes('revoke all on table public.x_gonderileri from public, anon, authenticated'));
  assert(migration.includes('unique (tur, donem)'));
  assert(migration.includes("cron.schedule('x-paylas', '40 16 * * 1-5'"));
  assertEquals(/create policy/i.test(migration), false);
});

Deno.test('x-onay: JWT kapalı ama gizli başlık ve yönetici kontrolü gövdeden ÖNCE', () => {
  assert(/\[functions\.x-onay\]\s*\nverify_jwt = false/.test(config));
  const gizli = onay.indexOf('sabitZamanliEsit(baslik, tg.gizli)');
  const govde = onay.indexOf('await req.json()');
  assert(gizli > 0 && govde > gizli);
  assert(onay.indexOf("String(cq.from?.id ?? '') !== tg.sohbet") < onay.indexOf("from('x_gonderileri')"));
});

Deno.test('x-paylas: cron secret fail-closed, mod kapıları varsayılan kapalı', () => {
  assert(paylas.includes("cronSecretZorunlu(secret, 'TEFAS_NAV_CRON_SECRET')"));
  assert(paylas.includes("Deno.env.get('X_BOT_MODU') ?? 'kapali'"));
  assert(paylas.includes("Deno.env.get('X_KUR_IZINLI') === '1'"));
  // x-paylas X'e yalnız otomatik modda ve anahtar varken yazar; o yol da
  // x-onay'daki koşullu kilidi (taslak → gonderiliyor) kullanır.
  assertEquals(/xGonder\(|xGorselYukle\(/.test(paylas), false);
  assert(paylas.includes("mod === 'otomatik' ? xKimligi() : null"));
  assert(paylas.includes(".eq('id', id).eq('durum', 'taslak').select('id')"));
});

Deno.test('botModu: yalnız bilinen değerler, gerisi kapalı (fail-closed)', () => {
  assertEquals(botModu(undefined), 'kapali');
  assertEquals(botModu(''), 'kapali');
  assertEquals(botModu('acik'), 'kapali');
  assertEquals(botModu('YAYIN'), 'kapali');
  assertEquals(botModu('taslak'), 'taslak');
  assertEquals(botModu(' yayin\n'), 'yayin');
  assertEquals(botModu('otomatik'), 'otomatik');
  assertEquals(xeGonderir('taslak'), false);
  assertEquals(xeGonderir('kapali'), false);
  assertEquals(xeGonderir('yayin'), true);
  assertEquals(xeGonderir('otomatik'), true);
});
