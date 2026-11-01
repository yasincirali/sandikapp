import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// `premium_ayarlari()` (0172) yanıtının okunması. Kesim ve acil durum artık
/// Remote Config'ten değil buradan gelir; yanlış okuma ya herkesi kilitler ya
/// da kilitleri kaldırır.
void main() {
  test('tam satır', () {
    final a = PremiumSunucuAyari.satirdan({
      'kapi_acik': true,
      'hediye_kesim': '2026-11-05T00:00:00+03:00',
      'acil_kapali': false,
    });
    expect(a.kapiAcik, isTrue);
    expect(a.hediyeKesim, DateTime.utc(2026, 11, 4, 21));
    expect(a.acilKapali, isFalse);
  });

  test('kesim null (hediye verilmemiş) ve eksik alanlar güvenli tarafa düşer',
      () {
    final a =
        PremiumSunucuAyari.satirdan({'kapi_acik': false, 'hediye_kesim': null});
    expect(a.hediyeKesim, isNull);
    expect(a.acilKapali, isFalse);
    expect(PremiumSunucuAyari.varsayilan.hediyeKesim, isNull);
    expect(PremiumSunucuAyari.varsayilan.acilKapali, isFalse);
  });

  test('acil kapatma okunur', () {
    expect(
        PremiumSunucuAyari.satirdan({'acil_kapali': true}).acilKapali, isTrue);
  });
}
