import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/gecmis_fiyatlar.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/gecmis_fiyatlar.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

import 'helpers/kaynak.dart';

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

  group('GecmisFiyatlarSatiri', () {
    final seri = {
      for (var i = 0; i < 90; i++)
        DateTime(2026, 6, 1, 18).add(Duration(days: i)).millisecondsSinceEpoch:
            i.isEven ? 100.0 + i : 99.0 + i * 0.5,
    };

    Future<void> pump(WidgetTester tester,
        {bool gorunur = true,
        bool kilitli = false,
        bool gunIci = false}) async {
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
                seri: seri,
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
      expect(find.text("Geçmiş fiyat tablosu Premium'da"), findsOneWidget);
      // Testte paywall RC'si kapalı: `PaywallScreen.show` sessizce döner;
      // önemli olan tablonun açılmaması.
      await tester.tap(find.byType(KilitSatiri));
      await tester.pumpAndSettle();
      expect(find.byType(GecmisFiyatlarTablosu), findsNothing);
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
