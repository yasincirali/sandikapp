import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';

/// Eurobond ekleme formunun aritmetiği ve seçici süzgeci (2026-10-08).
///
/// Kullanıcı TEMİZ fiyatı nominalin yüzdesi olarak yazar ("98,75"); lot
/// `purchasePrice` = KİRLİ/100 (fiyat servisi kotasyonuyla aynı ölçek).
/// Çeviri ters çevrilmezse düzenleme her açılışta fiyatı kaydırır; temiz %
/// birim değer diye yazılırsa lot 100 kat büyür.

final _tr28 = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Türkiye %9,875 2028',
  paraBirimi: 'USD',
  kuponOrani: 0.09875,
  vade: DateTime.utc(2028, 1, 15),
  ihracTarihi: DateTime.utc(2018, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

final _tr30 = EurobondSozlesmesi(
  isin: 'US900123CT57',
  ad: 'Türkiye %5,25 2030',
  paraBirimi: 'USD',
  kuponOrani: 0.0525,
  vade: DateTime.utc(2030, 3, 13),
  ihracTarihi: DateTime.utc(2020, 3, 13),
  ihracci: EurobondIhracci.hazine,
);

final _eur = EurobondSozlesmesi(
  isin: 'XS1234567896',
  ad: 'Türkiye EUR 2029',
  paraBirimi: 'EUR',
  kuponOrani: 0.04,
  vade: DateTime.utc(2029, 6, 1),
  ihracTarihi: DateTime.utc(2019, 6, 1),
  ihracci: EurobondIhracci.hazine,
  yillikKuponSayisi: 1,
  gunSayimi: GunSayimi.actAct,
);

final _vadesiGecmis = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Vadesi geçmiş',
  paraBirimi: 'USD',
  kuponOrani: 0.05,
  vade: DateTime.utc(2025, 1, 15),
  ihracTarihi: DateTime.utc(2015, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

final _fiyat = EurobondFiyati(
  isin: 'US900123DF45',
  temizFiyat: 104.125,
  guncellendi: DateTime.utc(2026, 10, 8, 12),
);

void main() {
  final gun = DateTime.utc(2026, 4, 15); // son kupondan 3 ay sonra

  group('temiz ↔ kirli birim değer', () {
    test('birim değer = (temiz + işlemiş faiz) / 100', () {
      // 30/360: 90 gün / 180 gün × 4,9375 = 2,46875 puan.
      expect(_tr28.islemisFaiz(gun), closeTo(2.46875, 1e-9));
      expect(eurobondBirimDegeri(_tr28, 98.75, gun),
          closeTo((98.75 + 2.46875) / 100, 1e-12));
    });

    test('kupon gününde işlemiş faiz sıfır, birim değer temiz/100', () {
      final kupon = DateTime.utc(2026, 7, 15);
      expect(eurobondBirimDegeri(_tr28, 100, kupon), closeTo(1.0, 1e-12));
    });

    test('ters çeviri gidiş-dönüş kayıpsız (düzenleme ekranı)', () {
      for (final temiz in [87.5, 98.75, 104.125]) {
        final birim = eurobondBirimDegeri(_tr28, temiz, gun);
        expect(eurobondTemizYuzde(_tr28, birim, gun), closeTo(temiz, 1e-9));
      }
    });
  });

  group('seçici süzgeci', () {
    final simdi = DateTime(2026, 10, 8);

    test('yalnız USD ve vadesi gelmemiş tahviller', () {
      final liste = eklenebilirEurobondlar([
        (_tr28, _fiyat),
        (_eur, null),
        (_vadesiGecmis, null),
        (_tr30, null),
      ], simdi: simdi);
      expect(liste.map((e) => e.$1.ad), [_tr28.ad, _tr30.ad]);
    });

    test('arama ad ve ISIN içinde, Türkçe büyük harf duyarsız', () {
      final liste = [(_tr28, _fiyat), (_tr30, null)];
      expect(eurobondAra(liste, 'TÜRKİYE').length, 2);
      expect(eurobondAra(liste, '2030').single.$1.isin, 'US900123CT57');
      expect(eurobondAra(liste, 'df45').single.$1.isin, 'US900123DF45');
      expect(eurobondAra(liste, '  ').length, 2);
    });

    test('ISIN araması nedeni söyler', () {
      final liste = [(_tr28, _fiyat)];
      expect(isinAramaSonucu('türkiye', liste), IsinAramaSonucu.isinDegil);
      expect(isinAramaSonucu('US900123DF46', liste), IsinAramaSonucu.gecersiz);
      expect(isinAramaSonucu(' us900123df45 ', liste),
          IsinAramaSonucu.bulundu);
      // Geçerli ama listede yok (EUR süzüldü ya da katalog dışı).
      expect(isinAramaSonucu('XS1234567896', liste),
          IsinAramaSonucu.katalogdaYok);
    });
  });

  group('form durumu', () {
    ProviderContainer kur() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('nominal ön ayarları ve birim', () {
      final s = AddAssetFormState.initial(prefillType: AssetType.eurobond);
      expect(s.quantityPresets, ['1.000', '5.000', '10.000', '50.000']);
      expect(s.quantitySuffix, 'nominal');
    });

    test('tahvil seçilmeden kayıt yok — düzenlemede de', () {
      final s = AddAssetFormState.initial(prefillType: AssetType.eurobond);
      expect(s.kimlikEksigi(tickerText: ''), KimlikEksigi.eurobond);
      expect(s.kimlikEksigi(tickerText: 'EUROBOND:US900123DF45', muaf: true),
          KimlikEksigi.eurobond,
          reason: 'sözleşmesiz çeviri yapılamaz; muafiyet temiz %\'yi birim '
              'değer diye yazdırırdı');
    });

    test('seçim: sembol, ad, USD kilidi, piyasa temiz fiyatı ön dolar', () {
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.eurobond);
      final n = c.read(addAssetFormProvider(args).notifier);
      final y = n.selectEurobond(_tr28, _fiyat, priceEmpty: true);
      expect(y.ticker, 'EUROBOND:US900123DF45');
      expect(y.name, _tr28.ad);
      expect(y.price, '104,125');

      final s = c.read(addAssetFormProvider(args));
      expect(s.currency, 'USD');
      expect(s.kimlikEksigi(tickerText: y.ticker!), isNull);
      final id = s.resolveIdentity(nameText: '', tickerText: y.ticker!);
      expect(id.ticker, 'EUROBOND:US900123DF45');
      expect(id.manual, isFalse);
      expect(s.resolveTicker(y.ticker!), isNull,
          reason: 'birim değer önizlemesi temiz % alanını yanıltırdı');

      n.setCurrency('TRY');
      expect(c.read(addAssetFormProvider(args)).currency, 'USD');
    });

    test('yazılmış fiyat ezilmez; düzenlemede birim değer temiz %\'ye döner',
        () {
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.eurobond);
      final n = c.read(addAssetFormProvider(args).notifier);
      n.setDate(gun);
      expect(n.selectEurobond(_tr28, _fiyat, priceEmpty: false).price, isNull);

      final birim = eurobondBirimDegeri(_tr28, 98.75, gun);
      final y = n.selectEurobond(_tr28, _fiyat,
          priceEmpty: true, duzenlemeBirimDegeri: birim);
      expect(y.price, '98,75');
      expect(c.read(addAssetFormProvider(args)).eurobondBirimFiyati(98.75),
          closeTo(birim, 1e-12));
    });

    test('tür değişince seçili tahvil düşer', () {
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.eurobond);
      final n = c.read(addAssetFormProvider(args).notifier);
      n.selectEurobond(_tr28, _fiyat, priceEmpty: true);
      n.selectType(AssetType.hisse);
      n.selectType(AssetType.eurobond);
      expect(c.read(addAssetFormProvider(args)).eurobondSozlesmesi, isNull);
    });
  });
}
