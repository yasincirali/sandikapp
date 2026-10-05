// Haftalık özetin para akışı cümlesi — saf yardımcıların testleri.
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Yalnız tutulan fon.** Kullanıcının portföyünde olmayan fonun olayı
//    cümleye girmez.
// 2. **Uydurma yok.** Olay yoksa cümle `null`; yüzdesiz mesajda yüzde yok.
// 3. **Kartla aynı biçim.** Tutar uygulamadaki `isaretliTutar` gibi yazılır
//    (eksi U+2212, `Mr`/`M` kısaltması).
// 4. **Dil.** "balina" yok, al/sat yok, yön yalnız "giriş"/"çıkış".
//
// Çalıştır:
//   deno test --allow-all supabase/tests/haftalik_akis_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  fonHareketleri,
  govdeyeAkisEkle,
  hacimCumlesi,
  hacimVarliklari,
  haftalikAkisCumlesi,
  notEkiyle,
  ozetCumlesi,
  isaretliTutar,
  varlikKodu,
  yalnizAkisMesaji,
} from '../functions/_shared/haftalik_akis.ts';
import { buildWeeklyMessage } from '../functions/weekly-summary/index.ts';

const olay = (kod: string, tutar: number, deger = false, tarih = '2026-09-29') => ({
  ticker: `TEFAS:${kod}`,
  tarih,
  tutar,
  bildirime_deger: deger,
});

Deno.test('bağlantı: cümle KAPALI doğar, yüzde kapıları yerinde, aylık özet taşımaz', async () => {
  const kaynak = await Deno.readTextFile(
    new URL('../functions/weekly-summary/index.ts', import.meta.url),
  );
  // İstemci kartı bayrak arkasında; bildirim ondan önce konuşmamalı.
  assertEquals(kaynak.includes("!aylik && Deno.env.get('HAFTALIK_AKIS_SATIRI') === '1'"), true);
  // Akış cümlesi yoksa kapılar eskisi gibi susturur.
  assertEquals(kaynak.split('if (akisCumlesi === null) continue;').length - 1, 4);
  // Yüzdesiz mesaj yalnız `yalnizAkis` yolunda kurulur.
  assertEquals(kaynak.includes('? yalnizAkisMesaji(akisCumlesi!)'), true);
});

Deno.test('varlikKodu TEFAS önekini atar, büyük harfe çevirir', () => {
  assertEquals(varlikKodu('TEFAS:tte'), 'TTE');
  assertEquals(varlikKodu(' THYAO '), 'THYAO');
});

Deno.test('isaretliTutar uygulamadaki kısa biçimle aynı', () => {
  assertEquals(isaretliTutar(412e6), '+₺412,00M');
  assertEquals(isaretliTutar(-2.28e9), '−₺2,28Mr');
  assertEquals(isaretliTutar(-10.85e6), '−₺10,85M');
  assertEquals(isaretliTutar(1500), '+₺1,5K');
  assertEquals(isaretliTutar(1_234_560_000_000), '+₺1,23Tn');
  assertEquals(isaretliTutar(0), '₺0');
});

Deno.test('yalnız tutulan fonların olayı alınır', () => {
  const h = fonHareketleri(
    [olay('DOV', -2.28e9), olay('ZZZ', 9e9)],
    new Set(['DOV', 'TTE']),
  );
  assertEquals(h.map((x) => x.kod), ['DOV']);
});

Deno.test('aynı fonun hafta içi olayları toplanır; net sıfır düşer', () => {
  const h = fonHareketleri(
    [
      olay('DOV', -2e9, false, '2026-09-28'),
      olay('DOV', -1e9, true, '2026-09-29'),
      olay('TTE', 50e6),
      olay('TTE', -50e6, false, '2026-09-30'),
    ],
    new Set(['DOV', 'TTE']),
  );
  assertEquals(h, [{ kod: 'DOV', tutar: -3e9, bildirimeDeger: true }]);
});

Deno.test('sıra: önce bildirim kademesi, sonra tutar büyüklüğü', () => {
  const h = fonHareketleri(
    [olay('AAA', 900e6), olay('BBB', -100e6, true), olay('CCC', -500e6)],
    new Set(['AAA', 'BBB', 'CCC']),
  );
  assertEquals(h.map((x) => x.kod), ['BBB', 'AAA', 'CCC']);
});

Deno.test('olay yoksa cümle yok', () => {
  assertEquals(haftalikAkisCumlesi([]), null);
  assertEquals(haftalikAkisCumlesi(fonHareketleri([olay('DOV', 1e9)], new Set())), null);
});

Deno.test('tek fon: kod, yön ve tutar', () => {
  assertEquals(
    haftalikAkisCumlesi([{ kod: 'DOV', tutar: -2.28e9, bildirimeDeger: true }]),
    'DOV fonunda geçen hafta büyük para çıkışı oldu (−₺2,28Mr).',
  );
  assertEquals(
    haftalikAkisCumlesi([{ kod: 'TTE', tutar: 412e6, bildirimeDeger: false }]),
    'TTE fonunda geçen hafta büyük para girişi oldu (+₺412,00M).',
  );
});

Deno.test('iki fon: ikisi de adıyla ve yönüyle', () => {
  assertEquals(
    haftalikAkisCumlesi([
      { kod: 'DOV', tutar: -2e9, bildirimeDeger: true },
      { kod: 'TTE', tutar: 4e8, bildirimeDeger: false },
    ]),
    'Geçen hafta 2 fonunda büyük para hareketi oldu: DOV (çıkış), TTE (giriş).',
  );
});

