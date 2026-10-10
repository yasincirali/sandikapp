// Fon X-Ray Katman A — KAP kalem ayıklamasının BEŞ KONTROLÜ ve yardımcıları
// (0132).
//
// Her kontrolün kendi başına belgeyi reddettiği ayrı ayrı sınanır; geçen
// belgede lot satırları birleşir, sayıya başka dokunulmaz. Ağ yok: PDF metni
// ve KAP satırları fixture.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  bantKontrolu,
  birlestir,
  bildirimAdresi,
  dogrula,
  donemBildirimleri,
  ekPdfNesnesi,
  fonTuru,
  HamKalem,
  istekGovdesi,
  KALEM_SEMASI,
  metinKontrolu,
  metinYeterliMi,
  oncekiAySonu,
  pdfBaytlari,
  pdrSatirlari,
  sayiOku,
  semaKontrolu,
  taramaKesinMi,
  taranacakGunler,
  tefasKontrolu,
  toplamKontrolu,
} from '../functions/_shared/fon_kalem.ts';

// Takasbank düzeninde kısa bir rapor: kod, alt satırlara kırılmış unvan,
// sonra sayılar (… DEĞER  %GRUP  %FPD  DÖVİZ  SÖZLEŞME  %FTD).
const RAPOR = `Eylül-2026
XYZ ÖRNEK PORTFÖY BİRİNCİ HİSSE SENEDİ (TL) FONU (HİSSE SENEDİ YOĞUN FON)
III-FON PORTFÖY DEĞERİ TABLOSU
Hisse
ASELS   ASELSAN
ELEKTRON
IK SANAYI
5.000,00   302,014536 29/09/26   336,500000   1.682.500,00   36,71   30,00 TL   80100511   29,80
TRAASELS91H2
ASELS   ASELSAN
ELEKTRON
IK SANAYI
1.000,00   290,000000 31/10/25   336,500000   336.500,00   13,72   11,21 TL   80100511   11,10
TRAASELS91H2
THYAO   TÜRK HAVA
YOLLARI A.O.
10.000,00   250,000000 28/07/26   300,000000   3.000.000,00   49,57   40,50 TL   80100511   40,22
TRATHYAO91M5
81,71 GRUP TOPLAMI
Ters Repo
TRT150127T13   T.C. HAZİNE   1.000.000,00   30/09/26   18,29 TL   18,10
GENEL TOPLAM 100,00 99,32 12,32 0,45 1,15 2,05
`;

const UNVAN = 'XYZ ÖRNEK PORTFÖY BİRİNCİ HİSSE SENEDİ (TL) FONU (HİSSE SENEDİ YOĞUN FON)';

function kalemler(): HamKalem[] {
  return [
    { ad: 'ASELSAN', kod: 'ASELS', tur: 'hisse', agirlik: 30, agirlik_metni: '30,00' },
    { ad: 'ASELSAN', kod: 'ASELS', tur: 'hisse', agirlik: 11.21, agirlik_metni: '11,21' },
    { ad: 'TÜRK HAVA YOLLARI', kod: 'THYAO', tur: 'hisse', agirlik: 40.5, agirlik_metni: '40,50' },
    { ad: 'T.C. HAZİNE ters repo', kod: '', tur: 'para_piyasasi', agirlik: 18.29, agirlik_metni: '18,29' },
  ];
}

const TEFAS = { hs: 80.9, tr: 18.3 };

function girdi(over: Partial<{ ks: unknown; tefas: Record<string, number> | null; unvan: string }> = {}) {
  return {
    ham: { kalemler: over.ks ?? kalemler() },
    pdfMetni: RAPOR,
    tefas: over.tefas === undefined ? TEFAS : over.tefas,
    unvan: over.unvan ?? UNVAN,
  };
}

// ── Beşi birden geçer ────────────────────────────────────────────────────────

Deno.test('dogrula: beş kontrol geçer; ASELS lotları birleşir, sıra ağırlığa göre', () => {
  const s = dogrula(girdi());
  assert(s.gecti);
  assertEquals(s.kalemler, [
    { ad: 'ASELSAN', kod: 'ASELS', tur: 'hisse', agirlik: 41.21 },
    { ad: 'TÜRK HAVA YOLLARI', kod: 'THYAO', tur: 'hisse', agirlik: 40.5 },
    { ad: 'T.C. HAZİNE ters repo', kod: '', tur: 'para_piyasasi', agirlik: 18.29 },
  ]);
  assertEquals(s.ozet.toplam, 100);
  assertEquals(s.ozet.hisse_toplam, 81.71);
  assertEquals(s.ozet.fon_turu, 'hisse_yogun');
});

