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
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/hesap_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/login_screen.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/hesap_gecisi.dart';
import 'package:portfoy_takip/services/hesap_kasasi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hesap_secici.dart';
import 'package:portfoy_takip/widgets/uygulama_kabugu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çoklu hesap GÖRSEL önizlemesi — `build/gorsel/` altına PNG. Assert
/// etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/coklu_hesap_gorsel_onizleme_test.dart
///
/// Adlar DEMO'dur. "Önce" bayrak kapalı (bugünkü main), "sonra" bu dal.
final _yasin = AppUser(
  id: 'u-yasin',
  email: 'yasin@example.com',
  displayName: 'yasin',
  username: 'yasin',
  createdAt: DateTime(2026, 1, 1),
);

final _simdi = DateTime.now();
final _hesaplar = [
  KayitliHesap(uid: 'u-yasin', eposta: 'yasin@example.com', ad: 'yasin',
      sonKullanim: _simdi),
  KayitliHesap(uid: 'u-sirket', eposta: 'muhasebe@example.com',
      ad: 'cirali_holding',
      sonKullanim: _simdi.subtract(const Duration(days: 1))),
  KayitliHesap(uid: 'u-anne', eposta: 'anne@example.com', ad: 'Ayşe Cıralı',
      sonKullanim: _simdi.subtract(const Duration(days: 9)),
      oturumDustu: true),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _yasin;
}

class _BosAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const [], ownerId: 'u-yasin', usdTry: 42.0, eurTry: 46.0,
      gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

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
  tearDown(() {
    RemoteConfigService.testAcik = {};
    HesapGecisi.instance.eklemedenDonulecek.value = null;
  });

  Future<void> bekle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ciz(
    WidgetTester tester,
    String ad, {
    required Widget ekran,
    bool bayrak = true,
    List<KayitliHesap>? hesaplar,
    bool premium = true,
    bool girisYok = false,
    Brightness parlaklik = Brightness.dark,
    Future<void> Function(WidgetTester t)? hazirla,
  }) async {
    RemoteConfigService.testAcik = {
      'paywall_enabled',
      if (bayrak) 'coklu_hesap',
    };
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(girisYok ? _BosAuth.new : _FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
        signalProvider.overrideWith(_FakeSignals.new),
        kayitliHesaplarProvider.overrideWithValue(hesaplar ?? _hesaplar),
        isPushAdminProvider.overrideWith((_) async => false),
        gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
        magazaPremiumProvider.overrideWith((_) => premium),
        gecerliPremiumHakkiProvider.overrideWithValue(null),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(
              parlaklik == Brightness.dark
                  ? SandikPalette.dark
                  : SandikPalette.light,
              parlaklik),
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
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  Future<void> seciciyiAc(WidgetTester t) async {
    await t.tap(find.byType(HesapBasligi));
  }

  testWidgets('profil önce', (t) => ciz(t, 'hesap_profil_once',
      ekran: const ProfileScreen(), bayrak: false));
  testWidgets('profil sonra', (t) => ciz(t, 'hesap_profil_sonra',
      ekran: const ProfileScreen()));
  testWidgets('seçici', (t) => ciz(t, 'hesap_secici',
      ekran: const ProfileScreen(), hazirla: seciciyiAc));
  testWidgets('seçici açık tema', (t) => ciz(t, 'hesap_secici_acik',
      ekran: const ProfileScreen(),
      parlaklik: Brightness.light,
      hazirla: seciciyiAc));
  testWidgets('seçici düzenle', (t) => ciz(t, 'hesap_secici_duzenle',
      ekran: const ProfileScreen(), hazirla: (t) async {
        await seciciyiAc(t);
        await bekle(t, 20);
        await t.tap(find.text('Düzenle'));
      }));
  testWidgets('seçici ücretsiz kullanıcı', (t) => ciz(t, 'hesap_secici_ucretsiz',
      ekran: const ProfileScreen(),
      premium: false,
      hesaplar: [_hesaplar.first],
      hazirla: seciciyiAc));

  Widget cikisEkrani() => Builder(
        builder: (ctx) => ColoredBox(
          color: ctx.c.background,
          child: Center(
            child: TextButton(
              onPressed: () => cokluCikisSor(ctx, 'yasin', 3),
              child: const Text('aç'),
            ),
          ),
        ),
      );
  testWidgets('çıkış', (t) => ciz(t, 'hesap_cikis',
      ekran: cikisEkrani(), hazirla: (t) => t.tap(find.text('aç'))));

  testWidgets('giriş: hesap eklerken', (t) {
    HesapGecisi.instance.eklemedenDonulecek.value = _hesaplar.first;
    return ciz(t, 'hesap_giris_ekleme',
        ekran: const LoginScreen(), girisYok: true);
  });
  testWidgets('giriş: çıkıştan sonra', (t) => ciz(t, 'hesap_giris_cikis_sonrasi',
      ekran: const LoginScreen(),
      girisYok: true,
      hesaplar: _hesaplar.sublist(1)));

  testWidgets('geçiş perdesi', (t) => ciz(t, 'hesap_gecis_perdesi',
      ekran: const HesapGecisPerdesiGorunumu(
          perde: HesapGecisPerdesi(
              basHarf: 'C',
              ad: 'cirali_holding',
              alt: 'hesabına geçiliyor'))));
}
