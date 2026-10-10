import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart'
    show yillikTasarrufOrani;

/// Yıllık plan rozeti fiyat metinlerinden hesaplanır (sabit '%40' değil).
/// Fiyat Remote Config'ten değişince rozet yanlış indirim vaat etmemeli.
void main() {
  test('bugünkü fiyatlar: 49×12=588, 399 → %32 (aşağı yuvarlanır)', () {
    expect(yillikTasarrufOrani('49₺/ay', '399₺/yıl'), 32);
    // 2026-10-10 fiyatı: 79,99×12=959,88; 649,99 → %32.
    expect(yillikTasarrufOrani('79,99₺/ay', '649,99₺/yıl'), 32);
    expect(yillikTasarrufOrani('49₺/ay', '349₺/yıl'), 40);
  });

  test('binlik ayraçlı ve kuruşlu fiyat', () {
    expect(yillikTasarrufOrani('129,99₺/ay', '1.099₺/yıl'), 29);
  });

  test('tasarruf yoksa ya da fiyat okunamazsa rozet yok', () {
    expect(yillikTasarrufOrani('49₺/ay', '588₺/yıl'), isNull);
    expect(yillikTasarrufOrani('49₺/ay', '700₺/yıl'), isNull);
    expect(yillikTasarrufOrani('ücretsiz', '349₺/yıl'), isNull);
    expect(yillikTasarrufOrani('0₺/ay', '349₺/yıl'), isNull);
  });
}