// ── (5) Şema ────────────────────────────────────────────────────────────────

Deno.test('kontrol 5 (şema): bozuk yanıtın tamamı reddedilir', () => {
  const bozuklar: unknown[] = [
    null,
    { kalemler: 'yok' },
    { kalemler: [] },
    { kalemler: [...kalemler(), { ad: 'X', kod: '', tur: 'tahvil', agirlik: 1, agirlik_metni: '1,00' }] },
    { kalemler: [{ ad: 'X', kod: '', tur: 'hisse', agirlik: '1,00', agirlik_metni: '1,00' }] },
    { kalemler: [{ ad: '', kod: '', tur: 'hisse', agirlik: 1, agirlik_metni: '1,00' }] },
    { kalemler: [{ ad: 'X', kod: '', tur: 'hisse', agirlik: 0, agirlik_metni: '0,00' }] },
    { kalemler: [{ ad: 'X', kod: '', tur: 'hisse', agirlik: 101, agirlik_metni: '101,00' }] },
    { kalemler: [{ ad: 'X', tur: 'hisse', agirlik: 1, agirlik_metni: '1,00' }] },
    { kalemler: [{ ad: 'X', kod: '', tur: 'hisse', agirlik: 1, agirlik_metni: '' }] },
  ];
  for (const ham of bozuklar) {
    const s = dogrula({ ham, pdfMetni: RAPOR, tefas: TEFAS, unvan: UNVAN });
    assertEquals(s.gecti, false, JSON.stringify(ham));
    if (!s.gecti) assertEquals(s.kontrol, 'sema');
  }
  assertEquals(semaKontrolu({ kalemler: kalemler() }).ok, true);
});

// ── (1) Metin ───────────────────────────────────────────────────────────────

Deno.test('kontrol 1 (metin): metinde olmayan ağırlık belgeyi reddeder', () => {
  const ks = kalemler();
  ks[2] = { ...ks[2], agirlik: 40.51, agirlik_metni: '40,51' };
  ks[3] = { ...ks[3], agirlik: 18.28, agirlik_metni: '18,28' };
  const s = dogrula(girdi({ ks }));
  assertEquals(s.gecti, false);
  if (!s.gecti) {
    assertEquals(s.kontrol, 'metin');
    assert(s.neden.startsWith('metinde_yok'));
  }
});

Deno.test('kontrol 1 (metin): dizgi ile sayı uyuşmazsa red', () => {
  const ks = kalemler();
  ks[0] = { ...ks[0], agirlik: 30.5 }; // metni hâlâ '30,00'
  const s = dogrula(girdi({ ks }));
  assert(!s.gecti && s.kontrol === 'metin' && s.neden.startsWith('deger_uyusmuyor'));
});

Deno.test('kontrol 1 (metin): ağırlık metinde var ama kodun yanında değil → red', () => {
  // "30,00" yalnız ASELS satırında; THYAO'ya yazılırsa reddedilmeli.
  assertEquals(
    metinKontrolu([{ ad: 'THY', kod: 'THYAO', tur: 'hisse', agirlik: 30, agirlik_metni: '30,00' }], RAPOR),
    'kodun_yaninda_yok:THYAO',
  );
  assertEquals(
    metinKontrolu([{ ad: 'GARAN', kod: 'GARAN', tur: 'hisse', agirlik: 30, agirlik_metni: '30,00' }], RAPOR),
    'kod_metinde_yok:GARAN',
  );
});

Deno.test('kontrol 1 (metin): sayı parçası tam sayı sayılmaz ("2,32" ≠ "12,32")', () => {
  assertEquals(
    metinKontrolu([{ ad: 'X', kod: '', tur: 'diger', agirlik: 2.32, agirlik_metni: '2,32' }], RAPOR),
    'metinde_yok:X',
  );
  assertEquals(
    metinKontrolu([{ ad: 'X', kod: '', tur: 'diger', agirlik: 12.32, agirlik_metni: '12,32' }], RAPOR),
    null,
  );
});

