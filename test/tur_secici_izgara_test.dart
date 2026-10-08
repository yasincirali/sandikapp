import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/eurobond_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset/tur_secici_izgara.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle tür seçicisi "gruplu ızgara + arama" (bayrak
/// `tur_secici_izgara`, 2026-10-08). Bayrak kapalıyken eski çip satırı
/// (`asset_type_ekleme_sirasi_test` onu kilitler); açıkken arama + üç grup,
/// seçimden sonra tek satır.

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

final _tr28 = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Türkiye %9,875 2028',
  paraBirimi: 'USD',
  kuponOrani: 0.09875,
  vade: DateTime.utc(2028, 1, 15),
  ihracTarihi: DateTime.utc(2018, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

Future<void> _ac(
  WidgetTester tester, {
  Set<String> bayraklar = const {'tur_secici_izgara', 'abd_hisse', 'eurobond'},
  Widget ekran = const AddAssetScreen(),
  double genislik = 375,
  double yukseklik = 812,
  double metinOlcegi = 1,
  ThemeData? tema,
}) async {
  RemoteConfigService.testAcik = bayraklar;
  addTearDown(() => RemoteConfigService.testAcik = {});
  await initializeDateFormatting('tr_TR');
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(genislik * 3, yukseklik * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => _BosPortfoy()),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      // Ağ yok: katalog sabit (aramadaki eurobond katmanı buradan).
      eurobondKatalogProvider.overrideWith((ref) async => [(_tr28, null)]),
    ],
    child: MaterialApp(
      theme: tema ?? ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(metinOlcegi)),
        child: child!,
      ),
      home: ekran,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder get _secici => find.byWidgetPredicate(
    (w) => w is TourAnchor && w.target == TourTarget.turSecici);

Finder _seciciIcinde(Finder f) => find.descendant(of: _secici, matching: f);

/// Yalnız `Text` (arama alanındaki yazı `EditableText`'tir, sayılmaz).
Finder _metin(String s) => _seciciIcinde(
    find.byWidgetPredicate((w) => w is Text && w.data == s));

Future<void> _yerles(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(SandikMotion.surface);
  await tester.pump(SandikMotion.surface);
}

void main() {
  testWidgets('yeni kayıt: arama + üç grup açık, form gövdesi ve Ekle yok',
      (tester) async {
    await _ac(tester);
    expect(_seciciIcinde(find.byType(TurSeciciIzgara)), findsOneWidget);
    expect(_seciciIcinde(find.byType(Wrap)), findsNothing,
        reason: 'Bayrak açıkken eski çip satırı çizilmez.');
    expect(find.text('BORSA VE FON'), findsOneWidget);
    expect(find.text('DÖVİZ VE DEĞERLİ'), findsOneWidget);
    expect(find.text('BİRİKİM'), findsOneWidget);
    expect(_seciciIcinde(find.text('ABD hisse')), findsOneWidget);
    expect(_seciciIcinde(find.text('Eurobond')), findsOneWidget);
    expect(find.text('Ekle'), findsNothing,
        reason: 'Izgara açıkken kaydet düğmesi yok.');
    expect(find.text('Değiştir'), findsNothing);
  });

  testWidgets('kutuya dokununca tek satıra katlanır, Değiştir geri açar',
      (tester) async {
    await _ac(tester);
    await tester.tap(_seciciIcinde(find.text('Fon')));
    await _yerles(tester);

    expect(find.text('BORSA VE FON'), findsNothing);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(_seciciIcinde(find.text('Fon')), findsOneWidget);
    expect(find.text('Ekle'), findsOneWidget, reason: 'Form görünür olmalı.');
    expect(find.text('Fon seçmek için dokun...'), findsWidgets);

    await tester.tap(find.text('Değiştir'));
    await _yerles(tester);
    expect(find.text('BORSA VE FON'), findsOneWidget);
    expect(find.text('Ekle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ABD kutusu: hisse türü ABD pazarıyla, satırda "ABD hisse"',
      (tester) async {
    await _ac(tester);
    await tester.tap(_seciciIcinde(find.text('ABD hisse')));
    await _yerles(tester);
    expect(_seciciIcinde(find.text('ABD hisse')), findsOneWidget);
    expect(find.text('Değiştir'), findsOneWidget);
    // Formun ABD seçici alanı (BIST alanı değil).
    expect(find.text('ABD hissesi seçmek için dokun...'), findsWidgets);
  });

  testWidgets('arama ızgarayı gizler; sonuca dokununca tür + kimlik seçilir',
      (tester) async {
    await _ac(tester);
    await tester.enterText(_seciciIcinde(find.byType(TextField)), 'THYAO');
    await tester.pump();

    expect(find.text('BORSA VE FON'), findsNothing,
        reason: 'Sorgu varken ızgara gizli.');
    final sonuc = _metin('THYAO');
    expect(sonuc, findsOneWidget);
    expect(_seciciIcinde(find.text('BIST')), findsOneWidget);

    // Ağ araması (çeyrek saniye bekleme) dolmadan seçilir: katlanma
    // bekleyen aramayı iptal eder.
    await tester.tap(sonuc);
    await _yerles(tester);

    expect(find.text('Değiştir'), findsOneWidget);
    expect(_seciciIcinde(find.text('Hisse')), findsOneWidget);
    expect(find.text('Türk Hava Yolları'), findsWidgets,
        reason: 'BIST seçicisi aramadan gelen hisseyle dolu açılmalı.');

    // "Değiştir" aramayı boş açar.
    await tester.tap(find.text('Değiştir'));
    await _yerles(tester);
    expect(find.text('BORSA VE FON'), findsOneWidget);
    final alan =
        tester.widget<TextField>(_seciciIcinde(find.byType(TextField)));
    expect(alan.controller!.text, isEmpty);
  });

  testWidgets('ISIN araması: katalogdaki eurobond seçilir', (tester) async {
    await _ac(tester);
    await tester.enterText(
        _seciciIcinde(find.byType(TextField)), 'US900123DF');
    await tester.pump();
    await tester.pump();
    final sonuc = _metin('US900123DF45');
    expect(sonuc, findsOneWidget);
    expect(_metin('Eurobond'), findsOneWidget, reason: 'Pazar etiketi');
    await tester.tap(sonuc);
    await _yerles(tester);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(_metin('Eurobond'), findsOneWidget);
    expect(find.text('Türkiye %9,875 2028'), findsWidgets,
        reason: 'Eurobond seçicisi aramadaki tahville dolu açılmalı.');
  });

  testWidgets('eurobond bayrağı kapalı: ne kutu ne arama sonucu',
      (tester) async {
    await _ac(tester, bayraklar: const {'tur_secici_izgara'});
    expect(_metin('Eurobond'), findsNothing);
    expect(_metin('ABD hisse'), findsNothing);
    await tester.enterText(
        _seciciIcinde(find.byType(TextField)), 'US900123DF');
    await tester.pump();
    expect(_metin('US900123DF45'), findsNothing);
    await tester.enterText(_seciciIcinde(find.byType(TextField)), '');
    await tester.pump();
  });

  testWidgets('düzenleme: kendi türünde katlı açılır', (tester) async {
    final lot = Asset(
      id: 'a',
      userId: 'u',
      name: 'Bitcoin',
      ticker: 'KRIPTO:BTC',
      type: AssetType.kripto,
      quantity: 0.1,
      purchasePrice: 1000,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );
    await _ac(tester, ekran: AddAssetScreen(editingAsset: lot));
    expect(find.text('BORSA VE FON'), findsNothing);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(_seciciIcinde(find.text('Kripto')), findsOneWidget);
    expect(find.text('Güncelle'), findsOneWidget);
  });

  testWidgets('bayrak kapalı: eski çip satırı, ızgara yok', (tester) async {
    await _ac(tester, bayraklar: const {});
    expect(find.byType(TurSeciciIzgara), findsNothing);
    expect(_seciciIcinde(find.byType(Wrap)), findsOneWidget);
    expect(find.text('BORSA VE FON'), findsNothing);
    expect(find.text('Ekle'), findsOneWidget);
  });

  for (final (ad, tema) in [
    ('dark', ThemeData.dark()),
    ('light', ThemeData.light()),
  ]) {
    testWidgets('320pt × 3.0 metin ($ad): taşma yok, açık ve katlı',
        (tester) async {
      await _ac(tester,
          genislik: 320, yukseklik: 640, metinOlcegi: 3.0, tema: tema);
      expect(tester.takeException(), isNull);
      expect(find.text('BORSA VE FON'), findsOneWidget);

      await tester.ensureVisible(_seciciIcinde(find.text('Kripto')));
      await tester.pump();
      await tester.tap(_seciciIcinde(find.text('Kripto')));
      await _yerles(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Değiştir'), findsOneWidget);

      await tester.ensureVisible(find.text('Değiştir'));
      await tester.tap(find.text('Değiştir'));
      await _yerles(tester);
      await tester.enterText(_seciciIcinde(find.byType(TextField)), 'GARAN');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_metin('GARAN'), findsOneWidget);
      // Bekleyen ağ araması test bitmeden iptal edilsin.
      await tester.enterText(_seciciIcinde(find.byType(TextField)), '');
      await tester.pump();
    });
  }

  testWidgets('kutular en az 48 pt yüksekliğinde', (tester) async {
    await _ac(tester);
    for (final t in ['Hisse', 'Fon', 'Döviz', 'Diğer']) {
      final kutu = find.ancestor(
          of: _seciciIcinde(find.text(t)),
          matching: find.byType(AnimatedContainer));
      expect(tester.getSize(kutu.first).height,
          greaterThanOrEqualTo(SandikSpace.xxl),
          reason: '$t kutusu dokunma hedefinin altında');
    }
  });
}
