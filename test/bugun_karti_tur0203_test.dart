import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bugün kartı, Ar-Ge 21 Kas gece turu: veri yokken "Canlı" yok, tutar yokken
/// "sadece fiyat etkisi" yok, kilitliyken kayıtlı hedef günü kartta durur.

final _simdi = DateTime(2026, 10, 9, 15);

Asset _lot() => Asset(
      id: 'u-THYAO',
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 300,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.4,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: [_lot()], usdTry: 42, eurTry: 46, gbpTry: 54);
}

/// Adaylardan biri [parca]'yı içeren SiganMetin (hangisinin seçildiği test
/// yazı tipinin genişliğine bağlı; kural "aday listesinde var").
Finder siganIceren(String parca) => find.byWidgetPredicate(
    (w) => w is SiganMetin && w.adaylar.any((a) => a.contains(parca)));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
    BugunKarti.saat = () => _simdi;
  });
  tearDown(() {
    HistoryService.gunIciSaat = DateTime.now;
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
    BugunKarti.saat = DateTime.now;
  });

  Future<ProviderContainer> kur(
    WidgetTester tester, {
    OzellikDurumu durum = OzellikDurumu.acik,
    DateTime? gun,
    int hedef = 0,
    bool seri = false,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      hedefTarihiDurumuProvider.overrideWithValue(durum),
    ]);
    addTearDown(container.dispose);
    if (hedef > 0) {
      await container.read(kapsamHedefiProvider('').notifier).set(hedef);
    }
    await container.read(kapsamHedefTarihiProvider('').notifier).set(gun);
    final state = await container.read(portfolioProvider.future);
    if (seri) {
      // Gün içi seri tohumlanır: kartta gerçek bir günlük tutar var.
      final gun = dayKey(_simdi);
      int ms(int saat) =>
          gun.add(Duration(hours: saat)).millisecondsSinceEpoch;
      final k = positionKey(state.assets.first);
      IntradaySeriesCache.instance.seedForTest(
        series: {ms(10): 31000, ms(15): 31240},
        fetchedAt: DateTime.now(),
        seansGunu: gun,
        kume: state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList(),
        byPosition: {
          k: {ms(10): 31000.0, ms(15): 31240.0}
        },
        positionType: {k: AssetType.hisse},
      );
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: BugunKarti(state: state)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    return container;
  }

  testWidgets('veri yok: başlıkta "Canlı" yok, dipnot yok, bağlantı durur',
      (tester) async {
    // Gün içi motoru da test anına: duvar saatinde seans/seri tutmaz.
    HistoryService.gunIciSaat = () => _simdi;
    await kur(tester);
    expect(find.text('Bugünün verisi henüz gelmedi'), findsOneWidget);
    expect(siganIceren('Canlı'), findsNothing);
    expect(find.text('Canlı'), findsNothing);
    expect(find.text('sadece fiyat etkisi'), findsNothing);
    expect(siganIceren("Performans'ta aç"), findsOneWidget);
  });

  testWidgets('tutar varken dipnot görünür', (tester) async {
    BugunYukleyici.reelTest = null;
    await kur(tester, seri: true);
    expect(find.text('sadece fiyat etkisi'), findsOneWidget);
    expect(siganIceren("Performans'ta aç"), findsOneWidget);
  });

  group('kilitli hedef günü', () {
    final gun = DateTime(2027, 12, 1);

    testWidgets('kilitli + kayıtlı gün: ek görünür', (tester) async {
      await kur(tester,
          durum: OzellikDurumu.kilitli, gun: gun, hedef: 100000);
      expect(tester.takeException(), isNull);
      expect(siganIceren('Hedef günün kayıtlı'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('kilitli + gün yok: ek yok', (tester) async {
      await kur(tester, durum: OzellikDurumu.kilitli, hedef: 100000);
      expect(siganIceren('Hedef günün kayıtlı'), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    });

    testWidgets('Premium + kayıtlı gün: ek yok, gün yazılır', (tester) async {
      await kur(tester, gun: gun, hedef: 100000);
      expect(siganIceren('Hedef günün kayıtlı'), findsNothing);
      expect(siganIceren('2027'), findsWidgets);
    });
  });
}
