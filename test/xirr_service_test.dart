import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/xirr_service.dart';

/// XIRR — para ağırlıklı getiri.
///
/// Testlerin ortak sorusu: **hesaplanamayan durumda `null` mı dönüyor?**
/// Bu servisin en büyük riski yanlış bir sayı üretmesi değil, hesaplanamaz
/// bir veriden makul GÖRÜNEN bir sayı üretmesi. Kullanıcı "%23 yıllık
/// getirin var" cümlesini doğrulayamaz.
void main() {
  Asset alim({
    required DateTime tarih,
    required double tutar,
    double fx = 1,
  }) =>
      Asset(
        id: 'b${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: tutar,
        currentPrice: tutar,
        currency: 'TRY',
        purchaseFxRate: fx,
        addedDate: tarih,
      );

  Asset satis({
    required DateTime tarih,
    required double tutar,
    double fx = 1,
  }) =>
      Asset(
        id: 's${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: tutar,
        currentPrice: tutar,
        sellPrice: tutar,
        currency: 'TRY',
        purchaseFxRate: fx,
        addedDate: tarih,
        kind: AssetKind.sell,
      );

  Asset temettu({required DateTime tarih, required double tutar}) => Asset(
        id: 'd${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 0,
        purchasePrice: 0,
        currentPrice: 0,
        currency: 'TRY',
        purchaseFxRate: 1,
        dividendAmount: tutar,
        addedDate: tarih,
        kind: AssetKind.dividend,
      );

  group('XirrService.compute — bilinen sonuçlar', () {
    test('tek yıl, tek akış: %10 kazanç → ~%10 XIRR', () {
      final r = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2026, 1, 1), tutar: 1100),
      ]);
      expect(r, isNotNull);
      // 365 gün / 365 = tam 1 yıl → tam %10.
      expect(r!, closeTo(10.0, 0.05));
    });

    test('yarım yıl %10 kazanç yıllıklandırılır (~%21)', () {
      final r = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2025, 7, 2), tutar: 1100),
      ]);
      expect(r, isNotNull);
      // (1.1)^2 − 1 ≈ %21 — yarım yılda %10, yılda iki kez bileşiklenir.
      expect(r!, closeTo(21.0, 1.5));
    });

    test('zarar negatif XIRR verir', () {
      final r = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2026, 1, 1), tutar: 800),
      ]);
      expect(r, isNotNull);
      expect(r!, closeTo(-20.0, 0.1));
    });

    test('dönem ortasında ek para: zamanlama sonucu etkiler', () {
      // Aynı toplam para, aynı bitiş değeri — ama ikinci alım DAHA GEÇ.
      final erken = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2025, 2, 1), tutar: -1000),
        (tarih: DateTime(2026, 1, 1), tutar: 2400),
      ]);
      final gec = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2025, 11, 1), tutar: -1000),
        (tarih: DateTime(2026, 1, 1), tutar: 2400),
      ]);
      expect(erken, isNotNull);
      expect(gec, isNotNull);
      // Para daha KISA süre çalıştıysa aynı kâr daha yüksek yıllık orana
      // karşılık gelir. XIRR'in TWR'den ayrıldığı nokta tam burası.
      expect(gec!, greaterThan(erken!));
    });

    test('birden fazla nakit akışı — yakınsar', () {
      final r = XirrService.compute([
        (tarih: DateTime(2024, 1, 15), tutar: -5000),
        (tarih: DateTime(2024, 4, 3), tutar: -2000),
        (tarih: DateTime(2024, 9, 20), tutar: 1500),
        (tarih: DateTime(2025, 2, 11), tutar: -3000),
        (tarih: DateTime(2025, 12, 1), tutar: 11000),
      ]);
      expect(r, isNotNull);
      expect(r!.isFinite, isTrue);
    });
  });

  group('XirrService.compute — hesaplanamayan durumlar `null`', () {
    test('tek akış', () {
      expect(
        XirrService.compute([(tarih: DateTime(2025, 1, 1), tutar: -1000)]),
        isNull,
      );
    });

    test('boş liste', () {
      expect(XirrService.compute(const []), isNull);
    });

    test('hepsi negatif — kök yok', () {
      expect(
        XirrService.compute([
          (tarih: DateTime(2025, 1, 1), tutar: -1000),
          (tarih: DateTime(2026, 1, 1), tutar: -500),
        ]),
        isNull,
      );
    });

    test('hepsi pozitif — kök yok', () {
      expect(
        XirrService.compute([
          (tarih: DateTime(2025, 1, 1), tutar: 1000),
          (tarih: DateTime(2026, 1, 1), tutar: 500),
        ]),
        isNull,
      );
    });

    test('pencere minGun altında — yıllıklandırma yalan olurdu', () {
      final r = XirrService.compute([
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
        (tarih: DateTime(2025, 1, 20), tutar: 1020),
      ]);
      expect(r, isNull,
          reason: '19 günlük %2 hareket "%45 yıllık" diye gösterilmemeli');
    });

    test('sıralanmamış girdi de doğru sonuç verir', () {
      final karisik = XirrService.compute([
        (tarih: DateTime(2026, 1, 1), tutar: 1100),
        (tarih: DateTime(2025, 1, 1), tutar: -1000),
      ]);
      expect(karisik, isNotNull);
      expect(karisik!, closeTo(10.0, 0.05));
    });
  });

  group('XirrService.portfolioXirr — defterden akış', () {
    test('alım + bugünkü değer', () {
      final now = DateTime(2026, 1, 1);
      final r = XirrService.portfolioXirr(
        assets: [alim(tarih: DateTime(2025, 1, 1), tutar: 1000)],
        bugunkuDegerTRY: 1100,
        now: now,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(10.0, 0.05));
    });

    test('temettü cebe giriş sayılır — XIRR yükselir', () {
      final now = DateTime(2026, 1, 1);
      final assets = [alim(tarih: DateTime(2025, 1, 1), tutar: 1000)];

      final temettusuz = XirrService.portfolioXirr(
        assets: assets,
        bugunkuDegerTRY: 1100,
        now: now,
      );
      final temettulu = XirrService.portfolioXirr(
        assets: [
          ...assets,
          temettu(tarih: DateTime(2025, 6, 1), tutar: 50),
        ],
        bugunkuDegerTRY: 1100,
        now: now,
      );

      expect(temettusuz, isNotNull);
      expect(temettulu, isNotNull);
      expect(temettulu!, greaterThan(temettusuz!));
    });

    test('satış cebe giriş sayılır', () {
      final now = DateTime(2026, 1, 1);
      final r = XirrService.portfolioXirr(
        assets: [
          alim(tarih: DateTime(2025, 1, 1), tutar: 1000),
          satis(tarih: DateTime(2025, 7, 1), tutar: 600),
        ],
        bugunkuDegerTRY: 600,
        now: now,
      );
      expect(r, isNotNull);
      expect(r!.isFinite, isTrue);
    });

    test('silinmiş lot akışa girmez', () {
      final now = DateTime(2026, 1, 1);
      final silinmis = Asset(
        id: 'silinmis',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 5000,
        currentPrice: 5000,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: DateTime(2025, 3, 1),
        deletedAt: DateTime(2025, 4, 1));

      final r = XirrService.portfolioXirr(
        assets: [alim(tarih: DateTime(2025, 1, 1), tutar: 1000), silinmis],
        bugunkuDegerTRY: 1100,
        now: now,
      );
      expect(r, isNotNull);
      // Silinmiş 5000'lik alım sayılsaydı oran çok farklı çıkardı.
      expect(r!, closeTo(10.0, 0.05));
    });

    test('bugünkü değer 0 ve satış yoksa `null`', () {
      final r = XirrService.portfolioXirr(
        assets: [alim(tarih: DateTime(2025, 1, 1), tutar: 1000)],
        bugunkuDegerTRY: 0,
        now: DateTime(2026, 1, 1),
      );
      expect(r, isNull, reason: 'yalnızca negatif akış — kök yok');
    });

    test('boş portföy `null`', () {
      expect(
        XirrService.portfolioXirr(
          assets: const [],
          bugunkuDegerTRY: 1000,
          now: DateTime(2026, 1, 1),
        ),
        isNull,
      );
    });
  });

  group('XirrService.dividendsInPeriod', () {
    test('yalnızca penceredeki temettüleri toplar', () {
      final assets = [
        temettu(tarih: DateTime(2025, 3, 10), tutar: 100),
        temettu(tarih: DateTime(2025, 6, 15), tutar: 250),
        temettu(tarih: DateTime(2025, 9, 1), tutar: 400),
      ];
      final toplam = XirrService.dividendsInPeriod(
        assets,
        DateTime(2025, 6, 1),
        DateTime(2025, 8, 31),
      );
      expect(toplam, 250);
    });

    test('pencere GÜN sınırlarına genişler — son günün temettüsü sayılır', () {
      final assets = [temettu(tarih: DateTime(2025, 6, 30, 18, 45), tutar: 90)];
      final toplam = XirrService.dividendsInPeriod(
        assets,
        DateTime(2025, 6, 1),
        DateTime(2025, 6, 30),
      );
      expect(toplam, 90);
    });

    test('alım ve satım satırları temettüye karışmaz', () {
      final assets = [
        alim(tarih: DateTime(2025, 6, 10), tutar: 1000),
        satis(tarih: DateTime(2025, 6, 20), tutar: 500),
      ];
      expect(
        XirrService.dividendsInPeriod(
            assets, DateTime(2025, 6, 1), DateTime(2025, 6, 30)),
        0,
      );
    });
  });
}
