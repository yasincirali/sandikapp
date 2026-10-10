@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ortak_paylasimi.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/ortak_paylasimi_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/screens/portfoy_yonetimi_screen.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kismi_aktarim_sayfasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ortak portföy paylaşımı (0135) ve kısmi aktarım (0136) GÖRSEL önizlemesi — `build/gorsel/`
/// altına PNG, önce/sonra. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/ortak_paylasim_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur; canlı veri değildir. "Önce" aynı veriyle seçim yüzeyi
/// kapalı (bugünkü main), "sonra" bu dal.
const _ben = 'u-ben';
const _ayseId = 'u-ayse';
const _emek = 'pf-emek';
const _cocuk = 'pf-cocuk';

final _ayse = AppUser(
  id: _ayseId,
  email: 'ayse@example.com',
  displayName: 'Ayşe Yılmaz',
  createdAt: DateTime(2026, 1, 1),
);

Asset _lot(String id, String sahip, String ticker, String ad, AssetType tur,
        double adet, double fiyat, {String? portfoy}) =>
    Asset(
      id: id,
      userId: sahip,
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat * 0.88,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2025, 3, 14),
      portfoyId: portfoy,
    );

// Benim defterim: Ana (hisseler), Emeklilik (fon + altın), Çocuk (altın).
final _benim = [
  _lot('1', _ben, 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 400, 312.4),
  _lot('2', _ben, 'ASELS.IS', 'Aselsan', AssetType.hisse, 600, 142.6),
  _lot('3', _ben, 'TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler', AssetType.fon,
      30000, 4.1,
      portfoy: _emek),
  _lot('4', _ben, 'ALTIN_GRAM', 'Gram Altın', AssetType.altin, 20, 4300,
      portfoy: _emek),
  _lot('5', _ben, 'ALTIN_CEYREK', 'Çeyrek Altın', AssetType.altin, 15, 7100,
      portfoy: _cocuk),
];

// Ayşe'nin bana gösterdiği defter: önce hepsi, sonra yalnız Ana.
final _ayseHepsi = [
  _lot('a1', _ayseId, 'TUPRS.IS', 'Tüpraş', AssetType.hisse, 300, 171.0),
  _lot('a2', _ayseId, 'TEFAS:TTE', 'İş Portföy BIST Teknoloji', AssetType.fon,
      40000, 3.2),
  _lot('a3', _ayseId, 'ALTIN_GRAM', 'Gram Altın', AssetType.altin, 35, 4300,
      portfoy: 'pf-ayse-kendi'),
];
final _ayseAna = _ayseHepsi.where((a) => a.portfoyId == null).toList();

