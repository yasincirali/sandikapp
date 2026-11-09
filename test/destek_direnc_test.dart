import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/destek_direnc.dart';

/// Destek/direnç (2026-10-17, "Seviye bilgisi" kararı). Kilitlenenler:
/// bölge sınırları serideki GERÇEK fiyatlardır (uydurma sayı yok), tek
/// dokunuş bölge değildir, kısa seride hiç bölge aranmaz.

/// 100 civarında iki kez dönen dip, 110 civarında iki kez dönen tepe;
/// sonda fiyat 105.
List<double> _testere() => [
      104, 106, 108, 110, 108, 106, 104, 102, 100, 102, //
      104, 106, 108, 109.5, 108, 106, 104, 102, 100.8, 102,
      104, 105, 105,
    ];

void main() {
  test('iki kez sınanan dip destek, iki kez sınanan tepe direnç', () {
    final s = _testere();
    final d = DestekDirenc.hesapla(s, 105)!;
    expect(d.destek, const FiyatBolgesi(alt: 100, ust: 100.8, temas: 2));
    expect(d.direnc, const FiyatBolgesi(alt: 109.5, ust: 110, temas: 2));
    expect(d.icinde, isNull);
    // Sınırlar serideki gerçek noktalar.
    for (final b in [d.destek!, d.direnc!]) {
      expect(s, contains(b.alt));
      expect(s, contains(b.ust));
    }
  });

  test('uzaklık: destekte üst sınıra, dirençte alt sınıra göre', () {
    final d = DestekDirenc.hesapla(_testere(), 105)!;
    expect(d.destek!.uzaklikPct(105), closeTo((105 / 100.8 - 1) * 100, 1e-9));
    expect(d.direnc!.uzaklikPct(105), closeTo((105 / 109.5 - 1) * 100, 1e-9));
  });

  test('fiyat bölgenin içindeyse "içinde" döner, destek/direnç değil', () {
    final d = DestekDirenc.hesapla(_testere(), 100.4)!;
    expect(d.icinde, const FiyatBolgesi(alt: 100, ust: 100.8, temas: 2));
    expect(d.destek, isNull);
    expect(d.direnc, isNotNull);
  });

  test('tek dokunuş bölge sayılmaz', () {
    // Yalnız bir dip (100) ve bir tepe (110): ikisi de tek.
    final s = <double>[
      for (var i = 0; i < 10; i++) 110 - i.toDouble(),
      for (var i = 0; i < 12; i++) 100 + i.toDouble(),
    ];
    final d = DestekDirenc.hesapla(s, s.last)!;
    expect(d.bos, isTrue);
  });

  test('kısa seri, bozuk fiyat ya da düz seri: bölge yok', () {
    expect(DestekDirenc.hesapla(List.filled(10, 5.0), 5), isNull);
    expect(DestekDirenc.hesapla(_testere(), double.nan), isNull);
    expect(DestekDirenc.hesapla(List.filled(40, 5.0), 5)!.bos, isTrue);
  });
}
