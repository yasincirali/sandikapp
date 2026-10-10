import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';

/// Temettü tahmini (Premium, 2026-10-10): son 12 ayın gerçekleşmiş temettüsü
/// bugünkü lotla tekrarlanır; başka bir şey tahmin edilmez.
TemettuOlayi _o(int y, int m, double pay) =>
    TemettuOlayi(hakTarihi: DateTime.utc(y, m, 15), tutarPay: pay);

void main() {
  final simdi = DateTime.utc(2026, 10, 10);

  test('son 12 ayın payı × bugünkü lot; 12 aydan eski olay girmez', () {
    final t = temettuTahmini([
      TahminGirdisi(ad: 'Tüpraş', sembol: 'TUPRS.IS', lot: 100, olaylar: [
        _o(2026, 5, 10),
        _o(2025, 11, 4),
        _o(2025, 9, 99), // 12 aydan eski
      ]),
    ], stopaj: 0.15, simdi: simdi);
    final s = t.satirlar.single;
    expect(s.brutPay, 14);
    expect(s.brutTry, 1400);
    expect(s.netTry, closeTo(1190, 1e-9));
    expect(s.aylar, [5, 11]);
    expect(t.aylik[4], 1000);
    expect(t.aylik[10], 400);
    expect(t.aylik.where((v) => v > 0), hasLength(2));
  });

  test('stopaj bilinmiyorsa net yok, brüt kalır', () {
    final t = temettuTahmini([
      TahminGirdisi(
          ad: 'A', sembol: 'A.IS', lot: 10, olaylar: [_o(2026, 3, 2)]),
    ], stopaj: null, simdi: simdi);
    expect(t.brutTry, 20);
    expect(t.netTry, isNull);
    expect(t.satirlar.single.netTry, isNull);
  });

  test('dağıtmamış ya da lotu olmayan varlık listelenmez; büyükten küçüğe', () {
    final t = temettuTahmini([
      TahminGirdisi(ad: 'Yok', sembol: 'Y.IS', lot: 10, olaylar: const []),
      TahminGirdisi(
          ad: 'Satıldı', sembol: 'S.IS', lot: 0, olaylar: [_o(2026, 1, 5)]),
      TahminGirdisi(
          ad: 'Küçük', sembol: 'K.IS', lot: 1, olaylar: [_o(2026, 1, 5)]),
      TahminGirdisi(
          ad: 'Büyük', sembol: 'B.IS', lot: 10, olaylar: [_o(2026, 2, 5)]),
    ], stopaj: 0.15, simdi: simdi);
    expect([for (final s in t.satirlar) s.ad], ['Büyük', 'Küçük']);
  });

  test('hiç girdi yoksa boş', () {
    expect(temettuTahmini(const [], stopaj: 0.15, simdi: simdi).bos, isTrue);
  });
}
