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
    // 'USD' DEĞİL 'TRY' (2026-09-16 düzeltmesi): dövizde `purchasePrice`
    // kurun kendisidir, yani zaten TL cinsindendir. 'USD' yazılınca
    // `totalCostTRY` fiyatı bir kez daha `purchaseFxRate` ile çarpıyor ve
    // maliyet kur katı şişiyordu (ölçüldü: ₺84.700 → ₺3.260.950).
    // `add_asset_screen` de 'TRY' yazıyor; iki yol ayrışamaz.
    expect(r.rows[2].currency, 'TRY');
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

  // ── Türkçe büyük harf başlık + satır doğrulama (2026-09-23 denetimi U08)
  //
  // `toLowerCase()` "İ"yi "i̇" yapıyordu: "FİYAT"/"TARİH" eşleşmiyor, fiyat
  // 0 ve tarih bugün kalıyordu — negatif fiyat ve 2099 tarihi de bu yüzden
  // hiç okunmadan "geçiyordu".

  test('BÜYÜK HARF Türkçe başlıklar eşleşir (FİYAT, TARİH, TÜR)', () {
    const text = 'SEMBOL;ADET;FİYAT;TARİH;TÜR\n'
        'THYAO;10;312,40;05.03.2026;HİSSE\n';
    final r = CsvImportService.parse(text, today: today);
    expect(r.errors, isEmpty);
    final row = r.rows.single;
    expect(row.price, 312.40);
    expect(row.addedDate, DateTime(2026, 3, 5));
    expect(row.type, AssetType.hisse);
  });

  test('ASCII ve İngilizce büyük harf başlıklar da eşleşir', () {
    final a = CsvImportService.parse(
        'KOD;MIKTAR;ALIS;TARIH\nTHYAO;1;5;01.02.2026', today: today);
    expect(a.rows.single.price, 5);
    expect(a.rows.single.addedDate, DateTime(2026, 2, 1));
    final b = CsvImportService.parse(
        'SYMBOL;QUANTITY;PRICE;DATE\nTHYAO;1;7;2026-02-01', today: today);
    expect(b.rows.single.price, 7);
    expect(b.rows.single.addedDate, DateTime(2026, 2, 1));
  });

  test('negatif fiyat, uzak gelecek, okunamayan fiyat/tarih → satır hatası',
      () {
    const text = 'SEMBOL;ADET;FİYAT;TARİH\n'
        'THYAO;10;-5;01.02.2026\n'
        'GARAN;10;5;01.01.2099\n'
        'ASELS;10;abc;01.02.2026\n'
        'AKBNK;10;5;32.13.2026\n'
        'BIMAS;10;5;01.02.2026\n';
    final r = CsvImportService.parse(text, today: today);
    expect(r.rows.map((e) => e.ticker), ['BIMAS.IS']);
    expect(r.errors.length, 4);
    expect(r.errors[0], contains('negatif'));
    expect(r.errors[1], contains('gelecekte'));
    expect(r.errors[2], contains('fiyat okunamadı'));
    expect(r.errors[3], contains('tarih okunamadı'));
  });

  // ── Döviz maliyeti ÇİFTE ÇEVRİLMEZ (2026-09-16) ────────────────────────
  //
  // Ölçülen arıza: `USD;2200;38,50` satırı `currency: 'USD'` ile
  // kaydediliyordu. `Asset.totalCostTRY` = miktar × fiyat ×
  // `purchaseFxRate` olduğu için fiyat bir kez daha kurla çarpılıyor,
  // maliyet ₺84.700 yerine ₺3.260.950 çıkıyordu (38 kat). Portföy toplamı
  // ve bütün getiri yüzdeleri bozuluyordu.

  test('döviz satırı TRY olarak kaydedilir — fiyat zaten kurun kendisi', () {
    final r = CsvImportService.parse(
        'Sembol;Adet;Fiyat;Tarih\nUSD;2200;38,50;03.10.2025');
    expect(r.errors, isEmpty);
    final row = r.rows.single;
    expect(row.type, AssetType.doviz);
    expect(row.ticker, 'USDTRY=X');
    expect(row.currency, 'TRY',
        reason: 'USD yazılırsa totalCostTRY fiyatı ikinci kez kurla çarpar');
    expect(row.price, 38.50);
  });

  test('EUR ve GBP de aynı kuralı izler', () {
    final r = CsvImportService.parse(
        'Sembol;Adet;Fiyat\nEUR;100;45,20\nGBP;50;52,10');
    expect(r.rows.map((e) => e.currency).toSet(), {'TRY'});
    expect(r.rows.map((e) => e.ticker).toList(), ['EURTRY=X', 'GBPTRY=X']);
  });

  test('döviz DIŞI türlerde para birimi değişmez', () {
    // Düzeltme yalnızca dövizi ilgilendiriyor; hisse/fon/altın TRY kalmalı.
    final r = CsvImportService.parse(
        'Sembol;Adet;Fiyat\nTHYAO;10;300\nAFT;100;0,98\nALTIN_CEYREK;2;7850');
    expect(r.rows.map((e) => e.currency).toSet(), {'TRY'});
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
