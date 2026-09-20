// Kısmi kanarya kararı — `kanaryaKismiMi`.
//
// 2026-09-19: fon alarmları 9 sembolün 6'sında fiyatlanmıyordu ve tam-arıza
// kanaryası (0 fiyat) susuyordu. Bu test "yarıdan azı fiyatlandı" eşiğini
// ve tek sembollü havuzun dışarıda kalışını sabitler.
import { assertEquals } from 'jsr:@std/assert@1';
import { kanaryaKismiMi } from '../functions/_shared/kanarya.ts';

Deno.test('9 sembolün 3\'ü fiyatlandı → kısmi arıza', () => {
  assertEquals(kanaryaKismiMi(3, 9), true);
});

Deno.test('tam yarı (4/8) arıza sayılmaz; 3/8 sayılır', () => {
  assertEquals(kanaryaKismiMi(4, 8), false);
  assertEquals(kanaryaKismiMi(3, 8), true);
});

Deno.test('hepsi fiyatlandı → sessiz', () => {
  assertEquals(kanaryaKismiMi(9, 9), false);
});

Deno.test('hiçbiri fiyatlanmadı → kısmi DEĞİL (tam arıza öbür yoldan bağırır)', () => {
  assertEquals(kanaryaKismiMi(0, 9), false);
});

Deno.test('tek sembollü havuzda oran anlamsız → sessiz', () => {
  assertEquals(kanaryaKismiMi(0, 1), false);
  assertEquals(kanaryaKismiMi(1, 1), false);
});
