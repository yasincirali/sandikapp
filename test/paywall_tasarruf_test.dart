import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart'
    show yillikTasarrufOrani;

/// Yıllık plan rozeti fiyat metinlerinden hesaplanır (sabit '%40' değil).
/// Fiyat Remote Config'ten değişince rozet yanlış indirim vaat etmemeli.
void main() {
  test('bugünkü fiyatlar: 49×12=588, 349 → %40 (aşağı yuvarlanır)', () {
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
