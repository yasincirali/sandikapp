import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tüm hareketler sonuç sayacının yanındaki "Alım ₺X · Satış ₺Y" satırı
/// (müşteri 2026-11-10).
///
/// Sabitlenenler: tutar kaydın kendi günündeki TL değeri (fiyat yeniden
/// çekilmez), TL karşılığı bilinmeyen tek kayıt satırı gizler (uydurma
/// sayı yok), sıfır parça yazılmaz, bakiye gizliyken ve Silinenler'de satır
/// yok.
const _uid = 'user-1';

Asset _a(
  String id, {
  AssetKind kind = AssetKind.buy,
  double q = 10,
  double fiyat = 100,
  double? satis,
  String currency = 'TRY',
  double kur = 1,
  double komisyon = 0,
  double temettu = 0,
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: id,
      ticker: id,
      type: AssetType.hisse,
      quantity: q,
      purchasePrice: fiyat,
      sellPrice: satis,
      currency: currency,
      purchaseFxRate: kur,
      commission: komisyon,
      dividendAmount: temettu,
      notes: '',
      isManualPrice: false,
      // Güncel fiyat alıştan farklı: toplam bugünkü fiyatla hesaplanırsa
      // test kırılır.
      currentPrice: fiyat * 3,
      addedDate: DateTime(2026, 11, 3, 10),
      kind: kind,
      deletedAt: silindi,
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
  final l = AppLocalizationsTr();
  const lira = BazPara.lira();

  group('hareketToplamlari', () {
    test('alım komisyon dahil, satış ele geçen tutar, temettü ayrı', () {
      final t = ContributionHistoryService.hareketToplamlari([
        _a('al', q: 10, fiyat: 100, komisyon: 5), // 1005
        _a('sat', kind: AssetKind.sell, q: 2, fiyat: 100, satis: 150), // 300
        _a('tem', kind: AssetKind.dividend, q: 0, temettu: 80), // 80
      ])!;
      expect(t.alim, 1005);
      expect(t.satis, 300);
      expect(t.temettu, 80);
    });

    test('dövizli kayıt kendi günündeki kurla', () {
      final t = ContributionHistoryService.hareketToplamlari([
        _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 34),
      ])!;
      expect(t.alim, 3400);
    });

    test('silinen kayıt ve mezar taşı sayılmaz', () {
      final t = ContributionHistoryService.hareketToplamlari([
        _a('al', q: 1, fiyat: 500),
        _a('sil', q: 1, fiyat: 900, silindi: DateTime(2026, 11, 4)),
        _a('tas', kind: AssetKind.deleteLog, q: 1, fiyat: 900),
      ])!;
      expect(t.alim, 500);
    });

    test('TL karşılığı bilinmeyen tek kayıt bile varsa null', () {
      expect(
        ContributionHistoryService.hareketToplamlari([
          _a('al', q: 1, fiyat: 500),
          _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 1.0),
        ]),
        isNull,
      );
      expect(
        ContributionHistoryService.hareketToplamlari([
          _a('al', q: 1, fiyat: 500),
          _a('tem',
              kind: AssetKind.dividend, q: 0, temettu: 3, currency: 'USD'),
        ]),
        isNull,
      );
    });
  });

  group('hareketToplamMetni', () {
    String? metin(({double alim, double satis, double temettu})? t,
            {bool silinenler = false, bool gizli = false}) =>
        hareketToplamMetni(l,
            toplamlar: t, silinenler: silinenler, baz: lira, gizli: gizli);

    test('sıfır parça yazılmaz, temettü yalnız varsa', () {
      expect(
          metin((alim: 1000, satis: 0, temettu: 0)), 'Alım ${lira.fmt(1000)}');
      expect(metin((alim: 1000, satis: 250, temettu: 0)),
          'Alım ${lira.fmt(1000)} · Satış ${lira.fmt(250)}');
      expect(metin((alim: 0, satis: 250, temettu: 40)),
          'Satış ${lira.fmt(250)} · Temettü ${lira.fmt(40)}');
      expect(metin((alim: 0, satis: 0, temettu: 0)), isNull);
    });

    test('bilinmeyen tutar, Silinenler ve bakiye gizli → satır yok', () {
      const t = (alim: 1000.0, satis: 0.0, temettu: 0.0);
      expect(metin(null), isNull);
      expect(metin(t, silinenler: true), isNull);
      expect(metin(t, gizli: true), isNull);
      expect(
          hareketToplamMetni(l,
              toplamlar: t,
              silinenler: false,
              baz: lira.gizlenmis(),
              gizli: false),
          isNull);
    });
  });

  group('ekran', () {
    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      DbLogger.silentInTests = true;
    });
    tearDownAll(() => DbLogger.silentInTests = false);

    testWidgets('sayacın yanında alım ve satış toplamı', (tester) async {
      await _pump(tester, [
        _a('al', q: 10, fiyat: 100),
        _a('sat', kind: AssetKind.sell, q: 2, fiyat: 100, satis: 150),
      ]);
      expect(
          find.textContaining(
              'Alım ${lira.fmt(1000)} · Satış ${lira.fmt(300)}'),
          findsOneWidget);
      expect(find.textContaining('Temettü'), findsNothing);
    });

    testWidgets('kuru bilinmeyen kayıt varken toplam yazılmaz', (tester) async {
      await _pump(tester, [
        _a('al', q: 10, fiyat: 100),
        _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 1.0),
      ]);
      expect(find.textContaining('Alım ₺'), findsNothing);
    });
  });
}
