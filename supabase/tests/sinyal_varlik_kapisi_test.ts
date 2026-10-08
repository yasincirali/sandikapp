// Ücretsiz planın tek sinyal varlığı kapısı (Premium planı, 2026-10-08).
//
// `ucretsizVarlikFiltresi` premium olmayan kullanıcının lotlarını seçtiği
// TEK varlığa süzer; seçim yoksa ya da seçilen varlık artık portföyde
// değilse en eski eklenen varlık (eşitlikte en küçük id) seçilir. Kapı
// `SINYAL_UCRETSIZ_VARLIK` tanımlı değilken yoktur. İstemci aynı kuralı aynalar.
//
// Çalıştır:
//   deno test supabase/tests/sinyal_varlik_kapisi_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  sinyalVarligiSec,
  type SinyalVarlikSecimi,
  ucretsizVarlikFiltresi,
} from '../functions/analyze-signals/index.ts';

type Lot = {
  id: string;
  user_id: string;
  type: string;
  ticker: string | null;
  added_date: string | null;
};

function lot(
  id: string,
  user_id: string,
  type: string,
  ticker: string | null,
  added_date: string | null,
): Lot {
  return { id, user_id, type, ticker, added_date };
}

const A = 'user-a';
const B = 'user-b';

const lotlar: Lot[] = [
  lot('1', A, 'hisse', 'THYAO', '2026-01-10'),
  lot('2', A, 'hisse', 'ASELS', '2026-02-01'),
  lot('3', A, 'fon', 'TTE', '2026-03-01'),
  lot('4', A, 'hisse', 'THYAO', '2026-04-01'), // aynı varlığın ikinci lotu
  lot('5', B, 'altin', 'GRAM', '2025-12-01'),
  lot('6', B, 'kripto', 'BTC', '2025-11-01'),
];

const ids = (l: Lot[]) => l.map((a) => a.id);
const bos = new Set<string>();

Deno.test('kapı 0 ya da tanımsız: lotlar olduğu gibi döner', () => {
  const secim: SinyalVarlikSecimi[] = [{ user_id: A, asset_type: 'fon', ticker: 'TTE' }];
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, 0, bos, secim)), ids(lotlar));
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, undefined, bos, secim)), ids(lotlar));
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, -1, bos, secim)), ids(lotlar));
});

Deno.test('premium kullanıcıya dokunulmaz', () => {
  const secim: SinyalVarlikSecimi[] = [{ user_id: A, asset_type: 'fon', ticker: 'TTE' }];
  const sonuc = ucretsizVarlikFiltresi(lotlar, 1, new Set([A, B]), secim);
  assertEquals(ids(sonuc), ids(lotlar));
  // Yalnız A premium: A'nın hepsi kalır, B tek varlığa iner.
  const kismi = ucretsizVarlikFiltresi(lotlar, 1, new Set([A]), secim);
  assertEquals(ids(kismi), ['1', '2', '3', '4', '6']);
});

Deno.test('seçilen varlık kalır, diğerleri elenir (tüm lotlarıyla)', () => {
  const secim: SinyalVarlikSecimi[] = [
    { user_id: A, asset_type: 'hisse', ticker: 'THYAO' },
    { user_id: B, asset_type: 'altin', ticker: 'GRAM' },
  ];
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, 1, bos, secim)), ['1', '4', '5']);
});

Deno.test('ticker büyük/küçük harf ve boşluk duyarsız', () => {
  const kirli = [
    lot('10', A, 'hisse', ' thyao ', '2026-01-01'),
    lot('11', A, 'hisse', 'ASELS', '2025-01-01'),
  ];
  const secim: SinyalVarlikSecimi[] = [{ user_id: A, asset_type: 'hisse', ticker: 'Thyao  ' }];
  assertEquals(ids(ucretsizVarlikFiltresi(kirli, 1, bos, secim)), ['10']);
});

Deno.test('tür de eşleşmeli: aynı ticker başka türde seçilmiş sayılmaz', () => {
  const l = [
    lot('20', A, 'hisse', 'ALTIN', '2026-01-01'),
    lot('21', A, 'emtia', 'ALTIN', '2026-02-01'),
  ];
  const secim: SinyalVarlikSecimi[] = [{ user_id: A, asset_type: 'emtia', ticker: 'ALTIN' }];
  assertEquals(ids(ucretsizVarlikFiltresi(l, 1, bos, secim)), ['21']);
});

Deno.test('seçim yoksa yedek: en eski added_date', () => {
  // A: en eski THYAO (2026-01-10) → iki THYAO lotu kalır. B: en eski BTC.
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, 1, bos, [])), ['1', '4', '6']);
});

Deno.test('yedek: added_date null sona, eşitlikte en küçük id', () => {
  const l = [
    lot('b', A, 'hisse', 'ASELS', null),
    lot('c', A, 'hisse', 'THYAO', '2026-05-01'),
    lot('a', A, 'fon', 'TTE', '2026-05-01'),
  ];
  assertEquals(sinyalVarligiSec(l), 'fon|TTE');
  const hepsiNull = [
    lot('z', A, 'hisse', 'ASELS', null),
    lot('y', A, 'hisse', 'THYAO', null),
  ];
  assertEquals(sinyalVarligiSec(hepsiNull), 'hisse|THYAO');
});

Deno.test('seçilen varlık artık portföyde yoksa yedeğe düşer', () => {
  // A, satıp elden çıkardığı KCHOL'u seçmiş: hiç sinyal almamak yerine en
  // eski varlığı (THYAO) alır.
  const secim: SinyalVarlikSecimi[] = [{ user_id: A, asset_type: 'hisse', ticker: 'KCHOL' }];
  assertEquals(ids(ucretsizVarlikFiltresi(lotlar, 1, bos, secim)), ['1', '4', '6']);
  assertEquals(
    sinyalVarligiSec(lotlar.filter((a) => a.user_id === A), {
      asset_type: 'hisse',
      ticker: 'KCHOL',
    }),
    'hisse|THYAO',
  );
});

Deno.test('lot yoksa boş', () => {
  assertEquals(ucretsizVarlikFiltresi([] as Lot[], 1, bos, []), []);
  assertEquals(sinyalVarligiSec([] as Lot[]), null);
  assertEquals(sinyalVarligiSec([] as Lot[], { asset_type: 'hisse', ticker: 'THYAO' }), null);
});
