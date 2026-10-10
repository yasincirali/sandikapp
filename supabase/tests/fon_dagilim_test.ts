// Fon X-Ray Katman B — TEFAS dağılım ayrıştırıcısının testleri (0131).
//
// Kovalanan: yüzdeler kaynaktan AYNEN (null/0 düşer, yuvarlama yok), Java
// boş metni "veri yok" (hata değil), tanınmayan gövde "hata" (yazılmaz),
// fon başına en yeni gün, eski tarihli satırın yeniyi ezmemesi, tek fon
// süzgecinin `fonKod` alanıyla yapılması ve cron kapısı.
//
// Fixture `fon_dagilim_ornek.json`: AFT satırları 2026-10-10'da canlı uçtan
// alındı; AAL ve AEA araştırma notundaki doğrulanmış değerlerden aynı
// biçimde kuruldu (tmp/arastirma/…/kamu_kaynaklari.md).

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ayristir,
  DagilimSatiri,
  enYeniSatirlar,
  gunVeyaOncesi,
  istekGovdesi,
  pencere,
  satiriAyristir,
  yazilacaklar,
} from '../functions/_shared/fon_dagilim.ts';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../functions/_shared/cron_auth.ts';

const ornek = JSON.parse(
  await Deno.readTextFile(new URL('./fon_dagilim_ornek.json', import.meta.url)),
);

Deno.test('ayristir: AFT/AAL satırları kaynaktan aynen, null ve bilFiyat düşer', () => {
  const a = ayristir(JSON.stringify(ornek.yat), 'YAT');
  assertEquals(a.durum, 'ok');
  assertEquals(a.satirlar.length, 3);
  const aft = a.satirlar.find((s) => s.fon_kodu === 'AFT' && s.tarih === '2026-10-09')!;
  assertEquals(aft.fon_tipi, 'YAT');
  assertEquals(aft.dagilim, { tr: 0.8, yhs: 98.74, yyf: 0.46 });
  const aal = a.satirlar.find((s) => s.fon_kodu === 'AAL')!;
  assertEquals(aal.dagilim, {
    dt: 10.29, fb: 9.03, hb: 3.91, tpp: 14.53, tr: 34.29,
    vmtl: 23.88, khtl: 1.19, ost: 1.48, osks: 0.7, vdm: 0.7,
  });
  // Değerler yuvarlanmadı; kaynakta olmayan sınıf (hs, km…) eklenmedi.
  assertEquals(Object.keys(aal.dagilim).length, 10);
});

Deno.test('ayristir: BES (EMK) fonu AEA kıymetli maden kolonları', () => {
  const a = ayristir(JSON.stringify(ornek.emk), 'EMK');
  assertEquals(a.durum, 'ok');
  assertEquals(a.satirlar[0], {
    fon_kodu: 'AEA',
    fon_tipi: 'EMK',
    tarih: '2025-01-31',
    dagilim: { km: 18.46, kmbyf: 17.63, kmkks: 63.67, byf: 0.19, yyf: 0.05 },
    fon_unvan: 'ANADOLU HAYAT EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU',
  });
});

Deno.test('ayristir: Java boş metni ve errorMessage "veri yok" sayılır', () => {
  assertEquals(ayristir('Index 0 out of bounds for length 0', 'YAT').durum, 'bos');
  assertEquals(
    ayristir('{"errorCode":"500","errorMessage":"Index 0 out of bounds for length 0","resultList":null}', 'YAT')
      .durum,
    'bos',
  );
  assertEquals(ayristir('{"errorCode":null,"errorMessage":null,"resultList":[]}', 'EMK').durum, 'bos');
  assertEquals(ayristir('', 'BYF').durum, 'bos');
});

Deno.test('ayristir: WAF sayfası, bozuk JSON, başka hata metni → hata (yazılmaz)', () => {
  assertEquals(ayristir('<html>Request Rejected … support BT ID</html>', 'YAT').durum, 'hata');
  assertEquals(ayristir('{"resultList":', 'YAT').durum, 'hata');
  assertEquals(
    ayristir('{"errorMessage":"Geçersiz veri: Tarih aralığı 1 ayı aşamaz","resultList":null}', 'YAT').durum,
    'hata',
  );
  assertEquals(ayristir('42', 'YAT').durum, 'hata');
});

Deno.test('satiriAyristir: yeni (bilinmeyen) küçük harfli kod korunur, saçma değer alınmaz', () => {
  const s = satiriAyristir(
    { fonKodu: 'xyz', tarih: '2026-10-09T00:00:00', hs: 50, yeni: 12.5, tutar: 1e9, bilFiyat: 3, d: -0.5 },
    'YAT',
  );
  // `yeni` biçime uyuyor → aynen; `tutar` 200'ün üstü → alınmadı;
  // camelCase `bilFiyat` yüzde değil; kod büyük harfe çevrildi.
  assertEquals(s, {
    fon_kodu: 'XYZ',
    fon_tipi: 'YAT',
    tarih: '2026-10-09',
    dagilim: { hs: 50, yeni: 12.5, d: -0.5 },
  });
});

