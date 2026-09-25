// Alarm fiyatlarının kaynağa dağıtımı — saf.
//
// 2026-09-19 canlı raporu: `checked:9, priced:3`. Dokuz alarmın ikisi
// `TEFAS:DLY` / `TEFAS:IJC` idi ve Yahoo'ya gidip hiç fiyatlanmıyordu; fon
// alarmları sessizce ölüydü. Bu test fon sembolünün bir daha Yahoo'ya
// düşmemesini kilitler.
//
//   deno test supabase/tests/live_prices_kaynak_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import {
  isTefasSymbol,
  kaynakAyir,
  kriptoSatiriKotasyon,
} from '../functions/_shared/live_prices.ts';

Deno.test('TEFAS: öneki fon kaynağına gider, Yahoo\'ya DEĞİL', () => {
  const r = kaynakAyir(['TEFAS:DLY', 'TEFAS:IJC', 'ALTIN_GRAM', 'USDTRY=X', 'THYAO.IS']);
  assertEquals(r.tefas, ['TEFAS:DLY', 'TEFAS:IJC']);
  assertEquals(r.truncgil, ['ALTIN_GRAM', 'USDTRY=X']);
  assertEquals(r.yahoo, ['THYAO.IS']);
});

Deno.test('her sembol tam olarak bir kaynağa düşer', () => {
  const girdi = ['ALTIN_CEYREK', 'EURTRY=X', 'TEFAS:AFT', 'KCHOL.IS', 'GC=F', 'KRIPTO:ETH'];
  const r = kaynakAyir(girdi);
  assertEquals(
    r.truncgil.length + r.tefas.length + r.kripto.length + r.yahoo.length,
    girdi.length,
  );
});

Deno.test('isTefasSymbol yalnızca öneke bakar', () => {
  assertEquals(isTefasSymbol('TEFAS:DLY'), true);
  assertEquals(isTefasSymbol('DLY'), false);
  assertEquals(isTefasSymbol('tefas:dly'), false); // sembol büyük harf saklanır
});

// 2026-09-25: kripto alarmı. `KRIPTO:BTC` Yahoo'ya düşseydi fon hatasının
// aynısı olurdu — alarm hiç fiyatlanmaz, kullanıcı "hedefe gelmedi" sanar.
Deno.test('KRIPTO: öneki kripto kovasına gider, Yahoo\'ya DEĞİL', () => {
  const r = kaynakAyir(['KRIPTO:BTC', 'THYAO.IS', 'KRIPTO:SHIB', 'ALTIN_GRAM']);
  assertEquals(r.kripto, ['KRIPTO:BTC', 'KRIPTO:SHIB']);
  assertEquals(r.yahoo, ['THYAO.IS']);
  assertEquals(r.truncgil, ['ALTIN_GRAM']);
});

Deno.test('kripto satırı: taze fiyat + İstanbul günü değişimi', () => {
  const simdi = Date.parse('2026-09-25T12:00:00Z');
  const k = kriptoSatiriKotasyon(
    { fiyat_try: 0.00042, gun_acilis_try: 0.0004, guncellendi: '2026-09-25T11:59:00Z' },
    simdi,
  );
  assertEquals(k?.price, 0.00042);
  assertEquals(Math.round((k?.changePct ?? 0) * 1000) / 1000, 5);
});

Deno.test('kripto satırı: bayat (>10 dk) ya da bozuk satır alarmı tetiklemez', () => {
  const simdi = Date.parse('2026-09-25T12:00:00Z');
  assertEquals(
    kriptoSatiriKotasyon(
      { fiyat_try: 4_000_000, gun_acilis_try: null, guncellendi: '2026-09-25T11:49:00Z' },
      simdi,
    ),
    null,
  );
  assertEquals(
    kriptoSatiriKotasyon({ fiyat_try: 0, gun_acilis_try: null, guncellendi: '2026-09-25T11:59:00Z' }, simdi),
    null,
  );
  // Açılış yoksa değişim uydurulmaz.
  assertEquals(
    kriptoSatiriKotasyon(
      { fiyat_try: 4_000_000, gun_acilis_try: null, guncellendi: '2026-09-25T11:55:00Z' },
      simdi,
    )?.changePct,
    null,
  );
});
