import { assertEquals } from 'jsr:@std/assert@1';
import { yenilemeAtlanir } from '../functions/_shared/canli_etkinlik_yenileme.ts';

const an = (dk: number) => new Date(Date.UTC(2026, 10, 27, 9, dk));

Deno.test('alan yok: bugünkü ritim, hiç atlanmaz', () => {
  assertEquals(yenilemeAtlanir({}, an(7)), false);
});

Deno.test('15 dk: yalnız 0/15/30/45 dakikalarında push', () => {
  assertEquals(yenilemeAtlanir({ yenilemeDk: 15 }, an(30)), false);
  assertEquals(yenilemeAtlanir({ yenilemeDk: 15 }, an(31)), true);
  assertEquals(yenilemeAtlanir({ yenilemeDk: 5 }, an(10)), false);
  assertEquals(yenilemeAtlanir({ yenilemeDk: 30 }, an(15)), true);
});

Deno.test('tanınmayan değer yok sayılır', () => {
  for (const v of [1, 0, -5, 7, '15x', null]) {
    assertEquals(yenilemeAtlanir({ yenilemeDk: v }, an(31)), false);
  }
});
