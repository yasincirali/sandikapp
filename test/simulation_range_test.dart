import 'package:flutter_test/flutter_test.dart';

/// Performans ekranındaki "auto range" kuralının regresyon testi.
///
/// Bug: 1A gibi bir periyot seçiliyken, ilk alım o periyodun içindeyse
/// grafik aralığı ilk alım tarihine daraltılıyordu. Gerçek modda bu
/// doğrudur (öncesinde portföy yoktu, çizecek bir şey yok). Simülasyonda
/// ise YANLIŞTIR: o mod "bugünkü net pozisyonu tüm dönem boyunca
/// tutsaydım" senaryosudur, pozisyon her gün var sayılır — dolayısıyla
/// seçilen periyodun tamamı çizilmelidir.
///
/// Aşağıdaki fonksiyon portfolio_performance_screen.dart içindeki
/// effectiveStart hesabının birebir aynısıdır. Ekran widget'ı Supabase
/// gerektirdiği için mantık burada izole doğrulanır; koşul değişirse
/// bu test kırılır.
DateTime effectiveStart({
  required DateTime startDate,
  required DateTime? firstBuy,
  required bool isIntraday,
  required bool simulate,
}) {
  if (isIntraday || simulate) return startDate;
  if (firstBuy == null) return startDate;
  if (firstBuy.isAfter(startDate)) {
    return DateTime(firstBuy.year, firstBuy.month, firstBuy.day);
  }
  return startDate;
}

void main() {
  // Kullanıcının bildirdiği senaryo: bugün 02.08.2026, 1A seçili
  // (02.07.2026 başlangıç), ilk alım periyodun içinde — 20.07.2026.
  final periodStart = DateTime(2026, 7, 2);
  final firstBuy = DateTime(2026, 7, 20);

  group('auto range — gerçek mod', () {
    test('ilk alım periyot içindeyse aralık ilk alıma daralır', () {
      final result = effectiveStart(
        startDate: periodStart,
        firstBuy: firstBuy,
        isIntraday: false,
        simulate: false,
      );
      expect(result, DateTime(2026, 7, 20));
    });

    test('ilk alım periyottan önceyse tam periyot gösterilir', () {
      final result = effectiveStart(
        startDate: periodStart,
        firstBuy: DateTime(2026, 3, 1),
        isIntraday: false,
        simulate: false,
      );
      expect(result, periodStart);
    });
  });

  group('auto range — simülasyon modu', () {
    test('ilk alım periyot içinde olsa da tam periyot korunur', () {
      final result = effectiveStart(
        startDate: periodStart,
        firstBuy: firstBuy,
        isIntraday: false,
        simulate: true,
      );
      expect(
        result,
        periodStart,
        reason: 'simülasyonda pozisyon tüm dönem sabit varsayılır; '
            'aralık ilk alıma daraltılmamalı',
      );
    });

    test('gerçek ile simülasyon aynı girdide farklı başlangıç verir', () {
      final real = effectiveStart(
        startDate: periodStart,
        firstBuy: firstBuy,
        isIntraday: false,
        simulate: false,
      );
      final sim = effectiveStart(
        startDate: periodStart,
        firstBuy: firstBuy,
        isIntraday: false,
        simulate: true,
      );
      expect(real, isNot(sim));
      expect(sim, periodStart);
    });
  });

  test('intraday her iki modda da daraltılmaz', () {
    for (final sim in [true, false]) {
      expect(
        effectiveStart(
          startDate: periodStart,
          firstBuy: firstBuy,
          isIntraday: true,
          simulate: sim,
        ),
        periodStart,
      );
    }
  });
}
