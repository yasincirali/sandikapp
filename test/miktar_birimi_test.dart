import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// "TOPLAM MİKTAR" alanının birim göstergesi.
///
/// ## Yakaladığı hata (2026-09-10)
/// Performans ekranı ham `unitType`'ı basıyordu ve kullanıcı
/// **"15.603,00 piece"** görüyordu. `unitType` bir DB sabitidir
/// ('piece', 'gram', 'ounce'); ekrana basılmak için değil.
///
/// Kullanıcı isteği: "fon ise lot, gram altın ise gram, çeyrek ise adet,
/// dolar ise de işaretleriyle gösterilmeli… tüm varlıklarda varlığa uygun
/// miktar göstergesiyle gözükmeli."
///
/// `unitLabel` bu eşlemeyi zaten yapıyordu — ekran onu kullanmıyordu.
Asset _a({
  required AssetType type,
  String unitType = 'piece',
  String ticker = 'X',
  String currency = 'TRY',
}) =>
    Asset(
      id: 'i',
      userId: 'u',
      name: 'n',
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 1,
      currency: currency,
      notes: '',
      isManualPrice: false,
      unitType: unitType,
    );

/// Testte sabit biçim — `fmtNum`'a (ve locale'e) bağlı kalmadan kuralı
/// ölçer. Ondalık hane sayısı MODELDEN gelir; test onu yalnızca uygular.
String _f(double v, int d) => v.toStringAsFixed(d);

void main() {
  group('unitLabel — kullanıcının verdiği örnekler', () {
    test('fon → lot', () {
      expect(_a(type: AssetType.fon).unitLabel, 'lot');
    });

    test('hisse → lot', () {
      expect(_a(type: AssetType.hisse).unitLabel, 'lot');
    });

    test('gram altın → gr', () {
      expect(_a(type: AssetType.altin, unitType: 'gram').unitLabel, 'gr');
    });

    test('çeyrek altın → adet (unitType "piece")', () {
      // Çeyrek/yarım/ata/reşat/cumhuriyet hepsi `'piece'` taşır
      // (bkz. asset_categories.dart). Ham değer basılsaydı kullanıcı
      // "3,00 piece" görürdü.
      expect(_a(type: AssetType.altin, unitType: 'piece').unitLabel, 'adet');
    });

    test('dolar → \$ işareti', () {
      final usd =
          _a(type: AssetType.doviz, ticker: 'USDTRY=X', currency: 'USD');
      expect(usd.unitLabel, '\$');
    });

    test('euro → € işareti', () {
      final eur =
          _a(type: AssetType.doviz, ticker: 'EURTRY=X', currency: 'EUR');
      expect(eur.unitLabel, '€');
    });
  });

  group('unitLabel — kalan türler de bir karşılık verir', () {
    // "tüm varlıklarda" isteğinin karşılığı: hiçbir tür ham sabite
    // düşmemeli.
    test('hiçbir tür ham unitType döndürmez', () {
      const hamlar = {'piece', 'gram', 'ounce', 'kilogram', 'liter', 'barrel'};
      for (final t in AssetType.values) {
        for (final u in hamlar) {
          final etiket = _a(type: t, unitType: u).unitLabel;
          expect(hamlar.contains(etiket), isFalse,
              reason: '$t + $u → "$etiket" ham sabit kalmış.');
          expect(etiket.trim(), isNotEmpty,
              reason: '$t + $u için birim boş.');
        }
      }
    });

    test('emtia birimleri korunur — oz, kg, lt, bbl', () {
      expect(_a(type: AssetType.emtia, unitType: 'ounce').unitLabel, 'oz');
      expect(_a(type: AssetType.emtia, unitType: 'kilogram').unitLabel, 'kg');
      expect(_a(type: AssetType.emtia, unitType: 'liter').unitLabel, 'lt');
      expect(_a(type: AssetType.emtia, unitType: 'barrel').unitLabel, 'bbl');
    });

    test('mevduat → ₺', () {
      expect(_a(type: AssetType.mevduat).unitLabel, '₺');
    });
  });

  group('miktarMetni — birim doğru YERDE durur', () {
    test('döviz sembolü ÖNE gelir', () {
      // "100 \$" değil "\$100" — para birimi konvansiyonu.
      final usd =
          _a(type: AssetType.doviz, ticker: 'USDTRY=X', currency: 'USD');
      expect(usd.miktarMetni(100, _f), '\$100');
    });

    test('diğer birimler SONA gelir', () {
      expect(_a(type: AssetType.fon).miktarMetni(15603, _f), '15603 lot');
      expect(_a(type: AssetType.altin, unitType: 'gram').miktarMetni(2.5, _f),
          '2.50 gr');
      expect(_a(type: AssetType.altin, unitType: 'piece').miktarMetni(3, _f),
          '3 adet');
    });
  });

  group('ondalık — tam sayıda ",00" YAZILMAZ', () {
    // Kullanıcı isteği (2026-09-10): "adet miktar olduğundan tam adetli
    // varlıklarda ,00 kullanmayalım."
    test('tam sayı miktar ondalıksız', () {
      expect(_a(type: AssetType.altin, unitType: 'piece').miktarMetni(3, _f),
          '3 adet');
      expect(_a(type: AssetType.fon).miktarMetni(15603, _f), '15603 lot');
    });

    test('KÜSURAT korunur — bilgi kaybı olmaz', () {
      // Sabit 0 haneye inmek miktarı yanlış okuturdu: 2,5 gram altın
      // "3 gr" ya da "2 gr" görünemez.
      expect(_a(type: AssetType.altin, unitType: 'gram').miktarMetni(2.5, _f),
          '2.50 gr');
      expect(_a(type: AssetType.fon).miktarMetni(10.75, _f), '10.75 lot');
    });

    test('kayan nokta gürültüsü tam sayı sayılır', () {
      // Miktar toplama/çıkarma işlemlerinden geçiyor; 0,1+0,2 gibi
      // birikimler 3.0000000000000004 üretebilir. Kullanıcı bunu
      // "3,00 adet" olarak görmemeli.
      final a = _a(type: AssetType.altin, unitType: 'piece');
      expect(a.miktarMetni(3.0000000000000004, _f), '3 adet');
      expect(a.miktarMetni(2.9999999999999996, _f), '3 adet');
    });

    test('miktarOndalik getter\'ı da aynı kuralı verir', () {
      expect(_a(type: AssetType.fon).miktarOndalik, 0); // quantity = 1
    });
  });

  test('ekran ham unitType BASMAZ', () {
    // Asıl regresyon buydu. Kaynak denetimi, çünkü ekranın canlı yolu
    // portföy sağlayıcısı ve ağ istiyor.
    final kaynak = File('lib/screens/performance_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(kaynak.contains(r'${widget.asset.unitType}'), isFalse,
        reason: 'Ham unitType yine ekrana basılıyor ("… piece").');
    expect(kaynak.contains('miktarMetni('), isTrue,
        reason: 'Ekran ortak biçimlendirmeyi kullanmıyor.');
  });
}
