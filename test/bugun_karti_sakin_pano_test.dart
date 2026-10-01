import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// "Sakin pano" düzeni (2026-10-01, kullanıcı seçimi D) — kartın yeni
/// katmanları gerçek ağaçta kurulur ve dar ekranda taşmaz.
///
/// Emülatör Flutter'ı render edemiyor (CLAUDE.md); yerleşim hatası ancak
/// burada görünür: `IntrinsicHeight` içindeki `Spacer`, iki sütunlu ızgara,
/// 320pt'te başlık satırı. Veri kaynakları testte ağa çıkamaz, bu yüzden
/// kart "gün içi veri geliyor" + artıdaki varlık + hedef hâliyle çizilir;
/// enflasyon çubuğu kaynak sözleşmesiyle denetlenir.

Asset _asset(String ticker, double qty, double alis, double simdi) => Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: simdi,
      addedDate: DateTime(2026, 3, 14),
    );

final _defter = [
  _asset('THYAO', 100, 300, 312.40),
  _asset('ASELS', 10, 1100, 1000),
];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
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
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
  });

  Future<void> kur(WidgetTester tester, {required double genislik}) async {
    tester.view.physicalSize = Size(genislik * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ]);
    addTearDown(container.dispose);
    final state = await container.read(portfolioProvider.future);
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
    // Reel/haftalık yükleyicileri ağa çıkamaz; kendi bütçeleriyle düşer.
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
  }

  for (final genislik in [390.0, 320.0]) {
    testWidgets('${genislik.toInt()}pt: katmanlar kurulur, taşma yok',
        (tester) async {
      await kur(tester, genislik: genislik);
      expect(tester.takeException(), isNull);
      // Başlık: BUGÜN + gün adı; ölçüm bloğu etiketi; eylem kutusu.
      expect(find.text('BUGÜN'), findsOneWidget);
      expect(find.textContaining('Günün hareketi'), findsOneWidget);
      expect(find.text('Hedef belirle'), findsOneWidget);
      // Bilgi kutusu: dönen yuva artıdaki varlığı (1 / 2) ya da — Çarşamba
      // sonrası havuza giren — son 7 günü seçer; hangisi geldiyse kutu var.
      final yesil = find.text('Artıdaki varlık').evaluate().isNotEmpty;
      final hafta = find.text('Son 7 gün').evaluate().isNotEmpty;
      expect(yesil || hafta, isTrue, reason: 'bilgi kutusu çizilmedi');
      if (yesil) expect(find.text('1 / 2'), findsOneWidget);
    });
  }

  testWidgets('hedef belirlenince eylem kutusu ilerlemeyi yazar',
      (tester) async {
    await kur(tester, genislik: 390);
    // ₺41.240 defter → ₺100.000 hedef: %41, kalan ₺58,8 bin.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BugunKarti)));
    await container.read(kapsamHedefiProvider('').notifier).set(100000);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Hedefe %41'), findsOneWidget);
    expect(find.text('Hedef belirle'), findsNothing);
  });

  group('kaynak sözleşmesi', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');

    test('enflasyon kutusu çubuk + TÜFE imleci taşır', () {
      expect(
          src.contains(
              '_EnflasyonCubugu(nominal: s.nominal, tufe: s.inflation)'),
          isTrue);
      expect(src.contains('todayYourReturn(fmtPct(s.nominal))'), isTrue);
      expect(src.contains('todayCpiShort(fmtPct(s.inflation))'), isTrue);
    });

    test('gün içi eğri açılış seviyesini kesik çizgiyle gösterir', () {
      expect(src.contains('final tabanY = y(seri.first);'), isTrue,
          reason:
              'Açılış seviyesi serinin ilk noktası — DailySummary ile aynı');
    });

    test('haftalık yön kelimeyle (yükseliş / düşüş), yüzde işaretsiz', () {
      expect(src.contains('l10n.todayWeekUp(yuzde)'), isTrue);
      expect(src.contains('l10n.todayWeekDown(yuzde)'), isTrue);
    });
  });
}
