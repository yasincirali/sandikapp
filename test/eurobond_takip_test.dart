import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/services/canli_etkinlik_tarifi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';

/// Eurobond tek varlık olarak takip edilebilir mi (seri denetimi 2026-10-08).
///
/// Denetimden önce tahvil aramada hiç çıkmıyordu (takip listesine
/// eklenemezdi); çıksaydı `EUROBOND:` sembolü önek tanınmadığı için TRY
/// kote BIST hissesi sayılırdı — fiyat 100 kat küçük ve yanlış parada.
/// Alarm zili de varlık ekranında görünüyordu; sunucu alarmı tahvili
/// fiyatlayamadığı için kurulan alarm hiç tetiklenmezdi.
void main() {
  Map<String, dynamic> satir(String isin, String ad,
          {String para = 'USD', String vade = '2028-01-15'}) =>
      {
        'isin': isin,
        'ad': ad,
        'para_birimi': para,
        'kupon_orani': 0.09875,
        'vade': vade,
        'ihrac_yili': 2022,
        'kupon_sikligi': 2,
      };

  // ISIN'ler kontrol hanesi geçerli olanlar (`eurobond_test.dart`).
  final df45 = eurobondSozlesmesiFromMap(
      satir('US900123DF45', 'Türkiye %9,875 2028'))!;
  final eur = eurobondSozlesmesiFromMap(
      satir('XS1843443273', 'Türkiye EUR 2026', para: 'EUR'))!;

  group('arama katmanı', () {
    final kaynak = SymbolSearchService.eurobondKatalogKaynagi;
    var cagri = 0;

    setUp(() {
      SymbolSearchService.clearCacheForTest();
      cagri = 0;
      SymbolSearchService.eurobondKatalogKaynagi = () async {
        cagri++;
        return [(df45, null), (eur, null)];
      };
    });
    tearDown(() {
      SymbolSearchService.eurobondKatalogKaynagi = kaynak;
      RemoteConfigService.testAcik = {};
      SymbolSearchService.clearCacheForTest();
    });

    test('bayrak kapalıyken katalog İSTENMEZ, sonuç yok', () async {
      final r = await SymbolSearchService.instance.search('turkiye');
      expect(r.where((h) => h.source == SymbolSearchService.eurobondKaynagi),
          isEmpty);
      expect(cagri, 0);
    });

    test('bayrak açıkken Türkçe katlamayla ad ve ISIN ile bulunur', () async {
      RemoteConfigService.testAcik = {'eurobond'};
      final adla = await SymbolSearchService.instance.search('turkiye');
      final tahviller = adla
          .where((h) => h.source == SymbolSearchService.eurobondKaynagi)
          .toList();
      // EUR tahvil eklenemez (seri yalnız USD/TRY kurunu bilir).
      expect(tahviller.map((h) => h.ticker), ['EUROBOND:US900123DF45']);
      expect(tahviller.single.name, 'Türkiye %9,875 2028');

      final isinle = await SymbolSearchService.instance.search('us900123');
      expect(isinle.map((h) => h.ticker), contains('EUROBOND:US900123DF45'));
      // Katalog önbellekten: ikinci arama yeniden istemez.
      expect(cagri, 1);
    });

    test('katalog hata verirse arama düşmez', () async {
      RemoteConfigService.testAcik = {'eurobond'};
      SymbolSearchService.eurobondKatalogKaynagi =
          () async => throw StateError('ağ yok');
      final r = await SymbolSearchService.instance.search('THYAO');
      expect(r.map((h) => h.ticker), contains('THYAO.IS'));
    });
  });

  test('arama sonucu → kimlik: eurobond, USD (BIST hissesi DEĞİL)', () {
    final k = VarlikKimligi.fromSymbolHit(const SymbolHit(
      ticker: 'EUROBOND:US900123DF45',
      name: 'Türkiye %9,875 2028',
      source: SymbolSearchService.eurobondKaynagi,
    ))!;
    expect(k.type, AssetType.eurobond);
    expect(k.currency, 'USD');
    expect(k.ticker, 'EUROBOND:US900123DF45');
  });

  test('alarm: eurobond için sembol yok (zil gizli), ABD hissesi var', () {
    expect(alarmSembolu('EUROBOND:US900123DF45', null), isNull);
    expect(alarmSembolu('eurobond:US900123DF45', null), isNull);
    expect(alarmSembolu('AAPL', 'abd'), 'AAPL');
  });

  test('kilit ekranı: eurobond ve ABD hissesi oynayan parça', () {
    expect(CanliEtkinlikTarifi.oynayanTurler, contains(AssetType.eurobond));
    expect(CanliEtkinlikTarifi.oynayanTurler, contains(AssetType.hisse));
  });
}
