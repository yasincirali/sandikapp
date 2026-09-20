// TÜFE günü push'u — saf kurallar (oranlar, ay adı, mesaj).
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { ayAdi, enflasyonOranlari, tufeMesaji } from '../functions/_shared/tufe_push.ts';

Deno.test('ay adı period tarihinden', () => {
  assertEquals(ayAdi('2026-09-01'), 'Eylül');
  assertEquals(ayAdi('2026-12-01'), 'Aralık');
  assertEquals(ayAdi('bozuk'), null);
});

Deno.test('aylık oran son iki satırdan, yıllık 13 satır varsa', () => {
  const seri = Array.from({ length: 13 }, (_, i) => ({
    period: `2025-${String(9 + i).padStart(2, '0')}-01`,
    value: 1000 * Math.pow(1.02, i),
  }));
  const o = enflasyonOranlari(seri)!;
  assertEquals(o.period, seri[12].period);
  assertEquals(Math.round(o.aylikPct * 100) / 100, 2);
  // 12 aylık bileşik %2 ≈ %26,82
  assertEquals(Math.round(o.yillikPct! * 10) / 10, 26.8);
});

Deno.test('yıllık için 13 satır yoksa null — uydurma yok', () => {
  const o = enflasyonOranlari([
    { period: '2026-08-01', value: 100 },
    { period: '2026-09-01', value: 103 },
  ])!;
  assertEquals(Math.round(o.aylikPct * 10) / 10, 3);
  assertEquals(o.yillikPct, null);
});

Deno.test('tek satır ya da sıfır değer → null', () => {
  assertEquals(enflasyonOranlari([{ period: '2026-09-01', value: 100 }]), null);
  assertEquals(
    enflasyonOranlari([{ period: '2026-08-01', value: 0 }, { period: '2026-09-01', value: 100 }]),
    null,
  );
});

Deno.test('mesaj: oran başlıkta, yıllık ve soru gövdede, Türkçe virgül', () => {
  const m = tufeMesaji('Eylül', 2.87, 31.52);
  assertEquals(m.title, 'Eylül enflasyonu %2,87');
  assertStringIncludes(m.body, 'Yıllık %31,5');
  assertStringIncludes(m.body, 'Portföyün geçti mi?');
  assertStringIncludes(m.body, 'Yatırım tavsiyesi değildir');
});

Deno.test('yıllık yoksa gövde onsuz kurulur', () => {
  const m = tufeMesaji('Eylül', 2.87, null);
  assertEquals(m.body.startsWith('Portföyün geçti mi?'), true);
});
