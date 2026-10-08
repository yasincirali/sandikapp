import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/klavye_kapatici.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Klavye açıkken ekran anlamlı konumda kalır (kullanıcı, 2026-10-08):
/// *"klavye aksiyonu bulunan tüm ekranları incele, açılıp kapanabilir
/// klavye açıldığında ekran hâlâ anlamlı pozisyonda kalmalı."*
///
/// Denetimde 26 giriş yüzeyinden bulunan kırıklar burada kilitli:
/// - Hızlı Al/Sat diyaloğu kaymıyordu → klavyeyle Al/Sat kırpılıyordu.
/// - Hızlı Giriş sayfası toplu girişte taşıyor, "N varlığı kaydet"
///   klavyenin altında kalıyordu.
/// - Yükseklik sınırı kalkan sayfalar klavyeyle durum çubuğunun altına
///   giriyordu (`showSandikSheet` varsayılanı).
/// - Liste sürüklemek klavyeyi kapatmıyordu (`SandikKaydirmaDavranisi`).
///
/// Telefon: 390×844, üstte 47 pt durum çubuğu, 336 pt iOS metin klavyesi.

const _ust = 47.0;
const _klavye = 336.0;
const _yukseklik = 844.0;

void _telefon(WidgetTester tester, {bool klavye = true}) {
  tester.view.physicalSize = const Size(390 * 3, _yukseklik * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: _ust * 3);
  if (klavye) {
    tester.view.viewInsets = const FakeViewPadding(bottom: _klavye * 3);
  }
  addTearDown(tester.view.reset);
}

/// Bulgunun dikdörtgeni klavyenin üstünde ve durum çubuğunun altında mı.
void _gorunur(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  expect(r.bottom, lessThanOrEqualTo(_yukseklik - _klavye + 0.5),
      reason: '$f klavyenin altında kaldı (alt=${r.bottom})');
  expect(r.top, greaterThanOrEqualTo(_ust - 0.5),
      reason: '$f durum çubuğunun altına girdi (üst=${r.top})');
}

/// Dikey taşmaları toplar. Yatay taşma (test fontu Ahem gerçek fonttan
/// geniş; 390 pt'de başlık satırı sağa taşar) bu testin konusu değil.
List<String> _dikeyTasmalar() {
  final liste = <String>[];
  final onceki = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      if (m.contains('bottom')) liste.add(m);
      return;
    }
    onceki?.call(d);
  };
  addTearDown(() => FlutterError.onError = onceki);
  return liste;
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: const [],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
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

Asset _hisse() => Asset(
      id: 'a',
      userId: 'u',
      name: 'THYAO.IS',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 250,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 300,
      addedDate: DateTime(2026, 3, 14),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Hızlı Al/Sat diyaloğu', () {
    for (final mod in QuickAdjustMode.values) {
      testWidgets('${mod.name}: klavye açıkken taşmaz, düğme görünür',
          (tester) async {
        _telefon(tester);
        final tasmalar = _dikeyTasmalar();
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showQuickAdjustDialog(context, ref,
                      asset: _hisse(), mode: mod),
                  child: const Text('ac'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('ac'));
        await tester.pumpAndSettle();
        // Toplam kutusu miktar girilince çıkar — en uzun hâl.
        await tester.enterText(find.byType(TextField).first, '3');
        await tester.pumpAndSettle();

        expect(tasmalar, isEmpty);
        _gorunur(tester,
            find.text(mod == QuickAdjustMode.add ? 'Al' : 'Sat').last);
        _gorunur(tester, find.text('İptal').last);
      });
    }
  });

  testWidgets('Hızlı Giriş: toplu girişte taşmaz, kaydet düğmesi görünür',
      (tester) async {
    _telefon(tester);
    final tasmalar = _dikeyTasmalar();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: MaterialApp(
          theme: ThemeData.dark(), home: const AddAssetScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();

    final satirlar = List.generate(12, (i) => '${i + 1}00 dolar').join('\n');
    await tester.enterText(find.byType(TextField).last, satirlar);
    await tester.pumpAndSettle();

    expect(tasmalar, isEmpty);
    _gorunur(tester, find.byType(FilledButton).last);
    _gorunur(tester, find.byType(TextField).last);
  });

  testWidgets(
      'showSandikSheet: yüksek sayfa klavyeyle durum çubuğunun altına girmez',
      (tester) async {
    _telefon(tester);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSandikSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                // Sembol arama / BES seçici gibi: sabit 0.8 ekran yüksekliği.
                child: SizedBox(
                  height: _yukseklik * 0.8,
                  child: const Column(children: [
                    Text('baslik'),
                    TextField(),
                  ]),
                ),
              ),
            ),
            child: const Text('ac'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ac'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _gorunur(tester, find.text('baslik'));
    _gorunur(tester, find.byType(TextField));
  });

  testWidgets('liste sürüklemek açık klavyeyi kapatır', (tester) async {
    _telefon(tester, klavye: false);
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const SandikKaydirmaDavranisi(),
      home: Scaffold(
        body: Column(children: [
          const TextField(),
          Expanded(
            child: ListView(children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 48, child: Text('satir $i')),
            ]),
          ),
        ]),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(find.text('satir 3'), const Offset(0, -200));
    // pumpAndSettle değil: odak kalırsa (eski davranış) imleç yanıp söner,
    // test sonsuza kadar beklerdi.
    await tester.pump(const Duration(milliseconds: 500));
    expect(FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()));
  });

  group('kaynak kilitleri', () {
    test('uygulama kaydırma davranışı klavyeyi sürüklemeyle kapatır', () {
      final main = ekranKaynagiSync('lib/main.dart');
      expect(main, contains('scrollBehavior: const SandikKaydirmaDavranisi()'),
          reason: 'MaterialApp.scrollBehavior kaldırıldı: listeyi kaydırmak '
              'artık klavyeyi kapatmıyor.');
    });

    test('hiçbir ekran sürüklemeyle kapanmayı elle kapatmaz', () {
      // Bilinçli istisna gerekirse buraya gerekçesiyle eklenir.
      final ihlal = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f
              .readAsStringSync()
              .contains('ScrollViewKeyboardDismissBehavior.manual'))
          .map((f) => f.path)
          .toList();
      expect(ihlal, isEmpty);
    });
  });
}
