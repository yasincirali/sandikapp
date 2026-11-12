import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kapanis_ozeti.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/raporlar_provider.dart';
import 'package:portfoy_takip/providers/sattiklarin_provider.dart';
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_acildi_sayfasi.dart';

import 'helpers/kaynak.dart';

/// Satın alma sonrası sayfa (Ar-Ge 12 Kas 17:04 #4). Kilitlenen: satırlar
/// yalnız veri varken ve kendi sayısıyla; kaynağın satırı önde; en fazla
/// üç; hiç veri yoksa tek "Varlık sınırı kalktı"; satır doğru hedefi açar;
/// her yolda paywall `pop(true)`; 2× / 3,1× yazıda taşma yok.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const hepsi = PremiumAcildiVerisi(
    raporDonemi: null,
    temettuHisse: 3,
    kapanmisPozisyon: 5,
    getiriAy: 14,
  );

  group('premiumAcildiSatirlari (saf)', () {
    test('veri yoksa tek satır: varlık sınırı', () {
      expect(premiumAcildiSatirlari('direct', const PremiumAcildiVerisi()),
          [PremiumAcildiHedef.varlikSiniri]);
    });

    test('tek veri → tek satır, sınır satırı yok', () {
      expect(
          premiumAcildiSatirlari(
              'direct', const PremiumAcildiVerisi(kapanmisPozisyon: 2)),
          [PremiumAcildiHedef.sattiklarin]);
    });

    test('aylık getiri eşiğin (6 ay) altında satır yok', () {
      expect(
          premiumAcildiSatirlari(
              'direct', const PremiumAcildiVerisi(getiriAy: 5)),
          [PremiumAcildiHedef.varlikSiniri]);
    });

    test('dört veri → varsayılan sırayla ilk üç', () {
      final v = PremiumAcildiVerisi(
          raporDonemi: DateTime(2026, 10),
          temettuHisse: 3,
          kapanmisPozisyon: 5,
          getiriAy: 14);
      expect(premiumAcildiSatirlari('direct', v), [
        PremiumAcildiHedef.aylikRapor,
        PremiumAcildiHedef.temettu,
        PremiumAcildiHedef.sattiklarin,
      ]);
    });

    test('kaynağın satırı öne geçer (dördüncü olsa bile)', () {
      final v = PremiumAcildiVerisi(
          raporDonemi: DateTime(2026, 10),
          temettuHisse: 3,
          kapanmisPozisyon: 5,
          getiriAy: 14);
      expect(premiumAcildiSatirlari('aylik_getiri', v), [
        PremiumAcildiHedef.aylikGetiri,
        PremiumAcildiHedef.aylikRapor,
        PremiumAcildiHedef.temettu,
      ]);
      expect(premiumAcildiSatirlari('temettu_tahmini', hepsi).first,
          PremiumAcildiHedef.temettu);
      expect(premiumAcildiSatirlari('sattiklarin', hepsi).first,
          PremiumAcildiHedef.sattiklarin);
    });

    test('kaynağın verisi yoksa sıra değişmez', () {
      expect(
          premiumAcildiSatirlari('aylik_rapor', hepsi),
          [
            PremiumAcildiHedef.temettu,
            PremiumAcildiHedef.sattiklarin,
            PremiumAcildiHedef.aylikGetiri,
          ]);
    });

    test('varlık sınırından açıldıysa sınır önde + en fazla iki veri', () {
      expect(premiumAcildiSatirlari('asset_limit_10', hepsi), [
        PremiumAcildiHedef.varlikSiniri,
        PremiumAcildiHedef.temettu,
        PremiumAcildiHedef.sattiklarin,
      ]);
      expect(
          premiumAcildiSatirlari(
              'bulk_add_asset_limit', const PremiumAcildiVerisi()),
          [PremiumAcildiHedef.varlikSiniri]);
    });
  });

  group('sayfa', () {
    final gozlemci = _Gozlemci();

    Future<List<bool?>> pump(
      WidgetTester tester, {
      String kaynak = 'direct',
      DateTime? rapor,
      int temettu = 0,
      int kapanmis = 0,
      int getiriAy = 0,
    }) async {
      gozlemci.adlar.clear();
      final sonuclar = <bool?>[];
      final simdi = DateTime.now();
      final lotlar = [
        if (getiriAy > 0)
          _lot(DateTime(simdi.year, simdi.month - getiriAy + 1, 5)),
      ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          aylikRaporDonemiProvider.overrideWithValue(rapor),
          temettuTahminiProvider.overrideWith((ref) async => TemettuTahmini(
              satirlar: [for (var i = 0; i < temettu; i++) _tahmin(i)],
              aylik: List.filled(12, 0))),
          sattiklarinProvider.overrideWithValue(
              [for (var i = 0; i < kapanmis; i++) _kapanmis(i)]),
          portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
          premiumKilitliProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          navigatorObservers: [gozlemci],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    sonuclar.add(await Navigator.of(context).push<bool>(
                      adaptiveRoute(
                        settings: const RouteSettings(name: 'paywall'),
                        builder: (pc) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () =>
                                  premiumAcildiAkisi(pc, kaynak: kaynak),
                              child: const Text('satin_alindi'),
                            ),
                          ),
                        ),
                      ),
                    ));
                  },
                  child: const Text('paywall_ac'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('paywall_ac'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('satin_alindi'));
      await tester.pumpAndSettle();
      return sonuclar;
    }

    Finder satir(PremiumAcildiHedef h) =>
        find.byKey(ValueKey('premium_acildi_${h.name}'));

    testWidgets('veri yoksa yalnız varlık sınırı, dokunulmaz bilgi satırı',
        (tester) async {
      await pump(tester);
      expect(find.text('Premium açıldı'), findsOneWidget);
      expect(satir(PremiumAcildiHedef.varlikSiniri), findsOneWidget);
      expect(find.textContaining('Varlık sınırı kalktı'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      // Eski dekoratif halka ve genel cümle yok.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.text('Harika'), findsNothing);
    });

    testWidgets('tek veri → tek satır, kendi sayısıyla', (tester) async {
      await pump(tester, temettu: 3);
      expect(find.text('Temettü tahmini: 3 hisse'), findsOneWidget);
      expect(satir(PremiumAcildiHedef.varlikSiniri), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('üç satır; kaynak sattıkların → önce o', (tester) async {
      await pump(tester,
          kaynak: 'sattiklarin',
          rapor: DateTime(2026, 10),
          temettu: 3,
          kapanmis: 5,
          getiriAy: 14);
      expect(find.text('Sattıkların: 5 kapanmış pozisyon'), findsOneWidget);
      expect(find.text('Ekim raporun hazır'), findsOneWidget);
      expect(find.text('Temettü tahmini: 3 hisse'), findsOneWidget);
      expect(find.textContaining('Aylık getiri tablon'), findsNothing);
      final y = [
        PremiumAcildiHedef.sattiklarin,
        PremiumAcildiHedef.aylikRapor,
        PremiumAcildiHedef.temettu,
      ].map((h) => tester.getTopLeft(satir(h)).dy).toList();
      expect(y, orderedEquals([...y]..sort()));
      for (final h in [
        PremiumAcildiHedef.sattiklarin,
        PremiumAcildiHedef.aylikRapor,
        PremiumAcildiHedef.temettu,
      ]) {
        expect(tester.getSize(satir(h)).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('aylık getiri ay sayısı defterden (ilk alımdan bu aya)',
        (tester) async {
      await pump(tester, kaynak: 'aylik_getiri', getiriAy: 14);
      expect(find.text('Aylık getiri tablon: 14 ay'), findsOneWidget);
    });

    testWidgets('ekran okuyucu etiketi tam cümle', (tester) async {
      final h = tester.ensureSemantics();
      await pump(tester, rapor: DateTime(2026, 10));
      expect(
          find.bySemanticsLabel(
              RegExp(r'^Ekim raporun hazır\. Dokunursan rapor açılır\.')),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('"Kaldığın yere dön" paywall\'ı true ile kapatır',
        (tester) async {
      final sonuclar = await pump(tester, temettu: 2);
      await tester.tap(find.byKey(const ValueKey('premium_acildi_don')));
      await tester.pumpAndSettle();
      expect(sonuclar, [true]);
      expect(find.text('paywall_ac'), findsOneWidget);
    });

    testWidgets('sayfa aşağı kaydırılıp kapanınca da true', (tester) async {
      final sonuclar = await pump(tester);
      await tester.tapAt(const Offset(20, 20)); // perdeye dokun
      await tester.pumpAndSettle();
      expect(sonuclar, [true]);
    });

    testWidgets('temettü satırı: paywall true ile kapanır, tahmin açılır',
        (tester) async {
      final sonuclar = await pump(tester, temettu: 2);
      await tester.tap(satir(PremiumAcildiHedef.temettu));
      await tester.pumpAndSettle();
      expect(sonuclar, [true]);
      expect(gozlemci.adlar.last, 'temettu_tahmini');
      // Paywall yığında kalmadı: tahmin ekranı ana sayfanın üstünde.
      expect(gozlemci.adlar.where((a) => a == 'paywall'), hasLength(1));
    });

    test('rapor satırının rotası Raporlar kapısındakiyle aynı ad', () {
      final r = premiumAcildiRotasi(PremiumAcildiSecim(
          PremiumAcildiHedef.aylikRapor,
          raporDonemi: DateTime(2026, 10)));
      expect(r?.settings.name, 'aylik_rapor');
      expect(
          premiumAcildiRotasi(
                  const PremiumAcildiSecim(PremiumAcildiHedef.temettu))
              ?.settings
              .name,
          'temettu_tahmini');
    });

    testWidgets('aylık getiri satırı Performans sekmesini ister',
        (tester) async {
      final sonuclar = await pump(tester, getiriAy: 14);
      await tester.tap(satir(PremiumAcildiHedef.aylikGetiri));
      await tester.pumpAndSettle();
      expect(sonuclar, [true]);
      expect(MainNavigationScreen.sekmeIstegi.value,
          MainNavigationScreen.performansSekmesi);
      MainNavigationScreen.sekmeIstegi.value = null;
    });

    for (final olcek in [2.0, 3.1]) {
      testWidgets('yazı $olcek×, telefon: üç satırda taşma yok',
          (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = olcek;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester,
            rapor: DateTime(2026, 10), temettu: 3, kapanmis: 5, getiriAy: 14);
        expect(tester.takeException(), isNull);
        // Düğme her ölçekte görünür ve basılabilir.
        expect(find.byKey(const ValueKey('premium_acildi_don')).hitTestable(),
            findsOneWidget);
      });
    }
  });

  test('paywall başarıda akışı kullanır; halka/"Harika" gitti', () {
    final k = ekranKaynagiSync('lib/screens/paywall_screen.dart');
    expect(k, contains('premiumAcildiAkisi(context, kaynak: widget.source)'));
    expect(k, isNot(contains('greatWord')));
    expect(k, isNot(contains('premiumUnlockedBody')));
  });
}

class _Gozlemci extends NavigatorObserver {
  final adlar = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      adlar.add(route.settings.name);
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, ownerId: 'u1');
}

Asset _lot(DateTime tarih, {String id = 'a1'}) => Asset(
      id: id,
      userId: 'u1',
      name: 'Aselsan',
      ticker: 'ASELS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: tarih,
    );

TahminSatiri _tahmin(int i) => TahminSatiri(
      ad: 'Hisse $i',
      sembol: 'H$i',
      lot: 10,
      brutPay: 1,
      brutTry: 10,
      netTry: 9,
      aylar: const [5],
    );

KapanmisPozisyon _kapanmis(int i) => KapanmisPozisyon(
      anahtar: 'k$i',
      satis: _lot(DateTime(2026, 1, 5), id: 's$i'),
      ozet: KapanisOzeti(ad: 'Hisse $i', yil: 1, ay: 0, gun: 0),
    );
