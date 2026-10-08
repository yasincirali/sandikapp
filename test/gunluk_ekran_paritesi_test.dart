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
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ana sayfa Bugün kartı ile Performans GÜNLÜK (Grafik kartının "Sadece
/// piyasa etkisi" satırı ve Özet GÜNLÜK) AYNI günlük piyasa etkisini
/// göstermeli (kullanıcı bildirimi 2026-10-02: "ana sayfa bugün kartı ve
/// performans bugün kısmındaki günlük piyasa etkisi farklı çıkıyor").
///
/// Mantığın kopyası değil, GERÇEK iki ekran yan yana kurulur: bugün
/// açılıştan sonra alım (akış), borsa açılmadan önceki hisse slotları ve
/// fiyat değişimi sonrası. Kartın tutarı Performans'ta da görünmeli.
const _uid = 'user-1';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: _uid, email: 't@e.com', displayName: 'T', createdAt: DateTime(2025));
}

final _now = DateTime.now();
List<Asset> _lots([double thy = 150]) => [
      Asset(
          id: 'lot-1', userId: _uid, name: 'THYAO', ticker: 'THYAO.IS',
          type: AssetType.hisse, quantity: 10, purchasePrice: 90,
          currency: 'TRY', notes: '', isManualPrice: false, currentPrice: thy,
          addedDate: _now.subtract(const Duration(days: 800))),
      Asset(
          id: 'lot-2', userId: _uid, name: 'USD', ticker: 'USDTRY=X',
          type: AssetType.doviz, quantity: 100, purchasePrice: 30,
          currency: 'TRY', notes: '', isManualPrice: false, currentPrice: 42,
          addedDate: _now.subtract(const Duration(days: 300))),
      Asset(
          id: 'lot-3', userId: _uid, name: 'THYAO', ticker: 'THYAO.IS',
          type: AssetType.hisse, quantity: 5, purchasePrice: 148,
          currency: 'TRY', notes: '', isManualPrice: false, currentPrice: thy,
          addedDate: _now.subtract(const Duration(hours: 2))),
    ];

class _FakePortfolio extends PortfolioNotifier {
  void fiyatDegis(double f) {
        state = AsyncData(PortfolioState(
        assets: _lots(f),
        usdTry: 42, eurTry: 46, gbpTry: 54, ownerId: _uid));
  }
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _lots(), usdTry: 42, eurTry: 46, gbpTry: 54, ownerId: _uid);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

Future<List<(int, double)>> _seri(String sym, String range, String? interval) async {
  final bas = DateTime(_now.year, _now.month, _now.day - 1);
  final out = <(int, double)>[];
  var t = bas;
  var i = 0;
  final hisseSon = DateTime(_now.year, _now.month, _now.day - 1, 18);
  while (t.isBefore(_now)) {
    if (sym.endsWith('.IS') && (t.isAfter(hisseSon) || t.hour < 10)) { t = t.add(const Duration(minutes: 5)); i++; continue; }
    out.add((t.millisecondsSinceEpoch, (sym.startsWith('USD') ? 41.5 : 145) + i * 0.001));
    t = t.add(const Duration(minutes: 5));
    i++;
  }
  return out;
}

Future<void> _yerles(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Bugün kartının tutarı (ilk "+₺…" / "−₺…" metni) ekranda en az iki
/// kez görünür: kart + Performans'taki piyasa satırı (ya da Özet GÜNLÜK).
void _ayniRakam() {
  final metinler = [
    for (final e in find.byType(Text).evaluate())
      (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText(),
  ].whereType<String>().where((t) => RegExp(r'^[+−]₺').hasMatch(t)).toList();
  expect(metinler, isNotEmpty);
  final kart = metinler.first;
  expect(metinler.where((t) => t == kart).length, greaterThanOrEqualTo(2),
      reason: 'Bugün kartı $kart; Performans: $metinler');
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  setUp(() => HistoryService.seriCekici = _seri);

  testWidgets('parite', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      child: MaterialApp(
        home: Consumer(builder: (c, ref, _) {
          final s = ref.watch(portfolioProvider).valueOrNull;
          return Column(children: [
            if (s != null) SizedBox(height: 500, child: SingleChildScrollView(child: BugunKarti(state: s))),
            const Expanded(child: PortfolioPerformanceScreen(initialPeriodIdx: 0)),
          ]);
        }),
      ),
    ));
    await _yerles(tester);
    _ayniRakam();

    final el = tester.element(find.byType(BugunKarti));
    (ProviderScope.containerOf(el).read(portfolioProvider.notifier)
            as _FakePortfolio)
        .fiyatDegis(160);
    await _yerles(tester);
    _ayniRakam();

    await tester.tap(find.text('Özet'));
    await _yerles(tester);
    _ayniRakam();
  });
}
