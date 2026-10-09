// Kilit ekranı "günü sürükleyen" satırı (goz_alici madde 4) — sunucu tarafı.
//
// Metin vektörleri `test/kilit_surukleyen_test.dart` ile AYNI: iki taraf
// aynı girdiden aynı metni üretmeli, yoksa uygulama açıkken ve kapalıyken
// kilit ekranı farklı yazar.
//
//   deno test supabase/tests/kilit_surukleyen_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ileriTasi,
  satirSurukleyeni,
  surukleyenMetinleri,
  tarifCoz,
} from '../functions/_shared/canli_etkinlik.ts';

const fikstur = JSON.parse(
  await Deno.readTextFile(new URL('./canli_etkinlik_parite.json', import.meta.url)),
);

Deno.test('metinler Dart ile aynı vektörlerde aynı', () => {
  assertEquals(surukleyenMetinleri('X', 50000, 51910), {
    surukleyenAd: 'X',
    surukleyenPctText: '%3,82',
    surukleyenTutarText: '+₺1.910',
    surukleyenPozitif: true,
  });
  const d = surukleyenMetinleri('X', 12000, 11543.4)!;
  assertEquals(d.surukleyenPctText, '%3,81');
  assertEquals(d.surukleyenTutarText, '-₺457');
  assertEquals(d.surukleyenPozitif, false);
  assertEquals(surukleyenMetinleri('X', 100000, 100004), null);
  assertEquals(surukleyenMetinleri('X', 0, 500), null);
});

const srli = (sr: unknown) => ({ ...fikstur.tarif, sr });

Deno.test('sürükleyensiz eski tarif aynen çözülür', () => {
  const t = tarifCoz(fikstur.tarif)!;
  assertEquals(t.sr, undefined);
});

Deno.test('bozuk sürükleyen yalnız kendisi düşer, tarif kalır', () => {
  for (const bozuk of [null, { ad: '', a0: 1, v: 1 }, { ad: 'A', a0: 0, v: 1 }, {
    ad: 'A',
    a0: 1,
    v: 1,
    i: 99,
  }, { ad: 'A', a0: 1, v: 1, i: 0.5 }]) {
    const t = tarifCoz(srli(bozuk));
    assert(t !== null, JSON.stringify(bozuk));
    assertEquals(t!.sr, undefined);
  }
});

const vaka = fikstur.vakalar[0];
const kotasyonlar = () => new Map(Object.entries(vaka.kotasyonlar as Record<string, number>));

Deno.test('ileri taşıma parçanın kotasyon oranını sürükleyene uygular', () => {
  // parcalar[0] = THYAO.IS, p 300; vaka 306 → oran 1,02.
  const t = tarifCoz(srli({ ad: 'THYAO', a0: 32000, v: 33000, i: 0 }))!;
  const s = ileriTasi(t, kotasyonlar(), vaka.simdiMs, fikstur.bugun, true)!;
  assertEquals(s.surukleyen, {
    surukleyenAd: 'THYAO',
    surukleyenPctText: '%5,19',
    surukleyenTutarText: '+₺1.660',
    surukleyenPozitif: true,
  });
});

Deno.test('parçasız sürükleyen (fon) yazıldığı değerde kalır', () => {
  const t = tarifCoz(srli({ ad: 'AFT', a0: 2000, v: 1950 }))!;
  const s = ileriTasi(t, kotasyonlar(), vaka.simdiMs, fikstur.bugun, true)!;
  assertEquals(s.surukleyen?.surukleyenTutarText, '-₺50');
});

Deno.test('tutar gösterimi kapalıysa sürükleyen GİTMEZ', () => {
  const t = tarifCoz(srli({ ad: 'THYAO', a0: 32000, v: 33000, i: 0 }))!;
  const s = ileriTasi(t, kotasyonlar(), vaka.simdiMs, fikstur.bugun, false)!;
  assertEquals(s.surukleyen, null);
});

Deno.test('satırdaki metin (tarifsiz) aynen taşınır; boşsa yok', () => {
  assertEquals(
    satirSurukleyeni({
      surukleyenAd: 'THYAO',
      surukleyenPctText: '%1,00',
      surukleyenTutarText: '-₺10',
      surukleyenPozitif: false,
    }),
    {
      surukleyenAd: 'THYAO',
      surukleyenPctText: '%1,00',
      surukleyenTutarText: '-₺10',
      surukleyenPozitif: false,
    },
  );
  assertEquals(satirSurukleyeni({ surukleyenAd: '' }), null);
  assertEquals(satirSurukleyeni({}), null);
});
