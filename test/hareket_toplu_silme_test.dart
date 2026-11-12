import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/widgets/sandik_coklu_secim.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hareketler: uzun bas → çoklu seçim → toplu sil → "Geri al" (2026-11-12).
const _uid = 'user-1';

Asset _lot(String id, String ticker, DateTime t,
        {String userId = _uid,
        AssetKind kind = AssetKind.buy,
        DateTime? deletedAt}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: t,
      kind: kind,
      deletedAt: deletedAt,
    );

final _defter = [
  _lot('a1', 'THYAO', DateTime(2026, 3, 20, 12)),
  _lot('a2', 'ASELS', DateTime(2026, 3, 19, 12)),
  _lot('a3', 'THYAO', DateTime(2026, 3, 18, 12)),
  // Ortağın kaydı (silme yetkisi yok).
  _lot('o1', 'KCHOL', DateTime(2026, 3, 17, 12), userId: 'ortak-1'),
  // Silinmiş kayıt + mezar taşı: yalnız "Silinenler"de görünür.
  _lot('s1', 'EREGL', DateTime(2026, 3, 10, 12),
      deletedAt: DateTime(2026, 3, 11, 12)),
  _lot('m1', 'SISE', DateTime(2026, 3, 9, 12), kind: AssetKind.deleteLog),
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

/// Sahte servis: toplu silme/geri alma çağrılarını kaydeder, state'i
/// tekil silme gibi günceller (damga).
class _FakePortfolio extends PortfolioNotifier {
  static List<List<String>> silinen = [];
  static List<List<String>> geriAlinan = [];
  static Object? hata;

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);

  @override
  Future<List<SilinenPozisyon>> hareketleriSil(List<Asset> hareketler) async {
    if (hata case final h?) throw h;
    final ids = [for (final a in hareketler) a.id];
    silinen.add(ids);
    final cur = state.valueOrNull!;
    state = AsyncData(cur.copyWith(assets: [
      for (final a in cur.assets)
        if (ids.contains(a.id)) a.copyWithDeletedAt(DateTime(2026, 4)) else a,
    ]));
    return [SilinenPozisyon(lotIds: ids, logId: null)];
  }

  @override
  Future<void> hareketleriGeriAl(List<SilinenPozisyon> makbuzlar) async {
    final ids = [for (final m in makbuzlar) ...m.lotIds];
    geriAlinan.add(ids);
    final cur = state.valueOrNull!;
    state = AsyncData(cur.copyWith(assets: [
      for (final a in cur.assets)
        if (ids.contains(a.id)) a.copyWithDeletedAt(null) else a,
    ]));
  }
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _kur(WidgetTester tester, {double yazi = 1}) async {
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
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(yazi)),
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

Finder _satir(String ticker) => find.ancestor(
    of: find.text(ticker).first, matching: find.byType(GestureDetector)).first;

Future<void> _uzunBas(WidgetTester tester, String ticker) async {
  await tester.longPress(find.text(ticker).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('tr');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() {
    _FakePortfolio.silinen = [];
    _FakePortfolio.geriAlinan = [];
    _FakePortfolio.hata = null;
  });

  group('hareketSecilebilir (tekil silme kuralı)', () {
    test('kendi kaydı seçilir; ortağın, silinmiş, mezar taşı seçilmez', () {
      final byId = {for (final a in _defter) a.id: a};
      expect(hareketSecilebilir(byId['a1']!, benimId: _uid), isTrue);
      expect(hareketSecilebilir(byId['o1']!, benimId: _uid), isFalse);
      expect(hareketSecilebilir(byId['s1']!, benimId: _uid), isFalse);
      expect(hareketSecilebilir(byId['m1']!, benimId: _uid), isFalse);
      expect(hareketSecilebilir(byId['a1']!, benimId: null), isFalse);
    });
  });

  group('hareketleriVarligaBol', () {
    test('varlık başına gruplar, mezar taşı ve silinmişi atar', () {
      final g = hareketleriVarligaBol(_defter);
      final idler = [for (final x in g) x.map((a) => a.id).toList()];
      expect(idler, [
        ['a1', 'a3'],
        ['a2'],
        ['o1'],
      ]);
    });
  });

  group('PortfolioNotifier.hareketleriSil', () {
    test('her varlık deletePositionLots yolundan; düşerse öncekiler geri',
        () async {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(_YolNotifier.new),
      ]);
      addTearDown(c.dispose);
      await c.read(portfolioProvider.future);
      final n = c.read(portfolioProvider.notifier) as _YolNotifier;
      final m = await n.hareketleriSil(_defter.take(3).toList());
      expect(n.silinenGruplar, [
        ['a1', 'a3'],
        ['a2'],
      ]);
      expect(m, hasLength(2));
      await n.hareketleriGeriAl(m);
      expect(n.geriAlinan, [
        ['a1', 'a3'],
        ['a2'],
      ]);

      n
        ..silinenGruplar.clear()
        ..geriAlinan.clear()
        ..dusecek = 'a2';
      await expectLater(
          n.hareketleriSil(_defter.take(3).toList()), throwsStateError);
      expect(n.geriAlinan, [
        ['a1', 'a3'],
      ], reason: 'yarım kalan silme geri alınmalı');
    });
  });

  testWidgets('uzun bas seçim kipini açar, satır seçili; Vazgeç kapatır',
      (tester) async {
    await _kur(tester);
    expect(find.byType(SandikSecimCubugu), findsNothing);
    await _uzunBas(tester, 'ASELS');
    expect(find.byType(SandikSecimCubugu), findsOneWidget);
    expect(find.text('1 seçili'), findsOneWidget);
    expect(find.byType(SandikSecimIsareti), findsNWidgets(3),
        reason: 'yalnız kendi 3 kaydında işaret; ortağınkinde yok');
    // Dokunma seçimi değiştirir.
    await tester.tap(find.text('THYAO').first);
    await tester.pumpAndSettle();
    expect(find.text('2 seçili'), findsOneWidget);
    await tester.tap(find.text('THYAO').first);
    await tester.pumpAndSettle();
    expect(find.text('1 seçili'), findsOneWidget);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.byType(SandikSecimCubugu), findsNothing);
  });

  testWidgets('geri tuşu sayfayı değil seçim kipini kapatır', (tester) async {
    await _kur(tester);
    await _uzunBas(tester, 'ASELS');
    final pop = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(pop, isTrue);
    expect(find.byType(SandikSecimCubugu), findsNothing);
    expect(find.byType(AllTransactionsScreen), findsOneWidget);
  });

  testWidgets('ortağın satırı uzun basmayla da dokunmayla da seçilmez',
      (tester) async {
    await _kur(tester);
    await _uzunBas(tester, 'KCHOL');
    expect(find.byType(SandikSecimCubugu), findsNothing);
    await _uzunBas(tester, 'ASELS');
    await tester.tap(find.text('KCHOL'));
    await tester.pumpAndSettle();
    expect(find.text('1 seçili'), findsOneWidget);
  });

  testWidgets('Silinenler görünümünde (mezar taşı, silinmiş) seçim yok',
      (tester) async {
    await _kur(tester);
    await tester.tap(find.textContaining('Silinenler').first);
    await tester.pumpAndSettle();
    expect(find.text('EREGL'), findsOneWidget);
    await _uzunBas(tester, 'EREGL');
    expect(find.byType(SandikSecimCubugu), findsNothing);
    await _uzunBas(tester, 'SISE');
    expect(find.byType(SandikSecimCubugu), findsNothing);
  });

  testWidgets('Sil onaysız siler, snack "N işlem silindi", Geri al geri çevirir',
      (tester) async {
    await _kur(tester);
    await _uzunBas(tester, 'ASELS');
    await tester.tap(find.text('THYAO').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pump();
    await tester.pump();
    expect(_FakePortfolio.silinen, hasLength(1));
    expect(_FakePortfolio.silinen.single.toSet(), {'a1', 'a2'});
    expect(find.byType(AlertDialog), findsNothing, reason: 'onay sorusu yok');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 işlem silindi'), findsOneWidget);
    expect(find.byType(SandikSecimCubugu), findsNothing);
    expect(find.text('ASELS'), findsNothing, reason: 'liste tazelendi');

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(_FakePortfolio.geriAlinan.single.toSet(), {'a1', 'a2'});
    expect(find.text('ASELS'), findsOneWidget);
  });

  testWidgets('silme hatası friendlyError ile gösterilir, kip açık kalır',
      (tester) async {
    _FakePortfolio.hata = StateError('ham sunucu metni');
    await _kur(tester);
    await _uzunBas(tester, 'ASELS');
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ham sunucu metni'), findsNothing);
    expect(find.byType(SandikSecimCubugu), findsOneWidget);
  });

  testWidgets('Semantics: seçili durum ekran okuyucuya söylenir',
      (tester) async {
    final h = tester.ensureSemantics();
    await _kur(tester);
    await _uzunBas(tester, 'ASELS');
    final secili = tester.getSemantics(find.ancestor(
        of: find.byType(SandikSecimIsareti).at(1),
        matching: find.byType(Semantics)).first);
    expect(secili.flagsCollection.isSelected, Tristate.isTrue);
    final secilmemis = tester.getSemantics(find.ancestor(
        of: find.byType(SandikSecimIsareti).at(0),
        matching: find.byType(Semantics)).first);
    expect(secilmemis.flagsCollection.isSelected, Tristate.isFalse);
    h.dispose();
  });

  testWidgets('44 pt: seçim satırları ve çubuk düğmeleri', (tester) async {
    await _kur(tester);
    await _uzunBas(tester, 'ASELS');
    for (final f in [find.text('Sil'), find.text('Vazgeç')]) {
      final kutu = tester.getSize(
          find.ancestor(of: f, matching: find.byType(TextButton)).first);
      expect(kutu.height, greaterThanOrEqualTo(44));
    }
    final satir = tester.getSize(_satir('ASELS'));
    expect(satir.height, greaterThanOrEqualTo(44));
  });

  testWidgets('yazı ×2: seçim kipi taşmaz', (tester) async {
    await _kur(tester, yazi: 2);
    await _uzunBas(tester, 'ASELS');
    expect(tester.takeException(), isNull);
    expect(find.byType(SandikSecimCubugu), findsOneWidget);
  });
}

/// [PortfolioNotifier.hareketleriSil]'in kendi gövdesini koşar; alttaki
/// tekil yol (deletePositionLots/restorePositionLots) sahte.
class _YolNotifier extends PortfolioNotifier {
  final silinenGruplar = <List<String>>[];
  final geriAlinan = <List<String>>[];
  String? dusecek;

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);

  @override
  Future<SilinenPozisyon?> deletePositionLots(List<Asset> lots) async {
    final ids = [for (final a in lots) a.id];
    if (dusecek != null && ids.contains(dusecek)) throw StateError('düştü');
    silinenGruplar.add(ids);
    return SilinenPozisyon(lotIds: ids, logId: null);
  }

  @override
  Future<void> restorePositionLots(SilinenPozisyon kayit) async =>
      geriAlinan.add(kayit.lotIds);
}
