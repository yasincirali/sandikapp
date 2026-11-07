import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Rapor kapsam biçimleyicisi (yasin 2026-11-07, "tüm raporlarda zaman
/// aralığı belirtilmeli"): aynı ay/yıl tekrar etmez, iki dil.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  group('fmtTarihAraligi', () {
    test('aynı ay: gün aralığı bitişik, ay ve yıl bir kez', () {
      expect(fmtTarihAraligi(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
          '1–31 Ekim 2026');
    });

    test('ay sınırı: yıl bir kez', () {
      expect(fmtTarihAraligi(DateTime(2026, 10, 27), DateTime(2026, 11, 2)),
          '27 Ekim – 2 Kasım 2026');
    });

    test('yıl sınırı: iki uç tam', () {
      expect(fmtTarihAraligi(DateTime(2025, 12, 29), DateTime(2026, 1, 4)),
          '29 Aralık 2025 – 4 Ocak 2026');
    });

    test('tek gün: aralık değil tarih', () {
      expect(
          fmtTarihAraligi(DateTime(2026, 11, 6, 9), DateTime(2026, 11, 6, 18)),
          '6 Kasım 2026');
    });

    test('ters verilirse sıralanır; saat atılır', () {
      expect(
          fmtTarihAraligi(
              DateTime(2026, 11, 2, 23, 59), DateTime(2026, 10, 27)),
          '27 Ekim – 2 Kasım 2026');
    });

    test('kısa ay adı', () {
      expect(
          fmtTarihAraligi(DateTime(2026, 10, 27), DateTime(2026, 11, 2),
              kisa: true),
          '27 Eki – 2 Kas 2026');
    });

    test('İngilizce', () {
      expect(
          fmtTarihAraligi(DateTime(2026, 10, 1), DateTime(2026, 10, 31),
              dil: 'en_US'),
          '1–31 October 2026');
      expect(
          fmtTarihAraligi(DateTime(2026, 10, 27), DateTime(2026, 11, 2),
              dil: 'en_US'),
          '27 October – 2 November 2026');
    });
  });

  group('fmtTarih', () {
    test('saat yalnız biliniyorsa', () {
      expect(fmtTarih(DateTime(2026, 11, 6, 18)), '6 Kasım 2026');
      expect(fmtTarih(DateTime(2026, 11, 6, 18), saat: true),
          '6 Kasım 2026 18:00');
      // Gece yarısı = saat bilinmiyor: uydurma "00:00" yok.
      expect(fmtTarih(DateTime(2026, 11, 6), saat: true), '6 Kasım 2026');
    });
  });
}
