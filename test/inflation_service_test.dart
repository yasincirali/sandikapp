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

    test('%48,10 nominal / %36,70 TÜFE → %8,34 reel', () {
      // Ürün gereksiniminde adı geçen referans vaka. Puan farkı 11,40
      // olurdu; bileşik hesap 8,34 veriyor ve ikisi de ekranda gösteriliyor
      // (bkz. `PeriodSummary.reelGetiriPct` notu).
      expect(InflationService.realReturnPct(48.10, 36.70), closeTo(8.34, 0.01));
      expect(
          InflationService.spreadPoints(48.10, 36.70), closeTo(11.40, 1e-9));
    });

    test('negatif nominal getiri enflasyonla daha da kötüleşir', () {
      final reel = InflationService.realReturnPct(-10.0, 30.0);
      expect(reel, lessThan(-10.0));
      expect(reel, closeTo(-30.769, 1e-3));
    });

    test('deflasyonda (negatif TÜFE) reel getiri nominalden BÜYÜKTÜR', () {
      // Fiyatlar düşerken aynı nominal getiri daha fazla alım gücü demek.
      final reel = InflationService.realReturnPct(10.0, -5.0);
      expect(reel, greaterThan(10.0));
      expect(reel, closeTo(15.789, 1e-3));
    });

    test('−%100 enflasyon tanımsız — NaN döner, 0 UYDURULMAZ', () {
      // Payda sıfırlanıyor. NaN çağıran tarafta filtrelenir
      // (`PeriodSummaryService._sonluVeyaNull`); burada sessizce 0
      // dönseydi ekran "reel getirin sıfır" diye yanlış bir ölçüm yazardı.
      expect(InflationService.realReturnPct(10.0, -100.0).isNaN, isTrue);
    });
  });

  group('inflationForPeriod', () {
    tearDown(() => InflationService.instance.resetForTest());

    test('endeks boşken null — özellik sessizce kapalı kalır', () async {
      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.inflationForPeriod(365), null);
    });

    test('seri DURMUŞSA null — bayat endeksle hesap yapılmaz', () async {
      // Gerçek vaka (2026-09-14): TÜİK Ocak 2026'da baz yılını 2003=100'den
      // 2025=100'e çevirdi, eski `TP.FG.J0` serisi o ayda sona erdi. Tablo
      // 29 satırla DOLU görünüyordu ama son satır sekiz ay eskiydi.
      // Kapı olmasaydı ekran Şubat 2025 – Ocak 2026 aralığını "son 1 yılın
      // enflasyonu" diye gösterirdi.
      InflationService.instance.seedForTest({
        ay(2025, 1): 100.0,
        ay(2026, 1): 140.0,
      });
      expect(
        await InflationService.instance
            .inflationForPeriod(365, now: DateTime(2026, 9, 14)),
        isNull,
      );
    });

    test('bir aylık normal gecikme bayat SAYILMAZ', () async {
      // TÜİK ayın 3'ünde yayımlar; içinde bulunulan ay tabloda hiç yoktur.
      // Bu olağan durum kapıya takılmamalı.
      InflationService.instance.seedForTest({
        ay(2025, 9): 100.0,
        ay(2026, 8): 140.0,
      });
      final r = await InflationService.instance
          .inflationForPeriod(365, now: DateTime(2026, 9, 14));
      expect(r, isNotNull);
      expect(r!, closeTo(40.0, 1e-9));
    });

    test('isStale — boş tablo bayat sayılır', () async {
      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.isStale(), isTrue);
    });

    test('isStale — taze seri false, durmuş seri true', () async {
      InflationService.instance.seedForTest({ay(2026, 8): 140.0});
      expect(
        await InflationService.instance.isStale(now: DateTime(2026, 9, 14)),
        isFalse,
      );

      InflationService.instance.seedForTest({ay(2026, 1): 140.0});
      expect(
        await InflationService.instance.isStale(now: DateTime(2026, 9, 14)),
        isTrue,
      );
    });

    test('latestPeriod son ayı verir, boş tabloda null', () async {
      InflationService.instance.seedForTest({
        ay(2026, 6): 130.0,
        ay(2026, 8): 140.0,
      });
      expect(await InflationService.instance.latestPeriod(), ay(2026, 8));

      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.latestPeriod(), isNull);
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
