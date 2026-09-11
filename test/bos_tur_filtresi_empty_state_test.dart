import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';

/// Portföy performans ekranı — çizilecek veri YOKKEN spinner dönmemeli.
///
/// REGRESYON: tür çipiyle portföyde bulunmayan bir tür seçildiğinde
/// `HistoryService` boş varlık listesine boş seri döndürüyor; ekran bunu
/// "veri henüz gelmedi" sayıp sonsuza kadar dönen bir yükleme göstergesi
/// çiziyordu. Spinner bir sözdür ("bekle, geliyor") ve burada o söz asla
/// tutulmuyordu. Artık sebebini söyleyen bir boş durum gösteriliyor.
///
/// Üç ayrı "hiç gelmeyecek veri" hâli test edilir:
///   1. seçili türde varlık yok,
///   2. portföy tamamen boş (yeni kullanıcı, "Tümü" seçili),
///   3. varlık var ama fiyat geçmişi izlenmiyor ("Diğer", elle fiyat yok).

const _uid = 'user-1';

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
  double currentPrice = 312.40,
}) =>
    Asset(
      id: '$ticker-1',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 3, 14),
    );

/// Miktara GİRMEYEN satır: temettü. Kullanıcı o hisseyi artık tutmuyor
/// ama nakit temettü kaydı portföyde aktif satır olarak duruyor.
Asset _temettuSatiri() => Asset(
      id: 'THYAO-div-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 0,
      purchasePrice: 0,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 0,
      addedDate: DateTime(2026, 4, 2),
      kind: AssetKind.dividend,
      dividendAmount: 480.0,
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
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
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

Future<void> _pump(
  WidgetTester tester, {
  required List<Asset> assets,
  AssetType? initialTypeFilter,
}) async {
  // Geniş viewport: tüm tür çipleri aynı satıra sığsın, taşma uyarıları
  // testin odağını gölgelemesin.
  tester.view.physicalSize = const Size(1400 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: PortfolioPerformanceScreen(initialTypeFilter: initialTypeFilter),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('portföy performans — boş tür filtresi', () {
    // ASIL REGRESYON: kullanıcının bildirdiği durum. Portföyde yalnızca
    // hisse var, kullanıcı "Döviz" çipine basıyor.
    testWidgets('portföyde olmayan tür seçilince spinner değil boş durum',
        (tester) async {
      await _pump(tester, assets: [
        _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları'),
      ]);

      final dovizChip = find.text('Döviz');
      expect(dovizChip, findsWidgets,
          reason: 'ön koşul: tür çipleri çizilmeli');
      await tester.ensureVisible(dovizChip.first);
      await tester.tap(dovizChip.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CustomLoadingView), findsNothing,
          reason: 'portföyde o türden varlık yokken veri ASLA gelmez — '
              'spinner sonsuza kadar döner');
      expect(find.text('Portföyünde döviz yok'), findsOneWidget,
          reason: 'boş durum metni gösterilmedi');

      // Filtreler kaybolmadı: kullanıcı başka bir türe geçebilir.
      expect(find.text('Tümü'), findsWidgets);
      tester.takeException();
    });

    testWidgets('doğrudan boş türle açılınca da boş durum çizilir',
        (tester) async {
      await _pump(
        tester,
        assets: [_asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları')],
        initialTypeFilter: AssetType.fon,
      );

      expect(find.byType(CustomLoadingView), findsNothing);
      expect(find.text('Portföyünde fon yok'), findsOneWidget);
      tester.takeException();
    });

    testWidgets('portföy tamamen boşken yeni kullanıcı mesajı', (tester) async {
      await _pump(tester, assets: const []);

      expect(find.byType(CustomLoadingView), findsNothing,
          reason: 'boş portföyde beklenecek veri yok');
      expect(find.text('Henüz varlığın yok'), findsOneWidget);
      tester.takeException();
    });

    // TESTFLIGHT REGRESYONU (2026-09-11): ayrım ham satıra dayanıyordu.
    // Kullanıcının hissesi yoktu, yalnızca eski bir temettü kaydı vardı;
    // satır "varlık var" saydırıyor, çizilecek bir şey olmadığı için ekran
    // "Grafik verisi yok" diyordu. Doğru cevap NET pozisyondur.
    testWidgets('miktarsız satır (temettü) "varlık var" saydırmaz',
        (tester) async {
      await _pump(
        tester,
        assets: [_temettuSatiri()],
        initialTypeFilter: AssetType.hisse,
      );

      expect(find.byType(CustomLoadingView), findsNothing);
      expect(find.text('Portföyünde hisse yok'), findsOneWidget,
          reason: 'temettü satırı miktara girmez — net pozisyon yok, '
              'yani kullanıcının o türden varlığı YOK');
      expect(find.text('Grafik verisi yok'), findsNothing,
          reason: 'tutulmayan bir tür için "çizilemiyor" demek yanıltıcı');
      tester.takeException();
    });

    // Varlık VAR ama fiyat geçmişi izlenmiyor ("Diğer", elle fiyat girilmemiş).
    // Bu ayrı bir mesaj gerektirir: "varlığım kayboldu" diye okunmasın.
    testWidgets('fiyat geçmişi olmayan türde ayrı mesaj', (tester) async {
      await _pump(
        tester,
        assets: [
          _asset(
            ticker: '',
            name: 'Antika Saat',
            type: AssetType.diger,
            currentPrice: 0,
          ),
        ],
        initialTypeFilter: AssetType.diger,
      );

      expect(find.byType(CustomLoadingView), findsNothing);
      expect(find.text('Grafik verisi yok'), findsOneWidget,
          reason: 'çizilemeyen tür için ayrı mesaj bekleniyor');
      tester.takeException();
    });
  });
}
