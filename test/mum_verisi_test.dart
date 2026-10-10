import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Gerçek mum verisi — TradingView'deki gibi aralık seçilen mum grafiği
/// (yasin, 2026-10-10: "1 dk, 1 saat, 4 saat, günlük, haftalık, aylık
/// grafik verisi çekilebilmeli").
///
/// Kilitlenenler: kaynak kararı (tür başına hangi sağlayıcı, hangi
/// aralıklar), ayrıştırma (Yahoo boş satırları), uydurma yok (kuru
/// olmayan bar düşer, fona gün içi mum yok), ölçek ve son mumun canlı fiyata
/// sabitlenmesi, seçicinin sunacağı aralıklar.
void main() {
  Asset varlik({
    required AssetType type,
    String ticker = 'THYAO.IS',
    String currency = 'TRY',
    bool manuel = false,
  }) =>
      Asset(
        id: 'x',
        userId: 'u',
        name: ticker,
        ticker: ticker,
        type: type,
        quantity: 1,
        purchasePrice: 1,
        currency: currency,
        notes: '',
        currentPrice: 1,
        addedDate: DateTime(2026, 1, 1),
        isManualPrice: manuel,
      );

  OhlcBar bar(int t, double o, double h, double l, double c, {double? v}) =>
      OhlcBar(t: t, acilis: o, enYuksek: h, enDusuk: l, kapanis: c, hacim: v);

  const dk = 60 * 1000;
  const gun = 24 * 60 * dk;

  group('kaynak kararı (FiyatKaynagi.mumKaynagi)', () {
    test('BIST hissesi: Yahoo, TL, hiza yok, altı aralık', () {
      final k = FiyatKaynagi.mumKaynagi(varlik(type: AssetType.hisse));
      expect(k.tur, MumKaynakTuru.yahoo);
      expect(k.sembol, 'THYAO.IS');
      expect(k.usdCevir, isFalse);
      expect(k.olcekAlt, isNull);
      expect(k.araliklar, MumAraligi.values);
      expect(k.gercekOhlc, isTrue);
    });

    test('ABD hissesi ve emtia USD → kurla çevrilir', () {
      expect(
          FiyatKaynagi.mumKaynagi(varlik(
                  type: AssetType.hisse, ticker: 'AAPL', currency: 'USD'))
              .usdCevir,
          isTrue);
      expect(
          FiyatKaynagi.mumKaynagi(varlik(
                  type: AssetType.emtia, ticker: 'BZ=F', currency: 'USD'))
              .usdCevir,
          isTrue);
    });

    test('TL dövizi: kendi paritesi, çevrim yok, kur bandında hiza', () {
      // Döviz varsayılan para birimi USD olsa da parite TL kotedir —
      // ikinci kez kurla çarpılmaz.
      final k = FiyatKaynagi.mumKaynagi(varlik(
          type: AssetType.doviz, ticker: 'USDTRY=X', currency: 'USD'));
      expect(k.sembol, 'USDTRY=X');
      expect(k.usdCevir, isFalse);
      expect(k.olcekAlt, kurKalibreAltSinir);
      expect(k.olcekUst, kurKalibreUstSinir);
    });

    test('altın: spot önce, vadeli yedek; ürün çarpanı ve altın bandı', () {
      final k = FiyatKaynagi.mumKaynagi(
          varlik(type: AssetType.altin, ticker: 'ALTIN_CEYREK'));
      expect(k.sembol, FiyatKaynagi.xauTry);
      expect(k.yedekSembol, FiyatKaynagi.xauUsd);
      expect(k.altinAgirligi, PriceService.goldWeightFactor('ALTIN_CEYREK'));
      expect(k.olcekAlt, altinKalibreAltSinir);
    });

    test('kripto: sunucu, kod; altı aralık', () {
      final k = FiyatKaynagi.mumKaynagi(
          varlik(type: AssetType.kripto, ticker: 'KRIPTO:BTC'));
      expect(k.tur, MumKaynakTuru.kripto);
      expect(k.sembol, 'BTC');
      expect(k.araliklar, MumAraligi.values);
    });

    test('fon, BES, eurobond: yalnız kapanış → gün/hafta/ay, gün içi YOK', () {
      for (final a in [
        varlik(type: AssetType.fon, ticker: 'TEFAS:AFT'),
        varlik(type: AssetType.bes, ticker: 'TEFAS:AEA'),
        varlik(
            type: AssetType.eurobond,
            ticker: 'EUROBOND:US900123DG28',
            currency: 'USD'),
      ]) {
        final k = FiyatKaynagi.mumKaynagi(a);
        expect(k.tur, MumKaynakTuru.kapanis, reason: a.type.name);
        expect(k.gercekOhlc, isFalse);
        expect(k.araliklar,
            [MumAraligi.gun1, MumAraligi.hafta1, MumAraligi.ay1]);
      }
    });

    test('elle fiyat, mevduat, diğer: mum yok', () {
      for (final a in [
        varlik(type: AssetType.hisse, manuel: true),
        varlik(type: AssetType.mevduat, ticker: 'MEVDUAT:abc'),
        varlik(type: AssetType.diger, ticker: 'EV'),
      ]) {
        expect(FiyatKaynagi.mumKaynagi(a).tur, MumKaynakTuru.yok,
            reason: a.type.name);
        expect(gecerliAraliklar(a, 30 * 1440), isEmpty);
      }
    });

    test('tlKote: geçmiş yollarının kuralıyla aynı', () {
      expect(FiyatKaynagi.tlKote('THYAO.IS'), isTrue);
      expect(FiyatKaynagi.tlKote('EURTRY=X'), isTrue);
      expect(FiyatKaynagi.tlKote('KRIPTO:BTC'), isTrue);
      expect(FiyatKaynagi.tlKote('AAPL'), isFalse);
      expect(FiyatKaynagi.tlKote('GC=F'), isFalse);
    });
  });

  group('ayrıştırma', () {
    test('Yahoo: boş satır atlanır, fitil gövdeyi kapsar, hacim taşınır', () {
      final body = {
        'chart': {
          'result': [
            {
              'timestamp': [1000, 2000, 3000],
              'indicators': {
                'quote': [
                  {
                    'open': [10, null, 11],
                    'high': [12, null, 11.5],
                    'low': [9, null, 10.8],
                    // 3. barda Yahoo yüksek < kapanış bırakmış.
                    'close': [11, null, 11.7],
                    'volume': [500, null, null],
                  }
                ]
              }
            }
          ]
        }
      };
      final b = yahooOhlcCoz(body);
      expect(b, [
        bar(1000000, 10, 12, 9, 11, v: 500),
        bar(3000000, 11, 11.7, 10.8, 11.7),
      ]);
    });

    test('Yahoo: hata yanıtı boş liste', () {
      expect(yahooOhlcCoz({'chart': <String, Object?>{'result': null, 'error': <String, Object?>{}}}), isEmpty);
    });

    test('kripto-seri mumlar: bozuk satır atlanır', () {
      expect(
          kriptoMumlariCoz([
            [1000, 10, 12, 9, 11, 3],
            [2000, 10, 12],
            'x',
            [3000, 0, 1, 1, 1, 0],
          ]),
          [bar(1000, 10, 12, 9, 11, v: 3)]);
      expect(kriptoMumlariCoz(null), isEmpty,
          reason: 'Eski sunucu `mumlar` göndermez — boş, ekran türetilene düşer.');
    });
  });

  group('dönüşümler', () {
    test('kur: barın KAPANIŞ anındaki kur; kuru olmayan bar düşer', () {
      final barlar = [
        bar(0, 10, 12, 9, 11),
        bar(60 * dk, 11, 12, 10, 12),
      ];
      final kur = [(30 * dk, 40.0), (100 * dk, 41.0)];
      final tl = kurlaCevir(barlar, kur, aralik: MumAraligi.saat1);
      // 1. bar 60. dk'da kapanır → 30. dk kuru (40); 2. bar 120. dk'da →
      // 100. dk kuru (41).
      expect(tl, [bar(0, 400, 480, 360, 440), bar(60 * dk, 451, 492, 410, 492)]);
    });

    test('kur: bardan önce kur yoksa ya da çok eskiyse bar YOK (madde 3)', () {
      final barlar = [bar(0, 10, 12, 9, 11), bar(10 * gun, 11, 12, 10, 12)];
      final kur = [(30 * dk, 40.0)];
      final tl = kurlaCevir(barlar, kur, aralik: MumAraligi.saat1);
      expect(tl.length, 1, reason: '10 gün sonraki barın kuru bilinmiyor');
      expect(kurlaCevir(barlar, const [], aralik: MumAraligi.saat1), isEmpty);
    });

    test('altın: ons/TL → gram22k × ürün çarpanı, şekil aynı', () {
      final b = altinaCevir([bar(0, 3110.35, 3421.385, 2799.315, 3110.35)], 1.75);
      final k = PriceService.gram22kFromXauTry(1) * 1.75;
      expect(b.single.kapanis, closeTo(3110.35 * k, 1e-9));
      expect(b.single.enYuksek / b.single.kapanis, closeTo(1.1, 1e-9));
    });

    test('hiza: bant içindeyse bütün seri oranlanır; dışındaysa dokunulmaz', () {
      final simdi = DateTime(2026, 10, 10, 12);
      final barlar = [
        bar(DateTime(2026, 10, 8).millisecondsSinceEpoch, 100, 110, 90, 100),
        bar(DateTime(2026, 10, 9).millisecondsSinceEpoch, 100, 105, 95, 100),
      ];
      final h = canliyaHizala(barlar,
          canli: 102,
          aralik: MumAraligi.gun1,
          simdi: simdi,
          alt: kurKalibreAltSinir,
          ust: kurKalibreUstSinir);
      expect(h.first.enYuksek, closeTo(112.2, 1e-9));
      expect(h.last.kapanis, closeTo(102, 1e-9));
      final bantDisi = canliyaHizala(barlar,
          canli: 150,
          aralik: MumAraligi.gun1,
          simdi: simdi,
          alt: kurKalibreAltSinir,
          ust: kurKalibreUstSinir);
      expect(bantDisi, barlar);
    });

    test('son bar AÇIKSA kapanış canlı fiyattır, kapanmışsa tarih', () {
      final simdi = DateTime(2026, 10, 10, 12, 30);
      final acik = [bar(DateTime(2026, 10, 10, 12).millisecondsSinceEpoch,
          100, 101, 99, 100)];
      final h = canliyaHizala(acik,
          canli: 103, aralik: MumAraligi.saat1, simdi: simdi);
      expect(h.single.kapanis, 103);
      expect(h.single.enYuksek, 103, reason: 'fitil canlı fiyatı kapsar');
      expect(h.single.acilis, 100);

      final kapali = [bar(DateTime(2026, 10, 10, 10).millisecondsSinceEpoch,
          100, 101, 99, 100)];
      expect(
          canliyaHizala(kapali,
              canli: 103, aralik: MumAraligi.saat1, simdi: simdi),
          kapali);
    });

    test('canlı fiyat %10\'dan çok saparsa son mum ezilmez', () {
      final simdi = DateTime(2026, 10, 10, 12, 30);
      final acik = [bar(DateTime(2026, 10, 10, 12).millisecondsSinceEpoch,
          100, 101, 99, 100)];
      expect(
          canliyaHizala(acik,
              canli: 150, aralik: MumAraligi.saat1, simdi: simdi),
          acik);
    });

    test('kapanıştan mum: açılış önceki kapanış, hafta Pazartesi', () {
      int g(int d) => DateTime(2026, 10, d, 18).millisecondsSinceEpoch;
      final kapanislar = [
        (g(5), 10.0), // Pazartesi
        (g(6), 11.0),
        (g(7), 9.0),
        (g(12), 12.0), // sonraki Pazartesi
      ];
      final gunluk = kapanislardanMumlar(kapanislar, MumAraligi.gun1);
      expect(gunluk.map((b) => (b.acilis, b.kapanis)).toList(),
          [(10.0, 10.0), (10.0, 11.0), (11.0, 9.0), (9.0, 12.0)]);
      expect(gunluk[2].enYuksek, 11);
      expect(gunluk[2].enDusuk, 9);

      final haftalik = kapanislardanMumlar(kapanislar, MumAraligi.hafta1);
      expect(haftalik.length, 2);
      expect(haftalik[0].t, DateTime(2026, 10, 5).millisecondsSinceEpoch);
      expect((haftalik[0].acilis, haftalik[0].enYuksek, haftalik[0].enDusuk,
          haftalik[0].kapanis), (10.0, 11.0, 9.0, 9.0));
      expect((haftalik[1].acilis, haftalik[1].kapanis), (9.0, 12.0));
    });

    test('pencere: kısmen içeride kalan bar alınır', () {
      final b = [bar(0, 1, 1, 1, 1), bar(gun, 1, 1, 1, 1), bar(2 * gun, 1, 1, 1, 1)];
      expect(pencereyeKirp(b, gun ~/ 2, gun, MumAraligi.gun1).length, 2);
    });

    test('aylık barın uzunluğu takvim ayı', () {
      final subat = DateTime(2026, 2, 1).millisecondsSinceEpoch;
      expect(barUzunluguMs(subat, MumAraligi.ay1), 28 * gun);
      expect(barUzunluguMs(subat, MumAraligi.gun1), gun);
    });

    test('grafik uzayı: dönem başından kesirli gün', () {
      final bas = DateTime(2026, 10, 1).millisecondsSinceEpoch.toDouble();
      final m = grafikMumlari(
        [bar(DateTime(2026, 10, 2, 12).millisecondsSinceEpoch, 1, 2, 1, 2)],
        aralik: MumAraligi.saat4,
        baslangicMs: bas,
        birimMs: gun.toDouble(),
      ).single;
      expect(m.x, closeTo(1.5, 1e-9));
      expect(m.kovaMs, closeTo(4 / 24, 1e-9));
    });
  });

  group('aralık seçimi', () {
    final bist = varlik(type: AssetType.hisse);
    final btc = varlik(type: AssetType.kripto, ticker: 'KRIPTO:BTC');
    final fon = varlik(type: AssetType.fon, ticker: 'TEFAS:AFT');
    const gunluk = 1440.0, hafta = 7 * 1440.0, ay = 30 * 1440.0;
    const yil = 365 * 1440.0, besYil = 5 * 365 * 1440.0;

    test('BIST GÜNLÜK: 1 dk ve 1 sa var; 4 sa (2 mum) yok', () {
      expect(gecerliAraliklar(bist, gunluk), [MumAraligi.dk1, MumAraligi.saat1]);
    });

    test('kripto GÜNLÜK: 1 dk (1.440 mum) sığar; 1H × 1 dk (10.080) sığmaz', () {
      expect(gecerliAraliklar(btc, gunluk),
          [MumAraligi.dk1, MumAraligi.saat1, MumAraligi.saat4]);
      expect(gecerliAraliklar(btc, hafta).contains(MumAraligi.dk1), isFalse);
    });

    test('uzun dönem: 5Y\'de gün içi yok, haftalık ve aylık var', () {
      final g = gecerliAraliklar(bist, besYil);
      expect(g.any((a) => a.gunIci), isFalse);
      expect(g, containsAll([MumAraligi.hafta1, MumAraligi.ay1]));
    });

    test('fon: gün içi hiç yok; GÜNLÜK\'te mum aralığı yok (eski mum kalır)', () {
      expect(gecerliAraliklar(fon, gunluk), isEmpty);
      expect(etkinAralik(fon, gunluk, null), isNull);
      expect(gecerliAraliklar(fon, ay), [MumAraligi.gun1, MumAraligi.hafta1]);
    });

    test('seçim geçerliyse korunur, değilse otomatiğe düşer', () {
      expect(etkinAralik(bist, ay, MumAraligi.gun1), MumAraligi.gun1);
      expect(etkinAralik(bist, besYil, MumAraligi.dk1), isNotNull);
      expect(etkinAralik(bist, besYil, MumAraligi.dk1)!.gunIci, isFalse);
    });

    test('otomatik: ~80 muma en yakın', () {
      expect(etkinAralik(bist, gunluk, null), MumAraligi.dk1);
      expect(etkinAralik(btc, gunluk, null), MumAraligi.saat1);
      expect(etkinAralik(bist, ay, null), MumAraligi.saat4);
      expect(etkinAralik(bist, yil, null), MumAraligi.hafta1);
      expect(etkinAralik(bist, besYil, null), MumAraligi.ay1);
    });

    test('kripto-seri dönemi pencereyi kapsayan en dar dönem', () {
      expect(MumVerisi.kriptoDonemi(const Duration(hours: 24)), '1d');
      expect(MumVerisi.kriptoDonemi(const Duration(days: 7)), '1mo');
      expect(MumVerisi.kriptoDonemi(const Duration(days: 365)), '1y');
      expect(MumVerisi.kriptoDonemi(const Duration(days: 4000)), 'max');
    });
  });
}
