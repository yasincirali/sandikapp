import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';

/// Zirvedeki Portföyler — cümle, sıra, eksen ve kat kuralları.
///
/// Sayı yalnız başına konuşmaz; cümleler burada sınanır ki ekran ve kart
/// aynı dili konuşsun (2026-09-29 kullanıcı kararı: "anlaşılabilir
/// ifadelerle"). Veriler o günkü gerçek anonim 30 günlük koşudan.
void main() {
  const zirvePay = {
    'altin': 55.7,
    'kripto': 17.9,
    'hisse': 12.9,
    'doviz': 7.6,
    'fon': 5.9,
  };
  const senPay = {'fon': 82.0, 'altin': 18.0};

  group('getiri cümlesi', () {
    test('kazandı / kaybetti fiille, fark puanla', () {
      final c = ZirveKiyas.getiriCumlesi(
          donem: ZirveDonem.ay, zirveRoi: 2.70, senRoi: -6.36);
      expect(
          c,
          'Bu ay zirvedeki portföy %2,7 kazandı; seninki %6,4 kaybetti. '
          'Zirveye 9,1 puan uzaksın.');
    });

    test('kullanıcı önde', () {
      expect(ZirveKiyas.mesafeCumlesi(senRoi: 5.0, zirveRoi: 2.7),
          'Zirvenin 2,3 puan önündesin.');
    });

    test('getiri yoksa uydurma sayı yok', () {
      final c = ZirveKiyas.getiriCumlesi(
          donem: ZirveDonem.hafta, zirveRoi: 1.4, senRoi: null);
      expect(c, contains('Bu hafta zirvedeki portföy %1,4 kazandı.'));
      expect(c, contains('henüz hesaplanamıyor'));
      expect(c, isNot(contains('null')));
    });

    test('sıfıra yakın getiri "yerinde saydı"', () {
      expect(ZirveKiyas.getiriParcasi(0.02), 'yerinde saydı');
      expect(ZirveKiyas.isaretliYuzde(0.02), '%0,0');
      expect(ZirveKiyas.isaretliYuzde(-6.36), '−%6,4');
    });
  });

  group('sıra ve konum', () {
    const zirve = [2.70, -3.30, -3.32];
    test('üçünün gerisinde', () {
      expect(ZirveKiyas.sira(senRoi: -6.36, zirveRoileri: zirve), 4);
      expect(ZirveKiyas.konumCumlesi(senRoi: -6.36, zirveRoileri: zirve),
          'Zirvedeki 3 portföyün gerisindesin');
    });
    test('arada', () {
      expect(ZirveKiyas.konumCumlesi(senRoi: 0.0, zirveRoileri: zirve),
          'Zirvede 2. olurdun');
    });
    test('önde', () {
      expect(ZirveKiyas.konumCumlesi(senRoi: 9.0, zirveRoileri: zirve),
          'Zirvenin önündesin');
    });
    test('getiri yok', () {
      expect(ZirveKiyas.sira(senRoi: null, zirveRoileri: zirve), isNull);
    });
  });

  group('dağılım cümlesi', () {
    test('çoğunlukla + yanında iki tür', () {
      expect(ZirveKiyas.dagilimCumlesi(zirvePay, sen: false),
          'Bu portföy çoğunlukla altın (%56), yanında kripto ve hisse.');
    });
    test('neredeyse tamamen + kalanı', () {
      expect(ZirveKiyas.dagilimCumlesi(senPay, sen: true),
          'Senin portföyün neredeyse tamamen fon (%82), kalanı altın.');
    });
    test('dengeli', () {
      expect(
          ZirveKiyas.dagilimCumlesi(
              const {'altin': 45.0, 'hisse': 40.0, 'fon': 15.0},
              sen: false),
          'Bu portföy altın ve hisse arasında dengeli, biraz fon.');
    });
    test('boş ve gürültü', () {
      expect(ZirveKiyas.dagilimCumlesi(const {}, sen: true),
          'Portföyün şu an boş.');
      // %0,5 altı tür cümleye girmez.
      expect(
          ZirveKiyas.dagilimCumlesi(const {'altin': 99.7, 'fon': 0.3},
              sen: false),
          'Bu portföy neredeyse tamamen altın (%100).');
    });
  });

  group('fark cümlesi', () {
    test('yön + tür, yönelme hâli doğru', () {
      expect(
          ZirveKiyas.farkCumlesi(
              senPay: senPay, zirvePay: zirvePay, zirveAd: 'zirve'),
          'Sen fona ağırlık vermişsin, zirve altına.');
      expect(
          ZirveKiyas.farkCumlesi(
              senPay: const {'hisse': 90.0, 'doviz': 10.0},
              zirvePay: const {'kripto': 70.0, 'emtia': 30.0},
              zirveAd: '2. portföy'),
          'Sen hisseye ağırlık vermişsin, 2. portföy kriptoya.');
    });
    test('aynı ağırlık', () {
      expect(
          ZirveKiyas.farkCumlesi(
              senPay: const {'altin': 60.0, 'fon': 40.0},
              zirvePay: zirvePay,
              zirveAd: 'zirve'),
          'İkiniz de altına ağırlık vermişsiniz; fark kalan kısımda.');
    });
    test('en büyük fark', () {
      expect(ZirveKiyas.enBuyukFarkCumlesi(senPay, zirvePay),
          'En büyük fark fon: sende %82, onda %6.');
    });
    test('bilinmeyen tür cümleyi bozmaz', () {
      expect(ZirveKiyas.turYonelme('nft'), "nft'a");
    });
  });

  group('eksen ve katlar', () {
    test('sıfır daima içeride, uçlarda pay', () {
      final e = ZirveKiyas.eksen([2.70, -3.30, -3.32, -6.36]);
      expect(e.lo, lessThan(-6.36));
      expect(e.hi, greaterThan(2.70));
      final hepsiArti = ZirveKiyas.eksen([1.0, 2.0]);
      expect(hepsiArti.lo, lessThanOrEqualTo(0));
    });

    test('çakışan işaretler üst kata çıkar', () {
      // 2. ve 3. aynı noktada; 1. ve Sen uzakta.
      final k = ZirveKiyas.katlar([0.9, 0.31, 0.30, 0.05]);
      expect(k[0], 0);
      expect(k[3], 0);
      expect({k[1], k[2]}, {0, 1});
    });

    test('üç üst üste → üç kat', () {
      final k = ZirveKiyas.katlar([0.5, 0.5, 0.5]);
      expect(k.toSet(), {0, 1, 2});
    });
  });

  test('Performans dönemi en yakın zirve dönemine eşlenir', () {
    expect(ZirveDonem.yakin(0), ZirveDonem.hafta); // GÜNLÜK
    expect(ZirveDonem.yakin(7), ZirveDonem.hafta);
    expect(ZirveDonem.yakin(30), ZirveDonem.ay);
    expect(ZirveDonem.yakin(90), ZirveDonem.ay);
    expect(ZirveDonem.yakin(180), ZirveDonem.yil);
    expect(ZirveDonem.yakin(1825), ZirveDonem.yil);
  });

  group('fon kırılımı (0084)', () {
    test('TEFAS kodu kalıbı; serbest metin "diğer"', () {
      expect(ZirveKiyas.fonAnahtari('aft'), 'AFT');
      expect(ZirveKiyas.fonAnahtari('TEFAS:TTE'), 'TTE');
      expect(ZirveKiyas.fonAnahtari('Babamın fonu'), ZirveKiyas.fonDiger);
      expect(ZirveKiyas.fonAnahtari(null), ZirveKiyas.fonDiger);
    });

    test('toplam portföyün yüzdesi; %1 altı "diğer"e katılır', () {
      final d = ZirveKiyas.fonDetayiTopla(
          const {'AFT': 250, 'TTE': 125, 'IPB': 5, ZirveKiyas.fonDiger: 5},
          1000);
      expect(d, {'AFT': 25.0, 'TTE': 12.5, ZirveKiyas.fonDiger: 1.0});
    });

    test('sıralama: büyükten küçüğe, "diğer" en sonda', () {
      final s = ZirveKiyas.fonSirali(
          const {ZirveKiyas.fonDiger: 30.0, 'TTE': 12.5, 'AFT': 25.0});
      expect(s.map((e) => e.kod), ['AFT', 'TTE', ZirveKiyas.fonDiger]);
    });

    test('özet satırı: en fazla 4 kod, kalan "diğer"de', () {
      expect(
          ZirveKiyas.fonOzeti(
              const {'AFT': 25.0, 'TTE': 12.5, ZirveKiyas.fonDiger: 1.0}),
          'AFT %25 · TTE %13 · diğer %1,0');
      expect(
          ZirveKiyas.fonOzeti(const {
            'A01': 20.0, 'A02': 15.0, 'A03': 10.0, 'A04': 8.0, 'A05': 2.0,
          }),
          'A01 %20 · A02 %15 · A03 %10 · A04 %8,0 · diğer %2,0');
      expect(ZirveKiyas.fonOzeti(const {}), '');
    });
  });
}
