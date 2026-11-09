import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Yurt dışı aracı kurum dökümü (Midas tarzı, 2026-10-15; yasin: "Midas
/// gibi yabancı piyasa aracı kurumlarında varlık PDF ya da Excelleri de
/// işlemde kullanılabilmeli"). Önceden USD'li "AAPL" satırı `AAPL.IS`
/// (olmayan BIST hissesi), üç harfli "AMD" TEFAS fonu yazılıyordu. Düzen
/// uydurma; gerçek örnek gelince ona göre genişler.
void main() {
  setUp(() => CsvImportService.abdHisseAcik = () => true);

  group('abdSatiriMi', () {
    test('tür hücresi ABD diyorsa', () {
      expect(CsvImportService.abdSatiriMi('AAPL', 'ABD Hissesi', null), isTrue);
      expect(CsvImportService.abdSatiriMi('SPY', 'US ETF', null), isTrue);
    });

    test('USD + hisse sembolü biçimi; BIST kodu ve döviz kodu değil', () {
      expect(CsvImportService.abdSatiriMi('AMD', null, 'USD'), isTrue);
      expect(CsvImportService.abdSatiriMi('BRK.B', 'Hisse', r'$'), isTrue);
      expect(CsvImportService.abdSatiriMi('THYAO', null, 'USD'), isFalse);
      expect(CsvImportService.abdSatiriMi('USD', null, 'USD'), isFalse);
      expect(CsvImportService.abdSatiriMi('AAPL', 'Altın', 'USD'), isFalse);
    });

    test('USD işareti yoksa eski davranış (AMD fon kodu da olabilir)', () {
      expect(CsvImportService.abdSatiriMi('AMD', null, null), isFalse);
      expect(CsvImportService.abdSatiriMi('AMD', null, 'TRY'), isFalse);
    });
  });

  test('para birimi sütunlu satır ABD hissesi olarak eklenir', () {
    final r = CsvImportService.parse(
        'sembol;adet;fiyat;para birimi\nAAPL;10;150,5;USD\nTHYAO;100;312,4;TRY');
    expect(r.errors, isEmpty);
    expect(
        r.rows.map((x) => (x.type, x.ticker, x.currency, x.subCategory)), [
      (AssetType.hisse, 'AAPL', 'USD', StockSubCategory.abd.name),
      (AssetType.hisse, 'THYAO.IS', 'TRY', null),
    ]);
  });

  test('bayrak kapalıyken ABD satırı eklenmez, nedeni söylenir', () {
    CsvImportService.abdHisseAcik = () => false;
    final r = CsvImportService.parse(
        'sembol;adet;fiyat;para birimi\nAAPL;10;150,5;USD');
    expect(r.rows, isEmpty);
    expect(r.errors.single, contains('ABD hissesi'));
  });

  test('dolar işaretli döküm: para birimi sütunu yokken USD yazılır', () {
    final s = ekstreyiAnla(EkstreBicimi.xlsx, const [
      EkstreTablosu(kaynak: 'Portföy', satirlar: [
        ['Sembol', 'Adet', 'Ortalama Maliyet', 'Piyasa Değeri'],
        ['AAPL', '10', r'$150.00', r'$2,500.00'],
        ['AMD', '5', r'$100.00', r'$800.00'],
        ['BRK.B', '2', r'$400.00', r'$900.00'],
      ]),
    ], '');
    final r = CsvImportService.parse(s.kanonikMetin());
    expect(r.errors, isEmpty);
    expect(r.rows.map((x) => (x.ticker, x.quantity, x.price, x.currency)), [
      ('AAPL', 10.0, 150.0, 'USD'),
      ('AMD', 5.0, 100.0, 'USD'),
      ('BRK-B', 2.0, 400.0, 'USD'),
    ]);
    expect(r.rows.every((x) => x.subCategory == StockSubCategory.abd.name),
        isTrue);
  });
}
