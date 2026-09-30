import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset/bes_formu.dart';
import 'package:portfoy_takip/screens/add_asset/mevduat_formu.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mevduat ve BES "Varlık Ekle"den girilir, genel form BOZULMAZ
/// (kullanıcı kuralı 2026-09-30: "varlık ekle kısmından da eklenebilir
/// olmalı, o yüzden orayı da bozmamalı").
///
/// Kilitlenenler:
///   · tür çipi yalnız gövdeyi değiştirir; başka türe dönünce genel form
///     alanları geri gelir;
///   · boş sözleşme formu kaydedilmez, doğrulama mesajı çıkar;
///   · toplu ekleme (sepet) ve düzenleme sözleşmeli türü sunmaz.
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

void main() {
  Future<void> ac(WidgetTester tester, Widget ekran) async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _BosPortfoy()),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: ekran),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder cip(AssetType t) => find.text(t.label);

  testWidgets('Mevduat çipi mevduat formunu açar; Hisse\'ye dönünce genel form',
      (tester) async {
    await ac(tester, const AddAssetScreen());
    // Genel formun bir alanı: miktar (listenin üstünde, tembel ListView onu kurar).
    expect(find.text('Miktar'), findsWidgets);

    await tester.tap(cip(AssetType.mevduat));
    await tester.pumpAndSettle();
    expect(find.byType(MevduatFormu), findsOneWidget);
    expect(find.text('Miktar'), findsNothing,
        reason: 'Sözleşme formunda miktar × fiyat alanları yok');

    await tester.tap(cip(AssetType.bes));
    await tester.pumpAndSettle();
    expect(find.byType(BesFormu), findsOneWidget);
    expect(find.byType(MevduatFormu), findsNothing);

    await tester.tap(cip(AssetType.hisse));
    await tester.pumpAndSettle();
    expect(find.byType(BesFormu), findsNothing);
    expect(find.text('Miktar'), findsWidgets,
        reason: 'Genel form geri geldi — durumu bozulmadı');
  });

  testWidgets('boş mevduat formu kaydedilmez, doğrulama mesajı çıkar',
      (tester) async {
    await ac(tester, const AddAssetScreen());
    await tester.tap(cip(AssetType.mevduat));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Banka adını yaz.'), findsOneWidget);
    expect(find.byType(AddAssetScreen), findsOneWidget, reason: 'ekran açık');
  });

  testWidgets('boş BES formu: şirket ve fon dağılımı istenir', (tester) async {
    await ac(tester, const AddAssetScreen());
    await tester.tap(cip(AssetType.bes));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Şirket adını yaz.'), findsOneWidget);
    expect(find.text('En az bir emeklilik fonu seç.'), findsOneWidget);
  });

  testWidgets('sepet modunda sözleşmeli tür sunulmaz', (tester) async {
    await ac(tester, const AddAssetScreen(cartMode: true));
    expect(cip(AssetType.mevduat), findsNothing);
    expect(cip(AssetType.bes), findsNothing);
    expect(cip(AssetType.fon), findsWidgets);
  });

  testWidgets('mevduat lotu düzenlenirken genel form yerine bildirim',
      (tester) async {
    final lot = Asset(
      id: 'm',
      userId: 'u',
      name: 'Enpara · Vadeli',
      ticker: mevduatSembolu('abc'),
      type: AssetType.mevduat,
      quantity: 1000,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      sozlesmeId: 'abc',
    );
    await ac(tester, AddAssetScreen(editingAsset: lot));
    expect(find.textContaining('sözleşmeden yönetilir'), findsOneWidget);
    expect(find.text('Miktar'), findsNothing);
    expect(find.byType(MevduatFormu), findsNothing);
  });

  // Dynamic Type: sözleşme formları da 320pt × 3.0'da taşmamalı
  // (`text_scale_overflow_test` genel formu tarar; bu ikisini burada).
  for (final tur in [AssetType.mevduat, AssetType.bes]) {
    testWidgets('${tur.label} formu 320pt x3.0 taşmaz', (tester) async {
      await initializeDateFormatting('tr_TR');
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _BosPortfoy()),
          addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3.0)),
            child: AddAssetScreen(prefillType: null),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text(tur.label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
