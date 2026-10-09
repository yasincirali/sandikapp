import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/disclaimer_widget.dart';

import 'helpers/kaynak.dart';

/// Katmanlı varlık detayı (Sadeleştirme 2, S4; bayrak
/// `varlik_detay_katmanli`). Bekçi iki yönlü:
///   · bayrak KAPALI → eski yığın birebir (yedi satır açık, analiz başlığı
///     ve "Ayrıntı" yok, sinyal kartı fiyatın altında);
///   · bayrak AÇIK → Pozisyonun özeti (üç sayı) + "Ayrıntı", Analiz satırları
///     kapalı başlar ve yerinde açılır, İleri seviyede açık başlar. Hiçbir
///     sayı kaybolmaz: yedi satır ayrıntıda, panel satırda.

const _uid = 'user-1';
const _bayrak = 'varlik_detay_katmanli';

Asset _asset() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
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
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset()],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

Future<void> _ac(WidgetTester tester,
    {YatirimciSeviyesi seviye = YatirimciSeviyesi.orta}) async {
  tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      yatirimciSeviyesiProvider.overrideWithValue(seviye),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: _asset(), showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f.first).dy;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('bayrak KAPALI: eski yığın — yedi satır açık, katman yok',
      (tester) async {
    await _ac(tester);

    expect(find.text('POZİSYONUN'), findsOneWidget);
    expect(find.text('Alış fiyatın (ortalama)'), findsOneWidget);
    expect(find.text('Ödediğin toplam'), findsOneWidget);
    expect(find.text('Ayrıntı'), findsNothing);
    expect(find.text('ANALİZ'), findsNothing);
    expect(find.text('Teknik sinyaller'), findsNothing);
    // Sinyal kartı fiyatın altında, panel en altta, ikisi de açık.
    expect(find.byType(AssetSignalCard), findsOneWidget);
    expect(find.byType(TechnicalSignalPanel), findsOneWidget);
    expect(_y(tester, find.byType(AssetSignalCard)),
        lessThan(_y(tester, find.text('POZİSYONUN'))));
    expect(find.byType(DisclaimerWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('bayrak AÇIK: özet kart + Ayrıntı, analiz kapalı başlar',
      (tester) async {
    RemoteConfigService.testAcik = {_bayrak};
    await _ac(tester);

    // Pozisyonun: üç sayı ilk bakışta; yedi satırın geri kalanı kapalı.
    expect(find.text('POZİSYONUN'), findsOneWidget);
    expect(find.text('Bugünkü değer'), findsOneWidget);
    expect(find.text('Toplam kâr/zarar'), findsOneWidget);
    expect(find.text('Miktar'), findsOneWidget);
    expect(find.textContaining('+₺6.165 · +%24,59'), findsOneWidget);
    expect(find.text('Alış fiyatın (ortalama)'), findsNothing);
    // Dönem kâr/zararı ilk bakışta tekrar etmez (fiyatın altında var).
    expect(find.textContaining('kâr/zarar'), findsOneWidget);

    // Sinyal kartı üstten kalktı; Analiz'de kapalı satır.
    expect(find.text('ANALİZ'), findsOneWidget);
    expect(find.text('Teknik sinyaller'), findsOneWidget);
    expect(find.byType(AssetSignalCard), findsNothing);
    expect(find.byType(TechnicalSignalPanel), findsNothing);

    // Sıra: Pozisyonun → Analiz; ibare en altta duruyor.
    expect(_y(tester, find.text('POZİSYONUN')),
        lessThan(_y(tester, find.text('ANALİZ'))));
    expect(find.byType(DisclaimerWidget), findsOneWidget);
    expect(_y(tester, find.text('ANALİZ')),
        lessThan(_y(tester, find.byType(DisclaimerWidget))));
    expect(tester.takeException(), isNull);

    // Ayrıntı açılır: eski yedi satır (dönem satırı dahil) yerinde.
    await tester.tap(find.text('Ayrıntı'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    for (final etiket in [
      'Alış fiyatın (ortalama)',
      'Bugünkü fiyat',
      'Ödediğin toplam',
    ]) {
      expect(find.text(etiket), findsOneWidget, reason: '$etiket satırı yok');
    }
    // Toplam (özet + ayrıntı) ve dönem satırı.
    expect(find.textContaining('kâr/zarar'), findsNWidgets(3));

    // Analiz satırı yerinde açılır: kart + panel.
    await tester.ensureVisible(find.text('Teknik sinyaller'));
    await tester.tap(find.text('Teknik sinyaller'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AssetSignalCard), findsOneWidget);
    expect(find.byType(TechnicalSignalPanel), findsOneWidget);
    expect(_y(tester, find.text('ANALİZ')),
        lessThan(_y(tester, find.byType(TechnicalSignalPanel))));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('bayrak AÇIK, İleri seviye: analiz satırları açık başlar',
      (tester) async {
    RemoteConfigService.testAcik = {_bayrak};
    await _ac(tester, seviye: YatirimciSeviyesi.ileri);
    expect(find.text('Teknik sinyaller'), findsOneWidget);
    expect(find.byType(TechnicalSignalPanel), findsOneWidget);
    expect(find.byType(AssetSignalCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('masraflar bayrağıyla birlikte: Masraflar kartı katmanlı düzende de',
      (tester) async {
    // 2026-10-09: #113 kartı yalnız eski yığına eklemişti; iki bayrak
    // birlikte açılınca kart kayboluyordu.
    RemoteConfigService.testAcik = {_bayrak, 'varlik_masraflari'};
    await _ac(tester);
    expect(find.text('MASRAFLAR'), findsOneWidget);
    expect(_y(tester, find.text('POZİSYONUN')),
        lessThan(_y(tester, find.text('MASRAFLAR'))));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  test('eski yığındaki kartlar katmanlı gövdede de çağrılır', () {
    // Eski yığına sonradan eklenen kart katmanlı gövdeye taşınmazsa iki
    // bayrak birlikte açıkken sessizce kaybolur; bu bekçi onu yakalar.
    final govde = ekranKaynagiSync('lib/screens/asset_detail/katmanlar.dart');
    for (final kart in [
      '_eurobondKarti(',
      '_masrafKarti(',
      '_sozlesmeKarti(',
      '_temettuKarti(',
      '_kapBaglantisi(',
    ]) {
      expect(govde, contains(kart), reason: '$kart katmanlı düzende yok');
    }
  });

  testWidgets('bayrak AÇIK, Başlangıç: sinyal yok → Analiz başlığı da yok',
      (tester) async {
    // Bu varlıkta (radar kapalı, fon değil) analiz kartı yalnız sinyaldir;
    // Başlangıç'ta o da gizli. Boş bölümün başlığı çizilmez.
    RemoteConfigService.testAcik = {_bayrak};
    await _ac(tester, seviye: YatirimciSeviyesi.baslangic);
    expect(find.text('ANALİZ'), findsNothing);
    expect(find.byType(DisclaimerWidget), findsNothing);
    expect(find.text('POZİSYONUN'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  test('katman hareketi ortak SandikAcilir; varlık sayfası katmana geçmez', () {
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(detay, contains('SandikAcilir('));
    expect(detay, contains('varlikDetayKatmanli'));
    // Kullanıcı kararı 2026-10-08: iki varlık yüzeyi ayrı kalır.
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    expect(sayfa, isNot(contains('varlikDetayKatmanli')));
  });
}
