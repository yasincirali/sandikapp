import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/fon_karnesi.dart';

/// Emülatör bulgusu #2 (2026-09-29): eski fon kaydı `AFT` (ticker'da
/// `TEFAS:` öneki yok) fiyatlanmıyordu, portföy ~₺24.500 eksikti ve aramada
/// "Portföyünde" rozeti çıkmıyordu.
///
/// Düzeltme OKUMA tarafında: `Asset.fromSupabase` sembolü `kanonikTicker`
/// ile `TEFAS:AFT`'ye çevirir; `toSupabase` kayıtlı biçimi geri yazar —
/// veri göçü yok.
void main() {
  Map<String, dynamic> satir({
    String ticker = 'AFT',
    String type = 'fon',
    bool manuel = false,
    String id = 'eski',
  }) =>
      {
        'id': id,
        'user_id': 'u',
        'name': 'Ak Portföy Yeni Teknolojiler',
        'ticker': ticker,
        'type': type,
        'quantity': 70000,
        'purchase_price': 0.69,
        'currency': 'TRY',
        'current_price': 0.69,
        'is_manual_price': manuel,
        'added_date': '2025-06-01T00:00:00Z',
      };

  group('kanonikTicker', () {
    String k(String t, {AssetType tur = AssetType.fon, bool manuel = false}) =>
        kanonikTicker(type: tur, ticker: t, isManualPrice: manuel);

    test('öneksiz TEFAS kodu önek alır (küçük harf/boşluk dahil)', () {
      expect(k('AFT'), 'TEFAS:AFT');
      expect(k(' aft '), 'TEFAS:AFT');
      expect(k('TI2'), 'TEFAS:TI2', reason: 'TEFAS kodunda rakam olabilir');
    });

    test('idempotent — önekli kod olduğu gibi kalır', () {
      expect(k('TEFAS:AFT'), 'TEFAS:AFT');
      expect(k(k('AFT')), 'TEFAS:AFT');
    });

    test('elle fiyatlı fon, TEFAS biçiminde olmayan kod, başka tür: dokunulmaz',
        () {
      expect(k('AFT', manuel: true), 'AFT',
          reason: 'Elle fiyatlı kayıtta kod etikettir, fiyat kaynağı değil.');
      expect(k('GLDTR.IS'), 'GLDTR.IS',
          reason: 'Bugün Yahoo\'dan fiyat alan eski kayıt bozulmamalı.');
      expect(k('ABCD'), 'ABCD');
      expect(k(''), '');
      expect(k('AFT', tur: AssetType.hisse), 'AFT');
    });
  });

  group('okuma sınırı (Asset.fromSupabase / toSupabase)', () {
    test('eski satır kanonik sembolle okunur', () {
      final a = Asset.fromSupabase(satir());
      expect(a.ticker, 'TEFAS:AFT');
      expect(a.displayTicker, 'AFT', reason: 'Kullanıcı yine `AFT` görür.');
      expect(fonKoduOf(tur: a.type, ticker: a.ticker), 'AFT');
    });

    test('yazarken KAYITLI biçim geri konur — veri göçü yok', () {
      final a = Asset.fromSupabase(satir());
      expect(a.toSupabase()['ticker'], 'AFT',
          reason: '`updateAsset` gövdenin tamamını yazar; her fiyat turu eski '
              'satırı sessizce değiştirmemeli.');
      // Silme/geri alma kopyası da aynı kuralı taşır.
      expect(a.copyWithDeletedAt(DateTime(2026)).toSupabase()['ticker'], 'AFT');
      expect(a.copyWithNotes('not').toSupabase()['ticker'], 'AFT');
    });

    test('kullanıcı sembolü değiştirirse YENİ değer yazılır', () {
      final a = Asset.fromSupabase(satir())..ticker = 'TEFAS:TTE';
      expect(a.toSupabase()['ticker'], 'TEFAS:TTE');
    });

    test('yeni (önekli) satır ve başka türler aynen gidip gelir', () {
      final yeni = Asset.fromSupabase(satir(ticker: 'TEFAS:AFT'));
      expect(yeni.ticker, 'TEFAS:AFT');
      expect(yeni.toSupabase()['ticker'], 'TEFAS:AFT');
      final hisse =
          Asset.fromSupabase(satir(ticker: 'THYAO.IS', type: 'hisse'));
      expect(hisse.toSupabase()['ticker'], 'THYAO.IS');
      final manuel = Asset.fromSupabase(satir(manuel: true));
      expect(manuel.ticker, 'AFT');
      expect(manuel.toSupabase()['ticker'], 'AFT');
    });
  });

  group('kimlik', () {
    test('eski ve yeni AFT lot\'u AYNI pozisyonda toplanır', () {
      final eski = Asset.fromSupabase(satir());
      final yeni = Asset.fromSupabase(satir(ticker: 'TEFAS:AFT', id: 'yeni'));
      expect(positionKey(eski), positionKey(yeni));
      expect(aggregatePositions([eski, yeni]), hasLength(1));
    });

    test('ortak sınırı KORUNUR — sahip ayrımı positionKey\'e girmez', () {
      // `positionKey` sahip taşımaz (bellek: ortak aggregation değişmezi);
      // kanonikleştirme bunu değiştirmez, sahip ayrımı çağıranın işi.
      final ben = Asset.fromSupabase(satir());
      final ortak = Asset.fromSupabase(
          {...satir(ticker: 'TEFAS:AFT', id: 'o'), 'user_id': 'ortak'});
      expect(positionKey(ben), positionKey(ortak));
      expect(ben.userId == ortak.userId, isFalse);
    });

    test('aramadaki fon kimliği portföydeki eski kayıtla eşleşir (rozet)', () {
      final a = Asset.fromSupabase(satir());
      final kimlik = VarlikKimligi.fon('AFT', 'Ak Portföy');
      expect(
          varlikAnahtari(
              type: a.type, ticker: a.ticker, subCategory: a.subCategory),
          kimlik.key,
          reason: '"Portföyünde" rozeti bu anahtarla karar veriyor.');
    });
  });

  test('CSV içe aktarma fonu önekli yazar', () {
    final r = CsvImportService.parse('TCD;250;12,34;2026-01-10\n',
        today: DateTime(2026, 9, 29));
    expect(r.errors, isEmpty);
    expect(r.rows.single.type, AssetType.fon);
    expect(r.rows.single.ticker, 'TEFAS:TCD');
    expect(r.rows.single.name, 'TCD');
  });
}
