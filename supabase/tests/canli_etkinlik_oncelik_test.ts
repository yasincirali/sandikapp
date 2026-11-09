import { assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import {
  pushImzasi,
  pushOnceligi,
} from '../functions/_shared/canli_etkinlik_oncelik.ts';

const temel = {
  totalText: '₺1.234.567',
  changeText: '+₺1.234',
  changePctText: '+%0,10',
  isPositive: true,
  sparkline: [0.1, 0.5, 0.9],
  isMarketOpen: true,
  isLightTheme: false,
  updatedAtText: '13:05',
  dateText: '12 Ekim Pazartesi',
  sessionEndsAtUnix: 1760000000,
};

Deno.test('saat ve tarih imzayı değiştirmez', () => {
  assertEquals(
    pushImzasi(temel),
    pushImzasi({ ...temel, updatedAtText: '13:06', dateText: 'x', sessionEndsAtUnix: 1 }),
  );
});

Deno.test('görünen her rakam imzayı değiştirir', () => {
  for (const [k, v] of Object.entries({
    totalText: '₺1.234.568',
    changePctText: '+%0,11',
    isPositive: false,
    sparkline: [0.1, 0.5, 0.91],
    isMarketOpen: false,
    isLightTheme: true,
  })) {
    assertNotEquals(pushImzasi(temel), pushImzasi({ ...temel, [k]: v }), k);
  }
});

Deno.test('anahtar sırası imzayı değiştirmez', () => {
  const ters = Object.fromEntries(Object.entries(temel).reverse());
  assertEquals(pushImzasi(temel), pushImzasi(ters));
});

Deno.test('öncelik: aynı içerik 5, yeni içerik / önceki yok 10', () => {
  const imza = pushImzasi(temel);
  assertEquals(pushOnceligi(imza, imza), '5');
  assertEquals(pushOnceligi(imza, pushImzasi({ ...temel, totalText: 'x' })), '10');
  assertEquals(pushOnceligi(imza, undefined), '10');
  assertEquals(pushOnceligi(imza, null), '10');
  assertEquals(pushOnceligi(imza, ''), '10');
});
