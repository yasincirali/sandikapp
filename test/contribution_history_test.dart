import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';

/// Birikim disiplini serisi.
///
/// Kritik değişmez: **negatif katkı pozitif birikim gibi sayılmaz.** Para
/// çeken bir ayı "biriktirdin" diye kutlamak, kullanıcının uygulamaya
/// güvenini bitiren türden bir hatadır.
void main() {
  Asset alim({required DateTime tarih, required double tutar}) => Asset(
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
        purchaseFxRate: 1,
        addedDate: tarih,
      );

  Asset satis({required DateTime tarih, required double tutar}) => Asset(
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
        purchaseFxRate: 1,
        addedDate: tarih,
        kind: AssetKind.sell,
      );

  // Referans "şimdi": 15 Haziran 2025, Pazar.
  final now = DateTime(2025, 6, 15, 12);

  group('ContributionInterval.pencere', () {
    test('aylık pencere takvim ayıdır', () {
      final (bas, son) = ContributionInterval.aylik.pencere(now, 0);
      expect(bas, DateTime(2025, 6, 1));
      expect(son, DateTime(2025, 6, 30));
    });

    test('aylık geriye gitmek yıl sınırını aşar', () {
      final (bas, son) = ContributionInterval.aylik.pencere(now, 6);
      expect(bas, DateTime(2024, 12, 1));
      expect(son, DateTime(2024, 12, 31));
    });

    test('Şubat 28/29 gün olarak doğru kırpılır', () {
      final (bas, son) = ContributionInterval.aylik
          .pencere(DateTime(2024, 3, 31), 1); // 2024 artık yıl
      expect(bas, DateTime(2024, 2, 1));
      expect(son, DateTime(2024, 2, 29));
    });

    test('haftalık pencere pazartesi başlar', () {
      final (bas, son) = ContributionInterval.haftalik.pencere(now, 0);
      expect(bas.weekday, DateTime.monday);
      expect(bas, DateTime(2025, 6, 9));
      expect(son, DateTime(2025, 6, 15));
    });

    test('yıllık pencere takvim yılıdır', () {
      final (bas, son) = ContributionInterval.yillik.pencere(now, 1);
      expect(bas, DateTime(2024, 1, 1));
      expect(son, DateTime(2024, 12, 31));
    });
  });

  group('buckets', () {
    test('istenen sayıda kova, eskiden yeniye sıralı', () {
      final k = ContributionHistoryService.buckets(
        const [],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 4,
      );
      expect(k.length, 4);
      expect(k.first.start, DateTime(2025, 3, 1));
      expect(k.last.start, DateTime(2025, 6, 1));
      for (var i = 1; i < k.length; i++) {
        expect(k[i].start.isAfter(k[i - 1].start), isTrue);
      }
    });

    test('yalnızca son kova kısmi işaretlenir', () {
      final k = ContributionHistoryService.buckets(
        const [],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 3,
      );
      expect(k.map((b) => b.kismi).toList(), [false, false, true]);
    });

    test('alım doğru kovaya düşer', () {
      final k = ContributionHistoryService.buckets(
        [
          alim(tarih: DateTime(2025, 4, 10), tutar: 1000),
          alim(tarih: DateTime(2025, 6, 3), tutar: 500),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 4,
      );
      expect(k[0].netTRY, 0); // Mart
      expect(k[1].netTRY, 1000); // Nisan
      expect(k[2].netTRY, 0); // Mayıs
      expect(k[3].netTRY, 500); // Haziran (kısmi)
    });

    test('satış kovayı NEGATİFE çeker', () {
      final k = ContributionHistoryService.buckets(
        [
          alim(tarih: DateTime(2025, 4, 10), tutar: 1000),
          satis(tarih: DateTime(2025, 4, 20), tutar: 1500),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 4,
      );
      expect(k[1].netTRY, -500);
      expect(k[1].pozitif, isFalse);
    });

    test('kovaSayisi 0 ise boş liste', () {
      expect(
        ContributionHistoryService.buckets(
          const [],
          aralik: ContributionInterval.aylik,
          now: now,
          kovaSayisi: 0,
        ),
        isEmpty,
      );
    });
  });

  group('summarize', () {
    test('boş kova listesi `null`', () {
      expect(ContributionHistoryService.summarize(const []), isNull);
    });

    test('hiç katkı yoksa özet döner ama bos=true', () {
      final s = ContributionHistoryService.compute(
        const [],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s, isNotNull);
      expect(s!.bos, isTrue);
      expect(s.ortalamaTRY, isNull, reason: 'sıfıra bölme yok, 0 uydurulmaz');
      expect(s.zirve, isNull);
      expect(s.katkiliKovaSayisi, 0);
    });

    test('ortalama YALNIZCA katkılı kovalardan hesaplanır', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 3, 5), tutar: 1000),
          alim(tarih: DateTime(2025, 5, 5), tutar: 3000),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s, isNotNull);
      expect(s!.katkiliKovaSayisi, 2);
      // 4000 / 2 = 2000. Altı kovaya bölünseydi 666 çıkardı ve "ayda
      // ortalama ne biriktiriyorum" sorusuna yanlış cevap olurdu.
      expect(s.ortalamaTRY, 2000);
      expect(s.toplamTRY, 4000);
    });

    test('negatif kova birikim SAYILMAZ', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 3, 5), tutar: 1000),
          satis(tarih: DateTime(2025, 4, 5), tutar: 2000),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.katkiliKovaSayisi, 1);
      expect(s.ortalamaTRY, 1000);
      expect(s.toplamTRY, -1000, reason: 'net toplam satışla eksiye düşer');
    });

    test('zirve en yüksek katkılı kovadır', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 2, 5), tutar: 500),
          alim(tarih: DateTime(2025, 4, 5), tutar: 7000),
          alim(tarih: DateTime(2025, 5, 5), tutar: 1200),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.zirve!.netTRY, 7000);
      expect(s.zirve!.start, DateTime(2025, 4, 1));
    });

    test('sonFark KISMİ kovayı dışarıda bırakır', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 4, 5), tutar: 1000),
          alim(tarih: DateTime(2025, 5, 5), tutar: 1800),
          alim(tarih: DateTime(2025, 6, 5), tutar: 200), // kısmi ay
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      // Son TAM kova Mayıs (1800), önceki Nisan (1000) → +800.
      // Kısmi Haziran (200) alınsaydı fark −1600 çıkar ve "birikimin
      // düştü" denirdi — oysa ay daha bitmedi.
      expect(s!.sonFarkTRY, 800);
    });

    test('tek tam kovada sonFark `null`', () {
      final s = ContributionHistoryService.compute(
        [alim(tarih: DateTime(2025, 5, 5), tutar: 1000)],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 2, // Mayıs (tam) + Haziran (kısmi)
      );
      expect(s!.sonFarkTRY, isNull);
    });

    test('düzenlilik oranı katkılı kova / toplam kova', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 3, 5), tutar: 100),
          alim(tarih: DateTime(2025, 4, 5), tutar: 100),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 4,
      );
      expect(s!.duzenlilik, 0.5);
    });

    test('enBuyukMutlak negatif kovayı da kapsar — çubuk taşmasın', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 3, 5), tutar: 100),
          satis(tarih: DateTime(2025, 4, 5), tutar: 5000),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.enBuyukMutlak, 5000);
    });
  });

  group('trend', () {
    test('yetersiz tam kovada `null` — tek fark eğilim ilan edilmez', () {
      final s = ContributionHistoryService.compute(
        [alim(tarih: DateTime(2025, 5, 5), tutar: 1000)],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 3, // Nisan, Mayıs tam + Haziran kısmi = 2 tam
      );
      expect(s!.trend, isNull);
    });

    test('son kova ortalamanın belirgin üstündeyse artıyor', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 2, 5), tutar: 500),
          alim(tarih: DateTime(2025, 3, 5), tutar: 500),
          alim(tarih: DateTime(2025, 4, 5), tutar: 500),
          alim(tarih: DateTime(2025, 5, 5), tutar: 3000),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.trend, ContributionTrend.artiyor);
    });

    test('küçük fark gürültü sayılır — sabit', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 2, 5), tutar: 1000),
          alim(tarih: DateTime(2025, 3, 5), tutar: 1000),
          alim(tarih: DateTime(2025, 4, 5), tutar: 1000),
          alim(tarih: DateTime(2025, 5, 5), tutar: 1020), // %2 fark
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.trend, ContributionTrend.sabit);
    });

    test('son kova ortalamanın belirgin altındaysa azalıyor', () {
      final s = ContributionHistoryService.compute(
        [
          alim(tarih: DateTime(2025, 2, 5), tutar: 3000),
          alim(tarih: DateTime(2025, 3, 5), tutar: 3000),
          alim(tarih: DateTime(2025, 4, 5), tutar: 3000),
          alim(tarih: DateTime(2025, 5, 5), tutar: 200),
        ],
        aralik: ContributionInterval.aylik,
        now: now,
        kovaSayisi: 6,
      );
      expect(s!.trend, ContributionTrend.azaliyor);
    });
  });
}
