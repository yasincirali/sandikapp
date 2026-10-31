import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/tekrar_al.dart';
import 'package:portfoy_takip/models/tur_secici_duzeni.dart';

/// Varlık Ekle "Tekrar al" çiplerinin ve kayıt sonu "Bir tane daha ekle"
/// bildiriminin kuralı (müşteri raporu 31 Eki 13:15, yasin "yap").

var _n = 0;

Asset _lot({
  required AssetType type,
  required String ticker,
  String name = 'Ad',
  String userId = 'ben',
  double qty = 1,
  DateTime? tarih,
  AssetKind kind = AssetKind.buy,
  String? subCategory,
  String unitType = 'piece',
  DateTime? silindi,
}) =>
    Asset(
      id: 'a${_n++}',
      userId: userId,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      subCategory: subCategory,
      unitType: unitType,
      kind: kind,
      addedDate: tarih ?? DateTime(2026, 10, 1),
      deletedAt: silindi,
    );

Asset _gram(double qty, DateTime tarih, {String userId = 'ben'}) {
  final g = GoldSubCategory.gr24;
  return _lot(
    type: AssetType.altin,
    ticker: goldTickerMap[g.label]!,
    name: g.label,
    subCategory: g.label,
    unitType: g.unitType,
    qty: qty,
    tarih: tarih,
    userId: userId,
  );
}

List<TekrarAlAdayi> _adaylar(List<Asset> lotlar,
        {bool Function(AssetType)? turAcik, bool abdAcik = true}) =>
    tekrarAlAdaylari(lotlar,
        sahip: 'ben', turAcik: turAcik ?? (_) => true, abdAcik: abdAcik);

void main() {
  group('tekrarAlAdaylari', () {
    test('en sık alınan önde, eşitlikte en son alınan; en fazla 3', () {
      final lotlar = [
        _gram(10, DateTime(2026, 8, 1)),
        _gram(10, DateTime(2026, 9, 1)),
        _gram(12, DateTime(2026, 10, 1)),
        _lot(
            type: AssetType.fon,
            ticker: 'TEFAS:AFT',
            tarih: DateTime(2026, 9, 1)),
        _lot(
            type: AssetType.fon,
            ticker: 'TEFAS:AFT',
            tarih: DateTime(2026, 10, 1)),
        _lot(
            type: AssetType.hisse,
            ticker: 'THYAO.IS',
            tarih: DateTime(2026, 10, 20)),
        _lot(
            type: AssetType.hisse,
            ticker: 'GARAN.IS',
            tarih: DateTime(2026, 10, 10)),
      ];
      final a = _adaylar(lotlar);
      expect(a.map((e) => e.sonuc.sembol),
          [GoldSubCategory.gr24.label, 'AFT', 'THYAO']);
      // Son alımın miktarı ve birimi (forma yazılmaz, çipte ipucu).
      expect(a.first.sonMiktar, 12);
      expect(a.first.birim, 'gr');
      expect(a.first.sonuc.altin, GoldSubCategory.gr24);
      expect(a[1].sonuc.ticker, 'TEFAS:AFT');
      expect(a[2].sonuc.ticker, 'THYAO.IS');
    });

    test('yalnız kendi alışları; satış, silinmiş ve ortağın lotu sayılmaz', () {
      final lotlar = [
        _gram(5, DateTime(2026, 10, 1), userId: 'ortak'),
        _lot(
            type: AssetType.hisse,
            ticker: 'ASELS.IS',
            kind: AssetKind.sell),
        _lot(
            type: AssetType.hisse,
            ticker: 'SISE.IS',
            silindi: DateTime(2026, 10, 2)),
      ];
      expect(_adaylar(lotlar), isEmpty);
    });

    test('satılmış varlığın ALIŞI aday kalır', () {
      final alis = _lot(type: AssetType.hisse, ticker: 'EREGL.IS');
      final satis = _lot(
          type: AssetType.hisse, ticker: 'EREGL.IS', kind: AssetKind.sell);
      expect(_adaylar([alis, satis]).single.sonuc.sembol, 'EREGL');
    });

    test('arama sonucuyla temsil edilemeyen kayıt çip olmaz', () {
      final lotlar = [
        _lot(type: AssetType.hisse, ticker: 'SERBEST'),
        _lot(type: AssetType.fon, ticker: 'AFT'),
        _lot(type: AssetType.mevduat, ticker: ''),
        _lot(type: AssetType.doviz, ticker: 'TRY', subCategory: 'TRY'),
      ];
      expect(_adaylar(lotlar), isEmpty);
    });

    test('döviz kodu kutu ve etiketle gelir', () {
      final a = _adaylar([
        _lot(type: AssetType.doviz, ticker: 'USDTRY=X', subCategory: 'USD'),
      ]).single;
      expect(a.sonuc.kutu, const TurKutusu(AssetType.doviz));
      expect(a.sonuc.dovizEtiketi, 'USD');
    });

    test('kapalı tür süzülür', () {
      final lotlar = [
        _gram(10, DateTime(2026, 10, 1)),
        _lot(type: AssetType.fon, ticker: 'TEFAS:AFT'),
      ];
      final a = _adaylar(lotlar, turAcik: (t) => t != AssetType.altin);
      expect(a.single.sonuc.sembol, 'AFT');
    });
  });

  group('birTaneDahaOnerilsinMi', () {
    List<Asset> pozisyonlar(int adet) => [
          for (var i = 0; i < adet; i++)
            _lot(type: AssetType.hisse, ticker: 'H$i.IS'),
        ];

    test('kendi açık pozisyonu 5ten azsa önerilir', () {
      expect(birTaneDahaOnerilsinMi(pozisyonlar(1), sahip: 'ben'), isTrue);
      expect(birTaneDahaOnerilsinMi(pozisyonlar(4), sahip: 'ben'), isTrue);
      expect(birTaneDahaOnerilsinMi(pozisyonlar(5), sahip: 'ben'), isFalse);
    });

    test('aynı varlığın iki lotu tek pozisyondur', () {
      final lotlar = [
        for (var i = 0; i < 6; i++)
          _lot(type: AssetType.hisse, ticker: 'THYAO.IS'),
      ];
      expect(birTaneDahaOnerilsinMi(lotlar, sahip: 'ben'), isTrue);
    });

    test('ortağın pozisyonları sayılmaz; sahip bilinmiyorsa önerilmez', () {
      final ortak = [
        for (var i = 0; i < 6; i++)
          _lot(type: AssetType.hisse, ticker: 'O$i.IS', userId: 'ortak'),
      ];
      expect(birTaneDahaOnerilsinMi(ortak, sahip: 'ben'), isTrue);
      expect(birTaneDahaOnerilsinMi(const [], sahip: ''), isFalse);
    });
  });
}
