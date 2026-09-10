import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Gün içi ("GÜNLÜK") seride FONUN günlük değişimi.
///
/// Kullanıcı bildirimi (2026-09-10): "Günlükte fon seçilince de değişim yok
/// gözüküyor ancak aslında var."
///
/// Sebep: TEFAS gün içi NAV yayınlamıyor, fon gün boyu `currentPrice` ile
/// SABİT çiziliyordu. Tür dökümündeki `first` ve `last` aynı sayı oluyor,
/// değişim tanım gereği %0 çıkıyordu — oysa iki NAV arasında gerçek bir
/// fark var.
///
/// Çözüm bir BASAMAK: gün önceki NAV ile açılır, seansın ilk gerçek fiyat
/// verisi geçildikten sonra güncel NAV'a atlar. Bu dosya o kuralı kilitler.
void main() {
  group('gunIciFonBirimFiyati', () {
    test('seans başlamadan ÖNCE önceki NAV kullanılır', () {
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: 10.0, seansBasladi: false),
        10.0,
      );
    });

    test('seans başladıktan SONRA güncel NAV kullanılır', () {
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: 10.0, seansBasladi: true),
        10.5,
      );
    });

    test('gün içi seri iki uçta FARKLI değer taşır — değişim görünür', () {
      const guncel = 10.5;
      const onceki = 10.0;
      final ilk = gunIciFonBirimFiyati(
          guncelNav: guncel, oncekiNav: onceki, seansBasladi: false);
      final son = gunIciFonBirimFiyati(
          guncelNav: guncel, oncekiNav: onceki, seansBasladi: true);
      expect(son - ilk, closeTo(0.5, 1e-9),
          reason: 'değişim NAV farkının kendisi olmalı');
      expect((son - ilk) / ilk * 100, closeTo(5.0, 1e-9));
    });

    test('önceki NAV bilinmiyorsa davranış eskisi gibi SABİT kalır', () {
      // Tek noktalı seri / elle fiyatlanan fon / TEFAS erişilemedi.
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: null, seansBasladi: false),
        10.5,
      );
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: null, seansBasladi: true),
        10.5,
      );
    });

    test('geçersiz (<=0) önceki NAV yok sayılır', () {
      // Bozuk bir NAV baz alınırsa fonun günlük değişimi %-100 gibi
      // saçma bir sayıya çıkardı.
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: 0, seansBasladi: false),
        10.5,
      );
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: -3, seansBasladi: false),
        10.5,
      );
    });

    test('NAV düştüğünde basamak da aşağı iner', () {
      final ilk = gunIciFonBirimFiyati(
          guncelNav: 9.4, oncekiNav: 10.0, seansBasladi: false);
      final son = gunIciFonBirimFiyati(
          guncelNav: 9.4, oncekiNav: 10.0, seansBasladi: true);
      expect(son, lessThan(ilk));
    });

    test('ara değer UYDURULMAZ — yalnızca iki seviye vardır', () {
      // Doğrusal rampa çizmek, fonun olmayan bir gün içi hareketini icat
      // etmek olurdu. Fonksiyon yalnızca iki değerden birini döndürebilir.
      const guncel = 12.0;
      const onceki = 11.0;
      final seviyeler = <double>{
        for (final basladi in [false, true])
          gunIciFonBirimFiyati(
              guncelNav: guncel, oncekiNav: onceki, seansBasladi: basladi),
      };
      expect(seviyeler, {onceki, guncel});
    });
  });
}
