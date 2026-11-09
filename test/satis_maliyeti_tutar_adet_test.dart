import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Ar-Ge raporu 2026-10-24 §1 ve §2'nin saf kuralları.
///
/// §1: fiyatı boş bırakılan YENİ, BUGÜNKÜ altın/döviz alımında maliyet
/// truncgil'in satış fiyatından yazılır; geçmiş tarih, elle fiyat, satış
/// gelmeyen tür bugünkü gibi kalır (uydurma sayı yok).
/// §2: tutar girince adet = tutar ÷ birim fiyat, yuvarlanmadan; fiyat yoksa
/// adet yok.
class _Kapi implements AddAssetPriceLookup, SatisFiyatiOkuyucu {
  _Kapi({this.kotasyon, this.spotFiyat = 3000, this.hist});
  AlisSatis? kotasyon;
  double spotFiyat;
  double? hist;
  final istekler = <String>[];

  @override
  Future<AlisSatis?> alisSatis(String ticker) async {
    istekler.add('alisSatis:$ticker');
    return kotasyon;
  }

  @override
  Future<double?> historicalClose(String ticker, DateTime date) async {
    istekler.add('hist:$ticker');
    return hist;
  }

  @override
  Future<double?> spot(String ticker) async {
    istekler.add('spot:$ticker');
    return spotFiyat;
  }

  @override
  Future<String?> companyName(String ticker) async => null;
}

/// Satış yeteneği OLMAYAN kapı (var olan test sahteleri gibi).
class _EskiKapi implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 3000;
  @override
  Future<String?> companyName(String ticker) async => null;
}

final _bugun = DateTime(2026, 10, 24, 14);
final _dun = DateTime(2026, 10, 23);

