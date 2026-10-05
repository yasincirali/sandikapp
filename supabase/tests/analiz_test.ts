// Balina F2 — `_shared/analiz.ts` saf yardımcılarının testleri (0117).
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Ölçüm doğru.** Paket sayıları elle hesaplanan değerlerle aynı; oranın
//    paydası dönem başı büyüklük; veri yoksa paket yok (uydurma not çıkmaz).
// 2. **Rozet veriden.** Olay → büyük giriş/çıkış, olağandışı hacim; kripto
//    alıcı payı eşikleri.
// 3. **Kapılar.** Girdide olmayan, yuvarlanmış ya da hesaplanmış sayı ve
//    al/sat/hedef/kesin/balina dili reddedilir; bilinmeyen kanıt anahtarı reddedilir.
// 4. **Maliyet** ve tavan.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/analiz_test.ts

import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import {
  ayAraligi,
  dolar,
  FonGunu,
  fonPaketi,
  haftaAraligi,
  HacimSatiri,
  hacimPaketi,
  istekGovdesi,
  kapidanGecir,
  kullaniciMesaji,
  maliyetUsd,
  ozelKimlik,
  Paket,
  sonucSatiri,
  tavanaGoreModel,
  tickerdan,
  tlTutar,
  yuzde,
} from '../functions/_shared/analiz.ts';

Deno.test('dönem: haftalık son tam hafta, aylık önceki ay', () => {
  // 5 Eki 2026 Pazartesi → 28 Eyl–4 Eki.
  assertEquals(haftaAraligi('2026-10-05'), { baslangic: '2026-09-28', bitis: '2026-10-04' });
  // Pazar 4 Eki akşamı koşan iş o haftayı anlatır.
  assertEquals(haftaAraligi('2026-10-04'), { baslangic: '2026-09-28', bitis: '2026-10-04' });
  assertEquals(ayAraligi('2026-10-01'), { baslangic: '2026-09-01', bitis: '2026-09-30' });
  assertEquals(ayAraligi('2026-01-01'), { baslangic: '2025-12-01', bitis: '2025-12-31' });
});

Deno.test('biçim: Türkçe yüzde ve dolar', () => {
  assertEquals(yuzde(0.031, true), '+%3,1');
  assertEquals(yuzde(-0.0125, true), '−%1,3');
  assertEquals(dolar(212_400_000), '$212,40M');
  assertEquals(dolar(-1500, true), '−$1,5K');
  // İşaretsiz tutar '+' taşımaz (büyüklük, hacim).
  assertEquals(tlTutar(3_320_000_000), '₺3,32Mr');
  assertEquals(tlTutar(-56_370_000, true), '−₺56,37M');
});

const fonGunu = (tarih: string, net: number | null, deger: number, kisi: number | null = null): FonGunu =>
  ({ tarih, net_akis: net, portfoy_degeri: deger, yatirimci: kisi, fon_turu: 'Hisse Senedi Fonu' });

const ARALIK = { baslangic: '2026-09-28', bitis: '2026-10-04' };

Deno.test('fonPaketi: net akış, oran paydası dönem başı, fiyat etkisi, yatırımcı', () => {
  const p = fonPaketi('TEFAS:TTE', 'haftalik', ARALIK, [
    fonGunu('2026-09-25', 0, 1_000_000_000, 10_000),
    fonGunu('2026-09-28', 20_000_000, 1_030_000_000, 10_050),
    fonGunu('2026-09-29', 10_000_000, 1_045_000_000),
    fonGunu('2026-10-02', null, 1_050_000_000, 10_200),
  ], [
    { tarih: '2026-09-28', tur: 'fon_giris', tutar: 20_000_000, buyukluk_orani: 0.02 },
    { tarih: '2026-08-01', tur: 'fon_giris', tutar: 99, buyukluk_orani: 0.5 }, // dönem dışı
  ], { sira: 2, fonSayisi: 14 })!;
  const o = Object.fromEntries(p.olcumler.map((x) => [x.anahtar, x]));
  assertEquals(p.kod, 'TTE');
  assertEquals(o.net_akis.deger, 30_000_000);
  assertEquals(o.net_akis.gosterim, '+₺30,00M');
  assertAlmostEquals(o.akis_orani.deger, 0.03);
  assertEquals(o.akis_orani.gosterim, '+%3,0');
  assertAlmostEquals(o.buyukluk_degisim.deger, 0.05);
  // Büyüklük %5 arttı, %3'ü para → %2'si fiyat.
  assertAlmostEquals(o.fiyat_etkisi.deger, 0.02);
  assertEquals(o.yatirimci_degisim.gosterim, '+200');
  assertEquals(o.kategori_sira.gosterim, '2. / 14 fon');
  assertEquals(p.rozet, 'buyuk_giris');
  assertEquals(p.olaylar, ['28 Eyl büyük giriş']);
  // Akışı olan son gün 29 Eyl; 2 Eki'nin akışı bilinmiyor.
  assertEquals(p.bitis, '2026-09-29');
});

