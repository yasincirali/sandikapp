import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ice_aktarma_satislari.dart';

/// Aracı kurum ekstresi (karar 5.1 + 5.4, 2026-09-30): kurum sütun adları,
/// alış/satış yönü, tutardan birim fiyat ve satış planlayıcısı.
void main() {
  final bugun = DateTime(2026, 9, 30);

  group('kurum sütun adları (5.1)', () {
    test('"Menkul Kıymet / Nominal / Ortalama Maliyet / İşlem Tarihi"', () {
      const metin = 'Menkul Kıymet;Nominal;Ortalama Maliyet;İşlem Tarihi\n'
          'THYAO;100;278,40;12.03.2026\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.errors, isEmpty);
      expect(r.rows.single.ticker, 'THYAO.IS');
      expect(r.rows.single.quantity, 100);
      expect(r.rows.single.price, 278.40);
      expect(r.rows.single.addedDate, DateTime(2026, 3, 12));
    });

    test('"Maliyet Tutarı" birim fiyat SANILMAZ; fiyat tutar / adet', () {
      const metin = 'Sembol;Adet;Maliyet Tutarı;Tarih\n'
          'ASELS;250;24.030;02.02.2026\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.errors, isEmpty);
      expect(r.rows.single.price, closeTo(96.12, 1e-9));
    });

    test('"İşlem Tutarı" yön sütunu SANILMAZ', () {
      const metin = 'Sembol;Adet;İşlem Tutarı\nASELS;10;1.000\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.errors, isEmpty);
      expect(r.rows.single.satis, isFalse);
      expect(r.rows.single.price, 100);
    });

    test('sembol ayıklama: "THYAO - Türk Hava Yolları" ve "THYAO.E"', () {
      expect(CsvImportService.sembolAyikla('THYAO - Türk Hava Yolları'),
          'THYAO');
      expect(CsvImportService.sembolAyikla('THYAO.E'), 'THYAO');
      // Boşluklu ad bölünmez; altın tanınmaya devam eder.
      expect(CsvImportService.sembolAyikla('GRAM ALTIN'), 'GRAM ALTIN');
      expect(CsvImportService.sembolAyikla('TTE'), 'TTE');
    });
  });

  group('alış / satış (5.4)', () {
    test('"İşlem Türü" sütunu: Alış ve Satış', () {
      const metin = 'Sembol;İşlem Türü;Adet;Fiyat;Tarih\n'
          'THYAO;Alış;100;250;01.03.2026\n'
          'THYAO;Satış;40;300;01.06.2026\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.errors, isEmpty);
      expect(r.rows.map((e) => e.satis), [false, true]);
      expect(r.rows[1].quantity, 40);
      expect(r.rows[1].price, 300);
    });

    test('kısaltmalar: A / S / Buy / Sell / SATIŞ', () {
      expect(CsvImportService.yonCoz('A'), isFalse);
      expect(CsvImportService.yonCoz('S'), isTrue);
      expect(CsvImportService.yonCoz('Buy'), isFalse);
      expect(CsvImportService.yonCoz('SELL'), isTrue);
      expect(CsvImportService.yonCoz('SATIŞ'), isTrue);
      expect(CsvImportService.yonCoz('ALIM'), isFalse);
      expect(CsvImportService.yonCoz('Virman'), isNull);
    });

    test('yön sütunu yoksa EKSİ adet satıştır', () {
      const metin = 'Sembol;Adet;Fiyat;Tarih\nTHYAO;-25;300;01.06.2026\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.rows.single.satis, isTrue);
      expect(r.rows.single.quantity, 25);
    });

    test('okunamayan yön satırı hata olur, sessizce alım sayılmaz', () {
      const metin = 'Sembol;Yön;Adet\nTHYAO;Virman;10\n';
      final r = CsvImportService.parse(metin, today: bugun);
      expect(r.rows, isEmpty);
      expect(r.errors.single, contains('alış/satış okunamadı'));
    });
  });

  group('IceAktarmaSatislari.planla', () {
    Asset alim(double adet, double fiyat, DateTime t, {double kur = 1}) =>
        Asset(
          id: 'a${t.millisecondsSinceEpoch}$adet',
          userId: 'u',
          name: 'THYAO',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: adet,
          purchasePrice: fiyat,
          currency: 'TRY',
          notes: '',
          addedDate: t,
          purchaseFxRate: kur,
        );
    BulkCartItem satis(double adet, DateTime t) => BulkCartItem(
          id: 's${t.millisecondsSinceEpoch}$adet',
          type: AssetType.hisse,
          name: 'THYAO',
          ticker: 'THYAO.IS',
          quantity: adet,
          price: 300,
          currency: 'TRY',
          addedDate: t,
          satis: true,
        );

    test('maliyet = satış gününe kadarki alımların ağırlıklı ortalaması', () {
      final defter = [
        alim(100, 200, DateTime(2026, 1, 10)),
        alim(100, 300, DateTime(2026, 2, 10)),
        // Satıştan SONRAKİ alım maliyete girmez.
        alim(100, 900, DateTime(2026, 5, 10)),
      ];
      final p = IceAktarmaSatislari.planla(
          defter: defter, satislar: [satis(50, DateTime(2026, 3, 1))]);
      expect(p.reddedilen, isEmpty);
      expect(p.yazilacak.single.maliyet, 250);
      expect(p.yazilacak.single.kur, 1);
    });

    test('o gün elde olandan fazla satış REDDEDİLİR (kısmen de yazılmaz)',
        () {
      final defter = [alim(100, 200, DateTime(2026, 1, 10))];
      final p = IceAktarmaSatislari.planla(
          defter: defter, satislar: [satis(150, DateTime(2026, 3, 1))]);
      expect(p.yazilacak, isEmpty);
      expect(p.reddedilen.single.quantity, 150);
    });

    test('aynı ekstredeki önceki satış eldekinden düşülür, tarih sırasıyla',
        () {
      final defter = [alim(100, 200, DateTime(2026, 1, 10))];
      final p = IceAktarmaSatislari.planla(defter: defter, satislar: [
        // Listede SONRA gelen ama tarihçe ÖNCE olan satış önce işlenir.
        satis(60, DateTime(2026, 4, 1)),
        satis(60, DateTime(2026, 3, 1)),
      ]);
      expect(p.yazilacak.single.kalem.addedDate, DateTime(2026, 3, 1));
      expect(p.reddedilen.single.addedDate, DateTime(2026, 4, 1));
    });

    test('alımdan önceki tarihte satış reddedilir', () {
      final defter = [alim(100, 200, DateTime(2026, 5, 1))];
      final p = IceAktarmaSatislari.planla(
          defter: defter, satislar: [satis(10, DateTime(2026, 4, 1))]);
      expect(p.yazilacak, isEmpty);
    });

    test('aynı gün alım + satış: gün sonu kuralıyla elde sayılır', () {
      final defter = [alim(100, 200, DateTime(2026, 3, 1, 15, 30))];
      final p = IceAktarmaSatislari.planla(
          defter: defter, satislar: [satis(100, DateTime(2026, 3, 1))]);
      expect(p.yazilacak.single.kalem.quantity, 100);
    });

    test('pozisyon görünümü pos: kimlikli, maliyet ve kur plandan', () {
      final defter = [alim(10, 100, DateTime(2026, 1, 1), kur: 1)];
      final p = IceAktarmaSatislari.planla(
          defter: defter, satislar: [satis(5, DateTime(2026, 2, 1))]);
      final g = IceAktarmaSatislari.pozisyonGorunumu(p.yazilacak.single, 120);
      expect(g.id.startsWith('pos:'), isTrue);
      expect(g.purchasePrice, 100);
      expect(g.currentPrice, 120);
    });
  });
}
