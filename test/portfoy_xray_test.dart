import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/services/portfoy_xray.dart';

/// Portföy X-Ray birleştirmesi (Premium, 2026-10-10).
///
/// Kilitlenen kurallar (`portfoy_xray.dart` başlığı): doğrudan varlık tek
/// kovaya, fon/BES dağılım × TL değer; dağılımı olmayan fon ve Σ<100 farkı
/// "X-Ray dışı" (yeniden normalize EDİLMEZ); TL tutarlar `toTRY`'den;
/// fiyatsız pozisyon girmez; ortak lotları ve kapanmış pozisyon girmez;
/// örtüşme (Katman A) yalnız iki ve daha fazla kaynakta.
final _gun = DateTime(2026, 9, 1);

Asset _lot(
  String ticker,
  AssetType tur, {
  double miktar = 1,
  double fiyat = 100,
  String para = 'TRY',
  String? sub,
  String user = 'ben',
  AssetKind kind = AssetKind.buy,
  String? id,
}) =>
    Asset(
      id: id ?? '$user-$ticker-${kind.name}',
      userId: user,
      name: '$ticker adı',
      ticker: ticker,
      type: tur,
      subCategory: sub,
      quantity: miktar,
      purchasePrice: fiyat,
      currentPrice: fiyat,
      currency: para,
      notes: '',
      isManualPrice: false,
      kind: kind,
      addedDate: _gun,
    );

FonDagilimi _dag(String kod, Map<String, double> d, {DateTime? tarih}) =>
    FonDagilimi(
      fonKodu: kod,
      fonTipi: 'YAT',
      tarih: tarih ?? DateTime(2026, 10, 9),
      dagilim: d,
    );

double? _try(Position p) {
  final a = p.asDisplayAsset();
  if (a.currentPrice <= 0) return null;
  return switch (a.currency) {
    'USD' => a.totalValue * 40,
    _ => a.totalValue,
  };
}

PortfoyXray _xray(List<Asset> lotlar,
        {Map<String, FonDagilimi> dag = const {},
        Map<String, FonKalemleri> kalem = const {}}) =>
    portfoyXray(
      pozisyonlar: aggregatePositions(lotlar),
      deger: _try,
      dagilimlar: dag,
      kalemler: kalem,
    );