Deno.test('kontrol 1 (metin): gerçek KAP düzeni (BTE Eylül 2026) — FPD sütunu kodun penceresinde', () => {
  // Canlı rapordan (kamuya açık) bir satır, pdfjs çıktısı biçiminde.
  const bte = 'ASELS   ASELSAN\nELEKTRON\nIK SANAYI\nVE\nTICARET\nA.Ş.\n' +
    '5.000,00   302,014536 29/09/26   336,500000   1.682.500,00   1,57   1,21 TL   80100511   1,17\nTRAASELS91H2\n';
  assertEquals(
    metinKontrolu([{ ad: 'ASELSAN', kod: 'ASELS', tur: 'hisse', agirlik: 1.21, agirlik_metni: '1,21' }], bte),
    null,
  );
});

// ── (2) Toplam ──────────────────────────────────────────────────────────────

Deno.test('kontrol 2 (toplam): %100 ± 1,5 dışında red', () => {
  const ks = kalemler().slice(0, 3); // ters repo yok → 81,71
  const s = dogrula(girdi({ ks, tefas: { hs: 81.71 } }));
  assert(!s.gecti && s.kontrol === 'toplam', JSON.stringify(s));
  assertEquals(toplamKontrolu([{ agirlik: 98.6 }]), null);
  assertEquals(toplamKontrolu([{ agirlik: 101.5 }]), null);
  assertEquals(toplamKontrolu([{ agirlik: 101.6 }]), 'toplam:101.60');
});

// ── (3) TEFAS ───────────────────────────────────────────────────────────────

Deno.test('kontrol 3 (TEFAS): hisse toplamı ay sonu TEFAS hs ile ± 3 puan', () => {
  const s = dogrula(girdi({ tefas: { hs: 75 } }));
  assert(!s.gecti && s.kontrol === 'tefas' && s.neden.startsWith('hisse:'));
  assertEquals(tefasKontrolu(kalemler(), { hs: 84.71 }), null);
  assertEquals(tefasKontrolu(kalemler(), { hs: 84.72 }) !== null, true);
});

Deno.test('kontrol 3 (TEFAS): yabancı hisse yhs ile karşılaştırılır', () => {
  const ks = [{ tur: 'yabanci_hisse' as const, agirlik: 98.7 }];
  assertEquals(tefasKontrolu(ks, { yhs: 98.74, tr: 0.8 }), null);
  assertEquals(tefasKontrolu(ks, { yhs: 90 }), 'yabanci_hisse:98.70~90');
});

Deno.test('kontrol 3 (TEFAS): ay sonu satırı yoksa doğrulanamaz → red', () => {
  const s = dogrula(girdi({ tefas: null }));
  assert(!s.gecti && s.kontrol === 'tefas' && s.neden === 'tefas_satiri_yok');
});

// ── (4) Yasal bant ──────────────────────────────────────────────────────────

Deno.test('kontrol 4 (bant): hisse yoğun fonda hisse < %79,5 → red', () => {
  const ks = kalemler();
  ks[2] = { ...ks[2], tur: 'borclanma' }; // THYAO'yu yanlış sınıfla
  const s = dogrula(girdi({ ks, tefas: { hs: 41.21 } }));
  assert(!s.gecti && s.kontrol === 'bant' && s.neden.startsWith('hisse_yogun'), JSON.stringify(s));
});

Deno.test('kontrol 4 (bant): türler ve bilgi vermeyen fonlar', () => {
  assertEquals(fonTuru('AK PORTFÖY YENİ TEKNOLOJİLER YABANCI HİSSE SENEDİ FONU'), 'yabanci_hisse');
  assertEquals(fonTuru(UNVAN), 'hisse_yogun');
  assertEquals(fonTuru('ATA PORTFÖY PARA PİYASASI (TL) FONU'), 'para_piyasasi');
  assertEquals(fonTuru('ANADOLU HAYAT EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU'), 'kiymetli_maden');
  assertEquals(fonTuru('X PORTFÖY KAMU BORÇLANMA ARAÇLARI FONU'), 'borclanma');
  assertEquals(fonTuru('BTE BV PORTFÖY OYUN VE TEKNOLOJİ DEĞİŞKEN FON'), 'bilgisiz');
  assertEquals(fonTuru('X PORTFÖY HİSSE SENEDİ SERBEST FON'), 'bilgisiz');
  assertEquals(fonTuru(null), 'bilgisiz');

  const maden = [{ tur: 'kiymetli_maden' as const, agirlik: 99.76 }];
  assertEquals(bantKontrolu(maden, 'ANADOLU HAYAT ALTIN KATILIM EMEKLİLİK YATIRIM FONU'), null);
  assertEquals(
    bantKontrolu([{ tur: 'kiymetli_maden', agirlik: 60 }, { tur: 'mevduat', agirlik: 40 }], 'X ALTIN FONU'),
    'kiymetli_maden:60.00',
  );
  assertEquals(
    bantKontrolu([{ tur: 'hisse', agirlik: 2 }, { tur: 'para_piyasasi', agirlik: 98 }], 'ATA PORTFÖY PARA PİYASASI (TL) FONU'),
    'para_piyasasi_hisse:2.00',
  );
  assertEquals(bantKontrolu([{ tur: 'hisse', agirlik: 10 }], 'BTE BV PORTFÖY OYUN VE TEKNOLOJİ DEĞİŞKEN FON'), null);
});

