import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_siralama.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/en_cok_oynayan.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/sparkline_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Portföy "Toplam | Bugün" (Ar-Ge 1 Kas 16:45 #1, yasin "yap").
///
/// Kilitlenenler:
/// 1. Bugün değişimi Ana sayfa "en çok oynayan" ile AYNI kuraldan
///    (`pozisyonGunDegisimleri`), sıfır da döner, bugün işlem gören satır
///    sayı değil "işlem var" alır, serisi olmayan satır haritada yoktur.
/// 2. Segment yalnız Ben görünümünde; Bugün'e geçmek SIRAYI değiştirmez.
/// 3. "Bugünkü hareket" ayrı sıralama seçeneği, kodu kararlı.
/// 4. Sparkline ön yüklemesi ilk 5 kartla sınırlı.
const _uid = 'user-1';
final _gun = DateTime(2026, 10, 30);
int _ms(int saat) => DateTime(2026, 10, 30, saat).millisecondsSinceEpoch;

Asset _lot(String id, String ticker, double adet, double fiyat,
        {DateTime? alis}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: alis ?? DateTime(2026, 3, 14),
    );

PortfolioHistoryBreakdown _bd(Map<String, Map<int, double>> byPosition) =>
    PortfolioHistoryBreakdown(
      total: const {},
      byType: const {},
      byPosition: byPosition,
      positionType: {for (final k in byPosition.keys) k: AssetType.hisse},
      seansGunu: _gun,
    );

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
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

void main() {
  final thy = _lot('a', 'THYAO', 10, 300); // 3.000 ₺, en büyük değer
  final asl = _lot('b', 'ASELS', 10, 100); // 1.000 ₺
  final kThy = positionKey(thy);
  final kAsl = positionKey(asl);

  group('pozisyonGunDegisimleri', () {
    test('değişim, sıfır ve eksik seri', () {
      final m = pozisyonGunDegisimleri(
        _bd({
          kThy: {_ms(10): 1000, _ms(15): 1020}, // +%2
          kAsl: {_ms(10): 500, _ms(15): 500}, // düz
        }),
        lotlar: [thy, asl, _lot('c', 'GARAN', 1, 10)],
        now: DateTime(2026, 11, 1, 12),
      );
      expect(m[kThy]!.degisimPct, closeTo(2, 1e-9));
      expect(m[kThy]!.degisimTRY, closeTo(20, 1e-9));
      // Ana sayfa kutusu sıfırı eler; Portföy kartı "Değişim yok" yazar.
      expect(m[kAsl]!.duz, isTrue);
      // Serisi olmayan satıra sayı uydurulmaz.
      expect(m.containsKey(positionKey(_lot('c', 'GARAN', 1, 10))), isFalse);
    });

    test('bugün işlem gören pozisyon yüzde değil "işlem var" alır', () {
      final bugunAlis = _lot('d', 'ASELS', 10, 100,
          alis: DateTime(2026, 10, 30, 11));
      final m = pozisyonGunDegisimleri(
        _bd({
          kAsl: {_ms(10): 1000, _ms(15): 2000}, // miktar zıpladı
        }),
        lotlar: [asl, bugunAlis],
        now: DateTime(2026, 10, 30, 16),
      );
      expect(m[kAsl]!.islemVar, isTrue);
      expect(m[kAsl]!.duz, isFalse);
    });

    test('Ana sayfa "en çok oynayan" ile aynı yüzde', () {
      final bd = _bd({
        kThy: {_ms(10): 1000, _ms(15): 1032},
        kAsl: {_ms(10): 2000, _ms(15): 1900},
      });
      final now = DateTime(2026, 10, 30, 16);
      final m = pozisyonGunDegisimleri(bd, lotlar: [thy, asl], now: now);
      for (final o in enCokOynayanlar(bd, lotlar: [thy, asl], now: now)) {
        expect(m[o.positionKey]!.degisimPct, closeTo(o.degisimPct, 1e-9));
      }
    });
  });

  test('"Bugünkü hareket" kendi kararlı kodunu taşır', () {
    expect(PortfoySiralama.kodla('bugun_hareket'),
        PortfoySiralama.todayMoveDesc);
    // Mod seçimi sıralamayı kendiliğinden değiştirmez.
    expect(PortfoySiralama.varsayilan, PortfoySiralama.valueDesc);
  });

  test('sparkline ön yüklemesi ilk 5 kartla sınırlı', () {
    final k = ekranKaynagiSync('lib/services/sparkline_service.dart');
    expect(k, contains('int max = 5'));
  });

  group('ekran', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(IntradaySeriesCache.instance.clear);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final durum = PortfolioState(
          assets: [thy, asl], usdTry: 42, eurTry: 46, gbpTry: 54);
      IntradaySeriesCache.instance.seedForTest(
        series: {_ms(10): 3500, _ms(15): 3530},
        fetchedAt: DateTime.now(),
        seansGunu: _gun,
        kume: durum.activeAssets.where(FiyatKaynagi.seriyeGirer).toList(),
        byPosition: {
          kThy: {_ms(10): 3000, _ms(15): 3000}, // düz
          kAsl: {_ms(10): 1000, _ms(15): 1030}, // +%3
        },
        positionType: {kThy: AssetType.hisse, kAsl: AssetType.hisse},
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio([thy, asl])),
          partnersProvider.overrideWith(_FakePartners.new),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const PortfolioScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    double y(WidgetTester tester, String metin) =>
        tester.getTopLeft(find.text(metin).first).dy;

    testWidgets('Bugün: kart günün hareketini yazar, sıra değişmez',
        (tester) async {
      await pump(tester);
      expect(find.text('Toplam'), findsOneWidget);
      expect(find.text('Bugün'), findsWidgets);
      final once = y(tester, 'THYAO') < y(tester, 'ASELS');
      expect(once, isTrue); // değere göre: THYAO önde

      await tester.tap(find.text('Bugün').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('+%3'), findsOneWidget);
      expect(find.text('Değişim yok'), findsOneWidget);
      // Sıra kullanıcının seçimi: mod geçişi satırları yer değiştirmez.
      expect(y(tester, 'THYAO') < y(tester, 'ASELS'), isTrue);
      await tester.pumpWidget(const SizedBox());
      SparklineService.instance.clear();
    });
  });
}
