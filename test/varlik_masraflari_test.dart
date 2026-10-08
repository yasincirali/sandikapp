import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/varlik_masraflari.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/masraf_karti.dart';

/// Varlık masrafları (bayrak `varlik_masraflari`, 2026-10-08).
///
/// Kilitlenen kural: tutar YALNIZ kayıtlı komisyondan (her lot kendi
/// kuruyla) ya da resmî orandan (SEC, FINRA) gelir; gerisi tutarsız bilgi.
/// Kur ya da fiyat bilinmiyorsa tahmini kalem de tutarsız kalır.
Asset _lot({
  AssetType type = AssetType.hisse,
  String ticker = 'THYAO.IS',
  String currency = 'TRY',
  String? sub,
  double qty = 100,
  double price = 10,
  double current = 12,
  double fx = 1,
  double commission = 0,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double? sellFxRate,
}) =>
    Asset(
      id: '${ticker}_${kind.name}_$fx',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: price,
      currency: currency,
      notes: '',
      subCategory: sub,
      purchaseFxRate: fx,
      currentPrice: current,
      addedDate: DateTime(2026, 5, 1),
      commission: commission,
      kind: kind,
      sellPrice: sellPrice,
      sellFxRate: sellFxRate,
    );

MasrafOzeti _hesap(
  Asset varlik, {
  List<Asset>? lotlar,
  double? usdTry = 40,
  double? stopaj = 0.15,
  DateTime? simdi,
}) =>
    varlikMasraflari(
      varlik: varlik,
      lotlar: lotlar ?? [varlik],
      usdTry: usdTry,
      temettuStopajOrani: stopaj,
      simdi: simdi ?? DateTime(2026, 10, 8),
    );

MasrafKalemi _kalem(MasrafOzeti o, String baslik) =>
    o.kalemler.firstWhere((k) => k.baslik == baslik);

