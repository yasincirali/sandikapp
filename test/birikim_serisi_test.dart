import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/birikim_serisi.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';

/// Aylık birikim serisi (yasin kararları 2026-10-05: aylık ritim, son 12
/// ayda 1 mola, BES dahil). Değişmezler:
/// * seri yalnız birikim aylarını sayar, mola artırmaz;
/// * içinde bulunulan boş ay seriyi BOZMAZ;
/// * 12 ayda ikinci boş ay seriyi sıfırlar, en uzun seri kalır;
/// * net satış ayı birikim sayılmaz.
void main() {
  Asset alim(DateTime tarih, double tutar, {AssetType tur = AssetType.hisse}) =>
      Asset(
        id: 'b${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: tur,
        quantity: 1,
        purchasePrice: tutar,
        currentPrice: tutar,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: tarih,
      );

  Asset satis(DateTime tarih, double tutar) => Asset(
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

  /// Kova dizisi kısayolu: `true` = katkılı ay, `false` = boş ay.
  /// Son eleman içinde bulunulan ay.
  List<ContributionBucket> kovalar(List<bool> aylar) => [
        for (var i = 0; i < aylar.length; i++)
          ContributionBucket(
            start: DateTime(2025, 1 + i, 1),
            end: DateTime(2025, 2 + i, 0),
            netTRY: aylar[i] ? 1000 : 0,
            kismi: i == aylar.length - 1,
          ),
      ];

  group('sayım', () {
    test('art arda katkı ayları sayılır, bu ay dahil', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, true, true, true]))!;
      expect(s.guncel, 4);
      expect(s.enUzun, 4);
      expect(s.buAyKatkiVar, isTrue);
      expect(s.kalanMola, 1);
    });

    test('içinde bulunulan boş ay seriyi bozmaz ve molayı harcamaz', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, true, true, false]))!;
      expect(s.guncel, 3);
      expect(s.serit.last.durum, SeriAyDurumu.acik);
      expect(s.kalanMola, 1);
      expect(s.buAyKatkiVar, isFalse);
    });

    test('tek boş ay mola olur: seri bozulmaz ama artmaz', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, true, false, true, true]))!;
      expect(s.guncel, 4);
      expect(s.serit[2].durum, SeriAyDurumu.mola);
      expect(s.kalanMola, 0);
      // Mola Mart 2025'te → hak Mart 2026'da açılır.
      expect(s.molaAcilisAyi, DateTime(2026, 3, 1));
    });

    test('12 ay içinde ikinci boş ay seriyi sıfırlar, en uzun kalır', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, true, false, true, false, true]))!;
      expect(s.serit[4].durum, SeriAyDurumu.ara);
      expect(s.guncel, 1);
      expect(s.enUzun, 3);
    });

    test('mola 12 ay sonra yeniden kullanılabilir', () {
      // Ay 1 boş (mola), sonra 12 ay dolu, ay 14 boş → yeni mola.
      final aylar = [true, false, ...List.filled(12, true), false, true];
      final s = BirikimSerisiService.hesaplaKovalardan(kovalar(aylar))!;
      expect(s.serit.where((a) => a.durum == SeriAyDurumu.ara), isEmpty);
      expect(s.guncel, 14);
    });

    test('art arda iki boş ay seriyi sıfırlar', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, true, true, false, false, true]))!;
      expect(s.guncel, 1);
      expect(s.enUzun, 3);
      expect(s.yenidenBasladi, isFalse);
    });

    test('seri yokken boş ay mola harcamaz', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([true, false, false, false, true]))!;
      // Ay 1 mola, ay 2 ara (sıfır), ay 3 ara ama hak HARCANMAZ.
      expect(s.serit[1].durum, SeriAyDurumu.mola);
      expect(s.serit[2].durum, SeriAyDurumu.ara);
      expect(s.serit[3].durum, SeriAyDurumu.ara);
      expect(s.guncel, 1);
    });

    test('hiç katkı yoksa null', () {
      expect(
          BirikimSerisiService.hesaplaKovalardan(kovalar([false, false])),
          isNull);
    });

    test('ilk katkıdan önceki aylar seriye girmez', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar([false, false, true, true]))!;
      expect(s.serit[0].durum, SeriAyDurumu.oncesi);
      expect(s.gecmisAy, 2);
      expect(s.gosterilir, isFalse, reason: 'üç aydan kısa geçmiş');
    });

    test('şerit en çok 12 ay', () {
      final s = BirikimSerisiService.hesaplaKovalardan(
          kovalar(List.filled(20, true)))!;
      expect(s.serit, hasLength(12));
      expect(s.guncel, 20);
    });
  });

  group('defterden', () {
    final now = DateTime(2025, 6, 15, 12);

    test('alım lotları ay ay seri kurar, geç girilen geçmiş alım düzeltir',
        () {
      final defter = [
        alim(DateTime(2025, 3, 5), 1000),
        alim(DateTime(2025, 5, 5), 1000),
        alim(DateTime(2025, 6, 1), 1000),
      ];
      final once = BirikimSerisiService.hesapla(defter, now: now)!;
      expect(once.guncel, 3, reason: 'Nisan mola');
      expect(once.kalanMola, 0);

      final sonra = BirikimSerisiService.hesapla(
          [...defter, alim(DateTime(2025, 4, 20), 500)],
          now: now)!;
      expect(sonra.guncel, 4);
      expect(sonra.kalanMola, 1);
    });

    test('net satış ayı birikim sayılmaz', () {
      final s = BirikimSerisiService.hesapla([
        alim(DateTime(2025, 3, 5), 1000),
        alim(DateTime(2025, 4, 5), 1000),
        alim(DateTime(2025, 5, 2), 100),
        satis(DateTime(2025, 5, 20), 5000),
        alim(DateTime(2025, 6, 1), 1000),
      ], now: now)!;
      final mayis = s.serit.firstWhere((a) => a.ay.month == 5);
      expect(mayis.durum, SeriAyDurumu.mola);
      expect(s.guncel, 3);
    });

    test('BES katkısı sayılır (kullanıcı kararı 2026-10-05)', () {
      final s = BirikimSerisiService.hesapla([
        for (final ay in [3, 4, 5, 6])
          alim(DateTime(2025, ay, 10), 2000, tur: AssetType.bes),
      ], now: now)!;
      expect(s.guncel, 4);
      expect(s.gosterilir, isTrue);
    });

    test('boş defter null', () {
      expect(BirikimSerisiService.hesapla(const [], now: now), isNull);
    });
  });
}
