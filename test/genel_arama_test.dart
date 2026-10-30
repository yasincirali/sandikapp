import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/hizli_hesap.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/genel_arama_screen.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Genel arama (sadeleştirme 2; bayrak `genel_arama` 2026-10-20'de emekliye
/// ayrıldı).
///
/// Bayrak kapalı: ana ekran üst çubuğu birebir eski (yenile düğmesi).
/// Bayrak açık: aynı yuvada büyüteç; arama ekranı kendi varlığını,
/// piyasa sonucunu ve eylemleri gösterir.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset()],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

Future<void> _pump(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
      watchlistProvider.overrideWith(_Takip.new),
    ],
    child: MaterialApp(
        home: Material(type: MaterialType.transparency, child: ekran)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  tearDown(() => RemoteConfigService.testAcik = {});

  group('ana ekran üst çubuğu', () {
    // 2026-10-30 (UX raporu §3): tek arama girişi. Üst çubuktaki büyüteç
    // kalktı; piyasa şeridindeki "Ara" hapı genel aramayı açar.
    testWidgets('tek arama girişi: Ara hapı genel aramayı açar', (t) async {
      await _pump(t, const HomeScreen());
      expect(find.byKey(const ValueKey('genel-arama-dugmesi')), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      final ara = find.byType(PiyasaAramaDugmesi);
      expect(ara, findsOneWidget);
      // 44pt dokunma yüksekliği.
      expect(t.getRect(ara).height, 44);
      // Yenileme aşağı çekmede kalır.
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await t.tap(ara);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GenelAramaScreen), findsOneWidget);
      // Boş sorguda dört sabit eylem; ana ekranın açıcıları ("Bildirimler",
      // "Tüm hareketler") "Tüm eylemler"in arkasında.
      expect(find.text('EYLEMLER'), findsOneWidget);
      expect(find.text('Bildirimler'), findsNothing);
      await t.tap(find.text('Tüm eylemler'));
      await t.pumpAndSettle();
      expect(find.text('Bildirimler'), findsOneWidget);
      expect(find.text('Tüm hareketler'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('arama ekranı', () {
    setUp(SymbolSearchService.clearCacheForTest);

    Future<void> yaz(WidgetTester t, String q) async {
      await t.enterText(find.byKey(const ValueKey('genel-arama-alani')), q);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Widget ekran() => GenelAramaScreen(
          aramaServisi: (q) async => q.toLowerCase().contains('thy')
              ? const [
                  SymbolHit(
                      ticker: 'THYAO.IS',
                      name: 'Türk Hava Yolları',
                      source: 'BIST'),
                ]
              : const [],
          kotasyonServisi: (_) async => const {},
        );

    testWidgets('boş sorgu: eylem önerileri; açıcısı verilmeyenler yok',
        (t) async {
      await _pump(t, ekran());
      expect(find.text('EYLEMLER'), findsOneWidget);
      expect(find.text('Fiyat alarmları'), findsOneWidget);
      expect(find.text('Ayarlar'), findsOneWidget);
      // Çağıran açıcı vermedi → listelenmez.
      expect(find.text('Bildirimler'), findsNothing);
      expect(find.text('Tüm hareketler'), findsNothing);
      expect(find.text('VARLIKLARIM'), findsNothing);
      expect(find.text('PİYASA'), findsNothing);
    });

    // Boş arama sadeleşmesi (2026-10-26): dört sabit + "Tüm eylemler".
    const sabit = ['Fiyat alarmları', 'Takibe al', 'Toplu ekle', 'Ayarlar'];
    const kalan = [
      'Sinyal ayarları',
      'Ekstreden aktar (CSV)',
      'Tüm hareketler',
      'Karşılaştır',
      'Bildirimler',
    ];
    final tumu = find.byKey(const ValueKey('genel-arama-tum-eylemler'));
    Widget tamEkran() => GenelAramaScreen(
          tumHareketleriAc: () {},
          bildirimleriAc: () {},
          aramaServisi: (_) async => const [],
          kotasyonServisi: (_) async => const {},
        );
    int gorunenEylem() => [...sabit, ...kalan]
        .where((m) => find.text(m).evaluate().isNotEmpty)
        .length;

    testWidgets('boşta dört sabit + "Tüm eylemler"; dokununca 9, tekrar 4',
        (t) async {
      await _pump(t, tamEkran());
      for (final m in sabit) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      // Sıra: alarm, takip, toplu, ayarlar; "Tüm eylemler" en altta.
      final y = [for (final m in sabit) t.getTopLeft(find.text(m)).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(t.getTopLeft(tumu).dy, greaterThan(y.last));
      expect(gorunenEylem(), 4);

      await t.tap(tumu);
      await t.pumpAndSettle();
      expect(gorunenEylem(), 9);
      // Kalanlar satırın ALTINDA açılır; satır yerinde kalır.
      expect(t.getTopLeft(find.text('Sinyal ayarları')).dy,
          greaterThan(t.getTopLeft(tumu).dy));

      await t.tap(tumu);
      await t.pumpAndSettle();
      expect(gorunenEylem(), 4);
      expect(t.takeException(), isNull);
    });

    testWidgets('yazınca açılır satır yok, eşleşen hepsi', (t) async {
      await _pump(t, tamEkran());
      await yaz(t, 'sinyal');
      expect(find.text('Sinyal ayarları'), findsOneWidget);
      expect(tumu, findsNothing);
    });

    testWidgets('açık/kapalı kalıcı değil: yeniden açılışta kapalı', (t) async {
      await _pump(t, tamEkran());
      await t.tap(tumu);
      await t.pumpAndSettle();
      expect(gorunenEylem(), 9);
      await t.pumpWidget(const SizedBox());
      await _pump(t, tamEkran());
      expect(gorunenEylem(), 4);
    });

    testWidgets('VoiceOver: "Tüm eylemler" düğme + açık/kapalı durumu; 44pt',
        (t) async {
      final h = t.ensureSemantics();
      await _pump(t, tamEkran());
      expect(t.getSize(tumu).height, greaterThanOrEqualTo(44));
      final dugum = find.bySemanticsLabel('Tüm eylemler');
      expect(
          t.getSemantics(dugum),
          matchesSemantics(
            label: 'Tüm eylemler',
            isButton: true,
            hasExpandedState: true,
            isExpanded: false,
            hasTapAction: true,
          ));
      await t.tap(tumu);
      await t.pumpAndSettle();
      expect(
          t.getSemantics(dugum),
          matchesSemantics(
            label: 'Tüm eylemler',
            isButton: true,
            hasExpandedState: true,
            isExpanded: true,
            hasTapAction: true,
          ));
      h.dispose();
    });

    // ×2 en dar telefonda (320pt), ×3.1 375pt'de. 320pt × 3.1'de arama
    // ALANININ yer tutucusu taşıyor — bu satırdan önce de vardı, ayrı iş.
    testWidgets('Dynamic Type ×2 / ×3.1: taşma yok', (t) async {
      for (final (en, olcek) in [(320.0, 2.0), (375.0, 3.1)]) {
        t.view.physicalSize = Size(en * 3, 640 * 3);
        t.view.devicePixelRatio = 3.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            portfolioProvider.overrideWith(_FakePortfolio.new),
            watchlistProvider.overrideWith(_Takip.new),
          ],
          child: MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(olcek)),
              child: child!,
            ),
            home: Material(type: MaterialType.transparency, child: tamEkran()),
          ),
        ));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(tumu);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '${en}pt ×$olcek');
        expect(t.getSize(tumu).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('"thy": kendi varlığı + piyasa sonucu', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'thy');
      expect(find.text('VARLIKLARIM'), findsOneWidget);
      // Varlıklarım ve Piyasa satırı aynı alt satırı taşır.
      expect(find.text('THYAO · Hisse'), findsNWidgets(2));
      expect(find.text('PİYASA'), findsOneWidget);
      expect(find.text('Türk Hava Yolları'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('"alarm": yalnız eylem eşleşir', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'alarm');
      expect(find.text('Fiyat alarmları'), findsOneWidget);
      expect(find.text('Ayarlar'), findsNothing);
      expect(find.text('VARLIKLARIM'), findsNothing);
    });

    // Hızlı hesap (2026-10-24): "5 çeyrek" → en üstte "≈ ₺" satırı; fiyat
    // formun kaydedeceği sembolden, aynı kotasyon yolundan.
    Widget fiyatliEkran(Map<String, YahooQuote> q) => GenelAramaScreen(
          aramaServisi: (_) async => const [],
          kotasyonServisi: (semboller) async => {
            for (final s in semboller)
              if (q[s] case final v?) s: v,
          },
        );

    testWidgets('"5 çeyrek": fiyat varsa en üstte tutar satırı', (t) async {
      await _pump(
          t,
          fiyatliEkran(const {
            'ALTIN_CEYREK':
                YahooQuote(symbol: 'ALTIN_CEYREK', regularMarketPrice: 10500),
          }));
      await yaz(t, '5 çeyrek');
      expect(find.byKey(const ValueKey('genel-arama-hizli-hesap')),
          findsOneWidget);
      expect(find.text('5 Çeyrek Altın ≈ ₺52.500'), findsOneWidget);
      expect(find.text('Portföyüne ekle'), findsOneWidget);
      // Satır varken "sonuç yok" yazılmaz.
      expect(find.textContaining('için sonuç yok'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('"100 dolar": döviz kotasyonuyla', (t) async {
      await _pump(
          t,
          fiyatliEkran(const {
            'USDTRY=X': YahooQuote(symbol: 'USDTRY=X', regularMarketPrice: 42),
          }));
      await yaz(t, '100 dolar');
      expect(find.text('100 USD ≈ ₺4.200'), findsOneWidget);
    });

    testWidgets('satıra dokununca Varlık Ekle o tür ve miktarla açılır',
        (t) async {
      await _pump(
          t,
          fiyatliEkran(const {
            'ALTIN_YARIM':
                YahooQuote(symbol: 'ALTIN_YARIM', regularMarketPrice: 21000),
          }));
      await yaz(t, '3 yarım');
      await t.tap(find.byKey(const ValueKey('genel-arama-hizli-hesap')));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final form = t.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(form.hizliHesap,
          const HizliHesap(miktar: 3, altin: GoldSubCategory.yarim));
      expect(form.ekleYolu, 'arama');
    });

    testWidgets('fiyat bilinmiyorsa satır YOK', (t) async {
      await _pump(t, fiyatliEkran(const {}));
      await yaz(t, '5 çeyrek');
      expect(
          find.byKey(const ValueKey('genel-arama-hizli-hesap')), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
    });

    // İkinci adım (2026-10-25): ters yön SATIŞ fiyatından, hisse/fon adedi
    // yalnız aramanın kaynağında birebir bulunan sembolle.

    // `pushGuarded`ın çift dokunma penceresi GERÇEK saatle (500 ms) ve
    // testler arasında paylaşılır; önceki testin push'u bu dokunuşu
    // yutmasın diye pencere gerçek zamanda geçirilir.
    Future<void> satiraDokun(WidgetTester t) async {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.tap(find.byKey(const ValueKey('genel-arama-hizli-hesap')));
    }

    Widget ikinciAdim(Map<String, YahooQuote> q) => GenelAramaScreen(
          aramaServisi: (s) async => s.toLowerCase().contains('thy')
              ? const [
                  SymbolHit(
                      ticker: 'THYAO.IS',
                      name: 'Türk Hava Yolları',
                      source: 'BIST'),
                ]
              : s.toUpperCase() == 'AFT'
                  ? const [
                      SymbolHit(
                          ticker: 'TEFAS:AFT',
                          name: 'Ak Portföy Yeni Teknolojiler',
                          source: 'Fon'),
                    ]
                  : const [],
          kotasyonServisi: (semboller) async => {
            for (final s in semboller)
              if (q[s] case final v?) s: v,
          },
        );
    const ceyrekSatisli = {
      'ALTIN_CEYREK': YahooQuote(
          symbol: 'ALTIN_CEYREK',
          regularMarketPrice: 3800,
          satisFiyati: 4000,
          currency: 'TRY'),
    };

    testWidgets('ters "10.000 tl çeyrek": satış fiyatından adet', (t) async {
      await _pump(t, ikinciAdim(ceyrekSatisli));
      await yaz(t, '10.000 tl çeyrek');
      expect(find.byKey(const ValueKey('genel-arama-hizli-hesap')),
          findsOneWidget);
      // 10.000 ÷ 4.000 (satış), alış 3.800 değil.
      expect(find.text('₺10.000 ≈ 2,5 Çeyrek Altın'), findsOneWidget);
      expect(find.text('Kuyumcu satış fiyatından · Portföyüne ekle'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(r'^₺10\.000 ≈ 2,5 Çeyrek Altın\. '
              r'Kuyumcu satış fiyatından · Portföyüne ekle')),
          findsOneWidget);
      // 44pt satır.
      expect(
          t
              .getSize(find.byKey(const ValueKey('genel-arama-hizli-hesap')))
              .height,
          greaterThanOrEqualTo(44));
      expect(t.takeException(), isNull);
    });

    testWidgets('ters döviz: "kuyumcu" denmez', (t) async {
      await _pump(
          t,
          ikinciAdim(const {
            'USDTRY=X': YahooQuote(
                symbol: 'USDTRY=X',
                regularMarketPrice: 41.9,
                satisFiyati: 42,
                currency: 'TRY'),
          }));
      await yaz(t, '4200 tl dolar');
      expect(find.text('₺4.200 ≈ 100 USD'), findsOneWidget);
      expect(find.text('Satış fiyatından · Portföyüne ekle'), findsOneWidget);
    });

    testWidgets('ters: satış yoksa ya da kapıdan geçmezse satır YOK',
        (t) async {
      for (final q in const [
        // Satış hiç gelmedi: alışa düşülmez.
        YahooQuote(
            symbol: 'ALTIN_CEYREK', regularMarketPrice: 3800, currency: 'TRY'),
        // Satış alışın altında: veri bozuk.
        YahooQuote(
            symbol: 'ALTIN_CEYREK',
            regularMarketPrice: 3800,
            satisFiyati: 3700,
            currency: 'TRY'),
        // Makas sınır dışı.
        YahooQuote(
            symbol: 'ALTIN_CEYREK',
            regularMarketPrice: 3000,
            satisFiyati: 4000,
            currency: 'TRY'),
      ]) {
        await _pump(t, ikinciAdim({'ALTIN_CEYREK': q}));
        await yaz(t, '10.000 tl çeyrek');
        expect(
            find.byKey(const ValueKey('genel-arama-hizli-hesap')), findsNothing,
            reason: '${q.satisFiyati}');
        expect(find.textContaining('≈'), findsNothing);
      }
    });

    testWidgets('ters satıra dokununca form o TL ile açılır', (t) async {
      await _pump(t, ikinciAdim(ceyrekSatisli));
      await yaz(t, '10.000 tl çeyrek');
      await satiraDokun(t);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final form = t.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(
          form.hizliHesap,
          const HizliHesap(
              miktar: 10000, altin: GoldSubCategory.ceyrek, ters: true));
    });

    const thyFiyatli = {
      'THYAO.IS': YahooQuote(
          symbol: 'THYAO.IS', regularMarketPrice: 312.4, currency: 'TRY'),
    };

    testWidgets('"100 THYAO": birebir hisse, canlı fiyatla', (t) async {
      await _pump(t, ikinciAdim(thyFiyatli));
      await yaz(t, '100 THYAO');
      expect(find.text('100 THYAO ≈ ₺31.240'), findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^100 THYAO ≈ ₺31\.240\. Portföyüne ekle')),
          findsOneWidget);

      await satiraDokun(t);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final form = t.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(form.prefillTicker, 'THYAO.IS');
      expect(form.prefillType, AssetType.hisse);
      expect(form.hizliHesap?.adetOnDolgu, 100);
      expect(t.takeException(), isNull);
    });

    testWidgets('"1000 AFT": TEFAS fonu', (t) async {
      await _pump(
          t,
          ikinciAdim(const {
            'TEFAS:AFT': YahooQuote(
                symbol: 'TEFAS:AFT', regularMarketPrice: 1.5, currency: 'TRY'),
          }));
      await yaz(t, '1000 AFT');
      expect(find.text('1000 AFT ≈ ₺1.500'), findsOneWidget);
    });

    testWidgets('adet: fiyat yoksa, yarım kod ya da serbest metinse satır YOK',
        (t) async {
      await _pump(t, ikinciAdim(const {}));
      await yaz(t, '100 THYAO');
      expect(
          find.byKey(const ValueKey('genel-arama-hizli-hesap')), findsNothing);
      expect(find.textContaining('≈'), findsNothing);

      await _pump(t, ikinciAdim(thyFiyatli));
      for (final g in ['100 THY', '2025 raporu', '3 ay', '10 tl']) {
        await yaz(t, g);
        expect(
            find.byKey(const ValueKey('genel-arama-hizli-hesap')), findsNothing,
            reason: g);
      }
    });

    testWidgets('ipucu örnek verir', (t) async {
      await _pump(t, ekran());
      expect(find.text('ör. THYAO ya da 5 çeyrek'), findsOneWidget);
    });

    testWidgets('hiçbir şey eşleşmezse boş durum metni', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'qqzz');
      expect(find.text('"qqzz" için sonuç yok.'), findsOneWidget);
    });
  });
}