void main() {
  group('komisyon', () {
    test('her lot kendi kuruyla; satış satış günü kuruyla', () {
      final alim1 = _lot(currency: 'USD', fx: 30, commission: 2);
      final alim2 = _lot(currency: 'USD', fx: 35, commission: 1);
      final satis = _lot(
          currency: 'USD',
          fx: 32,
          commission: 3,
          kind: AssetKind.sell,
          sellPrice: 15,
          sellFxRate: 41);
      final o = _hesap(alim1, lotlar: [alim1, alim2, satis]);
      final k = _kalem(o, 'İşlem komisyonu');
      expect(k.nitelik, MasrafNiteligi.odendi);
      expect(k.tutarTry, closeTo(2 * 30 + 1 * 35 + 3 * 41, 1e-9));
      expect(o.odenenToplamTry, closeTo(218, 1e-9));
    });

    test('satış kuru yoksa alım kuru (sellProceedsTRY ile aynı kural)', () {
      final satis = _lot(
          currency: 'USD', fx: 32, commission: 3, kind: AssetKind.sell);
      final k = _kalem(_hesap(satis), 'İşlem komisyonu');
      expect(k.tutarTry, closeTo(96, 1e-9));
    });

    test('komisyon yok → tutarsız bilgi satırı', () {
      final o = _hesap(_lot());
      final k = _kalem(o, 'İşlem komisyonu');
      expect(k.nitelik, MasrafNiteligi.bilgi);
      expect(k.tutarTry, isNull);
      expect(k.aciklama, contains('Komisyon kaydetmedin'));
      expect(o.odenenToplamTry, 0);
    });

    test('silinmiş lot sayılmaz', () {
      final silinen = Asset(
        id: 's',
        userId: 'u',
        name: 'X',
        ticker: 'X.IS',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        commission: 50,
        deletedAt: DateTime(2026, 6, 1),
      );
      final k = _kalem(_hesap(_lot(), lotlar: [_lot(), silinen]),
          'İşlem komisyonu');
      expect(k.nitelik, MasrafNiteligi.bilgi);
    });
  });

  group('BIST hissesi', () {
    test('temettü stopajı oran Remote Config\'ten; BSMV bilgi', () {
      final o = _hesap(_lot());
      final s = _kalem(o, 'Temettü stopajı');
      expect(s.nitelik, MasrafNiteligi.bilgi);
      expect(s.oran, 0.15);
      expect(s.tutarTry, isNull);
      expect(_kalem(o, 'BSMV').tutarTry, isNull);
      expect(o.tahminiVar, isFalse);
    });

    test('stopaj oranı bilinmiyorsa oran yazılmaz', () {
      expect(_kalem(_hesap(_lot(), stopaj: null), 'Temettü stopajı').oran,
          isNull);
    });
  });

  group('ABD hissesi', () {
    Asset abd({double qty = 100, double current = 200}) => _lot(
        ticker: 'AAPL',
        currency: 'USD',
        sub: 'abd',
        qty: qty,
        current: current,
        fx: 40);

    test('SEC: değer × 20,60/1M × kur', () {
      // 100 × $200 = $20.000 → $0,412 → ₺16,48 (kur 40).
      final k = _kalem(_hesap(abd()), 'SEC ücreti (satışta)');
      expect(k.nitelik, MasrafNiteligi.tahmini);
      expect(k.tutarTry, closeTo(20000 * 0.0000206 * 40, 1e-9));
      expect(k.oran, secUcretOrani);
      expect(k.kaynak, secUcretKaynagi);
    });

    test('FINRA TAF: pay × 0,000195, emir başı 9,79 \$ tavanı', () {
      final az = _kalem(_hesap(abd(qty: 1000)), 'FINRA TAF (satışta)');
      expect(az.tutarTry, closeTo(1000 * 0.000195 * 40, 1e-9));
      // 100.000 pay × 0,000195 = 19,5 $ > 9,79 $ → tavan.
      final cok = _kalem(_hesap(abd(qty: 100000)), 'FINRA TAF (satışta)');
      expect(cok.tutarTry, closeTo(9.79 * 40, 1e-9));
    });

    test('tahmini toplam SEC + FINRA', () {
      final o = _hesap(abd());
      expect(
          o.tahminiToplamTry,
          closeTo(
              20000 * 0.0000206 * 40 + 100 * 0.000195 * 40, 1e-9));
    });

    test('kur yoksa tutar UYDURULMAZ: tahmini kalemler bilgiye iner', () {
      final o = _hesap(abd(), usdTry: null);
      for (final b in ['SEC ücreti (satışta)', 'FINRA TAF (satışta)']) {
        final k = _kalem(o, b);
        expect(k.nitelik, MasrafNiteligi.bilgi, reason: b);
        expect(k.tutarTry, isNull, reason: b);
      }
      expect(o.tahminiVar, isFalse);
      expect(o.tahminiToplamTry, 0);
    });

    test('güncel fiyat yoksa SEC tutarsız', () {
      final k = _kalem(_hesap(abd(current: 0)), 'SEC ücreti (satışta)');
      expect(k.tutarTry, isNull);
    });

    test('SEC oranının yürürlüğünden önce oran bilinmiyor', () {
      final k = _kalem(_hesap(abd(), simdi: DateTime(2026, 3, 1)),
          'SEC ücreti (satışta)');
      expect(k.nitelik, MasrafNiteligi.bilgi);
      expect(k.oran, isNull);
    });

    test('temettü stopajı %20, kur çevrimi ve vergi bilgi', () {
      final o = _hesap(abd());
      expect(_kalem(o, 'ABD temettü stopajı').oran, 0.20);
      for (final b in ['ABD temettü stopajı', 'Kur çevrimi', 'Vergi']) {
        expect(_kalem(o, b).tutarTry, isNull, reason: b);
      }
      // BIST kalemleri ABD'de yok.
      expect(o.kalemler.where((k) => k.baslik == 'BSMV'), isEmpty);
    });
  });

  group('öteki türler', () {
    List<String> basliklar(AssetType t, {String ticker = 'X'}) =>
        _hesap(_lot(type: t, ticker: ticker))
            .kalemler
            .map((k) => k.baslik)
            .toList();

    test('fon ve BES: yönetim ücreti', () {
      expect(basliklar(AssetType.fon), contains('Yönetim ücreti'));
      expect(basliklar(AssetType.bes), contains('Yönetim ücreti'));
    });

    test('mevduat: stopaj sözleşme kartına yönlendirir, komisyon yok', () {
      final b = basliklar(AssetType.mevduat);
      expect(b, ['Stopaj']);
    });

    test('kripto: borsa işlem ücreti', () {
      expect(basliklar(AssetType.kripto), contains('Borsa işlem ücreti'));
    });

    test('altın ve döviz: alış-satış makası', () {
      expect(basliklar(AssetType.altin), contains('Alış-satış makası'));
      expect(basliklar(AssetType.doviz), contains('Alış-satış makası'));
    });

    test('emtia/diğer yalnız komisyon', () {
      expect(basliklar(AssetType.emtia), ['İşlem komisyonu']);
      expect(basliklar(AssetType.diger), ['İşlem komisyonu']);
    });

    test('bilgi kalemlerinde hiçbir türde tutar yok', () {
      for (final t in AssetType.values) {
        for (final k in _hesap(_lot(type: t)).kalemler) {
          if (k.nitelik == MasrafNiteligi.bilgi) {
            expect(k.tutarTry, isNull, reason: '$t ${k.baslik}');
          }
        }
      }
    });
  });

  group('MasrafKarti', () {
    Future<void> ciz(WidgetTester tester, MasrafOzeti ozet,
        {required bool koyu}) async {
      await tester.pumpWidget(MaterialApp(
        theme: koyu
            ? SandikApp.buildTheme(SandikPalette.dark, Brightness.dark)
            : SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(child: MasrafKarti(ozet: ozet)),
        ),
      ));
      await tester.pump();
    }

    final abd = _lot(
        ticker: 'AAPL',
        currency: 'USD',
        sub: 'abd',
        fx: 40,
        commission: 1.5,
        current: 200);

    for (final koyu in [false, true]) {
      testWidgets('çizilir ve açılır (${koyu ? 'koyu' : 'açık'})',
          (tester) async {
        final ozet = _hesap(abd);
        expect(ozet.kalemler.length, greaterThan(MasrafKarti.kapaliKalem));
        await ciz(tester, ozet, koyu: koyu);

        expect(find.text('MASRAFLAR'), findsOneWidget);
        expect(find.text('Ödenen'), findsOneWidget);
        expect(find.text('Satarken tahmini'), findsOneWidget);
        // Kapalı: ilk üç kalem.
        expect(find.text('İşlem komisyonu'), findsOneWidget);
        expect(find.text('Vergi'), findsNothing);
        final tumu = find.text('Tümünü gör (${ozet.kalemler.length})');
        expect(tumu, findsOneWidget);
        // Dokunma hedefi ≥ 48.
        expect(tester.getSize(tumu).height, lessThan(48));
        final hedef = find
            .ancestor(of: tumu, matching: find.byType(ConstrainedBox))
            .first;
        expect(tester.getSize(hedef).height, greaterThanOrEqualTo(48));

        await tester.tap(tumu);
        await tester.pump();
        expect(find.text('Vergi'), findsOneWidget);
        expect(find.text('Daha az göster'), findsOneWidget);
        expect(find.text('Ödendi'), findsOneWidget);
        expect(find.text('Tahmini'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('az kalemde "Tümünü gör" yok, ödenen yoksa toplam satırı yok',
        (tester) async {
      await ciz(tester, _hesap(_lot(type: AssetType.altin, ticker: 'ALTIN_GRAM')),
          koyu: false);
      expect(find.textContaining('Tümünü gör'), findsNothing);
      expect(find.text('Ödenen'), findsNothing);
      expect(find.text('Alış-satış makası'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
    });
  });
}
