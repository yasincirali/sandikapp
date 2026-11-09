import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';

/// Zirvedeki portföylerin varlık bazında payları (0158, yasin 2026-10-19:
/// "detaylı varlıkların yüzdelerini anonim ve miktardan bağımsız oransal
/// olarak göstermek").
///
/// Değişmezler:
///  - Cihazdan/sunucudan çıkan şey yalnız SEMBOL + PAY; ad, not, miktar yok.
///  - Kamuya açık sembolü olmayan (elle fiyat, mevduat, uymayan kod) kalem
///    "DIGER"e düşer; mevduat hiç sayılmaz (fon_detay ile aynı kural).
///  - Kilitli kalem (`?n`) adıyla değil "••••" ile yazılır, ortaklık
///    hesabına girmez (sembol cihazda yok).
///  - Benzerlik = Σ min; sunucudaki `zirve_benzerlik_hesapla` ile aynı.
void main() {
  group('varlikAnahtari / varlikAdi', () {
    test('kamuya açık sembol büyük harfle; uymayan DIGER', () {
      expect(ZirveKiyas.varlikAnahtari('hisse', 'thyao.is', null), 'THYAO.IS');
      expect(ZirveKiyas.varlikAnahtari('kripto', 'BTCUSDT', null), 'BTCUSDT');
      expect(ZirveKiyas.varlikAnahtari('hisse', 'Benim hissem', null),
          ZirveKiyas.fonDiger);
      expect(ZirveKiyas.varlikAnahtari('hisse', null, null), ZirveKiyas.fonDiger);
    });

    test('altın kodu alt kategoriden çözülür', () {
      expect(ZirveKiyas.varlikAnahtari('altin', '', 'Çeyrek Altın'),
          'ALTIN_CEYREK');
      expect(ZirveKiyas.varlikAnahtari('altin', 'ALTIN_GRAM24', null),
          'ALTIN_GRAM24');
      expect(ZirveKiyas.varlikAnahtari('altin', '', 'bilinmeyen'),
          ZirveKiyas.fonDiger);
    });

    test('okunur ad', () {
      expect(ZirveKiyas.varlikAdi('THYAO.IS'), 'THYAO');
      expect(ZirveKiyas.varlikAdi('BTCUSDT'), 'BTC');
      expect(ZirveKiyas.varlikAdi('USDTRY=X'), 'USD');
      expect(ZirveKiyas.varlikAdi('ALTIN_CEYREK'), 'Çeyrek Altın');
      expect(ZirveKiyas.varlikAdi('GC=F'), 'GC');
      expect(ZirveKiyas.varlikAdi('?1'), 'Diğer');
      expect(ZirveKiyas.varlikAdi(ZirveKiyas.fonDiger), 'Diğer');
    });

    test('kilitli kod öneki', () {
      expect(ZirveKiyas.kilitliMi('?2'), isTrue);
      expect(ZirveKiyas.kilitliMi('THYAO.IS'), isFalse);
      expect(ZirveKiyas.mevduatMi('mevduat:abc'), isTrue);
      expect(ZirveKiyas.mevduatMi('AFT'), isFalse);
    });
  });

  group('özet ve ortaklık', () {
    const fon = {'AFT': 10.0, ZirveKiyas.fonDiger: 2.0};
    const varlik = {
      'hisse': {'THYAO.IS': 30.0, '?2': 12.0},
      'kripto': {'BTCUSDT': 20.0},
    };

    test('ayrıntı özeti: büyükten küçüğe, kilitli "••••", kalan "diğer"', () {
      expect(ZirveKiyas.ayrintiOzeti(fon, varlik, enFazla: 3),
          'THYAO %30 · BTC %20 · •••• %12 · diğer %12');
      expect(ZirveKiyas.ayrintiOzeti(const {}, const {}), '');
    });

    test('ortak kalemler kilitliyi ve DIGER\'i saymaz; benzerlik Σ min', () {
      final ortak = ZirveKiyas.ortakKalemler(
        senFon: const {'AFT': 4.0, ZirveKiyas.fonDiger: 9.0},
        senVarlik: const {
          'hisse': {'THYAO.IS': 50.0, 'ASELS.IS': 5.0},
        },
        zirveFon: fon,
        zirveVarlik: varlik,
      );
      expect([for (final o in ortak) o.kod], ['THYAO.IS', 'AFT']);
      expect(ZirveKiyas.benzerlik(ortak), 34);
      expect(ZirveKiyas.benzerlikCumlesi(34),
          'Seninle %34 benzer: aynı varlıklarda ortak payınız.');
      expect(ZirveKiyas.benzerlikCumlesi(0), 'Seninle ortak varlığı yok.');
    });
  });

  group('sunucu satırı (zirve_portfoyleri_ayrinti)', () {
    test('varlık ayrıntısı, kilit ve benzerlik okunur; bozuk satır atlanır',
        () {
      final l = LeaderboardService.zirveSatirlari([
        {
          'rank': 1,
          'roi_pct': 12.5,
          'allocation_pct': {'hisse': 60, 'fon': 40},
          'fon_detay': {'AFT': 40},
          'varlik_detay': {
            'hisse': {'THYAO.IS': 50, '?1': 10},
            'bos': <String, dynamic>{},
          },
          'ayrinti_kilitli': true,
          'benzerlik': 7.5,
          'ben': false,
        },
        {'rank': null, 'roi_pct': 1},
        'bozuk',
      ]);
      expect(l, hasLength(1));
      final r = l.single;
      expect(r.varlikDetay, {
        'hisse': {'THYAO.IS': 50.0, '?1': 10.0},
      });
      expect(r.ayrintiKilitli, isTrue);
      expect(r.benzerlik, 7.5);
      expect(r.fonDetay, {'AFT': 40.0});
    });

    test('eski sahip (varlik_detay null) boş ayrıntıyla gelir', () {
      final r = LeaderboardService.zirveSatirlari([
        {
          'rank': 2,
          'roi_pct': 3,
          'allocation_pct': {'hisse': 100},
          'varlik_detay': null,
        },
      ]).single;
      expect(r.varlikDetay, isEmpty);
      expect(r.ayrintiKilitli, isFalse);
      expect(r.benzerlik, isNull);
    });

    test('yanıt liste değilse boş', () {
      expect(LeaderboardService.zirveSatirlari(null), isEmpty);
      expect(LeaderboardService.zirveSatirlari({'a': 1}), isEmpty);
    });
  });

  group('kendi ayrıntın (computeVarlikDetay)', () {
    Asset varlik(String id, AssetType tur, String ticker, double tutar,
            {bool elle = false, String? alt}) =>
        Asset(
          id: id,
          userId: 'u1',
          name: 'Kullanıcının verdiği ad',
          ticker: ticker,
          type: tur,
          quantity: 1,
          purchasePrice: tutar,
          currency: 'TRY',
          notes: 'gizli not',
          isManualPrice: elle,
          subCategory: alt,
          addedDate: DateTime(2026, 1, 1),
        );

    test('fon ve mevduat dışarıda; elle fiyat ve %1 altı DIGER', () {
      final d = LeaderboardService.instance.computeVarlikDetay([
        varlik('1', AssetType.hisse, 'THYAO.IS', 500),
        varlik('2', AssetType.hisse, 'XYZ.IS', 5),
        varlik('3', AssetType.kripto, 'BTCUSDT', 200),
        varlik('4', AssetType.fon, 'AFT', 200),
        varlik('5', AssetType.mevduat, 'MEVDUAT:1', 50),
        varlik('6', AssetType.diger, 'ARSA', 45, elle: true),
      ], (v, _) => v);
      // Toplam 1000 TL (mevduat dahil — pay tabanı tüm portföy).
      expect(d, {
        'hisse': {'THYAO.IS': 50.0, ZirveKiyas.fonDiger: 0.5},
        'kripto': {'BTCUSDT': 20.0},
        'diger': {ZirveKiyas.fonDiger: 4.5},
      });
      final metin = d.toString();
      expect(metin.contains('Kullanıcının'), isFalse);
      expect(metin.contains('gizli'), isFalse);
    });
  });
}
