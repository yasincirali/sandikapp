import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Grafik → Özet geçişi ve Özet'teki dönem dokunuşu iskelete DÜŞMEZ
/// (kullanıcı bildirimi 2026-10-02: "Performansta grafikten özete geçerken
/// ekran flick oluyor; Özet'teyken diğer filtrelere de tıklayınca titreme
/// oluyor").
///
/// Eskiden her geçişte `_OzetSerisi` yeni State ile `_seri == null`
/// başlıyor ve en az bir kare iskelet çiziyordu; seri önbellekten gelse
/// bile `await` kareyi kaçırıyordu. Bu test geçişin İLK karesine bakar —
/// kullanıcının "anlık görüntü gelip gidiyor" dediği an.
///
/// Ağ yok: `HistoryService.seriCekici` sentetik günlük seri döndürür.
const _uid = 'user-1';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2025, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          Asset(
            id: 'lot-1',
            userId: _uid,
            name: 'THYAO',
            ticker: 'THYAO.IS',
            type: AssetType.hisse,
            quantity: 10,
            purchasePrice: 90,
            currency: 'TRY',
            notes: '',
            isManualPrice: false,
            currentPrice: 150,
            addedDate: DateTime.now().subtract(const Duration(days: 800)),
          ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
        ownerId: _uid,
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

/// Son ~6 yılın günlük kapanışları, yavaş yükselen fiyat.
Future<List<(int, double)>> _sentetikSeri(
    String sym, String range, String? interval) async {
  final bugun = DateTime.now();
  return [
    for (var g = 2200; g >= 0; g--)
      (
        DateTime(bugun.year, bugun.month, bugun.day - g, 12)
            .millisecondsSinceEpoch,
        100 + (2200 - g) * 0.02,
      ),
  ];
}

bool _iskeletVar() => find.byType(SandikSkeleton).evaluate().isNotEmpty;

/// Kare sonrası ısıtma + sahte seri (mikro görevler) yerleşsin.
Future<void> _yerles(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  setUp(() => HistoryService.seriCekici = _sentetikSeri);
  tearDown(
      () => HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  testWidgets(
      'Grafik → Özet ve Özet içinde dönem dokunuşu: ilk karede iskelet yok',
      (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(_FakePortfolio.new),
          partnersProvider.overrideWith(_FakePartners.new),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(
          home: PortfolioPerformanceScreen(
            initialPeriodIdx: SummaryPeriod.birAy.index,
          ),
        ),
      ),
    );
    await _yerles(tester);

    // ── Grafik → Özet ──────────────────────────────────────────────────
    await tester.tap(find.text('Özet'));
    await tester.pump(); // geçişin İLK karesi
    expect(_iskeletVar(), isFalse,
        reason: 'Grafik sekmesi görünür dönemi ısıttı; Özet ilk karede '
            'tam çizilmeli, iskelet karesi titremenin kendisi');
    expect(find.text('Nereden geldi'), findsOneWidget,
        reason: 'ön koşul: Özet gövdesi çizildi');

    // Özet açıkken öteki dönemler arkada ısınır.
    await _yerles(tester);

    // ── Özet içinde dönem dokunuşu ─────────────────────────────────────
    for (final etiket in ['3A', '1Y', '1H', '1A']) {
      await tester.tap(find.text(etiket).first);
      await tester.pump();
      expect(_iskeletVar(), isFalse,
          reason: '$etiket dokunuşunun ilk karesi iskelet olmamalı');
      expect(find.text('Nereden geldi'), findsOneWidget, reason: etiket);
    }

    // Grafik'e dönüp yine Özet'e gelince de aynı.
    await tester.tap(find.text('Grafik'));
    await tester.pump();
    await tester.tap(find.text('Özet'));
    await tester.pump();
    expect(_iskeletVar(), isFalse);
    expect(tester.takeException(), isNull);

    // Ağaç kapanırken bekleyen iş kalmasın.
    await tester.pumpWidget(const SizedBox());
    await _yerles(tester);
  });
}
