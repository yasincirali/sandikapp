// Kilit ekranı dakikalık ileri taşıma — uygulamayla parite.
//
// Kullanıcı kararı 2026-10-03: "Canlı aktiviteler her zaman 1 dk'da bir
// performans günlükle eş olmalı." Fikstür (`canli_etkinlik_parite.json`)
// Dart tarafında üretilir: her vakanın `beklenen`i, o fiyatlarda UYGULAMANIN
// (DailySummary + LiveActivityService) göstereceği metindir. Bu test sunucunun
// aynı tariften aynı metni ürettiğini kilitler.
//
//   deno test supabase/tests/canli_etkinlik_parite_test.ts
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import {
  fmtPct,
  fmtTRY,
  fmtTRYAxis,
  ileriTasi,
  istanbulGunMetni,
  paraAgirlikliPct,
  tarifCoz,
  tarifSembolleri,
  TAZE_YAZIM_MS,
} from '../functions/_shared/canli_etkinlik.ts';

const fikstur = JSON.parse(
  await Deno.readTextFile(new URL('./canli_etkinlik_parite.json', import.meta.url)),
);

Deno.test('fikstür tarifi geçerli bir tarif olarak çözülür', () => {
  const t = tarifCoz(fikstur.tarif);
  assert(t !== null);
  assertEquals(
    [...tarifSembolleri(t!)].sort(),
    ['AAPL', 'ALTIN_GRAM', 'THYAO.IS', 'USDTRY=X'],
  );
});

for (const vaka of fikstur.vakalar) {
  Deno.test(`parite: ${vaka.ad}`, () => {
    const t = tarifCoz(fikstur.tarif)!;
    const sonuc = ileriTasi(
      t,
      new Map(Object.entries(vaka.kotasyonlar as Record<string, number>)),
      vaka.simdiMs,
      fikstur.bugun,
      fikstur.tutarGoster,
    );
    assert(sonuc !== null, 'ileri taşınmalıydı');
    const b = vaka.beklenen;
    assertEquals(sonuc!.totalText, b.totalText);
    assertEquals(sonuc!.changeText, b.changeText);
    assertEquals(sonuc!.changePctText, b.changePctText);
    assertEquals(sonuc!.isPositive, b.isPositive);
    assertEquals(sonuc!.isFlatChange, b.isFlatChange);
    assertEquals(sonuc!.axisMinText, b.axisMinText);
    assertEquals(sonuc!.axisMaxText, b.axisMaxText);
    assertEquals(sonuc!.sparkline.length, b.sparkline.length);
    sonuc!.sparkline.forEach((v, i) => assertAlmostEquals(v, b.sparkline[i], 1e-9));
  });
}

Deno.test('başka günün tarifi ileri TAŞINMAZ (yeni günün açılışını sunucu bilmez)', () => {
  const t = tarifCoz(fikstur.tarif)!;
  const v = fikstur.vakalar[0];
  assertEquals(ileriTasi(t, new Map(), v.simdiMs, '2026-10-02', true), null);
});

Deno.test('taze yazım ileri TAŞINMAZ (uygulama önde, kendi rakamı gidiyor)', () => {
  const t = tarifCoz(fikstur.tarif)!;
  assertEquals(
    ileriTasi(t, new Map(), t.yazildiMs + TAZE_YAZIM_MS - 1, fikstur.bugun, true),
    null,
  );
});

Deno.test('kotasyon hiç yoksa rakam yazılı hâlde kalır (uydurma yok)', () => {
  const t = tarifCoz(fikstur.tarif)!;
  const s = ileriTasi(t, new Map(), t.yazildiMs + 2 * 60_000, fikstur.bugun, true)!;
  assertEquals(s.totalText, fmtTRY(t.toplam, 2));
});

Deno.test('akıl dışı oran (ölçek uyuşmazlığı) parçayı oynatmaz', () => {
  const t = tarifCoz(fikstur.tarif)!;
  // THYAO 300 → 3000: fiyat hareketi değil, birim/sembol hatası.
  const s = ileriTasi(
    t,
    new Map([['THYAO.IS', 3000]]),
    t.yazildiMs + 2 * 60_000,
    fikstur.bugun,
    true,
  )!;
  assertEquals(s.totalText, fmtTRY(t.toplam, 2));
});

Deno.test('tutar gizliyken eksen metni üretilmez', () => {
  const t = tarifCoz(fikstur.tarif)!;
  const s = ileriTasi(t, new Map(), t.yazildiMs + 2 * 60_000, fikstur.bugun, false)!;
  assertEquals(s.axisMinText, '');
  assertEquals(s.axisMaxText, '');
});

Deno.test('tanınmayan sürüm / bozuk tarif çözülmez', () => {
  assertEquals(tarifCoz({ ...fikstur.tarif, v: 2 }), null);
  assertEquals(tarifCoz({ ...fikstur.tarif, seri: [] }), null);
  assertEquals(tarifCoz({ ...fikstur.tarif, parcalar: [{ s: 'X', d: 1, p: 0 }] }), null);
  assertEquals(tarifCoz(null), null);
});

Deno.test('Türkçe biçim tr_format ile aynı', () => {
  assertEquals(fmtTRY(1234.5, 2), '₺1.234,50');
  assertEquals(fmtTRY(-1234.5, 2), '-₺1.234,50');
  assertEquals(fmtTRY(999, 2), '₺999,00');
  assertEquals(fmtPct(0.5), '%0,50');
  assertEquals(fmtTRYAxis(2_450_000, 100_000), '₺2,45M');
});

Deno.test('para ağırlıklı yüzde: akış yoksa (son − baş) / baş', () => {
  assertAlmostEquals(paraAgirlikliPct(100, 110, [])!, 10, 1e-12);
});

Deno.test('İstanbul günü UTC gece yarısından 3 saat önce döner', () => {
  // 2026-10-01 21:30 UTC = 2 Ekim 00:30 İstanbul.
  assertEquals(istanbulGunMetni(new Date(Date.UTC(2026, 9, 1, 21, 30))), '2026-10-02');
});
