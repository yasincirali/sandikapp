import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/insight_metrics_service.dart';

/// Düşüş / oynaklık / yoğunlaşma.
///
/// Bu testlerin ortak sorusu, `xirr_service_test` ile aynı: **yetersiz
/// veriyle sayı üretiliyor mu?** Bir risk metriğinin yanlış olması,
/// olmamasından kötüdür — kullanıcı ona bakıp pozisyon büyüklüğü seçer.
void main() {
  /// Günlük aralıklı seri kurar — ilk gün 2025-01-01.
  Map<int, double> seri(List<double> degerler, {int gunAdim = 1}) {
    final bas = DateTime(2025, 1, 1);
    final out = <int, double>{};
    for (var i = 0; i < degerler.length; i++) {
      out[bas.add(Duration(days: i * gunAdim)).millisecondsSinceEpoch] =
          degerler[i];
    }
    return out;
  }

  Asset varlik({
    required String ticker,
    required double deger,
    AssetType type = AssetType.hisse,
    String? alt,
  }) =>
      Asset(
        id: '$ticker$deger$alt',
        userId: 'u1',
        notes: '',
        name: ticker,
        ticker: ticker,
        type: type,
        subCategory: alt,
        quantity: 1,
        purchasePrice: deger,
        currentPrice: deger,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: DateTime(2025, 1, 1),
      );

  group('maxDrawdown', () {
    test('yetersiz örnekte `null` — uydurulmuş düşüş yok', () {
      expect(
        InsightMetricsService.maxDrawdown(seri([100, 90, 80])),
        isNull,
      );
    });

    test('sürekli yükselen seride düşüş sıfır (ölçüm, uydurma değil)', () {
      final d = InsightMetricsService.maxDrawdown(
        seri(List.generate(30, (i) => 100.0 + i)),
      );
      expect(d, isNotNull);
      expect(d!.isFlat, isTrue);
      expect(d.yuzde, closeTo(0, 0.001));
    });

    test('tepe→dip yüzdesi doğru', () {
      // 20 gün 100'de yatay, sonra 200'e çıkıp 150'ye iniyor.
      final degerler = <double>[
        ...List.filled(20, 100.0),
        200,
        180,
        150, // zirve 200 → dip 150 = %25
        160,
      ];
      final d = InsightMetricsService.maxDrawdown(seri(degerler));
      expect(d, isNotNull);
      expect(d!.yuzde, closeTo(25.0, 0.001));
    });

    test('toparlanmadıysa toparlanmaGun `null`', () {
      final degerler = <double>[
        ...List.filled(20, 100.0),
        200,
        120,
        130,
      ];
      final d = InsightMetricsService.maxDrawdown(seri(degerler));
      expect(d, isNotNull);
      expect(d!.toparlandi, isFalse);
      expect(d.toparlanmaGun, isNull);
    });

    test('zirveye dönüldüyse toparlanma gün sayısı ölçülür', () {
      final degerler = <double>[
        ...List.filled(20, 100.0),
        200,
        120, // dip
        150,
        200, // iki gün sonra zirveye dönüş
      ];
      final d = InsightMetricsService.maxDrawdown(seri(degerler));
      expect(d, isNotNull);
      expect(d!.toparlandi, isTrue);
      expect(d.toparlanmaGun, 2);
    });

    test('sıfır ve negatif slotlar atlanır — %100 düşüş uydurulmaz', () {
      final degerler = <double>[
        0, 0, 0, // veri başlamadan önceki boş slotlar
        ...List.filled(25, 100.0),
        95,
      ];
      final d = InsightMetricsService.maxDrawdown(seri(degerler));
      expect(d, isNotNull);
      expect(d!.yuzde, closeTo(5.0, 0.001),
          reason: '0 slotlar sayılsaydı düşüş %100 görünürdü');
    });
  });

  group('annualizedVolatility', () {
    test('yetersiz örnekte `null`', () {
      expect(
        InsightMetricsService.annualizedVolatility(
          seri([100, 101, 99, 102]),
          barSuresiGun: 1,
        ),
        isNull,
      );
    });

    test('kısa pencerede `null` — yıllıklandırma yalan olurdu', () {
      // 25 örnek var ama hepsi tek günün içinde (saatlik) → pencere 1 gün.
      final bas = DateTime(2025, 1, 1);
      final m = <int, double>{};
      for (var i = 0; i < 25; i++) {
        m[bas.add(Duration(hours: i)).millisecondsSinceEpoch] = 100.0 + i % 3;
      }
      expect(
        InsightMetricsService.annualizedVolatility(m,
            barSuresiGun: 1 / 24),
        isNull,
      );
    });

    test('sabit seride oynaklık sıfır', () {
      final v = InsightMetricsService.annualizedVolatility(
        seri(List.filled(60, 100.0)),
        barSuresiGun: 1,
      );
      expect(v, isNotNull);
      expect(v!, closeTo(0, 0.0001));
    });

    test('bar süresi yıllıklandırmayı ölçekler — sabit çarpan yok', () {
      // AYNI değer dizisi, iki farklı bar süresi.
      final degerler = List.generate(60, (i) => 100.0 * (1 + 0.01 * (i % 2)));

      final gunluk = InsightMetricsService.annualizedVolatility(
        seri(degerler),
        barSuresiGun: 1,
      );
      final haftalik = InsightMetricsService.annualizedVolatility(
        seri(degerler, gunAdim: 7),
        barSuresiGun: 7,
      );

      expect(gunluk, isNotNull);
      expect(haftalik, isNotNull);
      // Günlük bar yılda 365, haftalık 365/7 kez tekrarlanır. Aynı bar
      // standart sapmasında oran √365 / √(365/7) = √7 ≈ 2,646.
      //
      // Bu testin ASIL iddiası bu sayı değil, oranın 1 OLMAMASI: sabit bir
      // √252 çarpanı kullanılsaydı iki seri aynı oynaklığı verirdi ve
      // haftalık bar taşıyan 1Y penceresinde rakam 2,6 kat şişerdi.
      expect(gunluk! / haftalik!, closeTo(math.sqrt(7), 0.01));
    });

    test('bar süresi 0 ise `null`', () {
      expect(
        InsightMetricsService.annualizedVolatility(
          seri(List.filled(60, 100.0)),
          barSuresiGun: 0,
        ),
        isNull,
      );
    });
  });

  group('concentration', () {
    double toTRY(double v, String c) => v;

    test('boş portföyde `null`', () {
      expect(InsightMetricsService.concentration(const [], toTRY), isNull);
    });

    test('tek varlıkta pay %100', () {
      final c = InsightMetricsService.concentration(
        [varlik(ticker: 'THYAO', deger: 1000)],
        toTRY,
      );
      expect(c, isNotNull);
      expect(c!.enBuyukPay, closeTo(100, 0.001));
      expect(c.pozisyonSayisi, 1);
      expect(c.tekVarlikAgir, isTrue);
    });

    test('aynı hissenin iki lotu TEK pozisyon sayılır', () {
      final c = InsightMetricsService.concentration(
        [
          varlik(ticker: 'THYAO', deger: 600),
          varlik(ticker: 'THYAO', deger: 400),
          varlik(ticker: 'GARAN', deger: 1000),
        ],
        toTRY,
      );
      expect(c, isNotNull);
      expect(c!.pozisyonSayisi, 2,
          reason: 'iki THYAO lotu ayrı pozisyon sayılsaydı 3 çıkardı');
      expect(c.enBuyukPay, closeTo(50, 0.001));
    });

    test('dengeli portföyde tekVarlikAgir false', () {
      final c = InsightMetricsService.concentration(
        [
          varlik(ticker: 'A', deger: 100),
          varlik(ticker: 'B', deger: 100),
          varlik(ticker: 'C', deger: 100),
          varlik(ticker: 'D', deger: 100),
        ],
        toTRY,
      );
      expect(c!.enBuyukPay, closeTo(25, 0.001));
      expect(c.tekVarlikAgir, isFalse);
      // Dört eşit varlıkta HHI = 4 × 0.25² = 0.25
      expect(c.hhi, closeTo(0.25, 0.001));
    });

    test('tür payları toplamı %100', () {
      final c = InsightMetricsService.concentration(
        [
          varlik(ticker: 'THYAO', deger: 500),
          varlik(ticker: 'GAU', deger: 300, type: AssetType.altin),
          varlik(ticker: 'USD', deger: 200, type: AssetType.doviz),
        ],
        toTRY,
      );
      expect(c, isNotNull);
      final toplam = c!.turPaylari.values.fold<double>(0, (a, b) => a + b);
      expect(toplam, closeTo(100, 0.001),
          reason: 'Σ parça == bütün — kırılım değişmezi');
      expect(c.baskinTur!.tur, AssetType.hisse);
      expect(c.baskinTur!.pay, closeTo(50, 0.001));
    });

    test('satış ve silinmiş satırlar yoğunlaşmaya girmez', () {
      final satilmis = Asset(
        id: 'sell1',
        userId: 'u1',
        notes: '',
        name: 'X',
        ticker: 'X',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 9999,
        currentPrice: 9999,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: DateTime(2025, 1, 1),
        kind: AssetKind.sell,
      );
      final c = InsightMetricsService.concentration(
        [varlik(ticker: 'THYAO', deger: 1000), satilmis],
        toTRY,
      );
      expect(c!.pozisyonSayisi, 1);
      expect(c.enBuyukPay, closeTo(100, 0.001));
    });
  });
}