const _portfoyler = [
  Portfoy(id: _emek, userId: _ben, ad: 'Emeklilik', sira: 1),
  Portfoy(id: _cocuk, userId: _ben, ad: 'Çocuğum için', sira: 2),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _ben,
        email: 'yasin@example.com',
        displayName: 'Yasin',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _benim, ownerId: _ben, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async =>
      [PartnerAccount(user: _ayse, isActive: true)];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  _FakePartnerAssets(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<Map<String, List<Asset>>> build() async => {_ayseId: lotlar};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

class _SabitPortfoyler extends PortfoylerNotifier {
  @override
  Future<List<Portfoy>> build() async => _portfoyler;
}

class _SabitPaylasimlar extends OrtakPaylasimlariNotifier {
  _SabitPaylasimlar(this.liste);
  final List<OrtakPaylasimi> liste;
  @override
  Future<List<OrtakPaylasimi>> build() async => liste;
}

// Ben → Ayşe: Ana + Emeklilik görünür, Çocuğum için gizli.
const _benimSecimim = OrtakPaylasimi(
    sahipId: _ben,
    ortakId: _ayseId,
    tumu: false,
    ana: true,
    portfoyIdler: {_emek});
// Ayşe → ben: yalnız Ana (onun "Kendi birikimim"i gizli).
const _ayseninSecimi = OrtakPaylasimi(
    sahipId: _ayseId, ortakId: _ben, tumu: false, ana: true);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> bekle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ciz(
    WidgetTester tester,
    String ad, {
    required Widget ekran,
    required bool sonra,
    List<Asset>? ortakLotlari,
    Future<void> Function(WidgetTester t)? hazirla,
    double boy = 844,
    bool premium = true,
  }) async {
    RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(
            () => _FakePartnerAssets(ortakLotlari ?? _ayseHepsi)),
        signalProvider.overrideWith(_FakeSignals.new),
        portfoylerProvider.overrideWith(_SabitPortfoyler.new),
        ortakPaylasimlariProvider.overrideWith(() => _SabitPaylasimlar(
            sonra ? const [_benimSecimim, _ayseninSecimi] : const [])),
        if (!sonra) ortakPaylasimSecimiVarProvider.overrideWithValue(false),
        isPushAdminProvider.overrideWith((_) async => false),
        gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
        magazaPremiumProvider.overrideWith((_) => premium),
        gecerliPremiumHakkiProvider.overrideWithValue(null),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Material(type: MaterialType.transparency, child: ekran),
        ),
      ),
    ));
    await tester.pump();
    await bekle(tester, 40);
    if (hazirla != null) {
      await hazirla(tester);
      await bekle(tester, 30);
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  Future<void> ortaklaraKaydir(WidgetTester t) async {
    final ad = find.text('Ayşe Yılmaz', skipOffstage: false);
    if (ad.evaluate().isEmpty) return;
    await t.ensureVisible(ad.first);
    await bekle(t, 5);
  }

  Future<void> ortagaGec(WidgetTester t) async {
    // Kartı sola kaydır: Ben → Ayşe.
    await t.drag(find.text('TOPLAM NET VARLIK').first, const Offset(-300, 0));
  }

  testWidgets('profil önce', (t) => ciz(t, 'ortak_profil_once',
      ekran: const ProfileScreen(), sonra: false, boy: 1500));
  testWidgets('profil sonra', (t) => ciz(t, 'ortak_profil_sonra',
      ekran: const ProfileScreen(), sonra: true, boy: 1500));
  testWidgets('seçim sayfası', (t) => ciz(t, 'ortak_secim_sayfasi',
          ekran: const ProfileScreen(), sonra: true, boy: 1500,
          hazirla: (t) async {
        await ortaklaraKaydir(t);
        await t.tap(find.byKey(const ValueKey('ortak-paylasim-satiri-$_ayseId')));
      }));
  testWidgets('portföyler önce', (t) => ciz(t, 'ortak_portfoyler_once',
      ekran: const PortfoyYonetimiScreen(), sonra: false));
  testWidgets('portföyler sonra', (t) => ciz(t, 'ortak_portfoyler_sonra',
      ekran: const PortfoyYonetimiScreen(), sonra: true));
  testWidgets('profil kilitli', (t) => ciz(t, 'ortak_profil_kilitli',
      ekran: const ProfileScreen(), sonra: true, boy: 1500, premium: false));
  testWidgets('ana ortak önce', (t) => ciz(t, 'ortak_ana_ortak_once',
      ekran: const HomeScreen(), sonra: false, hazirla: ortagaGec));
  testWidgets('ana ortak sonra', (t) => ciz(t, 'ortak_ana_ortak_sonra',
      ekran: const HomeScreen(),
      sonra: true,
      ortakLotlari: _ayseAna,
      hazirla: ortagaGec));

  Widget aktarimSayfasi({required bool kismi}) => Builder(
        builder: (ctx) => ColoredBox(
          color: ctx.c.background,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: ctx.c.surface2,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(SandikRadius.lg))),
              child: KismiAktarimIcerik(
                gorunum: _benim[3],
                toplam: 20,
                hedefAdi: 'Çocuğum için',
                aktar: (_) async => false,
                ilkKismi: kismi,
              ),
            ),
          ),
        ),
      );
  testWidgets('aktarım kısmi', (t) => ciz(t, 'ortak_aktarim_kismi',
      ekran: aktarimSayfasi(kismi: true), sonra: true,
      hazirla: (t) => t.enterText(
          find.byKey(const ValueKey('kismi-aktarim-miktar')), '8')));
  testWidgets('aktarım kilitli', (t) => ciz(t, 'ortak_aktarim_kilitli',
      ekran: aktarimSayfasi(kismi: false), sonra: true, premium: false));
}
