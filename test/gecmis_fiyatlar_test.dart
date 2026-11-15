import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gecmis_fiyatlar.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/gecmis_fiyatlar.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

import 'helpers/kaynak.dart';

Asset _lot(DateTime added,
        {double qty = 5, bool satis = false, bool silinmis = false}) =>
    Asset(
      id: 'a${added.millisecondsSinceEpoch}${satis ? 's' : ''}',
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 100,
      addedDate: added,
      kind: satis ? AssetKind.sell : AssetKind.buy,
      sellPrice: satis ? 120 : null,
      deletedAt: silinmis ? DateTime(2026, 11, 10) : null,
    );

/// Varlık grafiğinin "Tablo olarak gör" sayfası (Premium, 2026-11-10).
void main() {
  int ms(int y, int a, int g, [int s = 18]) =>
      DateTime(y, a, g, s).millisecondsSinceEpoch;

  group('gunlukKapanislar', () {
    test('günün son noktası kapanış, en yeni üstte, değişim önceki satıra göre',
        () {
      final seri = {
        ms(2026, 11, 3, 10): 90.0,
        ms(2026, 11, 3, 18): 100.0, // 3 Kas kapanışı
        // 4 Kas yok (tatil): satır uydurulmaz.
        ms(2026, 11, 5, 18): 110.0,
        ms(2026, 11, 6, 12): 99.0,
      };
      final r = gunlukKapanislar(seri);
      expect(r.map((e) => e.gun.day), [6, 5, 3]);
      expect(r.map((e) => e.kapanis), [99.0, 110.0, 100.0]);
      expect(r[0].degisimPct, closeTo(-10, 1e-9));
      expect(r[1].degisimPct, closeTo(10, 1e-9));
      expect(r[2].degisimPct, isNull, reason: 'dönemin ilk günü');
    });

    test('en fazla 60 satır; 60. satırın da önceki kapanışı var', () {
      final seri = {
        for (var i = 0; i < 100; i++)
          DateTime(2026, 1, 1).add(Duration(days: i)).millisecondsSinceEpoch:
              100.0 + i,
      };
      final r = gunlukKapanislar(seri);
      expect(r.length, gecmisFiyatlarAzamiSatir);
      expect(r.first.kapanis, 199.0);
      expect(r.last.degisimPct, isNotNull);
    });

    test('sıfır/negatif/sonsuz fiyat atlanır', () {
      final r = gunlukKapanislar({
        ms(2026, 11, 3): 0,
        ms(2026, 11, 4): double.nan,
        ms(2026, 11, 5): 10,
      });
      expect(r.length, 1);
      expect(r.single.kapanis, 10);
    });
  });

  group('islemGunleri — grafiğin işaret kuralıyla gün eşleştirme', () {
    test('gün başına alış/satış toplanır; silinmiş lot sayılmaz', () {
      final r = islemGunleri([
        _lot(DateTime(2026, 10, 3, 10), qty: 7),
        _lot(DateTime(2026, 10, 3, 15), qty: 5),
        _lot(DateTime(2026, 10, 8, 11), qty: 4, satis: true),
        _lot(DateTime(2026, 10, 9, 11), silinmis: true),
      ]);
      expect(r.keys, unorderedEquals([DateTime(2026, 10, 3), DateTime(2026, 10, 8)]));
      expect(r[DateTime(2026, 10, 3)]!.alisMiktar, 12);
      expect(r[DateTime(2026, 10, 3)]!.satis, isFalse);
      expect(r[DateTime(2026, 10, 8)]!.satisMiktar, 4);
      expect(r[DateTime(2026, 10, 8)]!.alis, isFalse);
      expect(islemGunleri(const []), isEmpty);
    });
  });

  group('sonAlistanBeri', () {
    final satirlar = gunlukKapanislar({
      ms(2026, 10, 2): 90.0,
      ms(2026, 10, 3): 100.0,
      ms(2026, 10, 6): 104.0,
      ms(2026, 10, 7): 108.4,
    });

    test('son alış gününün kapanışından en yeni kapanışa', () {
      final r = sonAlistanBeri(satirlar, islemGunleri([
        _lot(DateTime(2026, 10, 2, 10)),
        _lot(DateTime(2026, 10, 3, 10)),
        _lot(DateTime(2026, 10, 6, 10), satis: true), // satış sayılmaz
      ]))!;
      expect(r.gun, DateTime(2026, 10, 3));
      expect(r.pct, closeTo(8.4, 1e-9));
    });

    test('son alış seride kapanış değilse daha eskiye düşülmez: null', () {
      // 4 Eki Cumartesi: kapanış yok; 2 Eki'ye düşmek "son alış" olmazdı.
      expect(
          sonAlistanBeri(satirlar, islemGunleri([
            _lot(DateTime(2026, 10, 2, 10)),
            _lot(DateTime(2026, 10, 4, 10)),
          ])),
          isNull);
    });

    test('son alış bugünse, dönem öncesiyse ya da alış yoksa null', () {
      expect(
          sonAlistanBeri(
              satirlar, islemGunleri([_lot(DateTime(2026, 10, 7, 10))])),
          isNull);
      expect(
          sonAlistanBeri(
              satirlar, islemGunleri([_lot(DateTime(2026, 9, 1, 10))])),
          isNull);
      expect(sonAlistanBeri(satirlar, const {}), isNull);
    });
  });

  group('kilitOzeti — ücretsiz yarım sonuç', () {
    test('tüm dönemin kapanış sayısı (60 kesiminden önce) ve en yüksek gün',
        () {
      final seri = {
        for (var i = 0; i < 100; i++)
          DateTime(2026, 1, 1, 18).add(Duration(days: i)).millisecondsSinceEpoch:
              i == 40 ? 500.0 : 100.0 + i,
      };
      final r = kilitOzeti(seri)!;
      expect(r.sayi, 100);
      expect(r.enYuksekGun, DateTime(2026, 2, 10));
    });

    test('kapanış yoksa null', () {
      expect(kilitOzeti(const {}), isNull);
      expect(kilitOzeti({ms(2026, 1, 1): 0, ms(2026, 1, 2): double.nan}),
          isNull);
    });
  });

  group('GecmisFiyatlarSatiri', () {
    final seri = {
      for (var i = 0; i < 90; i++)
        DateTime(2026, 6, 1, 18).add(Duration(days: i)).millisecondsSinceEpoch:
            i.isEven ? 100.0 + i : 99.0 + i * 0.5,
    };

    Future<void> pump(WidgetTester tester,
        {bool gorunur = true,
        bool kilitli = false,
        bool gunIci = false,
        Map<int, double>? ozelSeri,
        List<Asset> lotlar = const []}) async {
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
            body: Center(
              child: GecmisFiyatlarSatiri(
                seri: ozelSeri ?? seri,
                lotlar: lotlar,
                bicim: ayniOndalikFiyatBicimi(150),
                donemEtiketi: '3 ay',
                gunIci: gunIci,
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('Premium: sayfa açılır, ≤60 satır, yön ikonu ve işaret',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester);
      expect(find.byType(KilitSatiri), findsNothing);
      expect(tester.getSize(find.byType(GecmisFiyatlarSatiri)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(find.text('Tablo olarak gör'));
      await tester.pumpAndSettle();

      expect(find.text('Geçmiş fiyatlar'), findsOneWidget);
      expect(find.text('3 ay · 60 kapanış, en yeni üstte'), findsOneWidget);
      expect(find.byType(GecmisFiyatlarTablosu), findsOneWidget);
      final tablo = tester
          .widget<GecmisFiyatlarTablosu>(find.byType(GecmisFiyatlarTablosu));
      expect(
          tablo.satirlar.length, lessThanOrEqualTo(gecmisFiyatlarAzamiSatir));
      expect(tablo.satirlar.length, 60);
      // Yön renkle birlikte ok ikonu ve işaretle verilir.
      expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(find.textContaining('+%'), findsWidgets);
      // Ekran okuyucu satırı tek cümle okur.
      expect(find.bySemanticsLabel(RegExp(r'kapanış ₺.*önceki kapanışa göre')),
          findsWidgets);
    });

    testWidgets('ücretsiz: kilit satırı, dokununca sayfa açılmaz',
        (tester) async {
      await pump(tester, kilitli: true);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'gecmis_fiyatlar');
      // Yarım sonuç: sayı ve tarih açık, hiçbir fiyat yazılmaz.
      expect(
          find.text("3 ay · 90 kapanış · en yüksek 28 Ağu · tablo Premium'da"),
          findsOneWidget);
      expect(find.textContaining('₺'), findsNothing);
      // Testte paywall RC'si kapalı: `PaywallScreen.show` sessizce döner;
      // önemli olan tablonun açılmaması.
      await tester.tap(find.byType(KilitSatiri));
      await tester.pumpAndSettle();
      expect(find.byType(GecmisFiyatlarTablosu), findsNothing);
    });

    testWidgets('ücretsiz, seride kapanış yok: eski kilit metni',
        (tester) async {
      await pump(tester,
          kilitli: true,
          ozelSeri: {ms(2026, 1, 1): 0, ms(2026, 1, 2): double.nan});
      expect(find.text("Geçmiş fiyat tablosu Premium'da"), findsOneWidget);
    });

    testWidgets('Premium: alış/satış günü etiketli, son alış satırı başta',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final semantik = tester.ensureSemantics();
      // Seri 1 Haz–29 Ağu; 29 Ağu (i=89) en yeni, 25 Ağu (i=85) alış,
      // 27 Ağu (i=87) satış.
      await pump(tester, lotlar: [
        _lot(DateTime(2026, 8, 25, 11), qty: 12),
        _lot(DateTime(2026, 8, 27, 11), qty: 3, satis: true),
      ]);
      await tester.tap(find.text('Tablo olarak gör'));
      await tester.pumpAndSettle();
      expect(find.text('Alış · 12 lot'), findsOneWidget);
      expect(find.text('Satış · 3 lot'), findsOneWidget);
      // Yalnız renk değil: ikon da var.
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
      // 25 Ağu (i=85, tek) kapanışı 99+42,5=141,5; 29 Ağu 99+44,5=143,5.
      final pct = fmtPctIsaretli((143.5 / 141.5 - 1) * 100, digits: 1);
      expect(find.text('Son alışın 25 Ağu · o günden beri $pct'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^25 Ağu 2026, kapanış .*Senin işlem günün: Alış · 12 lot$')),
          findsOneWidget);
      semantik.dispose();
    });

    testWidgets('lot yoksa etiket ve son alış satırı yok', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pump(tester);
      await tester.tap(find.text('Tablo olarak gör'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alış'), findsNothing);
      expect(find.textContaining('Son alışın'), findsNothing);
    });

    testWidgets('paywall kapalı, admin değil: hiçbir şey', (tester) async {
      await pump(tester, gorunur: false);
      expect(find.text('Tablo olarak gör'), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('GÜNLÜK (gün içi) dönemde satır yok', (tester) async {
      await pump(tester, gunIci: true);
      expect(find.text('Tablo olarak gör'), findsNothing);
    });
  });

  // HIG vitrini (`hig_ortak_bilesen_test`) tembel ListView'ün sınırında;
  // oraya eklenen her öğe alttaki ölçümleri ekrandan itiyordu. Tablonun
  // Dynamic Type ×2 ölçümü burada.
  testWidgets('yazı ×2: tablo 320 pt\'de taşmıyor', (tester) async {
    tester.view.physicalSize = const Size(960, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [SandikPalette.light]),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 600), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: GecmisFiyatlarTablosu(
            bicim: ayniOndalikFiyatBicimi(312.4),
            ozet: 'Son alışın 5 Kas · o günden beri +%1,2',
            islemler: islemGunleri([_lot(DateTime(2026, 11, 5, 10), qty: 12)]),
            satirlar: [
              GunlukKapanis(
                  gun: DateTime(2026, 11, 6), kapanis: 312.4, degisimPct: 1.25),
              GunlukKapanis(
                  gun: DateTime(2026, 11, 5),
                  kapanis: 308.54,
                  degisimPct: -0.8),
              GunlukKapanis(
                  gun: DateTime(2026, 11, 4),
                  kapanis: 311.03,
                  degisimPct: null),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.text('Alış · 12 lot'), findsOneWidget);
  });

  test('iki yüzey de ortak satırı kullanır, yeni istek yok', () {
    expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
        contains('GecmisFiyatlarSatiri('));
    expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
        contains('GecmisFiyatlarSatiri('));
    final src = ekranKaynagiSync('lib/widgets/gecmis_fiyatlar.dart');
    expect(src, isNot(contains('HistoryService.instance')));
    expect(src, contains('showSandikSheet'));
  });
}
