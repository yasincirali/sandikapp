import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kur_ayrismasi.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/kur_ayrismasi_satiri.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

/// Kur ayrışması (Ar-Ge 2026-11-07 #1): "Fiyattan · Kurdan".
///
/// Kilitlenen: (1) iki etkinin toplamı pozisyon kartının TL kârına
/// (`toTRY(totalValue) − totalCostTRY`) eşit — komisyon ve kısmi satış
/// dahil; (2) kur ya da alış kuru bilinmiyorsa, TL varlıkta sayı yok;
/// (3) satır Premium görünmüyorsa yok, kilitliyse kilit satırı, bakiye
/// gizliyken tutar maskeli.
Asset _lot(
  String id, {
  double qty = 10,
  double price = 100,
  double fx = 30,
  double current = 120,
  double commission = 0,
  String currency = 'USD',
  AssetKind kind = AssetKind.buy,
  String? ref,
  double? sellPrice,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: 'Apple',
      ticker: 'AAPL',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: price,
      currency: currency,
      notes: '',
      purchaseFxRate: fx,
      currentPrice: current,
      commission: commission,
      kind: kind,
      refAssetId: ref,
      sellPrice: sellPrice,
      addedDate: DateTime(2026, 1, 1),
    );

/// Ekranın yaptığı gibi: açık pozisyonun görünüm varlığı.
Asset _pozisyon(List<Asset> lots) =>
    aggregatePositions(aktifLotlar(lots)).single.asDisplayAsset();

/// Pozisyon kartının TL kârı (`_pnlOzeti` formülü).
double _kartKari(Asset a, double kur) =>
    a.quantity * a.currentPrice * kur - a.totalCostTRY;

void main() {
  group('özdeşlik: fiyat + kur = kartın TL kârı', () {
    test('tek lot, komisyonsuz', () {
      final a = _pozisyon([_lot('1')]);
      final r = kurAyrismasi(a, guncelKur: 40)!;
      // Fiyat: 10 × (120 − 100) × 30 = 6.000; kur: 10 × 120 × 10 = 12.000.
      expect(r.fiyatEtkisi, closeTo(6000, 1e-9));
      expect(r.kurEtkisi, closeTo(12000, 1e-9));
      expect(r.fiyatEtkisi + r.kurEtkisi, closeTo(_kartKari(a, 40), 1e-6));
    });

    test('iki lot farklı kurla + komisyon: komisyon fiyat etkisinden düşer',
        () {
      final a = _pozisyon([
        _lot('1', qty: 10, price: 100, fx: 30, commission: 2),
        _lot('2', qty: 5, price: 140, fx: 34, commission: 1.5),
      ]);
      final r = kurAyrismasi(a, guncelKur: 41.37)!;
      expect(r.fiyatEtkisi + r.kurEtkisi, closeTo(_kartKari(a, 41.37), 1e-6));
    });

    test('kısmi satıştan sonra açık kalan miktarla', () {
      final a = _pozisyon([
        _lot('1', qty: 10, price: 100, fx: 30, commission: 1),
        _lot('2',
            qty: 4,
            price: 100,
            fx: 30,
            kind: AssetKind.sell,
            ref: '1',
            sellPrice: 130),
      ]);
      expect(a.quantity, 6);
      final r = kurAyrismasi(a, guncelKur: 38)!;
      expect(r.fiyatEtkisi + r.kurEtkisi, closeTo(_kartKari(a, 38), 1e-6));
    });

    test('kur düşünce kur etkisi eksi, toplam yine tutar', () {
      final a = _pozisyon([_lot('1', fx: 40, current: 150)]);
      final r = kurAyrismasi(a, guncelKur: 35)!;
      expect(r.kurEtkisi, lessThan(0));
      expect(r.fiyatEtkisi, greaterThan(0));
      expect(r.fiyatEtkisi + r.kurEtkisi, closeTo(_kartKari(a, 35), 1e-6));
    });
  });

  group('sayı yok (uydurma yasak)', () {
    test('TL cinsi varlık', () {
      expect(
          kurAyrismasi(_pozisyon([_lot('1', currency: 'TRY', fx: 1)]),
              guncelKur: 1),
          isNull);
    });
    test('bugünkü kur bilinmiyor', () {
      final a = _pozisyon([_lot('1')]);
      expect(kurAyrismasi(a, guncelKur: null), isNull);
      expect(kurAyrismasi(a, guncelKur: 0), isNull);
    });
    test('alış kuru bilinmiyor (varsayılan 1,0 ya da 0)', () {
      expect(
          kurAyrismasi(_pozisyon([_lot('1', fx: 1.0)]), guncelKur: 40), isNull);
      expect(
          kurAyrismasi(_pozisyon([_lot('1', fx: 0)]), guncelKur: 40), isNull);
    });
    test('fiyat ya da alış fiyatı yok', () {
      expect(kurAyrismasi(_pozisyon([_lot('1', current: 0)]), guncelKur: 40),
          isNull);
      expect(kurAyrismasi(_pozisyon([_lot('1', price: 0)]), guncelKur: 40),
          isNull);
    });
    test('iki etki de ₺0 → satır yok', () {
      expect(kurAyrismasi(_pozisyon([_lot('1', current: 100)]), guncelKur: 30),
          isNull);
    });
    test('pozisyonKuru: yalnız toTRY\'nin çevirdiği birimler', () {
      double? k(String c) =>
          pozisyonKuru(c, usdTry: 40, eurTry: 45, gbpTry: 52);
      expect(k('usd'), 40);
      expect(k('EUR'), 45);
      expect(k('GBP'), 52);
      expect(k('CHF'), isNull);
      expect(k('TRY'), isNull);
    });
  });

  group('kaynak sayılar ve alış kuru eksik kapısı (2026-11-13)', () {
    test('sayfanın sayıları modelden: X0, X, döviz kâr/değer, fark, toplam',
        () {
      final a = _pozisyon([_lot('1', commission: 5)]);
      final r = kurAyrismasi(a, guncelKur: 40)!;
      expect(r.alisKuru, 30);
      expect(r.guncelKur, 40);
      expect(r.dovizKar, closeTo(10 * 20 - 5, 1e-9));
      expect(r.dovizDeger, closeTo(1200, 1e-9));
      expect(r.kurFarki, 10);
      expect(r.sembol, r'$');
      expect(r.dovizKar * r.alisKuru, closeTo(r.fiyatEtkisi, 1e-9));
      expect(r.dovizDeger * r.kurFarki, closeTo(r.kurEtkisi, 1e-9));
      expect(r.toplam, closeTo(_kartKari(a, 40), 1e-6));
    });

    test('yalnız alış kuru eksikse true', () {
      expect(
          kurAyrismasiAlisKuruEksik(_pozisyon([_lot('1', fx: 1.0)]),
              guncelKur: 40),
          isTrue);
      expect(
          kurAyrismasiAlisKuruEksik(_pozisyon([_lot('1', fx: 0)]),
              guncelKur: 40),
          isTrue);
      // Kur kayıtlı → ayrışma çıkar, eksik satırı değil.
      expect(kurAyrismasiAlisKuruEksik(_pozisyon([_lot('1')]), guncelKur: 40),
          isFalse);
      // TL varlık, bilinmeyen bugünkü kur, fiyatsız pozisyon: söylenmez.
      expect(
          kurAyrismasiAlisKuruEksik(
              _pozisyon([_lot('1', currency: 'TRY', fx: 1)]),
              guncelKur: 40),
          isFalse);
      expect(
          kurAyrismasiAlisKuruEksik(_pozisyon([_lot('1', fx: 1.0)]),
              guncelKur: null),
          isFalse);
      expect(
          kurAyrismasiAlisKuruEksik(_pozisyon([_lot('1', fx: 1.0, current: 0)]),
              guncelKur: 40),
          isFalse);
    });
  });

  group('KurAyrismasiSatiri', () {
    // Tutarlı bir örnek: 10 × (120 − 100) = $200 kâr × 30 = 6.000;
    // $1.200 × (29 − 30) = −1.200; toplam 4.800.
    const ayrisma = (
      fiyatEtkisi: 6000.0,
      kurEtkisi: -1200.0,
      alisKuru: 30.0,
      guncelKur: 29.0,
      dovizKar: 200.0,
      dovizDeger: 1200.0,
      sembol: r'$',
      kurFarki: -1.0,
      toplam: 4800.0,
    );

    Future<void> pump(WidgetTester tester,
        {required bool gorunur,
        bool kilitli = false,
        BazPara baz = const BazPara.lira()}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(
            body: KurAyrismasiSatiri(ayrisma: ayrisma, baz: baz),
          ),
        ),
      ));
    }

    testWidgets('Premium: işaretli iki tutar, ekran okuyucu tek cümle',
        (tester) async {
      await pump(tester, gorunur: true);
      final metin = find.textContaining('Fiyattan', findRichText: true);
      expect(metin, findsOneWidget);
      final yazi = tester.widget<RichText>(
          find.textContaining('Fiyattan', findRichText: true));
      final duz = yazi.text.toPlainText();
      expect(duz, contains('+₺6.000'));
      expect(duz, contains('Kurdan −₺1.200'));
      expect(find.bySemanticsLabel(RegExp('fiyattan gelen kısmı \\+₺6.000')),
          findsOneWidget);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('ücretsiz (kilitli): kilit satırı, tutar yok, 44 pt',
        (tester) async {
      await pump(tester, gorunur: true, kilitli: true);
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.textContaining('6.000', findRichText: true), findsNothing);
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('Premium görünmüyorsa hiçbir şey', (tester) async {
      await pump(tester, gorunur: false);
      expect(find.textContaining('Fiyattan', findRichText: true), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('bakiye gizli: tutar maskeli, işaret ve kelime kalır',
        (tester) async {
      await pump(tester, gorunur: true, baz: const BazPara.lira().gizlenmis());
      final yazi = tester.widget<RichText>(
          find.textContaining('Fiyattan', findRichText: true));
      final duz = yazi.text.toPlainText();
      expect(duz, isNot(contains('6.000')));
      expect(duz, contains('Fiyattan +₺••••'));
      expect(duz, contains('Kurdan −₺••••'));
    });
    testWidgets('dokununca sayfa: gerçek sayılarla kaynak', (tester) async {
      await pump(tester, gorunur: true);
      expect(tester.getSize(find.byType(SandikTappable)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(find.byType(KurAyrismasiSatiri));
      await tester.pumpAndSettle();
      expect(find.byType(KurAyrismasiSayfasi), findsOneWidget);
      expect(find.text('Kâr nereden geldi'), findsOneWidget);
      expect(find.text('₺30,00 → ₺29,00'), findsOneWidget);
      expect(find.text(r'Döviz bazında kâr $200 × alış kuru ₺30,00'),
          findsOneWidget);
      expect(find.text(r'Bugünkü döviz değeri $1.200 × kur farkı −₺1,00'),
          findsOneWidget);
      expect(find.text('+₺4.800'), findsOneWidget);
    });

    testWidgets('bakiye gizli: sayfada tutarlar maskeli', (tester) async {
      await pump(tester, gorunur: true, baz: const BazPara.lira().gizlenmis());
      await tester.tap(find.byType(KurAyrismasiSatiri));
      await tester.pumpAndSettle();
      expect(find.textContaining('4.800'), findsNothing);
      expect(find.textContaining('6.000'), findsNothing);
      expect(find.textContaining(r'$••••'), findsNWidgets(2));
    });
  });

  group('KurAyrismasiEksikSatiri', () {
    Future<void> pump(WidgetTester tester, {required bool kilitli}) =>
        tester.pumpWidget(ProviderScope(
          overrides: [
            premiumOzellikleriGorunurProvider.overrideWithValue(true),
            premiumKilitliProvider.overrideWithValue(kilitli),
          ],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark],
            ),
            home: const Scaffold(body: KurAyrismasiEksikSatiri()),
          ),
        ));

    testWidgets('Premium: alış kuru eksik satırı görünür', (tester) async {
      await pump(tester, kilitli: false);
      expect(find.textContaining('Alış kuru kayıtlı değil'), findsOneWidget);
    });

    testWidgets('ücretsiz: hiçbir şey (davranış değişmedi)', (tester) async {
      await pump(tester, kilitli: true);
      expect(find.textContaining('Alış kuru kayıtlı değil'), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });
  });
}