void main() {
  group('doğrudan varlıklar tek kovaya', () {
    test('hisse + altın + döviz + kripto + mevduat + eurobond + emtia + diğer',
        () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, fiyat: 300),
        _lot('AAPL', AssetType.hisse,
            miktar: 2, fiyat: 250, para: 'USD', sub: 'abd'),
        _lot('ALTIN_GRAM', AssetType.altin, miktar: 5, fiyat: 4000),
        _lot('USD', AssetType.doviz, miktar: 100, fiyat: 1, para: 'USD'),
        _lot('KRIPTO:BTC', AssetType.kripto, miktar: 0.01, fiyat: 4000000),
        _lot('MEV', AssetType.mevduat, miktar: 1, fiyat: 50000),
        _lot('US900123AL40', AssetType.eurobond,
            miktar: 1000, fiyat: 1, para: 'USD'),
        _lot('BZ=F', AssetType.emtia, miktar: 1, fiyat: 70, para: 'USD'),
        _lot('X', AssetType.diger, miktar: 1, fiyat: 123),
      ]);
      expect(x.kovalar[XrayKova.bistHisse], 3000);
      expect(x.kovalar[XrayKova.yabanciHisse], 2 * 250 * 40);
      expect(x.kovalar[XrayKova.kiymetliMaden], 20000);
      expect(x.kovalar[XrayKova.doviz], 4000);
      expect(x.kovalar[XrayKova.kripto], 40000);
      expect(x.kovalar[XrayKova.mevduat], 50000);
      expect(x.kovalar[XrayKova.dovizBorclanma], 40000);
      expect(x.kovalar[XrayKova.emtia], 2800);
      expect(x.kovalar[XrayKova.diger], 123);
      expect(x.xrayDisi, 0);
      expect(x.fonTarihleri, isNull);
      // Σ parça == bütün.
      expect(x.kovalar.values.fold(0.0, (t, v) => t + v), x.toplam);
    });
  });

  group('fonlar dağılımla bölünür', () {
    test('hisse + fon + altın + döviz: fonun TL değeri × kova yüzdesi', () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, fiyat: 100), // 1.000
        _lot('TEFAS:AAL', AssetType.fon, miktar: 1000, fiyat: 10), // 10.000
        _lot('ALTIN_GRAM', AssetType.altin, miktar: 1, fiyat: 4000), // 4.000
        _lot('USD', AssetType.doviz,
            miktar: 25, fiyat: 1, para: 'USD'), // 1.000
      ], dag: {
        'AAL': _dag('AAL', {'hs': 20, 'tr': 50, 'vmtl': 30}),
      });
      expect(x.toplam, 16000);
      expect(x.kovalar[XrayKova.bistHisse], 1000 + 2000);
      expect(x.kovalar[XrayKova.paraPiyasasi], 5000);
      expect(x.kovalar[XrayKova.mevduat], 3000);
      expect(x.kovalar[XrayKova.kiymetliMaden], 4000);
      expect(x.kovalar[XrayKova.doviz], 1000);
      expect(x.xrayDisi, 0);
      expect(x.pay(x.kovalar[XrayKova.bistHisse]!), closeTo(18.75, 1e-9));
      expect(x.siraliKovalar.first.key, XrayKova.paraPiyasasi);
    });

    test('BES fonu da dağılımla (EMK)', () {
      final x = _xray([
        _lot('AEA', AssetType.bes, miktar: 100, fiyat: 10),
      ], dag: {
        'AEA': _dag(
            'AEA', {'km': 18.46, 'kmbyf': 17.63, 'kmkks': 63.67, 'byf': 0.24}),
      });
      expect(x.kovalar[XrayKova.kiymetliMaden], closeTo(997.6, 1e-9));
      expect(x.kovalar[XrayKova.fon], closeTo(2.4, 1e-9));
    });

    test('öneksiz ve TEFAS: önekli kayıt aynı koda iner (fonKoduOf)', () {
      final x = _xray([
        _lot('aft', AssetType.fon, fiyat: 100)
      ], dag: {
        'AFT': _dag('AFT', {'yhs': 100})
      });
      expect(x.kovalar[XrayKova.yabanciHisse], 100);
    });

    test('kaynak tarihleri: en eski ve en yeni', () {
      final x = _xray([
        _lot('AAA', AssetType.fon),
        _lot('BBB', AssetType.fon),
      ], dag: {
        'AAA': _dag('AAA', {'hs': 100}, tarih: DateTime(2026, 10, 7)),
        'BBB': _dag('BBB', {'hs': 100}, tarih: DateTime(2026, 10, 9)),
      });
      expect(x.fonTarihleri, (DateTime(2026, 10, 7), DateTime(2026, 10, 9)));
    });
  });

  group('X-Ray dışı — yeniden normalize EDİLMEZ', () {
    test('dağılımı olmayan fonun bütün değeri ayrı satır', () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, fiyat: 100),
        _lot('YOK', AssetType.fon, miktar: 100, fiyat: 30),
      ]);
      expect(x.xrayDisi, 3000);
      expect(x.xrayDisiFonlar.single.kod, 'YOK');
      // Hisse payı yükseltilmedi: 1.000 / 4.000 = %25, %100 DEĞİL.
      expect(x.pay(x.kovalar[XrayKova.bistHisse]!), 25);
      expect(x.kovalar.containsKey(XrayKova.diger), isFalse);
    });

    test('Σ < 100 farkı X-Ray dışında; Σ > 100 kaynaktaki gibi', () {
      final eksik = _xray([
        _lot('AAA', AssetType.fon, miktar: 10, fiyat: 100)
      ], dag: {
        'AAA': _dag('AAA', {'hs': 60, 'dt': 30})
      });
      expect(eksik.kovalar[XrayKova.bistHisse], 600);
      expect(eksik.kovalar[XrayKova.devletBorclanma], 300);
      expect(eksik.xrayDisi, closeTo(100, 1e-9));
      expect(eksik.xrayDisiFonlar, isEmpty);

      final fazla = _xray([
        _lot('BBB', AssetType.fon, miktar: 10, fiyat: 100)
      ], dag: {
        'BBB': _dag('BBB', {'hs': 101})
      });
      expect(fazla.kovalar[XrayKova.bistHisse], closeTo(1010, 1e-9));
      expect(fazla.xrayDisi, 0);
    });

    test('kodsuz BES (sözleşme adı) X-Ray dışı, adıyla', () {
      final x = _xray([_lot('', AssetType.bes, fiyat: 500)]);
      expect(x.xrayDisi, 500);
      expect(x.xrayDisiFonlar.single.kod, isNull);
    });
  });

  group('kapsam', () {
    test('fiyatı bilinmeyen pozisyon girmez (portföy toplamıyla aynı kural)',
        () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse, fiyat: 100),
        _lot('FIYATSIZ.IS', AssetType.hisse, fiyat: 0),
      ]);
      expect(x.toplam, 100);
    });

    test('boş portföy', () {
      final x = _xray(const []);
      expect(x.bos, isTrue);
      expect(x.pay(10), 0);
    });
  });

  group('örtüşme (Katman A)', () {
    FonKalemleri kalem(String fon, List<(String, String, double)> l) =>
        FonKalemleri(
          fonKodu: fon,
          donem: DateTime(2026, 9, 30),
          kalemler: [
            for (final (kod, tur, a) in l)
              FonKalemi(ad: '$kod adı', kod: kod, tur: tur, agirlik: a),
          ],
        );

    test('THYAO üç fonda + doğrudan; tek kaynaklı hisse listede yok', () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, fiyat: 100), // 1.000
        _lot('AAA', AssetType.fon, miktar: 100, fiyat: 100), // 10.000
        _lot('BBB', AssetType.fon, miktar: 50, fiyat: 100), // 5.000
        _lot('CCC', AssetType.fon, miktar: 20, fiyat: 100), // 2.000
      ], dag: {
        'AAA': _dag('AAA', {'hs': 100}),
        'BBB': _dag('BBB', {'hs': 100}),
        'CCC': _dag('CCC', {'hs': 100}),
      }, kalem: {
        'AAA': kalem('AAA', [('THYAO', 'hisse', 8), ('ASELS', 'hisse', 5)]),
        'BBB':
            kalem('BBB', [('THYAO', 'hisse', 10), ('TRT1', 'borclanma', 50)]),
        'CCC': kalem('CCC', [('thyao', 'hisse', 5)]),
      });
      expect(x.ortusmeler.length, 1);
      final o = x.ortusmeler.single;
      expect(o.kod, 'THYAO');
      expect(o.fonlar, ['AAA', 'BBB', 'CCC']);
      expect(o.dogrudan, isTrue);
      expect(o.kaynakSayisi, 4);
      expect(o.tutar, closeTo(1000 + 800 + 500 + 100, 1e-9));
      expect(x.kalemDonemi, DateTime(2026, 9, 30));
    });

    test('ABD hissesi fon içindeki "AAPL US" ile eşleşir', () {
      final x = _xray([
        _lot('AAPL', AssetType.hisse,
            miktar: 1, fiyat: 100, para: 'USD', sub: 'abd'), // 4.000
        _lot('AFT', AssetType.fon, miktar: 10, fiyat: 100), // 1.000
      ], dag: {
        'AFT': _dag('AFT', {'yhs': 100}),
      }, kalem: {
        'AFT': kalem('AFT', [('AAPL US', 'yabanci_hisse', 10)]),
      });
      expect(x.ortusmeler.single.kod, 'AAPL US');
      expect(x.ortusmeler.single.tutar, closeTo(4100, 1e-9));
    });

    test('yalnız doğrudan tutulan hisse örtüşme değil; kalemsiz fon katılmaz',
        () {
      final x = _xray([
        _lot('THYAO.IS', AssetType.hisse),
        _lot('AAA', AssetType.fon),
      ], dag: {
        'AAA': _dag('AAA', {'hs': 100}),
      });
      expect(x.ortusmeler, isEmpty);
      expect(x.kalemDonemi, isNull);
    });
  });

  group('xrayPozisyonlariProvider — bugünkü, kendi lotların', () {
    ProviderContainer kap(List<Asset> lotlar) {
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith(_Oturum.new),
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<List<Position>> oku(ProviderContainer c) async {
      await c.read(authProvider.future);
      await c.read(portfolioProvider.future);
      return c.read(xrayPozisyonlariProvider);
    }

    test('ortağın lotları dahil değil', () async {
      final p = await oku(kap([
        _lot('THYAO.IS', AssetType.hisse, user: 'ben'),
        _lot('ASELS.IS', AssetType.hisse, user: 'ortak'),
        _lot('AAA', AssetType.fon, user: 'ortak'),
      ]));
      expect(p.map((x) => x.representative.ticker), ['THYAO.IS']);
    });

    test('kapanmış (tamamı satılmış) pozisyon dahil değil', () async {
      final p = await oku(kap([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, id: 'a1'),
        _lot('THYAO.IS', AssetType.hisse,
            miktar: 10, kind: AssetKind.sell, id: 's1'),
        _lot('ASELS.IS', AssetType.hisse, miktar: 5, id: 'a2'),
      ]));
      expect(p.map((x) => x.representative.ticker), ['ASELS.IS']);
    });

    test('kısmi satış: kalan miktar', () async {
      final p = await oku(kap([
        _lot('THYAO.IS', AssetType.hisse, miktar: 10, id: 'a1'),
        _lot('THYAO.IS', AssetType.hisse,
            miktar: 4, kind: AssetKind.sell, id: 's1'),
      ]));
      expect(p.single.totalQuantity, 6);
    });

    test('oturum yoksa boş', () async {
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith(_OturumYok.new),
        portfolioProvider
            .overrideWith(() => _Portfoy([_lot('THYAO.IS', AssetType.hisse)])),
      ]);
      addTearDown(c.dispose);
      await c.read(authProvider.future);
      await c.read(portfolioProvider.future);
      expect(c.read(xrayPozisyonlariProvider), isEmpty);
    });

    test('fon kodları sıralı ve tekil (fiyat turunda okuma tekrarlanmasın)',
        () async {
      final c = kap([
        _lot('TEFAS:BBB', AssetType.fon, id: 'b1'),
        _lot('AAA', AssetType.fon, id: 'a1'),
        _lot('AAA', AssetType.fon, id: 'a2'),
        _lot('AEA', AssetType.bes, id: 'e1'),
        _lot('THYAO.IS', AssetType.hisse, id: 't1'),
      ]);
      await c.read(authProvider.future);
      await c.read(portfolioProvider.future);
      expect(c.read(xrayFonKodlariProvider), 'AAA,AEA,BBB');
    });
  });
}

class _Oturum extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'ben', email: 'ben@x.com', displayName: 'Ben', createdAt: _gun);
}

class _OturumYok extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: 40, ownerId: 'ben');
}
