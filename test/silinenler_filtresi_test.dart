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
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Silinenler" filtresi (kullanıcı bildirimi 2026-09-29: "silinenler
/// filtresi silinmiş gibi, geri gelmeli, doğru şekilde gözükmeli").
///
/// İki kök neden:
///  1. Çip yalnızca silinmiş kayıt varken çiziliyordu — silinmişi olmayan
///     hesapta (emülatördeki test hesabı) filtre hiç görünmüyordu.
///  2. Eski tip silmeler (her lot için ayrı mezar taşı, `deletedCount` 0)
///     açılınca alt alta tekrarlı "Silindi" satırları basıyordu; canlı
///     defterde bir AVOD silmesi aynı dakikada 17 taş (ölçüldü).
const _uid = 'user-1';

Asset _lot(String id, {DateTime? silindi}) => Asset(
      id: id,
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: DateTime(2026, 7, 1),
      deletedAt: silindi,
    );

/// Eski tip mezar taşı: tek lot, `refAssetId` fiziksel silinmiş lota
/// işaret eder (defterde yok), `deletedCount` 0.
Asset _eskiTas(String id, DateTime an,
        {String ticker = 'AVOD.IS', double q = 100, double p = 5}) =>
    Asset(
      id: id,
      userId: _uid,
      name: 'A.V.O.D.',
      ticker: ticker,
      type: AssetType.hisse,
      quantity: q,
      purchasePrice: p,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: an,
      kind: AssetKind.deleteLog,
      refAssetId: 'yok-$id',
    );

List<Asset> _defter = const [];

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
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pump(WidgetTester tester, List<Asset> defter) async {
  _defter = defter;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const AllTransactionsScreen(
        allPartnerAssets: {},
        partners: [],
        initialView: '',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  group('eskiMezarTaslariniBirlestir', () {
    final an = DateTime(2026, 8, 10, 14, 30, 5);

    test('aynı varlık + aynı dakika → tek satır, tutar korunur', () {
      final taslar = [
        for (var i = 0; i < 17; i++)
          _eskiTas('t$i', an.add(Duration(seconds: i)), q: 100 + i.toDouble()),
      ];
      final sonuc = eskiMezarTaslariniBirlestir(taslar);
      expect(sonuc, hasLength(1));
      final g = sonuc.single;
      expect(g.isDeleteLog, isTrue);
      expect(g.deletedCount, 17);
      final beklenen =
          taslar.fold<double>(0, (t, a) => t + a.quantity * a.purchasePrice);
      expect(g.quantity * g.purchasePrice, closeTo(beklenen, 1e-6));
    });

    test('farklı dakika ya da farklı varlık birleşmez', () {
      final sonuc = eskiMezarTaslariniBirlestir([
        _eskiTas('a', an),
        _eskiTas('b', an.add(const Duration(minutes: 2))),
        _eskiTas('c', an, ticker: 'AGHOL.IS'),
      ]);
      expect(sonuc, hasLength(3));
    });

    test('yeni tip taş ve damgalı lot dokunulmaz', () {
      final lot = _lot('l1', silindi: an);
      final sonuc = eskiMezarTaslariniBirlestir([lot, _eskiTas('a', an)]);
      expect(sonuc, containsAll([lot]));
      expect(sonuc, hasLength(2));
    });
  });

  test('fon kodu önekli de öneksiz de aynı görünür (TEFAS:IJC → IJC)', () {
    Asset fon(String t) => Asset(
          id: t,
          userId: _uid,
          name: 'Fon',
          ticker: t,
          type: AssetType.fon,
          quantity: 1,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
        );
    expect(fon('TEFAS:IJC').displayTicker, 'IJC');
    expect(fon('DLY').displayTicker, 'DLY');
    expect(fon('THYAO.IS').displayTicker, 'THYAO');
  });

  testWidgets('silinmiş kayıt yokken de çip görünür; açınca boş durum',
      (tester) async {
    await _pump(tester, [_lot('l1')]);
    expect(find.text('Silinenler'), findsOneWidget,
        reason: 'filtre silinmişi olmayan hesapta da görünmeli');
    await tester.tap(find.text('Silinenler'));
    await tester.pumpAndSettle();
    expect(find.text('Silinmiş kayıt yok'), findsOneWidget);
    expect(find.text('Eşleşen kayıt bulunamadı'), findsNothing);
  });

  testWidgets('eski tip 17 taş listede tek "Silindi · 17 kayıt" satırı',
      (tester) async {
    final an = DateTime(2026, 8, 10, 14, 30);
    await _pump(tester, [
      _lot('l1'),
      for (var i = 0; i < 17; i++)
        _eskiTas('t$i', an.add(Duration(seconds: i))),
    ]);
    expect(find.text('Silinenler · 1'), findsOneWidget);
    await tester.tap(find.text('Silinenler · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Silindi · 17 kayıt'), findsOneWidget);
    expect(find.text('Silindi'), findsNothing,
        reason: 'tek tek "Silindi" satırları kalmamalı');
  });
}