Deno.test('üç ve üstü: ilk ikisi adıyla, kalanı sayıyla', () => {
  const h = ['AAA', 'BBB', 'CCC', 'DDD'].map((kod, i) => ({
    kod,
    tutar: (i % 2 === 0 ? -1 : 1) * (9 - i) * 1e8,
    bildirimeDeger: false,
  }));
  assertEquals(
    haftalikAkisCumlesi(h),
    'Geçen hafta 4 fonunda büyük para hareketi oldu: AAA (çıkış), BBB (giriş) ve 2 fon daha.',
  );
});

Deno.test('cümle "balina", al/sat ya da uyarı dili içermez', () => {
  const metinler = [
    haftalikAkisCumlesi([{ kod: 'DOV', tutar: -2e9, bildirimeDeger: true }])!,
    haftalikAkisCumlesi([
      { kod: 'DOV', tutar: -2e9, bildirimeDeger: true },
      { kod: 'TTE', tutar: 4e8, bildirimeDeger: false },
    ])!,
    yalnizAkisMesaji('X.').title + yalnizAkisMesaji('X.').body,
  ].join(' ').toLocaleLowerCase('tr-TR');
  for (const yasak of ['balina', ' al ', ' sat ', 'kaçırma', 'dikkat', '!']) {
    assertEquals(metinler.includes(yasak), false, yasak);
  }
});

Deno.test('yalnız akış mesajı yüzde taşımaz, ibareyi taşır', () => {
  const m = yalnizAkisMesaji('DOV fonunda geçen hafta büyük para çıkışı oldu (−₺2,28Mr).');
  assertEquals(m.title, 'Haftanın özeti');
  assertEquals(m.body.includes('%'), false);
  assertEquals(m.body.endsWith('Yatırım tavsiyesi değildir.'), true);
});

Deno.test('yüzdeli mesajın gövdesine cümle BAŞA eklenir; yoksa gövde aynen kalır', () => {
  const eski = buildWeeklyMessage(1.8, null);
  assertEquals(govdeyeAkisEkle(eski.body, null), eski.body);
  const yeni = buildWeeklyMessage(1.8, null, 'TTE fonunda geçen hafta büyük para girişi oldu (+₺412,00M).');
  assertEquals(yeni.title, eski.title);
  assertEquals(
    yeni.body,
    `TTE fonunda geçen hafta büyük para girişi oldu (+₺412,00M). ${eski.body}`,
  );
  // Üçüncü argüman verilmezse davranış BİREBİR eski (bozmama kuralı).
  assertEquals(buildWeeklyMessage(-2.4, 31.8), buildWeeklyMessage(-2.4, 31.8, null));
});

// ── hisse / kripto hacim cümlesi ────────────────────────────────────────────

const hacim = (ticker: string, tur = 'hisse_hacim_yukselis') => ({
  ticker,
  tarih: '2026-10-01',
  tutar: 35e9,
  bildirime_deger: false,
  tur,
});

Deno.test('hacim olayı fon cümlesine GİRMEZ (tutarı akış değil)', () => {
  const h = fonHareketleri(
    [hacim('THYAO.IS'), { ...olay('DOV', -2e9), tur: 'fon_cikis' }],
    new Set(['DOV', 'THYAO.IS']),
  );
  assertEquals(h.map((x) => x.kod), ['DOV']);
});

Deno.test('hacimVarliklari: yalnız tutulan, tekil, ada göre sıralı; fon olayı sayılmaz', () => {
  const adlar = hacimVarliklari(
    [
      hacim('THYAO.IS'),
      hacim('THYAO.IS', 'hisse_hacim_dusus'),
      hacim('KRIPTO:BTC', 'kripto_hacim_yukselis'),
      hacim('ASELS.IS'),
      { ...olay('DOV', -2e9), tur: 'fon_cikis' },
    ],
    new Set(['THYAO.IS', 'KRIPTO:BTC', 'TEFAS:DOV']),
  );
  assertEquals(adlar, ['BTC', 'THYAO']);
});

Deno.test('hacim cümlesi: 1, 2 ve 3+ varlık; yön ve tutar yazmaz', () => {
  assertEquals(hacimCumlesi([]), null);
  assertEquals(hacimCumlesi(['ASTOR']), 'Geçen hafta olağandışı hacim görülen varlık: ASTOR.');
  assertEquals(
    hacimCumlesi(['ASELS', 'ASTOR']),
    'Geçen hafta olağandışı hacim görülen varlıklar: ASELS, ASTOR.',
  );
  const uc = hacimCumlesi(['ASELS', 'ASTOR', 'BTC', 'SISE'])!;
  assertEquals(uc, 'Geçen hafta olağandışı hacim görülen varlıklar: ASELS, ASTOR ve 2 varlık daha.');
  for (const yasak of ['giriş', 'çıkış', '₺', 'balina']) {
    assertEquals(uc.includes(yasak), false, yasak);
  }
});

Deno.test('ozetCumlesi fon ve hacim cümlelerini birleştirir', () => {
  assertEquals(ozetCumlesi(null, null), null);
  assertEquals(ozetCumlesi('A.', null), 'A.');
  assertEquals(ozetCumlesi(null, 'B.'), 'B.');
  assertEquals(ozetCumlesi('A.', 'B.'), 'A. B.');
});

Deno.test('notEkiyle yalnız yayındaki not varken ek yapar', () => {
  assertEquals(notEkiyle('Geçen hafta X.', false), 'Geçen hafta X.');
  assertEquals(notEkiyle('Geçen hafta X.', true), 'Geçen hafta X. Varlık notların hazır.');
});
