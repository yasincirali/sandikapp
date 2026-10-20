import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/veri_kalitesi_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/widgets/varlik_guncelle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Bilgi eksik" akışının iki ucu (2026-10-20): düzenleme formu maliyeti
/// girilen lotun işaretini düşürür, girilmeyeninkini korur; Portföy satırı
/// eksiği küçük etiketle söyler.
const _uid = 'u1';

Asset _lot({
  String id = 'a',
  String ticker = 'AAPL',
  String ad = 'Apple',
  AssetType tur = AssetType.hisse,
  bool elle = false,
  bool? maliyetBilinmiyor = true,
  DateTime? addedDate,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: 5,
      purchasePrice: 10,
      currency: 'USD',
      notes: '',
      isManualPrice: elle,
      currentPrice: 10,
      addedDate: addedDate ?? DateTime(2026, 10, 1),
      maliyetBilinmiyor: maliyetBilinmiyor,
    );

class _Kaydeden extends PortfolioNotifier {
  _Kaydeden(this.lotlar);
  final List<Asset> lotlar;
  Asset? yazilan;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: 42, eurTry: 46, gbpTry: 54);

  @override
  Future<void> updateAsset(Asset asset) async => yazilan = asset;
}

class _Fiyat implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => 10;
  @override
  Future<double?> spot(String ticker) async => 10;
  @override
  Future<String?> companyName(String ticker) async => 'Apple';
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Ortaklar extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _OrtakLotlari extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Future<_Kaydeden> formuAc(WidgetTester t, Asset lot) async {
    t.view.physicalSize = const Size(390 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    final p = _Kaydeden([lot]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => p),
        addAssetPriceLookupProvider.overrideWithValue(_Fiyat()),
      ],
      child: MaterialApp(
          theme: ThemeData.dark(), home: AddAssetScreen(editingAsset: lot)),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    return p;
  }

  Future<void> guncelle(WidgetTester t) async {
    final d = find.widgetWithText(FilledButton, 'Güncelle');
    await t.ensureVisible(d);
    await t.tap(d);
    await t.pumpAndSettle();
  }

  testWidgets('maliyeti bilinmeyen lot: fiyat alanı boş açılır; girilince '
      'işaret düşer', (t) async {
    final p = await formuAc(t, _lot());
    final alan = find.widgetWithText(TextField, 'Otomatik');
    expect(t.widget<TextField>(alan).controller!.text, isEmpty,
        reason: 'Tahmini fiyat kullanıcının girdisi gibi dolu gelmemeli');
    await t.enterText(alan, '7');
    await t.pump();
    await guncelle(t);
    expect(p.yazilan, isNotNull);
    expect(p.yazilan!.purchasePrice, 7);
    expect(p.yazilan!.maliyetBilinmiyor, isFalse);
  });

  testWidgets('fiyat boş bırakılırsa işaret kalır', (t) async {
    final p = await formuAc(t, _lot());
    await guncelle(t);
    expect(p.yazilan, isNotNull);
    expect(p.yazilan!.maliyetBilinmiyor, isTrue);
  });

  testWidgets('işaretsiz lot (null) düzenlenince null kalır, alan dolu',
      (t) async {
    final p = await formuAc(t, _lot(maliyetBilinmiyor: null));
    expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Otomatik'))
            .controller!
            .text,
        '10');
    await guncelle(t);
    expect(p.yazilan!.maliyetBilinmiyor, isNull);
  });

  testWidgets('Portföy satırı eksiği etiketle söyler', (t) async {
    t.view.physicalSize = const Size(390 * 3, 1000 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _Kaydeden([
              _lot(),
              _lot(
                  id: 'b',
                  ticker: '',
                  ad: 'Arsa',
                  tur: AssetType.diger,
                  elle: true,
                  maliyetBilinmiyor: null,
                  addedDate: DateTime(2026, 9, 18)),
              _lot(id: 'c', ticker: 'MSFT', ad: 'Microsoft',
                  maliyetBilinmiyor: false),
            ])),
        authProvider.overrideWith(_Auth.new),
        partnersProvider.overrideWith(_Ortaklar.new),
        allPartnerAssetsProvider.overrideWith(_OrtakLotlari.new),
        watchlistProvider.overrideWith(_Takip.new),
        varlikGuncellemeProvider
            .overrideWithValue(VarlikGuncellemeDurumu.gizli),
        cokluPortfoyGorunurProvider.overrideWithValue(false),
        veriKalitesiSaatProvider
            .overrideWithValue(() => DateTime(2026, 10, 20, 14)),
      ],
      child:
          MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
    ));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Alış fiyatı eksik', findRichText: true), findsOneWidget);
    expect(find.textContaining('Fiyat 32 gün önce girildi',
            findRichText: true),
        findsOneWidget);
  });
}
