import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hedefe tarih — Bugün kartı ve hedef sayfası (2026-11-12).
///
/// Kilitlenenler:
/// 1. Gün geçmiş, hedefe ulaşılmamış: kart tek satırda günün geçtiğini,
///    ulaşılan yüzdeyi ve "yeni gün seç"i yazar; dokununca hedef sayfası
///    ve "Ne zamana kadar?" açılır. Sayfa da aynı satırı yazar. Eskiden
///    gün sessizce düşüyordu.
/// 2. Gün geçmiş ama hedefe ulaşılmış: eski "Ulaşıldı" aynen.
/// 3. 3,1× yazıda taşma yok; ekran okuyucu uzun yazımı okur.

final _simdi = DateTime(2026, 11, 12, 15);

/// Değeri ₺82.000 olan tek lotlu defter: ₺100.000 hedefe %82.
Asset _lot(String ticker, double tutar, DateTime gun) => Asset(
      id: 'u-$ticker-${gun.millisecondsSinceEpoch}',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 1,
      purchasePrice: tutar,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: tutar,
      addedDate: gun,
    );

List<Asset> _defter = [_lot('THYAO', 82000, DateTime(2025, 1, 10))];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
}

/// `SiganMetin` kendi RenderBox'ıyla çizer; `find.text` onu görmez.
Finder sigan(String metin) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return e.widget is SiganMetin &&
          r is SiganMetinRender &&
          r.secilen == metin;
    });

/// Seçilen yazım [parca]'yı içeriyor mu (dar ekranda kısa yazım seçilir).
Finder siganIceren(String parca) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return e.widget is SiganMetin &&
          r is SiganMetinRender &&
          r.secilen.contains(parca);
    });

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  setUp(() {
    _defter = [_lot('THYAO', 82000, DateTime(2025, 1, 10))];
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
    IntradaySeriesCache.instance.clear();
    BugunKarti.saat = () => _simdi;
    BugunYukleyici.reelTest = null;
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
    IntradaySeriesCache.instance.clear();
    BugunKarti.saat = DateTime.now;
  });

  Future<void> kur(
    WidgetTester tester, {
    required int hedef,
    DateTime? gun,
    double genislik = 390,
    double yaziOlcegi = 1,
    bool gizli = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (gizli) 'pref_balance_hidden': true,
    });
    await initPreferencesCache();
    tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      hedefTarihiDurumuProvider.overrideWithValue(OzellikDurumu.acik),
    ]);
    addTearDown(container.dispose);
    await container.read(kapsamHedefiProvider('').notifier).set(hedef);
    await container.read(kapsamHedefTarihiProvider('').notifier).set(gun);
    final state = await container.read(portfolioProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(yaziOlcegi)),
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(child: BugunKarti(state: state)),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 2));
  }

  group('gün geçti', () {
    const uzun = "Eki 2026 geçti · %82'ye ulaştın · yeni gün seç";

    testWidgets('ulaşılmadı: tek satır, ilerleme önde', (tester) async {
      // Geniş ekran: test yazı tipi (Ahem) geniş, uzun yazım ancak burada
      // sığar; dar ekranda kısa yazım seçilir (aşağıda).
      await kur(tester,
          hedef: 100000, gun: DateTime(2026, 10, 31), genislik: 1200);
      expect(tester.takeException(), isNull);
      expect(sigan('Hedefe %82'), findsOneWidget);
      expect(sigan(uzun), findsOneWidget);
      // Tarihsiz hedefin "kaldı" satırı çizilmez.
      expect(siganIceren('kaldı'), findsNothing);
    });

    testWidgets('ekran okuyucu uzun yazımı okur', (tester) async {
      final h = tester.ensureSemantics();
      await kur(tester, hedef: 100000, gun: DateTime(2026, 10, 31));
      expect(find.bySemanticsLabel('Hedefe %82. $uzun'), findsOneWidget);
      h.dispose();
    });

    testWidgets('dokununca hedef sayfası açılır, aynı satır orada da',
        (tester) async {
      await kur(tester, hedef: 100000, gun: DateTime(2026, 10, 31));
      // Dokunuş kutunun Material'ına düşer (SiganMetin isabet almaz).
      await tester.tap(siganIceren('geçti'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Ne zamana kadar?'), findsOneWidget);
      expect(find.text(uzun), findsOneWidget);
      // Aylık cümle geçmiş günde söylenmez.
      expect(find.textContaining('Ayda yaklaşık'), findsNothing);
    });

    testWidgets('bakiye gizli: oran yazılır (tutar ele vermez)',
        (tester) async {
      await kur(tester,
          hedef: 100000,
          gun: DateTime(2026, 10, 31),
          gizli: true,
          genislik: 1200);
      expect(sigan(uzun), findsOneWidget);
    });

    testWidgets('ulaşıldı: eski "Ulaşıldı" aynen', (tester) async {
      await kur(tester, hedef: 50000, gun: DateTime(2026, 10, 31));
      expect(sigan('Hedef · Ulaşıldı'), findsOneWidget);
      expect(siganIceren('geçti'), findsNothing);
    });

    testWidgets('bugün = geçmedi: gün yazılır', (tester) async {
      await kur(tester,
          hedef: 100000, gun: DateTime(2026, 11, 12), genislik: 1200);
      expect(siganIceren('geçti'), findsNothing);
      expect(siganIceren("Kas 2026'ya kadar"), findsOneWidget);
    });

    for (final genislik in [390.0, 320.0]) {
      testWidgets('${genislik.toInt()}pt, 3,1× yazı: taşma yok',
          (tester) async {
        await kur(tester,
            hedef: 100000,
            gun: DateTime(2026, 10, 31),
            genislik: genislik,
            yaziOlcegi: 3.1);
        expect(tester.takeException(), isNull);
        expect(siganIceren('geçti'), findsOneWidget);
      });
      testWidgets('${genislik.toInt()}pt: dar ekranda kısa yazım',
          (tester) async {
        await kur(tester,
            hedef: 100000, gun: DateTime(2026, 10, 31), genislik: genislik);
        expect(sigan('Eki 2026 geçti · yeni gün seç'), findsOneWidget);
      });
    }
  });
}
