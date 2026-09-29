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

/// Portföy hareketleri filtre düzeni — seçenek C (kullanıcı kararı
/// 2026-09-29): [Filtrele] dönem + tür sayfasını açar, hemen yanındaki
/// [Silinenler] sayfaya girmeden tek dokunuşla silinenleri getirir, etkin
/// filtreler aynı satırda × ile kaldırılır. İşlevler değişmedi; bu test
/// yeni yerleşimin aynı işlevlere ulaştırdığını sabitler.
const _uid = 'user-1';

Asset _lot(
  String id,
  AssetType type,
  DateTime added, {
  DateTime? silindi,
  String name = 'Varlık',
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: name,
      ticker: id.toUpperCase(),
      type: type,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: added,
      deletedAt: silindi,
    );

final _simdi = DateTime.now();
final _defter = [
  _lot('thyao', AssetType.hisse, _simdi.subtract(const Duration(days: 2)),
      name: 'Türk Hava Yolları'),
  _lot('asels', AssetType.hisse, _simdi.subtract(const Duration(days: 40)),
      name: 'Aselsan'),
  _lot('aft', AssetType.fon, _simdi.subtract(const Duration(days: 5)),
      name: 'Ak Portföy Teknoloji'),
  _lot('gram', AssetType.altin, _simdi.subtract(const Duration(days: 200)),
      name: 'Gram Altın'),
  _lot('sise', AssetType.hisse, _simdi.subtract(const Duration(days: 60)),
      name: 'Şişecam',
      silindi: _simdi.subtract(const Duration(days: 10))),
];

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

Future<void> _pump(WidgetTester tester,
    {double genislik = 390, double olcek = 1}) async {
  tester.view.physicalSize = Size(genislik * 3, 844 * 3);
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
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

  testWidgets('tek filtre satırı: Filtrele + Silinenler; çip satırları yok',
      (tester) async {
    await _pump(tester);
    expect(find.text('Filtrele'), findsOneWidget);
    expect(find.text('Silinenler · 1'), findsOneWidget);
    // Dönem/tür çipleri artık sayfada, ekranda değil.
    expect(find.text('Son 7 gün'), findsNothing);
    expect(find.text('Kripto'), findsNothing);
    expect(find.text('4 kayıt'), findsOneWidget);
  });

  testWidgets('Silinenler çipi sayfa açmadan silinenleri getirir',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Silinenler · 1'));
    await tester.pumpAndSettle();
    expect(find.text('DÖNEM'), findsNothing, reason: 'sayfa açılmamalı');
    expect(find.text('1 kayıt'), findsOneWidget);
    expect(find.textContaining('Silinme:'), findsOneWidget);

    await tester.tap(find.text('Silinenler · 1'));
    await tester.pumpAndSettle();
    expect(find.text('4 kayıt'), findsOneWidget, reason: 'tekrar dokununca kapanır');
  });

  testWidgets('sayfa: canlı sayı listeyle aynı, etkin çip × ile kalkar',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Filtrele'));
    await tester.pumpAndSettle();
    expect(find.text('DÖNEM'), findsOneWidget);
    expect(find.text('TÜR'), findsOneWidget);
    expect(find.text('4 kaydı göster'), findsOneWidget);

    // Taslak: seçim listeye uygulanmaz, yalnızca düğmedeki sayıyı değiştirir.
    await tester.tap(find.text('Hisse'));
    await tester.pumpAndSettle();
    expect(find.text('2 kaydı göster'), findsOneWidget);
    await tester.tap(find.text('Son 7 gün'));
    await tester.pumpAndSettle();
    expect(find.text('1 kaydı göster'), findsOneWidget);

    await tester.tap(find.text('1 kaydı göster'));
    await tester.pumpAndSettle();
    expect(find.text('DÖNEM'), findsNothing, reason: 'sayfa kapandı');
    expect(find.text('1 kayıt'), findsOneWidget);
    // Etkin filtreler satırda; rozet 2.
    expect(find.text('Son 7 gün'), findsOneWidget);
    expect(find.text('Hisse'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Son 7 gün'));
    await tester.pumpAndSettle();
    expect(find.text('Son 7 gün'), findsNothing);
    expect(find.text('2 kayıt'), findsOneWidget, reason: 'yalnız tür kaldı');

    await tester.tap(find.text('Filtreleri temizle'));
    await tester.pumpAndSettle();
    expect(find.text('4 kayıt'), findsOneWidget);
  });

  testWidgets('eşleşme yoksa göster düğmesi pasif', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Filtrele'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kripto'));
    await tester.pumpAndSettle();
    expect(find.text('Eşleşen kayıt yok'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
    // Sıfırla taslağı geri alır.
    await tester.tap(find.text('Sıfırla'));
    await tester.pumpAndSettle();
    expect(find.text('4 kaydı göster'), findsOneWidget);
  });

  for (final (w, o) in [(320.0, 1.0), (320.0, 1.6)]) {
    testWidgets('taşma: ${w.toInt()}pt × $o, sayfa açık', (tester) async {
      await _pump(tester, genislik: w, olcek: o);
      await tester.tap(find.text('Filtrele'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
