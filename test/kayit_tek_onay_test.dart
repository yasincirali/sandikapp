import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Kayıtta tek onay kutusu — Sadeleştirme 2, liste madde 1 (2026-10-04).
///
/// Bayrak `tek_onay_kutusu` varsayılan KAPALI (hukuki onay bekler). Kapalıyken
/// iki kutu birebir eski; açıkken tek cümleli tek kutu, cümlede iki belgeye
/// bağlantı. Değişmez: kutu işaretlenince İKİ onay da verilmiş olur ve kayıt
/// isteği iki yolda AYNIDIR — onay kaydının kendisi OTP sonrası
/// `DisclaimerService.kabulKaydet`'te, bayraktan bağımsız.
void main() {
  final l = AppLocalizationsTr();
  // Eski kutularda belge açılmadan etiketin altına "(Önce belgeyi oku)"
  // satırı eklenir; tek Text içinde.
  const eskiRizaCumlesi =
      'Verilerimin yurt dışına aktarılmasına açık rıza veriyorum.\n'
      '(Önce belgeyi oku)';
  const eskiKosulCumlesi =
      'Yasal Koşulları, KVKK Aydınlatma Metni\'ni ve 18+ olduğumu kabul '
      'ediyorum.\n(Önce belgeyi oku)';
  const eskiKosulHatasi = 'Devam etmek için yasal koşulları kabul etmelisin.';
  const eskiRizaHatasi =
      'Devam etmek için yurt dışı aktarım rızasını kabul etmelisin.';
  final tekCumle =
      l.tekOnayCumle(l.tekOnayKosullarBaglanti, l.tekOnayRizaBaglanti);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfigService.testAcik = {};
    RegisterScreen.kayitIstegiTesti = null;
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
    RegisterScreen.kayitIstegiTesti = null;
  });

  Future<void> ac(WidgetTester tester,
      {Size boyut = const Size(390, 2000), double olcek = 1.0}) async {
    tester.view.physicalSize = boyut * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: boyut, textScaler: TextScaler.linear(olcek)),
        child: const MaterialApp(
          locale: Locale('tr', 'TR'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RegisterScreen(),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder alan(String etiket) =>
      find.ancestor(of: find.text(etiket), matching: find.byType(TextField));

  Finder kayitDugmesi() => find.descendant(
      of: find.byType(ListView), matching: find.text(l.register));

  Future<void> kayitaBas(WidgetTester tester) async {
    await tester.ensureVisible(kayitDugmesi());
    await tester.tap(kayitDugmesi());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> formuDoldur(WidgetTester tester) async {
    for (final (etiket, metin) in [
      (l.kullaniciAdiEtiket, 'deneme_kisi'),
      (l.email, 'Deneme@Ornek.com'),
      (l.password, 'abcd1234'),
      (l.passwordRepeat, 'abcd1234'),
    ]) {
      // Şifre yazılınca kural listesi açılır, alttaki alan kayar: her
      // alandan sonra yerleşim otursun.
      await tester.enterText(alan(etiket), metin);
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  /// Kayıt isteğini yakalar; argümanları döner.
  List<Map<String, String>> istekleriYakala() {
    final istekler = <Map<String, String>>[];
    RegisterScreen.kayitIstegiTesti = ({
      required String email,
      required String displayName,
      required String password,
    }) async {
      istekler.add(
          {'email': email, 'displayName': displayName, 'password': password});
    };
    return istekler;
  }

  /// OTP ekranının sayaçları test sonunda açık kalmasın.
  Future<void> kapat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  group('bayrak KAPALI — eski iki kutu birebir', () {
    testWidgets('iki kutu görünür, tek cümle yok', (tester) async {
      await ac(tester);
      expect(find.text(eskiRizaCumlesi), findsOneWidget);
      expect(find.text('Açık Rıza: Yurt Dışı Veri Aktarımı'), findsOneWidget);
      expect(find.text(tekCumle, findRichText: true), findsNothing);
      expect(find.text('Belgeyi aç ve onayla'), findsNWidgets(2));
    });

    testWidgets('kutular boşken "Kayıt ol" iki kutunun hatasını da açar',
        (tester) async {
      final istekler = istekleriYakala();
      await ac(tester);
      await formuDoldur(tester);
      await kayitaBas(tester);
      expect(find.text(eskiKosulHatasi), findsOneWidget);
      expect(find.text(eskiRizaHatasi), findsOneWidget);
      expect(istekler, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('yalnız koşullar işaretliyse kayıt yok, rıza hatası görünür',
        (tester) async {
      final istekler = istekleriYakala();
      await ac(tester);
      await formuDoldur(tester);
      await tester.tap(find.text(eskiKosulCumlesi));
      await tester.pump();
      await kayitaBas(tester);
      expect(find.text(eskiKosulHatasi), findsNothing);
      expect(find.text(eskiRizaHatasi), findsOneWidget);
      expect(istekler, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('bayrak AÇIK — tek kutu', () {
    setUp(() => RemoteConfigService.testAcik = {'tek_onay_kutusu'});

    testWidgets('tek kutu, tek cümle; eski rıza kutusu yok', (tester) async {
      await ac(tester);
      expect(find.text(tekCumle, findRichText: true), findsOneWidget);
      expect(find.text(eskiRizaCumlesi), findsNothing);
      expect(find.text('Açık Rıza: Yurt Dışı Veri Aktarımı'), findsNothing);
      expect(find.text('Belgeyi aç ve onayla'), findsNothing);
      // Cümle iki eski kutunun cümlelerinin birleşimi; yeni iddia yok.
      expect(
          tekCumle,
          'Yasal Koşulları, KVKK Aydınlatma Metni\'ni ve 18+ olduğumu kabul '
          'ediyorum; verilerimin yurt dışına aktarılmasına açık rıza '
          'veriyorum.');
    });

    testWidgets('işaretlenmeden "Kayıt ol" → kayıt yok, hata kutunun altında',
        (tester) async {
      final istekler = istekleriYakala();
      await ac(tester);
      await formuDoldur(tester);
      await kayitaBas(tester);
      expect(istekler, isEmpty);
      // Kutunun altındaki satır (uyarı tostu da aynı metni taşır).
      expect(find.text(l.tekOnayGerekli), findsWidgets);
      final kutuHatasi = find.descendant(
          of: find.ancestor(
              of: find.text(tekCumle, findRichText: true),
              matching: find.byType(Column)),
          matching: find.text(l.tekOnayGerekli));
      expect(kutuHatasi, findsOneWidget);
      expect(find.text(eskiKosulHatasi), findsNothing);
      expect(find.text(eskiRizaHatasi), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('kutuya basmak işaretler, ikinci basış kaldırır',
        (tester) async {
      await ac(tester);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(find.text(tekCumle, findRichText: true),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text(tekCumle, findRichText: true),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('bağlantılar doğru belgeyi açar, kutuyu işaretlemez',
        (tester) async {
      await ac(tester);
      await tester.tapOnText(find.textRange.ofSubstring(
          l.tekOnayKosullarBaglanti,
          descendentOf: find.text(tekCumle, findRichText: true)));
      await tester.pumpAndSettle();
      var belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
      expect(belge.title, 'Yasal Koşullar & KVKK Aydınlatma');
      expect(belge.blocks, same(LegalDocs.terms));
      // Tek kutuda belge yalnız okunur; onay kutunun kendisidir.
      expect(belge.confirmMode, isFalse);
      Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      // `pushGuarded` çift dokunma penceresi gerçek saatle (500 ms) işler.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tapOnText(find.textRange.ofSubstring(
          l.tekOnayRizaBaglanti,
          descendentOf: find.text(tekCumle, findRichText: true)));
      await tester.pumpAndSettle();
      belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
      expect(belge.title, 'Açık Rıza: Yurt Dışı Veri Aktarımı');
      expect(belge.blocks.length, LegalDocs.privacy.length);
      expect(belge.confirmMode, isFalse);
      Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });
  });

  testWidgets(
      'iki onay: tek kutu işaretlenince kayıt isteği iki kutulu eski yolla '
      'BİREBİR aynı', (tester) async {
    // Eski yol: iki kutu ayrı ayrı.
    final eski = istekleriYakala();
    await ac(tester);
    await formuDoldur(tester);
    await tester.tap(find.text(eskiKosulCumlesi));
    await tester.tap(find.text(eskiRizaCumlesi));
    await tester.pump();
    await kayitaBas(tester);
    await tester.pumpAndSettle();
    await kapat(tester);
    expect(eski, hasLength(1));

    // Yeni yol: tek kutu.
    RemoteConfigService.testAcik = {'tek_onay_kutusu'};
    final yeni = istekleriYakala();
    await ac(tester);
    await formuDoldur(tester);
    await tester.tap(find.text(tekCumle, findRichText: true),
        warnIfMissed: false);
    await tester.pump();
    await kayitaBas(tester);
    await tester.pumpAndSettle();
    await kapat(tester);
    expect(yeni, hasLength(1));
    expect(yeni.single, eski.single);
    expect(yeni.single['email'], 'deneme@ornek.com');
  });

  test('onay kaydı bayraktan bağımsız: OTP sonrası tek kabulKaydet, ekran '
      'bayrağı yalnız kutu görünüşü için okur', () {
    final otp = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    expect(otp, contains('DisclaimerService.instance.kabulKaydet('));
    expect(otp, isNot(contains('tekOnayKutusu')));
    final servis = ekranKaynagiSync('lib/services/disclaimer_service.dart');
    expect(servis, isNot(contains('tekOnayKutusu')));
    final kayit = ekranKaynagiSync('lib/screens/register_screen.dart');
    // Kapı iki bayrağı eskisi gibi okur.
    expect(kayit, contains('_termsAccepted &&\n      _consentAccepted;'));
    expect('tekOnayKutusu'.allMatches(kayit), hasLength(1));
  });

  group('dar ekranda taşma yok (bayrak açık)', () {
    setUp(() => RemoteConfigService.testAcik = {'tek_onay_kutusu'});
    for (final boyut in const [Size(320, 568), Size(360, 640)]) {
      for (final olcek in const [1.0, 1.3, 1.6]) {
        testWidgets('${boyut.width.toInt()} dp, yazı x$olcek', (tester) async {
          await ac(tester, boyut: boyut, olcek: olcek);
          await tester.pump(const Duration(seconds: 1));
          await tester.scrollUntilVisible(
              find.text(tekCumle, findRichText: true), 200,
              scrollable: find.byType(Scrollable).first);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant.only(TargetPlatform.android));
      }
    }
  });
}
