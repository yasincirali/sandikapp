import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/kayitli_cihaz.dart';
import 'package:portfoy_takip/providers/cihaz_provider.dart';
import 'package:portfoy_takip/screens/otp_verification_screen.dart';
import 'package:portfoy_takip/services/cihaz_oturumu_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/kaynak.dart';

/// Tek aktif cihaz + kayıtlı cihazlar + yeni cihazda e-posta kodu (0098).
///
/// Sunucu kuralları (kodsuz kayıt reddi, yerinden edilen cihazın geri
/// kapamaması, yatay erişim) yerel Supabase'de gerçek GoTrue token'larıyla
/// doğrulandı (2026-10-03); burada istemcinin yönlendirmesi sınanır.
class _SahteKapi extends CihazKapisiNotifier {
  int gonderim = 0;
  final dogrulanan = <String>[];

  @override
  Future<CihazKapisi> build() async => CihazKapisi.otpGerekli;

  @override
  Future<void> kodGonder() async => gonderim++;

  @override
  Future<void> kodDogrula(String kod) async {
    dogrulanan.add(kod);
    state = const AsyncData(CihazKapisi.serbest);
  }
}

void main() {
  group('cihaz kimliği', () {
    test('kalıcı, 32 hex, kullanıcıya özel', () async {
      SharedPreferences.setMockInitialValues({});
      final s = CihazOturumuService.instance;
      final a1 = await s.cihazKimligi('kullanici-a');
      final a2 = await s.cihazKimligi('kullanici-a');
      final b = await s.cihazKimligi('kullanici-b');
      expect(a1, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a2, a1);
      expect(b, isNot(a1), reason: 'iki hesap sunucuda eşleştirilemesin');
    });

    test('çıkışta silinen push kimliğinden bağımsız', () async {
      SharedPreferences.setMockInitialValues({});
      final s = CihazOturumuService.instance;
      final once = await s.cihazKimligi('u');
      // `AuthService.logout` push kimliğini siler (2026-09 L14); cihaz
      // kimliği kalmalı, yoksa kayıtlı cihaz her girişte kod isterdi.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefKeys.pushDeviceId);
      expect(await s.cihazKimligi('u'), once);
    });
  });

  test('sunucu yanıtı ve kural hataları', () {
    expect(CihazDurumu.parse('kayitli'), CihazDurumu.kayitli);
    expect(CihazDurumu.parse('ilk'), CihazDurumu.ilk);
    expect(CihazDurumu.parse('yeni'), CihazDurumu.yeni);
    expect(CihazDurumu.parse('muaf'), CihazDurumu.muaf);
    expect(CihazDurumu.parse('baska'), isNull);
    for (final k in ['otp_gerekli', 'yerinden_edildi', 'aktif_cihaz_silinemez']) {
      expect(
          CihazOturumuService.kuralHatasi(
              PostgrestException(message: k, code: '42501')),
          k);
    }
    expect(CihazOturumuService.kuralHatasi(StateError('x')), isNull);
  });

  group('OTP ekranı — cihaz modu', () {
    Future<_SahteKapi> kur(WidgetTester tester, {Size boyut = const Size(390, 844), double olcek = 1}) async {
      tester.view.physicalSize = boyut * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late _SahteKapi kapi;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cihazKapisiProvider.overrideWith(() => kapi = _SahteKapi()),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: boyut, textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            locale: const Locale('tr', 'TR'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(builder: (context, ref, _) {
              // Sağlayıcı kurulsun (ekran yalnız notifier'ı okur).
              ref.watch(cihazKapisiProvider);
              return const OtpVerificationScreen(
                  email: 'ben@ornek.com', amac: OtpAmaci.cihaz);
            }),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return kapi;
    }

    testWidgets('kodu kendisi ister, cihaz metnini gösterir', (tester) async {
      final kapi = await kur(tester);
      expect(kapi.gonderim, 1);
      expect(find.text(trMetni('cihazOtpBaslik')), findsOneWidget);
      expect(find.text(trMetni('cihazOtpVazgec')), findsOneWidget);
      expect(find.text(trMetni('otpTitle')), findsNothing);
      // Kod Gereksiz'e düşebiliyor — ipucu görünür olmalı.
      expect(find.text(trMetni('otpSpamIpucu')), findsOneWidget);
    });

    testWidgets('6 hane girilince kod kapıya gider', (tester) async {
      final kapi = await kur(tester);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pump(const Duration(milliseconds: 100));
      expect(kapi.dogrulanan, ['123456']);
    });

    for (final olcek in const [1.0, 1.6]) {
      testWidgets('320 dp, yazı x$olcek taşmaz', (tester) async {
        await kur(tester, boyut: const Size(320, 568), olcek: olcek);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('kaynak sözleşmesi', () {
    final main = ekranKaynagiSync('lib/main.dart');

    test('cihaz kapısı yasal onay, ad ve turdan önce', () {
      final kapi = main.indexOf('final kapi = _cihazKapisi(user);');
      expect(kapi, greaterThan(0));
      expect(kapi, lessThan(main.indexOf('return DisclaimerAcceptanceScreen(')));
      expect(kapi, lessThan(main.indexOf('return OnboardingScreen(')));
      expect(kapi, lessThan(main.indexOf("ValueKey('kullanici-adi')")));
    });

    test('atılan cihaz bildirip çıkar', () {
      final i = main.indexOf('CihazKapisi.atildi) return;');
      expect(i, greaterThan(0));
      final blok = main.substring(i, main.indexOf('});', i));
      expect(blok, contains('_baskaCihazdaBildir()'));
      expect(blok, contains('.logout()'));
    });

    test('Ayarlar › Hesap kayıtlı cihazlara açılır', () {
      final ayarlar = ekranKaynagiSync('lib/screens/settings_screen.dart');
      expect(ayarlar, contains('KayitliCihazlarScreen()'));
    });

    test('migration: definer fonksiyonlar search_path taşır, GRANT doğrulanır', () {
      final sql = ekranKaynagiSync(
          'supabase/migrations/0098_tek_aktif_cihaz.sql');
      final definer = RegExp(r'security definer\s*\n\s*set search_path')
          .allMatches(sql)
          .length;
      expect(definer, 4);
      expect(sql, contains("has_function_privilege('anon', f, 'execute')"));
      expect(sql, contains('force row level security'));
    });
  });
}
