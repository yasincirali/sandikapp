import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/varlik_guncelle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy kartının kaydırma eylemleri — Sil, Güncelle, Taşı birlikte.
///
/// yasin 2026-10-10: "varlığı sil feature'ı bozulmuş olabilir mi, derin
/// test et; ana feature'larda hata olmamalı". #159 kaydırma paneline
/// Güncelle'yi ekledi; bu dosya GERÇEK `PortfolioScreen` üstünde kartı
/// kaydırıp düğmeye basar ve sağlayıcıya ne gittiğini doğrular. Sağlayıcı
/// sahtedir (Supabase'siz); sunucu yolu `integration_test/smoke_test.dart`.
const _uid = 'u1';

Asset _lot(String id, String ticker, String ad, double adet, double fiyat,
        {AssetKind kind = AssetKind.buy}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      sellPrice: kind == AssetKind.sell ? fiyat : null,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      kind: kind,
      addedDate: DateTime(2025, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  List<String>? silinen;

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [
        _lot('t1', 'THYAO.IS', 'Türk Hava Yolları', 400, 300),
        _lot('t2', 'THYAO.IS', 'Türk Hava Yolları', 100, 320),
        _lot('t3', 'THYAO.IS', 'Türk Hava Yolları', 50, 330,
            kind: AssetKind.sell),
        _lot('a1', 'ASELS.IS', 'Aselsan', 600, 140),
      ], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);

  @override
  Future<SilinenPozisyon?> deletePositionLots(List<Asset> lots) async {
    silinen = [for (final l in lots) l.id];
    final ids = silinen!.toSet();
    final s = state.valueOrNull!;
    state = AsyncData(s.copyWith(
        assets: [for (final a in s.assets) if (!ids.contains(a.id)) a]));
    return SilinenPozisyon(lotIds: silinen!, logId: null);
  }
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

class _Portfoyler extends PortfoylerNotifier {
  _Portfoyler(this.liste);
  final List<Portfoy> liste;
  @override
  Future<List<Portfoy>> build() async => liste;
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
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<_Portfoy> ac(
    WidgetTester t, {
    bool guncelle = true,
    bool cokluPortfoy = false,
    List<Portfoy> portfoyler = const [],
  }) async {
    t.view.physicalSize = const Size(390 * 3, 1000 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    final p = _Portfoy();
    await t.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => p),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        watchlistProvider.overrideWith(_Takip.new),
        varlikGuncellemeProvider.overrideWithValue(guncelle
            ? VarlikGuncellemeDurumu.acik
            : VarlikGuncellemeDurumu.gizli),
        cokluPortfoyGorunurProvider.overrideWithValue(cokluPortfoy),
        portfoylerProvider.overrideWith(() => _Portfoyler(portfoyler)),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
    ));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return p;
  }

  Future<void> kaydir(WidgetTester t, String metin) async {
    await t.drag(find.textContaining(metin).first, const Offset(-340, 0));
    await t.pumpAndSettle();
  }

  for (final guncelle in [false, true]) {
    testWidgets(
        'Sil: pozisyonun TÜM lotları gider, satır kalkar '
        '(Güncelle ${guncelle ? 'açık' : 'kapalı'})', (t) async {
      final p = await ac(t, guncelle: guncelle);
      expect(find.textContaining('THYAO'), findsWidgets);
      await kaydir(t, 'THYAO');
      expect(find.text('Sil'), findsOneWidget);
      expect(find.text('Güncelle'), guncelle ? findsOneWidget : findsNothing);

      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      expect(find.text('Yine de sil'), findsOneWidget,
          reason: 'Silme onay ister');
      await t.tap(find.text('Yine de sil'));
      await t.pumpAndSettle();

      expect(p.silinen, unorderedEquals(['t1', 't2', 't3']),
          reason: 'Satış dahil bütün lotlar; ASELS dokunulmaz');
      expect(find.textContaining('THYAO'), findsNothing);
      expect(find.textContaining('ASELS'), findsWidgets);
    });
  }

  testWidgets('Sil onayında İptal: hiçbir şey silinmez', (t) async {
    final p = await ac(t);
    await kaydir(t, 'THYAO');
    await t.tap(find.text('Sil'));
    await t.pumpAndSettle();
    await t.tap(find.text('İptal'));
    await t.pumpAndSettle();
    expect(p.silinen, isNull);
    expect(find.textContaining('THYAO'), findsWidgets);
  });

  testWidgets('Güncelle: form pozisyonun net miktarıyla açılır', (t) async {
    await ac(t);
    await kaydir(t, 'THYAO');
    await t.tap(find.text('Güncelle'));
    await t.pumpAndSettle();
    expect(find.text('Varlığı güncelle'), findsOneWidget);
    expect(find.textContaining('3 hareketi'), findsOneWidget);
    expect(find.widgetWithText(TextField, '450'), findsOneWidget,
        reason: '400 + 100 − 50');
  });

  group('Taşı', () {
    testWidgets('ikinci portföy yokken görünmez', (t) async {
      await ac(t, cokluPortfoy: true);
      await kaydir(t, 'THYAO');
      expect(find.text('Taşı'), findsNothing);
      expect(find.text('Sil'), findsOneWidget);
    });
    testWidgets('adlandırılmış portföy varken görünür', (t) async {
      await ac(t, cokluPortfoy: true, portfoyler: const [
        Portfoy(id: 'p1', userId: _uid, ad: 'Emeklilik'),
      ]);
      await kaydir(t, 'THYAO');
      expect(find.text('Taşı'), findsOneWidget);
    });
    testWidgets('çoklu portföy kapalıyken görünmez', (t) async {
      await ac(t, portfoyler: const [
        Portfoy(id: 'p1', userId: _uid, ad: 'Emeklilik'),
      ]);
      await kaydir(t, 'THYAO');
      expect(find.text('Taşı'), findsNothing);
    });
  });

  test('tasinacakPortfoyVar', () {
    expect(tasinacakPortfoyVar(null), isFalse);
    expect(tasinacakPortfoyVar(const []), isFalse);
    expect(
        tasinacakPortfoyVar(const [Portfoy(id: 'p', userId: _uid, ad: 'X')]),
        isTrue);
  });
}
