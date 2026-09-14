import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';

/// CSV yapıştırarak içe aktarma (Faz 3.5) — saf ayrıştırıcı.
void main() {
  final today = DateTime(2026, 9, 14);

  test('başlıklı, noktalı virgüllü, TR sayılı ekstre', () {
    const text = 'Sembol;Adet;Fiyat;Tarih\n'
        'THYAO;1.000;312,40;05.03.2026\n'
        'TCD;250,5;12,34;2026-01-10\n'
        'USD;500;;\n';
    final r = CsvImportService.parse(text, today: today);
    expect(r.errors, isEmpty);
    expect(r.rows.length, 3);
    expect(r.rows[0].ticker, 'THYAO.IS');
    expect(r.rows[0].type, AssetType.hisse);
    expect(r.rows[0].quantity, 1000);
    expect(r.rows[0].price, 312.40);
    expect(r.rows[0].addedDate, DateTime(2026, 3, 5));
    expect(r.rows[1].type, AssetType.fon);
    expect(r.rows[1].quantity, 250.5);
    expect(r.rows[1].addedDate, DateTime(2026, 1, 10));
    expect(r.rows[2].type, AssetType.doviz);
    expect(r.rows[2].ticker, 'USDTRY=X');
    expect(r.rows[2].currency, 'USD');
    expect(r.rows[2].price, 0, reason: 'boş fiyat → kapanış çekilecek');
    expect(r.rows[2].addedDate, today);
  });

  test('başlıksız, virgüllü, İngiliz sayılı; tırnaklı ad', () {
    const text = 'GARAN.IS,10,45.5,2026-02-01\n"ALTIN ÇEYREK",2,,01/02/2026\n';
    final r = CsvImportService.parse(text, today: today);
    expect(r.errors, isEmpty);
    expect(r.rows[0].ticker, 'GARAN.IS');
    expect(r.rows[0].price, 45.5);
    expect(r.rows[1].type, AssetType.altin);
    expect(r.rows[1].subCategory, 'ceyrek');
    expect(r.rows[1].unitType, 'piece');
  });

  test('tür sütunu çıkarımı ezer; hatalı satır atlanır ama diğerleri kalır', () {
    const text = 'kod\ttür\tadet\tfiyat\n'
        'ABC\tHisse\t5\t10\n'
        'XYZ\tfon\t0\t10\n'
        '\tfon\t3\t10\n'
        'DEF\tfon\t3\t10\t\n';
    final r = CsvImportService.parse(text, today: today);
    expect(r.rows.length, 2);
    expect(r.rows[0].type, AssetType.hisse);
    expect(r.rows[0].ticker, 'ABC.IS');
    expect(r.errors.length, 2);
    expect(r.errors[0], contains('adet'));
    expect(r.errors[1], contains('sembol'));
  });

  test('gelecek tarih ve boş metin reddedilir', () {
    expect(CsvImportService.parse('', today: today).errors, isNotEmpty);
    final r = CsvImportService.parse('THYAO;1;1;01.01.2027', today: today);
    expect(r.rows, isEmpty);
    expect(r.errors.single, contains('gelecekte'));
  });

  test('inferType', () {
    expect(CsvImportService.inferType('eur'), AssetType.doviz);
    expect(CsvImportService.inferType('xautry=x'), AssetType.altin);
    expect(CsvImportService.inferType('TCD'), AssetType.fon);
    expect(CsvImportService.inferType('thyao'), AssetType.hisse);
    expect(CsvImportService.inferType('TCD.IS'), AssetType.hisse);
    expect(CsvImportService.inferType('bitcoin-x'), AssetType.diger);
  });
}
