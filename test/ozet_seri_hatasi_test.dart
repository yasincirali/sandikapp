import 'dart:async';

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
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// **Özet › 1A fiyat geçmişi gelmeyince iskelette KALMAZ** (2026-10-19).
///
/// Frankfurt duman testi (2026-10-18): fiyat sunucusuna ulaşılamayınca
/// Özet'in 1A dönemi 60 sn'den uzun iskelet gösterdi; hata ya da "Tekrar
/// dene" çıkmadı. Aynı anda Grafik sekmesi "Grafik verisi alınamadı"
/// diyordu. Kullanıcı yüklenmeyi bekliyor sanır. Kilitlenen: seri boş
/// dönünce Özet de aynı hâli gösterir, "tekrar dene" yeniden ister ve seri
/// gelince özet çizilir.
const _uid = 'user-1';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          Asset(
            id: 'a-1',
            userId: _uid,
            name: 'THYAO',
            ticker: 'THYAO.IS',
            type: AssetType.hisse,
            quantity: 10,
            purchasePrice: 90,
            currency: 'TRY',
            notes: '',
            isManualPrice: false,
            currentPrice: 120,
            addedDate: DateTime(2026, 1, 5),
          ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDown(() => PortfolioPerformanceScreen.ozetSerisiTestCekici = null);

  PortfolioHistoryBreakdown dolu() {
    final bugun = DateTime.now();
    final gun = DateTime(bugun.year, bugun.month, bugun.day);
    return PortfolioHistoryBreakdown(
      total: {
        for (var g = 30; g >= 0; g--)
          gun.subtract(Duration(days: g)).millisecondsSinceEpoch: 1100.0 + g,
      },
      byType: const {},
      byPosition: const {},
      positionType: const {},
    );
  }

  Future<void> ac(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(_FakePortfolio.new),
        ],
        child: const MaterialApp(
          home: PortfolioPerformanceScreen(
              initialOzet: true, initialPeriodIdx: 2 /* 1A */),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> bekle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  final hata = find.text('Grafik verisi alınamadı');
  final ozet = find.text('Nereden geldi');
  Finder tekrar() => find.text('Tekrar Dene');

  testWidgets('istek asılı kalırsa süre sonunda hata + tekrar dene; '
      'geç gelen seri özeti çizer', (tester) async {
    final ag = Completer<PortfolioHistoryBreakdown>();
    PortfolioPerformanceScreen.ozetSerisiTestCekici = (_, __, ___) => ag.future;
    await ac(tester);
    expect(hata, findsNothing, reason: 'önce yükleniyor');
    expect(find.byType(SandikSkeleton), findsWidgets);

    await tester.pump(const Duration(seconds: 21));
    expect(hata, findsOneWidget, reason: 'süresiz iskelet yok');
    expect(tekrar(), findsWidgets);

    ag.complete(dolu());
    await bekle(tester);
    expect(hata, findsNothing);
    expect(ozet, findsOneWidget, reason: 'geç gelen seri hatayı kaldırır');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hata verirse hata + tekrar dene; tekrar dene yeniden ister',
      (tester) async {
    var istek = 0;
    var ag = false;
    PortfolioPerformanceScreen.ozetSerisiTestCekici = (_, __, ___) async {
      istek++;
      if (!ag) throw Exception('ağ yok');
      return dolu();
    };
    await ac(tester);
    await bekle(tester);
    expect(hata, findsOneWidget);
    final once = istek;

    ag = true;
    await tester.tap(tekrar().hitTestable().first);
    await bekle(tester);
    expect(istek, greaterThan(once));
    expect(hata, findsNothing);
    expect(ozet, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('boş seri de iskelette bırakmaz', (tester) async {
    PortfolioPerformanceScreen.ozetSerisiTestCekici =
        (_, __, ___) async => const PortfolioHistoryBreakdown.empty();
    await ac(tester);
    await bekle(tester);
    expect(hata, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
