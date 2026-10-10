// Fiyat ve miktar hanesi (yasin, 2026-10-10): "yuvarlama yapmayalım, fiyat
// kaynaktan nasıl geliyorsa öyle gösterelim; 1.23000 ise 1,23 olsun,
// 1.00000012 ise öyle kalsın." Kural `goz_alici` arkasında; kapalıyken eski
// kural ([fiyatOndaligi]) — ama sabit 2 hanenin ₺0,00 hatası her durumda
// kapalı.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

Asset _asset(AssetType type, double qty) => Asset(
      id: 'a',
      userId: 'u',
      name: 'x',
      ticker: 'X',
      type: type,
      quantity: qty,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 1,
      addedDate: DateTime(2026, 3, 14),
    );

WatchlistItem _takip(AssetType type, double fiyat) => WatchlistItem(
      id: '1',
      userId: 'u',
      ticker: 'X',
      name: 'x',
      type: type,
      currency: 'TRY',
      addedAt: DateTime(2026),
      currentPrice: fiyat,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  tearDown(() => RemoteConfigService.testAcik.remove('goz_alici'));

  group('kaynak hassasiyeti (azami verildi)', () {
    String f(double v, int azami) => fmtFiyat(v, azami: azami);

    test('sondaki sıfırlar atılır, en az 2 hane kalır', () {
      expect(f(1.23000, 8), '₺1,23');
      expect(f(5, 8), '₺5,00');
      expect(f(1.2, 6), '₺1,20');
    });
    test('kaynaktaki haneler yuvarlanmaz', () {
      expect(f(1.00000012, 8), '₺1,00000012');
      expect(f(1.234567, 6), '₺1,234567');
      expect(f(41.6789, 6), '₺41,6789');
      expect(f(0.000412, 8), '₺0,000412');
      expect(f(4523456.78, 8), '₺4.523.456,78');
    });
    test('türün standardını aşan hesap artığı kesilir', () {
      expect(f(0.1 + 0.2, 8), '₺0,30');
      expect(f(9387.512345678, 4), '₺9.387,5123');
    });
  });

  test('tür standartları', () {
    expect(AssetType.fon.fiyatAzamiOndalik, 6);
    expect(AssetType.bes.fiyatAzamiOndalik, 6);
    expect(AssetType.doviz.fiyatAzamiOndalik, 6);
    expect(AssetType.hisse.fiyatAzamiOndalik, 4);
    expect(AssetType.kripto.fiyatAzamiOndalik, 8);
  });

  group('bayrak kapalı', () {
    test('eski kural birebir; ₺0,00 yok', () {
      expect(AssetType.fon.fiyatHassasiyeti, isNull);
      expect(takipFiyatMetni(_takip(AssetType.fon, 1.234567)), '₺1,23');
      expect(takipFiyatMetni(_takip(AssetType.kripto, 0.000412)),
          isNot('₺0,00'));
      expect(takipFiyatMetni(_takip(AssetType.bes, 0.179147)), '₺0,1791');
    });
    test('miktar eski kural', () {
      expect(_asset(AssetType.fon, 10.7538).miktarOndalik, 2);
      expect(_asset(AssetType.fon, 10.7538).azamiOndalik, 4);
    });
  });

  group('bayrak açık (goz_alici)', () {
    setUp(() => RemoteConfigService.testAcik.add('goz_alici'));

    test('takip satırı kaynak hassasiyetinde', () {
      expect(takipFiyatMetni(_takip(AssetType.fon, 1.234567)), '₺1,234567');
      expect(takipFiyatMetni(_takip(AssetType.hisse, 312.75)), '₺312,75');
      expect(takipFiyatMetni(_takip(AssetType.kripto, 1.00000012)),
          '₺1,00000012');
    });
    test('miktar girildiği kadar, sıfırsız', () {
      final pay = _asset(AssetType.fon, 10.7538);
      expect(pay.miktarMetni(10.7538, (v, d) => fmtNum(v, digits: d)),
          contains('10,7538'));
      final gram = _asset(AssetType.altin, 2.5);
      expect(gram.miktarMetni(2.5, (v, d) => fmtNum(v, digits: d)),
          startsWith('2,5 '));
      expect(_asset(AssetType.hisse, 1500).miktarOndalik, 0);
      expect(pay.azamiOndalik, 8);
    });
  });
}