// ── Yardımcılar ─────────────────────────────────────────────────────────────

Deno.test('birlestir: aynı kod + tür toplanır, kodsuz kalem adla', () => {
  const b = birlestir([
    { ad: 'A', kod: 'aaa', tur: 'hisse', agirlik: 0.1, agirlik_metni: '0,10' },
    { ad: 'A', kod: 'AAA', tur: 'hisse', agirlik: 0.2, agirlik_metni: '0,20' },
    { ad: 'Mevduat', kod: '', tur: 'mevduat', agirlik: 1, agirlik_metni: '1,00' },
    { ad: 'mevduat', kod: '', tur: 'mevduat', agirlik: 2, agirlik_metni: '2,00' },
  ]);
  assertEquals(b, [
    { ad: 'Mevduat', kod: '', tur: 'mevduat', agirlik: 3 },
    { ad: 'A', kod: 'aaa', tur: 'hisse', agirlik: 0.3 },
  ]);
});

Deno.test('sayiOku: TR ve US biçimi, yüzde işareti, bozuk girdi', () => {
  assertEquals(sayiOku('1,21'), 1.21);
  assertEquals(sayiOku('1.234,56'), 1234.56);
  assertEquals(sayiOku('1,234.56'), 1234.56);
  assertEquals(sayiOku('%12,5'), 12.5);
  assertEquals(sayiOku('12.50'), 12.5);
  assertEquals(sayiOku('1.234.567'), 1234567);
  assertEquals(sayiOku('abc'), null);
  assertEquals(sayiOku(''), null);
});

Deno.test('metinYeterliMi: metin katmanı olmayan PDF reddedilir', () => {
  assertEquals(metinYeterliMi(RAPOR), true);
  assertEquals(metinYeterliMi(''), false);
  assertEquals(metinYeterliMi('Eylül-2026\nFON\n'.repeat(5)), false);
  assertEquals(metinYeterliMi('a'.repeat(1000)), false);
});

Deno.test('pdfBaytlari: Java serileştirme sarmalı soyulur', () => {
  const sarmal = new Uint8Array([0xac, 0xed, 0x00, 0x05, 0x75, 0x72, 0x00, 0x02, 0x5b, 0x42, ...new TextEncoder().encode('%PDF-1.5\n%x')]);
  const p = pdfBaytlari(sarmal)!;
  assertEquals(new TextDecoder().decode(p.subarray(0, 8)), '%PDF-1.5');
  assertEquals(pdfBaytlari(new TextEncoder().encode('<html>Request Rejected</html>')), null);
});

// KAP liste satırı — 2026-10-08 canlı yanıtındaki biçim.
const KAP_LISTE = [
  {
    publishDate: '08.10.2026 23:18:20', fundCode: 'BTE', subject: 'Portföy Dağılım Raporu',
    summary: 'Aylık Rapor', year: 2026, ruleType: '9. Ay', period: 9, disclosureIndex: 1678119,
  },
  { publishDate: '08.10.2026 23:18:21', fundCode: 'BTE', subject: 'Fon Gider Bilgileri', year: 2026, period: 9, disclosureIndex: 1678120 },
  // Düzeltme bildirimi: aynı dönem, daha büyük indeks kazanır.
  { fundCode: 'BTE', subject: 'Portföy Dağılım Raporu', year: 2026, period: 9, disclosureIndex: 1679000 },
  { fundCode: 'AFT', subject: 'Portföy Dağılım Raporu', year: 2026, period: 8, disclosureIndex: 1600000 },
  { fundCode: '', subject: 'Portföy Dağılım Raporu', year: 2026, period: 9, disclosureIndex: 5 },
];

