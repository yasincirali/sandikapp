import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/inflation_service.dart';

/// Reel getiri hesabı.
///
/// Bu testlerin varlık sebebi: rozet kullanıcıya "eridin mi?" sorusunun
/// cevabını veriyor ve o cevap TÜİK'in açıkladığı rakamla karşılaştırılacak.
/// Yanlış bir hesap, rozeti göstermemekten kötüdür — kullanıcı sayının
/// tutmadığını görür ve uygulamanın geri kalanına da güvenmez.
void main() {
  DateTime ay(int y, int m) => DateTime(y, m, 1);

  group('ayBasi', () {
    test('gün alanı düşürülür — tablo anahtarıyla aynı biçim', () {
      expect(InflationService.ayBasi(DateTime(2026, 3, 17)), ay(2026, 3));
      expect(InflationService.ayBasi(DateTime(2026, 3, 1)), ay(2026, 3));
    });
  });

  group('changePct', () {
    final endeks = {
      ay(2025, 9): 100.0,
      ay(2026, 3): 125.0,
      ay(2026, 9): 150.0,
    };

    test('endeks oranından tek bölmeyle hesaplanır', () {
      // Aylık yüzdeleri birbiriyle çarpmak her ay bir yuvarlama hatası
      // eklerdi; endeks değeri saklanmasının sebebi bu.
      //
      // `closeTo` ZORUNLU, `equals` değil: 150/125 ikili tabanda tam
      // gösterilemiyor ve sonuç 19.999999999999996 çıkıyor (150/100 ise
      // tesadüfen tam 50.0 veriyor — testi yazarken bu farkı gizlemişti).
      // Yuvarlama hatasının BÜYÜKLÜĞÜ denetleniyor; tam eşitlik beklemek
      // kayan nokta aritmetiğinde doğru bir değişmez değil.
      expect(InflationService.changePct(endeks, ay(2025, 9), ay(2026, 9)),
          closeTo(50.0, 1e-9));
      expect(InflationService.changePct(endeks, ay(2026, 3), ay(2026, 9)),
          closeTo(20.0, 1e-9));
    });

    test('gün alanı fark etmez — uçlar ay başına indirgenir', () {
      expect(
        InflationService.changePct(
            endeks, DateTime(2025, 9, 28), DateTime(2026, 9, 4)),
        50.0,
      );
    });

    test('eksik uç null döner — tahmin yürütülmez', () {
      expect(InflationService.changePct(endeks, ay(2024, 1), ay(2026, 9)), null);
      expect(InflationService.changePct(endeks, ay(2025, 9), ay(2027, 1)), null);
      expect(InflationService.changePct(const {}, ay(2025, 9), ay(2026, 9)),
          null);
    });
  });

  group('spreadPoints', () {
    test('kullanıcıya gösterilen sayı puan farkıdır', () {
      expect(InflationService.spreadPoints(46.4, 40.0), closeTo(6.4, 1e-9));
    });

    test('geride kalmak negatif puan verir', () {
      expect(InflationService.spreadPoints(30.0, 40.0), closeTo(-10.0, 1e-9));
    });
  });

  group('realReturnPct', () {
    test('bileşik reel getiri puan farkından KÜÇÜKTÜR', () {
      // Yüksek enflasyonda ikisi ayrışır: %46 nominal / %40 enflasyon
      // puan farkı 6,4 ama alım gücü artışı yalnızca ~%4,6.
      final puan = InflationService.spreadPoints(46.4, 40.0);
      final reel = InflationService.realReturnPct(46.4, 40.0);
      expect(reel, lessThan(puan));
      expect(reel, closeTo(4.5714, 1e-3));
    });

    test('enflasyona eşit nominal getiri sıfır reel getiridir', () {
      expect(InflationService.realReturnPct(40.0, 40.0), closeTo(0, 1e-9));
    });

    test('enflasyon sıfırken reel getiri nominale eşittir', () {
      expect(InflationService.realReturnPct(12.0, 0.0), closeTo(12.0, 1e-9));
    });
  });

  group('inflationForPeriod', () {
    tearDown(() => InflationService.instance.resetForTest());

    test('endeks boşken null — özellik sessizce kapalı kalır', () async {
      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.inflationForPeriod(365), null);
    });

    test('son AÇIKLANMIŞ ay kullanılır, içinde bulunulan ay değil', () async {
      // TÜİK bir ayın verisini ertesi ayın 3'ünde yayımlar; tabloda içinde
      // bulunulan ay YOKTUR. Hesap tablodaki en son aya dayanmalı.
      InflationService.instance.seedForTest({
        ay(2025, 9): 100.0,
        ay(2026, 8): 140.0,
      });
      final r = await InflationService.instance
          .inflationForPeriod(365, now: DateTime(2026, 9, 20));
      expect(r, closeTo(40.0, 1e-9));
    });
  });
}
