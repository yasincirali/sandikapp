import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

import 'helpers/kaynak.dart';

/// Defter fiyat turlarında sunucudan yeniden okunur (2026-10-03).
///
/// Kullanıcı bildirimi: "Bir cihazda varlık ekleyince diğerinde kill edip
/// açana kadar varlıklar gözükmedi." Defter yalnız `build()`'de okunuyordu;
/// fiyat turları bellekteki listeyi tazeliyordu. Ayrıca fiyat yazımı tüm
/// satırı yazıyor, bayat cihaz başka cihazdaki miktar düzeltmesini geri
/// alabiliyordu.
Asset _lot(String id,
        {double adet = 10,
        double fiyat = 100,
        DateTime? guncel,
        bool elle = false}) =>
    Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: id,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: 90,
      currency: 'TRY',
      notes: '',
      isManualPrice: elle,
      currentPrice: fiyat,
      lastUpdated: guncel,
      // Sabit: verilmezse kurucu `DateTime.now()` yazar ve iki `_lot('A')`
      // farklı mikrosaniyede doğar — `ayniDefter` addedDate'e baktığı için
      // Linux CI'da "aynı" lotlar farklı çıkıyordu (Windows'ta saat
      // çözünürlüğü kaba olduğundan yerelde geçiyordu).
      addedDate: DateTime(2026, 9, 1),
    );

void main() {
  final eski = DateTime(2026, 10, 3, 10);
  final yeni = DateTime(2026, 10, 3, 10, 5);

  group('defteriBirlestir', () {
    test('başka cihazda eklenen lot deftere girer', () {
      final sonuc = PortfolioNotifier.defteriBirlestir(
        [_lot('YENI'), _lot('A')],
        [_lot('A')],
      );
      expect(sonuc.map((a) => a.id), ['YENI', 'A']);
    });

    test('bellekteki daha taze canlı fiyat korunur', () {
      final sonuc = PortfolioNotifier.defteriBirlestir(
        [_lot('A', fiyat: 100, guncel: eski)],
        [_lot('A', fiyat: 105, guncel: yeni)],
      );
      expect(sonuc.single.currentPrice, 105);
      expect(sonuc.single.lastUpdated, yeni);
    });

    test('sunucunun fiyatı daha tazeyse sunucu kazanır', () {
      final sonuc = PortfolioNotifier.defteriBirlestir(
        [_lot('A', fiyat: 110, guncel: yeni)],
        [_lot('A', fiyat: 105, guncel: eski)],
      );
      expect(sonuc.single.currentPrice, 110);
    });

    test('miktar sunucudan gelir (başka cihazdaki düzeltme)', () {
      final sonuc = PortfolioNotifier.defteriBirlestir(
        [_lot('A', adet: 7, guncel: eski)],
        [_lot('A', adet: 10, guncel: yeni)],
      );
      expect(sonuc.single.quantity, 7);
    });

    test('elle fiyatlı lotta sunucu esastır', () {
      final sonuc = PortfolioNotifier.defteriBirlestir(
        [_lot('A', fiyat: 50, guncel: eski, elle: true)],
        [_lot('A', fiyat: 40, guncel: yeni, elle: true)],
      );
      expect(sonuc.single.currentPrice, 50);
    });
  });

  group('ayniDefter', () {
    test('yalnız canlı fiyat farkı defter farkı değildir', () {
      expect(
          PortfolioNotifier.ayniDefter(
              [_lot('A', fiyat: 100)], [_lot('A', fiyat: 120)]),
          isTrue);
    });
    test('miktar, eklenen ve silinen lot fark sayılır', () {
      expect(
          PortfolioNotifier.ayniDefter([_lot('A')], [_lot('A', adet: 3)]),
          isFalse);
      expect(PortfolioNotifier.ayniDefter([_lot('A')], [_lot('A'), _lot('B')]),
          isFalse);
      final silinmis = _lot('A').copyWithDeletedAt(DateTime(2026));
      expect(PortfolioNotifier.ayniDefter([_lot('A')], [silinmis]), isFalse);
    });
  });

  group('kaynak sözleşmesi', () {
    final provider =
        ekranKaynagiSync('lib/providers/portfolio_provider.dart');
    final servis = ekranKaynagiSync('lib/services/supabase_service.dart');

    test('fiyat turu tüm satırı değil yalnız fiyatı yazar', () {
      final i = provider.indexOf('void _fiyatlariYaz(');
      final govde = provider.substring(i, provider.indexOf('\n  }\n', i));
      expect(govde, contains('fiyatYaz('));
      expect(govde, isNot(contains('updateAsset(')));

      final j = servis.indexOf('Future<void> fiyatYaz(');
      final fiyatYaz = servis.substring(j, servis.indexOf('\n  }\n', j));
      expect(fiyatYaz, contains("'current_price'"));
      expect(fiyatYaz, isNot(contains('quantity')));
      expect(fiyatYaz, isNot(contains('toSupabase')));
    });

    test('defter boşluk kontrolünden önce tazelenir', () {
      final i = provider.indexOf('Future<void> _fiyatTuru(');
      final tazele = provider.indexOf('_defteriTazele(s)', i);
      final bos = provider.indexOf('if (s.assets.isEmpty) return;', i);
      expect(tazele, greaterThan(i));
      expect(tazele, lessThan(bos));
    });
  });
}