Deno.test('pdrSatirlari + donemBildirimleri: yalnız PDR, dönem süzgeci, düzeltme kazanır', () => {
  const s = pdrSatirlari(KAP_LISTE);
  assertEquals(s.length, 3);
  const m = donemBildirimleri(s, 2026, 9);
  assertEquals([...m.entries()], [['BTE', 1679000]]);
  assertEquals(pdrSatirlari(null), []);
});

Deno.test('oncekiAySonu / taranacakGunler / taramaKesinMi', () => {
  assertEquals(oncekiAySonu('2026-10-10'), { donem: '2026-09-30', yil: 2026, ay: 9 });
  assertEquals(oncekiAySonu('2026-01-09'), { donem: '2025-12-31', yil: 2025, ay: 12 });
  assertEquals(oncekiAySonu('2028-03-08').donem, '2028-02-29');
  assertEquals(taranacakGunler('2026-09-30', '2026-10-03'), ['2026-10-01', '2026-10-02', '2026-10-03']);
  // Gün bitmeden (TR 23:59'dan önce) yapılan tarama kesin değil.
  assertEquals(taramaKesinMi('2026-10-08', '2026-10-08T20:59:00Z'), false);
  assertEquals(taramaKesinMi('2026-10-08', '2026-10-08T21:00:00Z'), true);
});

Deno.test('ekPdfNesnesi ve bildirim adresi', () => {
  const ek = [{ disclosure: {}, attachments: [{ objId: '4028328ca0b8418501a10b0d28f2378e', fileName: 'Fon Aylık Raporu_BTE.pdf', fileExtension: 'pdf' }] }];
  assertEquals(ekPdfNesnesi(ek), '4028328ca0b8418501a10b0d28f2378e');
  assertEquals(ekPdfNesnesi([{ attachments: [{ objId: '../x', fileExtension: 'pdf' }] }]), null);
  assertEquals(ekPdfNesnesi([{ attachments: [{ objId: 'abcdefabcdefabcdef', fileExtension: 'xls' }] }]), null);
  assertEquals(bildirimAdresi(1678119), 'https://www.kap.org.tr/tr/Bildirim/1678119');
});

Deno.test('istekGovdesi: zorunlu araç YOK (Opus 5.5\'te 400), yapılandırılmış çıktı var', () => {
  const g = istekGovdesi('metin', 'BTE', 'claude-opus-5-5');
  assertEquals('tool_choice' in g, false);
  assertEquals('tools' in g, false);
  const oc = g.output_config as Record<string, unknown>;
  assertEquals((oc.format as Record<string, unknown>).type, 'json_schema');
  assertEquals((oc.format as Record<string, unknown>).schema, KALEM_SEMASI);
  // Kullanıcı verisi yok: yalnız fon kodu ve belge metni.
  const icerik = String((g.messages as Array<{ content: string }>)[0].content);
  assert(icerik.includes('BTE') && icerik.includes('<rapor>'));
});

Deno.test('fon-kalem-raporu/index.ts: cron kapısı → bayrak → iş; ham hata dönmez', async () => {
  const src = (await Deno.readTextFile(new URL('../functions/fon-kalem-raporu/index.ts', import.meta.url)))
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  const govde = src.slice(src.indexOf('Deno.serve'));
  const kapi = govde.indexOf("cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET')");
  const yetki = govde.indexOf('cronYetkisiVarMi(request, cronSecret)');
  const bayrak = govde.indexOf("Deno.env.get('FON_KALEM_ACIK') !== '1'");
  assert(kapi > 0 && yetki > kapi && bayrak > yetki, 'sıra: secret → yetki → bayrak');
  for (const is of ['createClient(', 'tutulanFonlar(', 'gununPdrleri(', 'fonuIsle(', 'request.json()']) {
    assert(govde.indexOf(is) > bayrak, `${is} bayraktan önce`);
  }
  assertEquals(/error\.message|e\.message/.test(src), false);
  assertEquals(src.includes('tool_choice'), false);
  // Kişi bilgisi seçilmez: assets sorgusu yalnız pozisyon kolonları.
  assert(src.includes(".select('id, user_id, type, ticker, sub_category, currency, quantity, kind, added_date, ref_asset_id')"));
});
