// Alarm fiyatlarının kaynağa dağıtımı — saf.
//
// 2026-09-19 canlı raporu: `checked:9, priced:3`. Dokuz alarmın ikisi
// `TEFAS:DLY` / `TEFAS:IJC` idi ve Yahoo'ya gidip hiç fiyatlanmıyordu; fon
// alarmları sessizce ölüydü. Bu test fon sembolünün bir daha Yahoo'ya
// düşmemesini kilitler.
//
//   deno test supabase/tests/live_prices_kaynak_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { isTefasSymbol, kaynakAyir } from '../functions/_shared/live_prices.ts';

Deno.test('TEFAS: öneki fon kaynağına gider, Yahoo\'ya DEĞİL', () => {
  const r = kaynakAyir(['TEFAS:DLY', 'TEFAS:IJC', 'ALTIN_GRAM', 'USDTRY=X', 'THYAO.IS']);
  assertEquals(r.tefas, ['TEFAS:DLY', 'TEFAS:IJC']);
  assertEquals(r.truncgil, ['ALTIN_GRAM', 'USDTRY=X']);
  assertEquals(r.yahoo, ['THYAO.IS']);
});

Deno.test('her sembol tam olarak bir kaynağa düşer', () => {
  const girdi = ['ALTIN_CEYREK', 'EURTRY=X', 'TEFAS:AFT', 'KCHOL.IS', 'GC=F'];
  const r = kaynakAyir(girdi);
  assertEquals(r.truncgil.length + r.tefas.length + r.yahoo.length, girdi.length);
});

Deno.test('isTefasSymbol yalnızca öneke bakar', () => {
  assertEquals(isTefasSymbol('TEFAS:DLY'), true);
  assertEquals(isTefasSymbol('DLY'), false);
  assertEquals(isTefasSymbol('tefas:dly'), false); // sembol büyük harf saklanır
});
