import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/arama_eylemleri.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Genel aramanın (bayrak `genel_arama`) saf eşleştirme kuralları.
void main() {
  group('aramaEylemleriniSuz', () {
    test('boş sorgu: tüm eylemler, tanım sırasıyla (öneri listesi)', () {
      expect(aramaEylemleriniSuz(''), AramaEylemi.values);
      expect(aramaEylemleriniSuz('   '), AramaEylemi.values);
    });

    test('her eylemin anahtarı var', () {
      for (final e in AramaEylemi.values) {
        expect(aramaEylemAnahtarlari[e], isNotEmpty, reason: '$e');
      }
    });

    final beklenen = <String, AramaEylemi>{
      'alarm': AramaEylemi.fiyatAlarmlari,
      'fiyat alarmı': AramaEylemi.fiyatAlarmlari,
      'fiyat alarmi': AramaEylemi.fiyatAlarmlari, // aksansız
      'FİYAT ALARMI': AramaEylemi.fiyatAlarmlari,
      'fiyat alarmı kur': AramaEylemi.fiyatAlarmlari, // cümle
      'ekstre': AramaEylemi.ekstreAktar,
      'csv': AramaEylemi.ekstreAktar,
      'ice aktar': AramaEylemi.ekstreAktar,
      'toplu': AramaEylemi.topluEkle,
      'sinyal': AramaEylemi.sinyalAyarlari,
      'temettü': AramaEylemi.tumHareketler,
      'temettu': AramaEylemi.tumHareketler,
      'hareketler': AramaEylemi.tumHareketler,
      'hareket': AramaEylemi.tumHareketler, // önek
      'karşılaştır': AramaEylemi.karsilastir,
      'karsilastir': AramaEylemi.karsilastir,
      'takip': AramaEylemi.takipListesi,
      'ayarlar': AramaEylemi.ayarlar,
      'bildirim': AramaEylemi.bildirimler,
      'bildirimler': AramaEylemi.bildirimler,
      'alerts': AramaEylemi.fiyatAlarmlari, // İngilizce
    };
    for (final e in beklenen.entries) {
      test('"${e.key}" → ${e.value.name}', () {
        expect(aramaEylemleriniSuz(e.key), contains(e.value));
      });
    }

    test('ilgisiz sorgu boş döner', () {
      expect(aramaEylemleriniSuz('thyao'), isEmpty);
      expect(aramaEylemleriniSuz('xyzq'), isEmpty);
    });

    test('mevcut: açılamayan hedef listelenmez', () {
      final r = aramaEylemleriniSuz('bildirim',
          mevcut: {AramaEylemi.ayarlar, AramaEylemi.fiyatAlarmlari});
      expect(r, isNot(contains(AramaEylemi.bildirimler)));
      expect(aramaEylemleriniSuz('', mevcut: {AramaEylemi.ayarlar}),
          [AramaEylemi.ayarlar]);
    });

    test('aylık rapor ve hafta özeti bilerek yok', () {
      expect(aramaEylemleriniSuz('aylık rapor'), isEmpty);
      expect(aramaEylemleriniSuz('hafta özeti'), isEmpty);
    });
  });

  group('aramaPozisyonlari', () {
    Asset lot(String id, String ticker, String ad,
            {bool sell = false, double q = 10}) =>
        Asset(
          id: id,
          userId: 'u',
          name: ad,
          ticker: ticker,
          type: AssetType.hisse,
          quantity: q,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 110,
          addedDate: DateTime(2026, 1, 1),
          kind: sell ? AssetKind.sell : AssetKind.buy,
        );

    final defter = [
      lot('1', 'THYAO.IS', 'Türk Hava Yolları'),
      lot('2', 'ASELS.IS', 'Aselsan'),
      // Tamamı satılmış: bugünkü mülkiyet değil, bulunmaz.
      lot('3', 'GARAN.IS', 'Garanti Bankası'),
      lot('4', 'GARAN.IS', 'Garanti Bankası', sell: true),
    ];

    test('sembol (sonek olmadan) ve ad, Türkçe-güvenli', () {
      expect(aramaPozisyonlari(defter, 'thy').map((p) => p.key).length, 1);
      expect(aramaPozisyonlari(defter, 'turk hava'), hasLength(1));
      expect(aramaPozisyonlari(defter, 'ASEL'), hasLength(1));
    });

    test('kapanmış pozisyon ve boş sorgu', () {
      expect(aramaPozisyonlari(defter, 'garan'), isEmpty);
      expect(aramaPozisyonlari(defter, ''), isEmpty);
    });
  });
}
