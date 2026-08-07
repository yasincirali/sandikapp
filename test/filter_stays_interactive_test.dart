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
import 'package:portfoy_takip/screens/performance_screen.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';

/// Filtre kontrolleri yükleme sırasında ekranda kalmalı (regresyon).
///
/// Eskiden periyot değişimi `FutureBuilder`'ı waiting'e sokuyor ve
/// `return CustomLoadingView()` ile grafiğin ALTINDAKİ her şeyi — periyot
/// toggle'ı dahil — ağaçtan siliyordu. Kullanıcı veri gelene kadar başka
/// bir filtreye dokunamıyordu. Artık yükleme yalnızca grafik alanını kaplar.
///
/// Test ortamında ağ yok; history future'ı boş/hatalı döner. Bu tam da
/// doğrulamak istediğimiz "veri yokken" durumudur.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-100',
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

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final asset = _asset();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio([asset])),
        partnersProvider.overrideWith(_FakePartners.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: PerformanceScreen(asset: asset, showBackButton: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('performans ekranı — filtreler yükleme sırasında tıklanabilir', () {
    testWidgets('periyot toggle veri yokken bile ekranda kalır',
        (tester) async {
      await _pump(tester);

      // Periyot etiketleri her durumda çizilmeli — yükleme göstergesi
      // bunları ağaçtan silmemeli.
      for (final label in ['HAFTALIK', 'AYLIK', 'YILLIK']) {
        expect(find.text(label), findsWidgets,
            reason: '$label periyot butonu yükleme sırasında kayboldu');
      }
    });

    // ASIL REGRESYON: MA20/LOG chip'leri ve compare şeridi FutureBuilder'ın
    // İÇİNDE yaşıyor. Eski kod waiting'de `return CustomLoadingView()`
    // yaptığı için periyot değiştirir değiştirmez bunlar ağaçtan düşüyordu.
    // Periyot toggle'ı FutureBuilder'ın üstünde olduğundan hep kalıyordu —
    // yani bu davranışı yalnızca aşağıdaki chip'ler yakalayabilir.
    testWidgets('periyot değişiminde grafik kontrolleri (MA20/LOG) kalır',
        (tester) async {
      await _pump(tester);

      // Başlangıçta veri gelmiş olmalı ki chip'ler çizilsin.
      expect(find.text('MA20'), findsWidgets,
          reason: 'ön koşul: ilk yüklemede chip\'ler görünmeli');

      // Periyot değiştir — future yenilenir, FutureBuilder waiting olur.
      await tester.tap(find.text('AYLIK').first, warnIfMissed: false);
      await tester.pump(); // waiting karesi

      // Tam bu karede chip'ler HÂLÂ ekranda olmalı.
      expect(find.text('MA20'), findsWidgets,
          reason: 'periyot değişiminde MA20 chip\'i kayboldu — '
              'yükleme tüm bloğu sildi');
      expect(find.text('LOG'), findsWidgets,
          reason: 'periyot değişiminde LOG chip\'i kayboldu');

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    // NOT: Bu test "duman testi" seviyesindedir. Test ortamında ağ yok,
    // history future'ı neredeyse anında resolve oluyor; dolayısıyla gerçek
    // "waiting" karesi burada gözlemlenemiyor ve fix geri alındığında bu
    // test KIRMIZIYA DÖNMÜYOR (denendi). Bayat-seri mantığının asıl
    // doğrulaması `stale_window_clip_test.dart` içindedir.
    testWidgets('periyot değişiminde grafik alanı spinner göstermez',
        (tester) async {
      await _pump(tester);

      // Ön koşul: ilk yüklemede grafik çizilmiş, spinner yok.
      expect(find.byType(CustomLoadingView), findsNothing,
          reason: 'ön koşul: ilk yükleme bitmiş olmalı');

      await tester.tap(find.text('YILLIK').first, warnIfMissed: false);
      await tester.pump(); // periyot değişiminin ilk karesi

      // ASIL İDDİA: bu karede spinner OLMAMALI — eski seri soluk çizilir.
      expect(find.byType(CustomLoadingView), findsNothing,
          reason: 'periyot değişiminde loading göstergesi çıktı — '
              'bayat seri çizilmek yerine spinner\'a düşülüyor');

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('arka arkaya periyot değişimi ekranı bozmaz', (tester) async {
      await _pump(tester);

      for (final label in ['HAFTALIK', 'AYLIK', 'YILLIK', 'HAFTALIK']) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('AYLIK'), findsWidgets);
    });
  });
}
