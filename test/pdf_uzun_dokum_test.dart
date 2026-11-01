import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';

/// Portföy dökümü PDF'i uzun işlem geçmişinde de üretilir (yasin
/// 2026-11-01 "pdf dışarı aktar çalışmıyor"): `pdf` paketinin 20 sayfa
/// varsayılan sınırı 750 işlemli hesapta belgeyi hiç üretmiyordu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (varlik, islem) in [(10, 3), (40, 3), (25, 30)]) {
    test('pdf $varlik varlık × $islem işlem', () async {
      await initializeDateFormatting('tr_TR');
      final lotlar = <Asset>[
        for (var v = 0; v < varlik; v++)
          for (var i = 0; i < islem; i++)
            Asset(
              id: '$v-$i', userId: 'u', name: 'Varlık uzun adı $v ğüşıöç',
              ticker: 'TCK$v', type: AssetType.values[v % 4], quantity: 10.0 + i,
              purchasePrice: 100, currency: v % 5 == 0 ? 'USD' : 'TRY', notes: '',
              isManualPrice: false, currentPrice: 120,
              kind: i % 7 == 6 ? AssetKind.sell : AssetKind.buy, sellPrice: 130,
              addedDate: DateTime(2025, 1, 1).add(Duration(days: v * 3 + i)),
            ),
      ];
      final b = portfoyBelgesi(lotlar: lotlar, tlYap: (t, c) => c == 'USD' ? t * 42 : t,
          kim: 'yasin', olusturma: DateTime(2026, 11, 1, 18));
      final bytes = await pdfYaz(b,
          duz: await rootBundle.load('assets/fonts/DMSans-Regular.ttf'),
          kalin: await rootBundle.load('assets/fonts/DMSans-Bold.ttf'),
          logo: (await rootBundle.load('assets/images/sandik_icon.png')).buffer.asUint8List());
      expect(bytes.length, greaterThan(1000));
    });
  }
}