void main() {
  group('maliyetSatisFiyati (sözleşme)', () {
    double? m({
      String ticker = 'ALTIN_GRAM24',
      String para = 'TRY',
      DateTime? tarih,
      double? alis = 3000,
      double? satis = 3100,
    }) =>
        maliyetSatisFiyati(
          ticker: ticker,
          paraBirimi: para,
          tarih: tarih ?? _bugun,
          alis: alis,
          satis: satis,
          now: _bugun,
        );

    test('bugünkü altın ve döviz alımında satış yazılır', () {
      expect(m(), 3100);
      expect(m(ticker: 'USDTRY=X', alis: 41.9, satis: 42.1), 42.1);
      expect(m(ticker: 'EURTRY=X', alis: 48.0, satis: 48.3), 48.3);
      expect(m(ticker: 'ALTIN_CEYREK', alis: 5000, satis: 5250), 5250);
    });

    test('geçmiş tarih: satış bilinmez, kural uygulanmaz', () {
      expect(m(tarih: _dun), isNull);
    });

    test('yurt içi kotasyonu olmayan sembol (hisse, fon, kripto) dışarıda', () {
      expect(m(ticker: 'THYAO.IS'), isNull);
      expect(m(ticker: 'TEFAS:AFT'), isNull);
      expect(m(ticker: 'KRIPTO:BTC'), isNull);
    });

    test('TL dışı para birimi: kotasyon TL, satış yazılmaz', () {
      expect(m(para: 'USD'), isNull);
    });

    test('satış gelmedi ya da bozuk: uydurma yok', () {
      expect(m(satis: null), isNull);
      expect(m(alis: null), isNull);
      expect(m(satis: 2900), isNull, reason: 'satış alışın altında');
      expect(m(satis: 3000 * 1.3), isNull, reason: 'makas arıza boyutunda');
      expect(m(satis: double.nan), isNull);
      expect(m(alis: 0), isNull);
    });

    test('kuyumcu farkı: satıştan alınıp alıştan bozdurulan pay', () {
      expect(kuyumcuFarkiYuzde(alis: 3000, satis: 3100),
          closeTo(100 / 3100 * 100, 1e-9));
      expect(kuyumcuFarkiYuzde(alis: 10, satis: 10), 0);
    });
  });

  group('truncgil satış alanı', () {
    test('v4 sayısı ve eski metin biçimi okunur', () {
      expect(
          PriceService.parseTruncgilSatis(
              {'Buying': 3000.5, 'Selling': 3100.25}),
          3100.25);
      expect(
          PriceService.parseTruncgilSatis(
              {'Alış': '5.412,37', 'Satış': '5.500,10'}),
          5500.10);
    });

    test('satış yoksa ya da alış yoksa null', () {
      expect(PriceService.parseTruncgilSatis({'Buying': 3000}), isNull);
      expect(PriceService.parseTruncgilSatis({'Selling': 3100}), isNull,
          reason: 'alışsız kayıtta fiyat zaten satıştan okunur; sıfır makas '
              'uydurma olurdu');
      expect(PriceService.parseTruncgilSatis(null), isNull);
      expect(
          PriceService.parseTruncgilSatis({'Buying': 1, 'Selling': 0}), isNull);
    });
  });

  group('fiyatBul satış yolu', () {
    test('yeni kayıt, bugün: alış price, satış satis', () async {
      final k = _Kapi(kotasyon: (alis: 3000, satis: 3100));
      final r = await fiyatBul(
          lookup: k,
          ticker: 'ALTIN_GRAM24',
          date: _bugun,
          now: _bugun,
          satisParaBirimi: 'TRY');
      expect(r.price, 3000);
      expect(r.satis, 3100);
      expect(k.istekler, ['alisSatis:ALTIN_GRAM24'],
          reason: 'alış ve satış aynı kotasyondan; ayrıca spot sorulmaz');
    });

    test('kural kapalı (düzenleme/sepet): bugünkü gibi spot, satış yok',
        () async {
      final k = _Kapi(kotasyon: (alis: 3000, satis: 3100));
      final r = await fiyatBul(
          lookup: k, ticker: 'ALTIN_GRAM24', date: _bugun, now: _bugun);
      expect(r.price, 3000);
      expect(r.satis, isNull);
      expect(k.istekler, ['spot:ALTIN_GRAM24']);
    });

    test('geçmiş tarih: kapanış, satış yok', () async {
      final k = _Kapi(kotasyon: (alis: 3000, satis: 3100), hist: 2800);
      final r = await fiyatBul(
          lookup: k,
          ticker: 'ALTIN_GRAM24',
          date: _dun,
          now: _bugun,
          satisParaBirimi: 'TRY');
      expect(r.price, 2800);
      expect(r.satis, isNull);
      expect(k.istekler, ['hist:ALTIN_GRAM24']);
    });

    test('satış gelmeyen tür: alış atanır, satır yok', () async {
      final k = _Kapi(kotasyon: (alis: 3000, satis: null));
      final r = await fiyatBul(
          lookup: k,
          ticker: 'ALTIN_GRAM24',
          date: _bugun,
          now: _bugun,
          satisParaBirimi: 'TRY');
      expect(r.price, 3000);
      expect(r.satis, isNull);
    });

    test('kotasyon gelmedi: spot yedeğine düşülür', () async {
      final k = _Kapi(kotasyon: null, spotFiyat: 2990);
      final r = await fiyatBul(
          lookup: k,
          ticker: 'ALTIN_GRAM24',
          date: _bugun,
          now: _bugun,
          satisParaBirimi: 'TRY');
      expect(r.price, 2990);
      expect(r.satis, isNull);
    });

    test('satış yeteneği olmayan kapı: bugünkü davranış', () async {
      final r = await fiyatBul(
          lookup: _EskiKapi(),
          ticker: 'ALTIN_GRAM24',
          date: _bugun,
          now: _bugun,
          satisParaBirimi: 'TRY');
      expect(r.price, 3000);
      expect(r.satis, isNull);
    });
  });

  group('tutardan adet', () {
    test('adet = tutar ÷ fiyat, yuvarlanmadan', () {
      expect(tutardanAdet(tutar: 10000, birimFiyat: 4), 2500);
      expect(tutardanAdet(tutar: 1000, birimFiyat: 3), 1000 / 3);
      final a = tutardanAdet(tutar: 5000, birimFiyat: 1.234567)!;
      expect(a * 1.234567, closeTo(5000, 1e-9));
    });

    test('fiyat ya da tutar yoksa adet yok', () {
      expect(tutardanAdet(tutar: 1000, birimFiyat: null), isNull);
      expect(tutardanAdet(tutar: null, birimFiyat: 3), isNull);
      expect(tutardanAdet(tutar: 0, birimFiyat: 3), isNull);
      expect(tutardanAdet(tutar: 1000, birimFiyat: 0), isNull);
      expect(tutardanAdet(tutar: double.infinity, birimFiyat: 3), isNull);
    });

    test('birim fiyat: yazılan kazanır, yoksa satış, yoksa önizleme', () {
      expect(
          tutarBirimFiyati(
              kullaniciFiyati: 50, onizlemeFiyati: 40, onizlemeSatis: 41),
          50);
      expect(
          tutarBirimFiyati(
              kullaniciFiyati: null, onizlemeFiyati: 40, onizlemeSatis: 41),
          41);
      expect(
          tutarBirimFiyati(
              kullaniciFiyati: 0, onizlemeFiyati: 40, onizlemeSatis: null),
          40);
      expect(
          tutarBirimFiyati(
              kullaniciFiyati: null, onizlemeFiyati: null, onizlemeSatis: null),
          isNull);
    });
  });

  test('önizleme fiyatı değişince eski satış düşer', () {
    final s = AddAssetFormState.initial(now: _bugun)
        .copyWith(previewPrice: 3000.0, previewSatis: 3100.0);
    expect(s.previewSatis, 3100);
    expect(s.copyWith(previewPrice: 2000.0).previewSatis, isNull);
    expect(s.copyWith(previewLoading: true).previewSatis, 3100);
  });
}
