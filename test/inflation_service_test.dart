import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/inflation_service.dart';

/// Reel getiri hesabı.
///
/// Bu testlerin varlık sebebi: rozet kullanıcıya "eridin mi?" sorusunun
/// cevabını veriyor ve o cevap TÜİK'in açıkladığı rakamla karşılaştırılacak.
/// Yanlış bir hesap, rozeti göstermemekten kötüdür — kullanıcı sayının
/// tutmadığını görür ve uygulamanın geri kalanına da güvenmez.
void main() {
  _pencereTestleri();
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
        ay(2025, 8): 100.0,
        ay(2026, 8): 140.0,
      });
      final r = await InflationService.instance
          .inflationForPeriod(365, now: DateTime(2026, 9, 14));
      expect(r, isNotNull);
      expect(r!, closeTo(40.0, 1e-9));
    });

    test('365 gün TAM 12 AY sayar — son açıklanmış aydan geriye', () async {
      // Gerçek arıza (2026-09-14, ekran görüntüsüyle yakalandı): ana ekran
      // şeridi "TÜFE %27" yazıyordu, TÜİK'in açıkladığı yıllık %31,51
      // yerine. Sebep: pencere BUGÜNDEN 365 gün geriye gidip ay başına
      // yuvarlanıyordu (2025-09-01) ve son açıklanmış ay 2026-08 olduğu
      // için aralık 11 AY oluyordu — bir ay eksik.
      //
      // Doğrusu Ağustos 2025 → Ağustos 2026. Eylül satırı tabloda VAR ve
      // yanlış hesap onu uç seçerdi; bu test ikisini ayırt ediyor.
      InflationService.instance.seedForTest({
        ay(2025, 8): 100.0,
        ay(2025, 9): 103.0,
        ay(2026, 8): 131.51,
      });
      final r = await InflationService.instance
          .inflationForPeriod(365, now: DateTime(2026, 9, 14));
      // 11 aylık (yanlış) hesap 27,68 verirdi; 12 aylık doğru hesap 31,51.
      expect(r!, closeTo(31.51, 1e-9));
    });

    test('aySayisi gün → ay: 365→12, 180→6, 30→1', () async {
      expect(InflationService.aySayisi(365), 12);
      expect(InflationService.aySayisi(180), 6);
      expect(InflationService.aySayisi(30), 1);
      expect(InflationService.aySayisi(7), 1); // asgari bir ay
    });

    test('6A penceresi tam altı ay sayar', () async {
      InflationService.instance.seedForTest({
        ay(2026, 2): 100.0,
        ay(2026, 8): 115.0,
      });
      final r = await InflationService.instance
          .inflationForPeriod(180, now: DateTime(2026, 9, 14));
      expect(r!, closeTo(15.0, 1e-9));
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
        ay(2025, 8): 100.0,
        ay(2026, 8): 140.0,
      });
      final r = await InflationService.instance
          .inflationForPeriod(365, now: DateTime(2026, 9, 20));
      expect(r, closeTo(40.0, 1e-9));
    });
  });

  group('monthlyInflation', () {
    tearDown(() => InflationService.instance.resetForTest());

    test('son açıklanmış ayın bir önceki aya göre değişimi', () async {
      // Aylık özetin eşiği bu: TÜİK'in Ağustos 2026 için açıkladığı aylık
      // TÜFE %1,84. Yıllık %31,51'i bir aylık pencereye uygulamak o ayı
      // otomatik kayıp yazardı.
      InflationService.instance.seedForTest({
        ay(2026, 7): 100.0,
        ay(2026, 8): 101.84,
      });
      final r = await InflationService.instance
          .monthlyInflation(now: DateTime(2026, 9, 14));
      expect(r!, closeTo(1.84, 1e-9));
    });

    test('önceki ay eksikse null — eksik veriyle tahmin yürütülmez', () async {
      InflationService.instance.seedForTest({
        ay(2026, 6): 100.0,
        ay(2026, 8): 103.0,
      });
      expect(
        await InflationService.instance
            .monthlyInflation(now: DateTime(2026, 9, 14)),
        isNull,
      );
    });

    test('bayat seride null — durmuş endeksle aylık hesap yapılmaz', () async {
      InflationService.instance.seedForTest({
        ay(2025, 12): 100.0,
        ay(2026, 1): 102.0,
      });
      expect(
        await InflationService.instance
            .monthlyInflation(now: DateTime(2026, 9, 14)),
        isNull,
      );
    });

    test('boş tabloda null', () async {
      InflationService.instance.seedForTest(const {});
      expect(await InflationService.instance.monthlyInflation(), isNull);
    });
  });
}

/// TÜFE'nin karşılaştırma penceresine oturtulması (2026-09-14 incelemesi).
///
/// Kapsanan hata: 1A sekmesinde pencere İÇİNDE tek endeks noktası kalıyor,
/// taşınan son noktayla birlikte iki EŞİT değer üretiyordu. `normalizeSeries`
/// bunu düz %0 çizgisine çeviriyor, kullanıcı "bir ayda enflasyon sıfır,
/// portföyüm onu tümüyle yendi" diye okuyordu.
void _pencereTestleri() {
  final endeks = <DateTime, double>{
    DateTime(2026, 6): 100.0,
    DateTime(2026, 7): 102.0,
    DateTime(2026, 8): 104.0,
    DateTime(2026, 9): 106.0,
  };
  final simdi = DateTime(2026, 9, 14);

  group('InflationService.pencereSerisi', () {
    test('1A: taban pencereden ÖNCEKİ ay — düz çizgi değil', () {
      final out = InflationService.pencereSerisi(endeks, simdi, 30);
      final degerler = (out.keys.toList()..sort()).map((k) => out[k]!).toList();
      expect(degerler.first, 104.0,
          reason: '15 Ağustos\'ta yürürlükteki endeks Ağustos\'unkidir');
      expect(degerler.last, 106.0);
      expect(degerler.toSet().length, greaterThan(1),
          reason: 'tek değerli seri %0 düz çizgi demek');
    });

    test('taban noktası pencere BAŞINA çakılır — eksen geriye uzamaz', () {
      final out = InflationService.pencereSerisi(endeks, simdi, 30);
      final ilk = (out.keys.toList()..sort()).first;
      expect(ilk, simdi.subtract(const Duration(days: 30)).millisecondsSinceEpoch);
    });

    test('pencerede hiç açıklama yoksa boş — 1H aylık gösterge çizmez', () {
      expect(InflationService.pencereSerisi(endeks, DateTime(2026, 9, 20), 7),
          isEmpty);
    });

    test('son açıklanan ay şimdiye kadar taşınır, ara gün üretilmez', () {
      final out = InflationService.pencereSerisi(endeks, simdi, 120);
      expect(out[simdi.millisecondsSinceEpoch], 106.0);
      // Haziran…Eylül dört ay + taban + şimdi; ara gün yok.
      expect(out.length, lessThanOrEqualTo(6));
    });

    test('endeks boşsa boş döner', () {
      expect(InflationService.pencereSerisi({}, simdi, 30), isEmpty);
    });

    test('tabandan öncesi yoksa yalnızca pencere içi noktalar', () {
      final tek = {DateTime(2026, 9): 106.0};
      final out = InflationService.pencereSerisi(tek, simdi, 30);
      expect(out.values.toSet(), {106.0});
    });
  });
}