Deno.test('fonPaketi: akis_kati uygulamadaki "Hareketli" ölçüsüyle aynı (önceki haftalar, en az 3)', () => {
  // Önceki üç haftanın |net|'i 10, 20, 30 mn → ortalama 20 mn; bu hafta 50 mn → 2,5 kat.
  const gunler = [
    fonGunu('2026-09-08', -10_000_000, 1e9),
    fonGunu('2026-09-15', 15_000_000, 1e9), fonGunu('2026-09-16', 5_000_000, 1e9),
    fonGunu('2026-09-22', -30_000_000, 1e9),
    fonGunu('2026-09-28', 50_000_000, 1e9),
  ];
  const p = fonPaketi('TEFAS:TTE', 'haftalik', ARALIK, gunler, [], null)!;
  const o = Object.fromEntries(p.olcumler.map((x) => [x.anahtar, x]));
  assertAlmostEquals(o.akis_kati.deger, 2.5);
  assertEquals(o.akis_kati.gosterim, '2,5 kat');
  // İki önceki hafta yetmez: ölçek uydurulmaz.
  const az = fonPaketi('TEFAS:TTE', 'haftalik', ARALIK, gunler.slice(2), [], null)!;
  assert(!az.olcumler.some((x) => x.anahtar === 'akis_kati'));
  // Aylık notta yok (ay, haftalık ölçekle anlatılmaz).
  const ay = fonPaketi('TEFAS:TTE', 'aylik', { baslangic: '2026-09-01', bitis: '2026-09-30' }, gunler, [], null)!;
  assert(!ay.olcumler.some((x) => x.anahtar === 'akis_kati'));
});

Deno.test('fonPaketi: dönemde akış yoksa paket yok', () => {
  assertEquals(fonPaketi('TEFAS:TTE', 'haftalik', ARALIK, [
    fonGunu('2026-09-25', 5, 1e9), fonGunu('2026-09-28', null, 1e9),
  ], [], null), null);
});

Deno.test('fonPaketi: tek fonlu kategoride sıra ölçümü yok, olaysız rozet sakin', () => {
  const p = fonPaketi('TEFAS:AAA', 'haftalik', ARALIK, [
    fonGunu('2026-09-28', -1_000_000, 500_000_000),
  ], [], { sira: 1, fonSayisi: 1 })!;
  assert(!p.olcumler.some((x) => x.anahtar === 'kategori_sira'));
  assertEquals(p.rozet, 'sakin');
});

