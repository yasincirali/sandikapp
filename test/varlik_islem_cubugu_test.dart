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
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';
import 'package:portfoy_takip/widgets/pozisyon_islemleri.dart';

import 'helpers/kaynak.dart';

/// Sadeleştirme 2 (2026-10-04), varlık ekranı maddeleri (bayrak
/// `varlik_islem_cubugu` 2026-10-05'te kalktı, davranış kalıcı):
///   · madde 6: varlık ekranının altında "Al · Sat · Temettü" çubuğu;
///     kaydırmayla AYNI kod yolu ve AYNI kurallar.
///   · madde 7: dönem yüzdesi tek yerde (fiyatın altında).
///   · madde 11: hiç çizilmeyen Sil menüsü ve ortak sekmesi silindi.
/// "Bayrak kapalı = eski ekran" testleri bayrakla birlikte silindi.

const _uid = 'user-1';

Asset _varlik({
  String userId = _uid,
  AssetType type = AssetType.hisse,
  String ticker = 'THYAO.IS',
  String? subCategory,
}) =>
    Asset(
      id: 'V-1',
      userId: userId,
      name: 'Türk Hava Yolları',
      ticker: ticker,
      type: type,
      subCategory: subCategory,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.varliklar);
  final List<Asset> varliklar;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: varliklar,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

Future<void> _ac(WidgetTester tester, Asset ekran, List<Asset> defter) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(defter)),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: ekran, showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('madde 6 — işlem çubuğu', () {
    testWidgets('hissede Al · Sat · Temettü', (tester) async {
      await _ac(tester, _varlik(), [_varlik()]);
      expect(find.byType(PozisyonIslemCubugu), findsOneWidget);
      expect(find.byKey(const ValueKey('pozisyon-islemi-al')), findsOneWidget);
      expect(find.byKey(const ValueKey('pozisyon-islemi-sat')), findsOneWidget);
      expect(find.byKey(const ValueKey('pozisyon-islemi-temettu')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Al dokunuşu hızlı alış diyaloğunu açar (kaydırmayla aynı yol)',
        (tester) async {
      await _ac(tester, _varlik(), [_varlik()]);
      await tester.tap(find.byKey(const ValueKey('pozisyon-islemi-al')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Test yazı tipi (Ahem, her harf kare) diyaloğun "Mevcut" satırını
      // taşırıyor — diyalog bu turda değişmedi, gerçek fontta sığıyor
      // (`portfoy_karti_bulgulari_test` diyaloğu geniş yüzeyde açar).
      // Burada yalnız diyaloğun AÇILDIĞI sorulur.
      tester.takeException();
      // Diyalog başlığı "Al" + elde tutulan miktar satırı ("Mevcut").
      expect(find.text('Mevcut'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('temettü dağıtmayan türde Temettü yok', (tester) async {
      final altin = _varlik(
          type: AssetType.altin, ticker: 'ALTIN_GRAM', subCategory: 'Gram');
      await _ac(tester, altin, [altin]);
      expect(find.byKey(const ValueKey('pozisyon-islemi-al')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pozisyon-islemi-temettu')), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('ortağın varlığında çubuk yok (kaydırma da yok)',
        (tester) async {
      await _ac(tester, _varlik(userId: 'ortak-1'), [_varlik()]);
      expect(find.byType(PozisyonIslemCubugu), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('kapanmış/defterde olmayan pozisyonda çubuk yok',
        (tester) async {
      await _ac(tester, _varlik(), const []);
      expect(find.byType(PozisyonIslemCubugu), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    test('işlem listesi: temettü yalnız supportsDividend türlerinde', () {
      expect(pozisyonIslemleri(_varlik()), [
        PozisyonIslemi.al,
        PozisyonIslemi.sat,
        PozisyonIslemi.temettu,
      ]);
      expect(pozisyonIslemleri(_varlik(type: AssetType.doviz)),
          [PozisyonIslemi.al, PozisyonIslemi.sat]);
    });

    test('kaydırma ve çubuk AYNI fonksiyonu çağırır', () {
      final portfoy = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
      final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect('pozisyonIslemiAc('.allMatches(portfoy).length, 3,
          reason: 'Al, Sat, Temettü kaydırması ortak yoldan açılmalı');
      expect(portfoy, isNot(contains('showQuickAdjustDialog(')));
      expect(portfoy, isNot(contains('showDividendDialog(')));
      expect(portfoy, contains('pozisyonIslemleri(a)'),
          reason: 'temettü kuralı ortak listeden');
      expect(detay, contains('pozisyonIslemiAc('));
      expect(detay, contains('pozisyonIslemleri('));
    });
  });

  group('madde 7 — dönem yüzdesi tek yerde', () {
    const ist = DonemIstatistigi(
      ilk: 280,
      son: 312.4,
      yuksek: 320,
      dusuk: 270,
      enBuyukDususPct: -4.2,
      oynaklikPct: 31.0,
    );

    Future<void> izgara(WidgetTester tester,
        {required bool gizli, required int gun}) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: DonemIstatistikIzgarasi(
            ist: ist,
            gun: gun,
            donemPct: 11.57,
            bugunPct: 0.85,
            donemGetirisiGizli: gizli,
          ),
        ),
      ));
    }

    testWidgets('varsayılan: 2×2, dönem getirisi dahil (birebir eski)',
        (tester) async {
      await izgara(tester, gizli: false, gun: 30);
      expect(find.text('DÖNEM GETİRİSİ'), findsOneWidget);
      expect(find.text('BUGÜN'), findsOneWidget);
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsOneWidget);
      expect(find.text('OYNAKLIK (YILLIK)'), findsOneWidget);
    });

    testWidgets('gizli: dönem getirisi yok, diğer ölçüler kalır',
        (tester) async {
      await izgara(tester, gizli: true, gun: 30);
      expect(find.text('DÖNEM GETİRİSİ'), findsNothing);
      expect(find.text('BUGÜN'), findsOneWidget);
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsOneWidget);
      expect(find.text('OYNAKLIK (YILLIK)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gizli + GÜNLÜK: "Bugün" de dönem yüzdesidir, o da düşer',
        (tester) async {
      await izgara(tester, gizli: true, gun: 0);
      expect(find.text('DÖNEM GETİRİSİ'), findsNothing);
      expect(find.text('BUGÜN'), findsNothing);
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsOneWidget);
    });

    test('dönem satırı yüzdesiz: yalnız tutar (piyasa etkisi)', () {
      String tl(double v) => '₺${v.round()}';
      final k = kazancSatiri(
          tutar: 120, yuzde: -2.5, tutarMetni: tl, yuzdesiz: true);
      expect(k?.metin, '+₺120');
      expect(k?.yon, 1);
      // Tutar sıfırsa fiyat oynamış olsa da "Değişim yok": satırın sorusu
      // sahibin kazancı.
      expect(
          kazancSatiri(tutar: 0.2, yuzde: -7.5, tutarMetni: tl, yuzdesiz: true),
          isNull);
    });

    test('pozisyon kartı yüzdesiz, ızgara dönem getirisini gizler', () {
      final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(detay, contains('yuzdesiz: true'));
      expect(detay, contains('donemGetirisiGizli: true'));
    });
  });

  test('madde 11 — hiç çizilmeyen Sil menüsü ve ortak sekmesi yok', () {
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(detay, isNot(contains('ModernTabSelector(')));
    expect(detay, isNot(contains('PopupMenuButton')));
    expect(detay, isNot(contains('_confirmDelete')));
    expect(detay, isNot(contains('!widget.showBackButton')));
  });
}