Deno.test('satiriAyristir: kodsuz, tarihsiz ya da tüm sınıfları boş satır düşer', () => {
  assertEquals(satiriAyristir({ tarih: '2026-10-09', hs: 1 }, 'YAT'), null);
  assertEquals(satiriAyristir({ fonKodu: 'AFT', hs: 1 }, 'YAT'), null);
  assertEquals(satiriAyristir({ fonKodu: 'AFT', tarih: '2026-10-09', hs: null, tr: 0 }, 'YAT'), null);
  assertEquals(satiriAyristir({ fonKodu: 'A F', tarih: '2026-10-09', hs: 1 }, 'YAT'), null);
  assertEquals(satiriAyristir(null, 'YAT'), null);
});

Deno.test('enYeniSatirlar: fon başına en yeni gün', () => {
  const a = ayristir(JSON.stringify(ornek.yat), 'YAT');
  const e = enYeniSatirlar(a.satirlar);
  assertEquals(e.map((s) => `${s.fon_kodu}@${s.tarih}`), ['AAL@2026-10-09', 'AFT@2026-10-09']);
});

Deno.test('yazilacaklar: eski tarihli satır daha yeniyi ezmez; aynı gün güncellenir', () => {
  const s = (kod: string, tarih: string): DagilimSatiri => ({ fon_kodu: kod, fon_tipi: 'YAT', tarih, dagilim: { hs: 1 } });
  const mevcut = new Map([['AFT', '2026-10-09'], ['AAL', '2026-10-08']]);
  const y = yazilacaklar([s('AFT', '2026-10-08'), s('AAL', '2026-10-08'), s('YAC', '2026-10-01')], mevcut);
  assertEquals(y.map((x) => x.fon_kodu), ['AAL', 'YAC']);
});

Deno.test('istekGovdesi: tek fon süzgeci fonKod (ve fonKodu); evren isteğinde fonKod boş', () => {
  const tek = istekGovdesi('EMK', '20250101', '20250131', 'AEA');
  assertEquals(tek.fonKod, 'AEA');
  assertEquals(tek.fonKodu, 'AEA');
  assertEquals(tek.fonTipi, 'EMK');
  const evren = istekGovdesi('YAT', '20261005', '20261009');
  // Yalnız `fonKodu` dolu olsa bile TÜM evren dönüyor (2026-10-10 testi);
  // evren çağrısı ikisini de boş bırakır.
  assertEquals(evren.fonKod, '');
  assertEquals(evren.fonKodu, null);
  assertEquals(evren.basSira, 1);
  assertEquals(evren.dil, 'TR');
});

Deno.test('pencere: son 5 takvim günü, TR gününe göre YYYYMMDD', () => {
  // 2026-10-09 22:30 UTC = TR 10 Ekim 01:30
  assertEquals(pencere(new Date('2026-10-09T22:30:00Z')), ['20261005', '20261010']);
});

Deno.test('gunVeyaOncesi: ay sonu tatilse son iş günü', () => {
  const s = (tarih: string): DagilimSatiri => ({ fon_kodu: 'X', fon_tipi: 'YAT', tarih, dagilim: { hs: 1 } });
  const l = [s('2026-08-27'), s('2026-08-28'), s('2026-09-01')];
  assertEquals(gunVeyaOncesi(l, '2026-08-31')?.tarih, '2026-08-28');
  assertEquals(gunVeyaOncesi(l, '2026-08-01'), null);
});

Deno.test('cron kapısı: secret tanımsız 503, başlıksız/yanlış 401, doğru geçer', () => {
  const env = Deno.env.get('CRON_AUTH_ALLOW_UNSET');
  Deno.env.delete('CRON_AUTH_ALLOW_UNSET');
  try {
    assertEquals(cronSecretZorunlu(undefined, 'TEFAS_NAV_CRON_SECRET')?.status, 503);
    const bos = new Request('https://x/functions/v1/fon-dagilim', { method: 'POST' });
    assertEquals(cronYetkisiVarMi(bos, 'gizli')?.status, 401);
    const yanlis = new Request('https://x', { method: 'POST', headers: { 'x-cron-secret': 'yanlis' } });
    assertEquals(cronYetkisiVarMi(yanlis, 'gizli')?.status, 401);
    const dogru = new Request('https://x', { method: 'POST', headers: { 'x-cron-secret': 'gizli' } });
    assertEquals(cronYetkisiVarMi(dogru, 'gizli'), null);
  } finally {
    if (env !== undefined) Deno.env.set('CRON_AUTH_ALLOW_UNSET', env);
  }
});

Deno.test('fon-dagilim/index.ts: kapı her işten önce, yanıtta ham hata yok', async () => {
  const src = (await Deno.readTextFile(new URL('../functions/fon-dagilim/index.ts', import.meta.url)))
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  const govde = src.slice(src.indexOf('Deno.serve'));
  const kapi = govde.indexOf("cronSecretZorunlu(cronSecret, 'TEFAS_NAV_CRON_SECRET')");
  const yetki = govde.indexOf('cronYetkisiVarMi(request, cronSecret)');
  assert(kapi > 0 && yetki > kapi);
  for (const is of ['tefasCek(', 'createClient(', 'request.json()']) {
    assert(govde.indexOf(is) > yetki, `${is} kapıdan önce`);
  }
  assertEquals(/error\.message|e\.message/.test(src), false);
  // Silme yok: kaynak boşken mevcut satırlar korunur.
  assertEquals(/\.delete\(/.test(src), false);
});