const gunler = (n: number, basla: string, para: number, kapanis = 100, pay?: number): HacimSatiri[] => {
  const out: HacimSatiri[] = [];
  const d = new Date(`${basla}T12:00:00Z`);
  for (let i = 0; i < n; i++) {
    out.push({ tarih: d.toISOString().slice(0, 10), kapanis, para_hacmi: para, alici_payi: pay ?? null });
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
};

Deno.test('hacimPaketi hisse: ortalama önceki 20 gün, kat, fiyat, olay rozeti', () => {
  const once = gunler(25, '2026-09-03', 100_000_000, 50);
  const donem = gunler(5, '2026-09-28', 300_000_000, 55);
  const p = hacimPaketi('THYAO.IS', 'hisse', 'haftalik', ARALIK, [...once, ...donem], [
    { tarih: '2026-09-29', tur: 'hisse_hacim_yukselis', tutar: 300_000_000, ortalama_kati: 3, fiyat_degisim: 0.04 },
  ])!;
  const o = Object.fromEntries(p.olcumler.map((x) => [x.anahtar, x]));
  assertEquals(p.kod, 'THYAO');
  assertEquals(o.ortalama_hacim.deger, 100_000_000);
  assertEquals(o.hacim_kati.gosterim, '3,0 kat');
  assertAlmostEquals(o.fiyat_degisim.deger, 0.1);
  assertEquals(p.rozet, 'olagandisi_hacim');
  assertEquals(p.olaylar, ['29 Eyl olağandışı yüksek hacim, fiyat yükseldi']);
});

Deno.test('hacimPaketi: 20 günden az geçmişte ortalama/kat ölçümü yok', () => {
  const p = hacimPaketi('THYAO.IS', 'hisse', 'haftalik', ARALIK,
    [...gunler(10, '2026-09-18', 1e8), ...gunler(5, '2026-09-28', 1e8)], [])!;
  assert(!p.olcumler.some((x) => x.anahtar === 'hacim_kati'));
});

Deno.test('hacimPaketi kripto: hacim ağırlıklı alıcı payı ve rozet eşikleri', () => {
  const satirlar: HacimSatiri[] = [
    { tarih: '2026-09-28', kapanis: 60000, para_hacmi: 100, alici_payi: 0.7 },
    { tarih: '2026-09-29', kapanis: 61000, para_hacmi: 300, alici_payi: 0.5 },
  ];
  const p = hacimPaketi('KRIPTO:BTC', 'kripto', 'haftalik', ARALIK, satirlar, [])!;
  const o = Object.fromEntries(p.olcumler.map((x) => [x.anahtar, x]));
  // (100·0,7 + 300·0,5) / 400 = 0,55 → eşikte alıcı istekli.
  assertAlmostEquals(o.alici_payi.deger, 0.55);
  assertAlmostEquals(o.net_alim.deger, 40);
  assertEquals(p.rozet, 'alici_istekli');
  assertEquals(p.kod, 'BTC');

  const sakin = hacimPaketi('KRIPTO:BTC', 'kripto', 'haftalik', ARALIK,
    [{ tarih: '2026-09-28', kapanis: 1, para_hacmi: 100, alici_payi: 0.5 }], [])!;
  assertEquals(sakin.rozet, 'sakin');
});

// ── Kapılar ─────────────────────────────────────────────────────────────────

const paket = (): Paket => fonPaketi('TEFAS:TTE', 'haftalik', ARALIK, [
  fonGunu('2026-09-25', 0, 1_000_000_000),
  fonGunu('2026-09-28', 30_000_000, 1_050_000_000),
], [], { sira: 2, fonSayisi: 14 })!;

const not = (metin: string, kanit = ['net_akis']) => ({
  baslik: 'Fona hafta boyunca para girdi.',
  maddeler: [{ metin, kanit }],
});

Deno.test('kapı: gösterimdeki sayılar aynen geçer', () => {
  const r = kapidanGecir(not('28 Eyl haftasında fona net +₺30,00M girdi; bu, büyüklüğün +%3,0 kadarı.',
    ['net_akis', 'akis_orani']), paket());
  assertEquals(r, { gecti: true });
  assertEquals(kapidanGecir(not('Fon kategorisinde 14 fon arasında 2. sırada.', ['kategori_sira']), paket()),
    { gecti: true });
});

Deno.test('kapı: yuvarlanmış, hesaplanmış ya da uydurma sayı reddedilir', () => {
  for (const metin of [
    'Fona yaklaşık ₺30M girdi.', // '30' gösterimde '30,00'
    'Fona net ₺30,00M girdi, bu da günlük ₺6,00M demek.', // hesap
    'Fona son 3 ayın en büyük girişi oldu.', // '3' girdide yok
  ]) {
    const r = kapidanGecir(not(metin), paket());
    assertEquals(r.gecti, false, metin);
  }
});

Deno.test('kapı: eylem, tahmin ve "balina" dili reddedilir', () => {
  for (const metin of [
    'Bu fonu satın alın, net +₺30,00M girdi.',
    'Fonda hedef fiyat yukarı yönlü.',
    'Balinalar fona +₺30,00M soktu.',
    'Fon kesin yükselecek.',
    'Bu bir fırsat olabilir.',
    'Bu not yatırım tavsiyesi değildir.',
    'Girişler önümüzdeki hafta artacak.',
  ]) {
    const r = kapidanGecir(not(metin), paket());
    assertEquals(r.gecti, false, metin);
  }
  // Betimleyici 'satış' ve 'alıcı' serbest.
  assertEquals(kapidanGecir(not('Hafta boyunca satış baskısı görülmedi, alıcılar ağır bastı.'), paket()),
    { gecti: true });
});

Deno.test('kapı: yapı ve kanıt', () => {
  assertEquals(kapidanGecir(null, paket()).gecti, false);
  assertEquals(kapidanGecir({ baslik: 'Kısa', maddeler: [] }, paket()).gecti, false);
  assertEquals(kapidanGecir(not('Fona para girdi.', ['uydurma_anahtar']), paket()).gecti, false);
  const bes = { baslik: 'Fona hafta boyunca para girdi.', maddeler: Array(5).fill({ metin: 'Fona para girdi.', kanit: [] }) };
  assertEquals(kapidanGecir(bes, paket()).gecti, false);
});

Deno.test('istek: şema, sistem önbelleği, efor; haiku efor almaz', () => {
  const g = istekGovdesi(paket(), 'claude-sonnet-5-5');
  const oc = g.output_config as Record<string, unknown>;
  assertEquals(oc.effort, 'low');
  assertEquals((oc.format as Record<string, unknown>).type, 'json_schema');
  const sys = g.system as Array<Record<string, unknown>>;
  assertEquals(sys[0].cache_control, { type: 'ephemeral' });
  assert(!('effort' in (istekGovdesi(paket(), 'claude-haiku-4-5').output_config as object)));
  const m = kullaniciMesaji(paket());
  assert(m.includes('TTE (yatırım fonu, kategori: Hisse Senedi Fonu)'));
  // Ham değer modele gitmez; yalnız gösterim.
  assert(!m.includes('"deger"'));
});

Deno.test('custom_id gidiş-dönüş ve Batch kuralı', () => {
  for (const t of ['TEFAS:TTE', 'THYAO.IS', 'KRIPTO:BTC', 'KRIPTO:1000SATS']) {
    const k = ozelKimlik(t);
    assert(/^[a-zA-Z0-9_-]{1,64}$/.test(k), k);
    assertEquals(tickerdan(k), t);
  }
});

Deno.test('maliyet: batch yarı fiyat; tavan aşılınca haiku', () => {
  // Sonnet 5.5: 1M girdi $2 + 1M çıktı $10 = $12, batch → $6.
  assertEquals(maliyetUsd('claude-sonnet-5-5', { input_tokens: 1e6, output_tokens: 1e6 }), 6);
  assertEquals(maliyetUsd('bilinmeyen', { input_tokens: 1 }), null);
  assertEquals(tavanaGoreModel('claude-sonnet-5-5', 49, 50), 'claude-sonnet-5-5');
  assertEquals(tavanaGoreModel('claude-sonnet-5-5', 50, 50), 'claude-haiku-4-5');
  assertEquals(tavanaGoreModel('claude-opus-5-5', 999, 0), 'claude-opus-5-5');
});

const B = { id: 'msgbatch_1', tur: 'haftalik', donem: '2026-09-28', model: 'claude-sonnet-5-5' };
const mesaj = (metin: string, stop = 'end_turn') => ({
  type: 'succeeded',
  message: {
    stop_reason: stop,
    content: [{ type: 'text', text: metin }],
    usage: { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 700 },
  },
});

Deno.test('sonucSatiri: geçen not yayında, rozet ve girdi paketten, maliyet yazılır', () => {
  const s = sonucSatiri(B, paket(), mesaj(JSON.stringify(
    not('Fona net +₺30,00M girdi.', ['net_akis']),
  )));
  assertEquals(s.durum, 'yayinda');
  assertEquals(s.rozet, 'sakin');
  assertEquals(s.girdi_token, 1700);
  assertEquals(s.cikti_token, 200);
  // (1000·2 + 200·10 + 700·0,2) / 1e6 · 0,5
  assertEquals(s.maliyet_usd, 0.00207);
  assertEquals((s.girdi as { kod: string }).kod, 'TTE');
});

Deno.test('sonucSatiri: red, kesilme, bozuk JSON, kapı, batch hatası', () => {
  assertEquals(sonucSatiri(B, paket(), mesaj('{}', 'refusal')).durum, 'reddedildi');
  assertEquals(sonucSatiri(B, paket(), mesaj('{"baslik":', 'max_tokens')).durum, 'reddedildi');
  assertEquals(sonucSatiri(B, paket(), mesaj('düz metin')).red_nedeni, 'yapi: json degil');
  const kapi = sonucSatiri(B, paket(), mesaj(JSON.stringify(not('Fona ₺31M girdi.'))));
  assertEquals(kapi.durum, 'reddedildi');
  assert(String(kapi.red_nedeni).startsWith('sayi:'));
  assertEquals(sonucSatiri(B, paket(), { type: 'expired' }).durum, 'hata');
});
