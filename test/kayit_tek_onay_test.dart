import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/widgets/zorunlu_okuma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Kayıtta tek onay kutusu — Sadeleştirme 2, liste madde 1 (2026-10-04).
///
/// Tek cümleli tek kutu, cümlede belgelere bağlantı. Değişmez: kutu
/// işaretlenince İKİ onay da verilmiş olur; onay kaydının kendisi OTP
/// sonrası `DisclaimerService.kabulKaydet`'te.
///
/// 2026-10-05: bayraklar `tek_onay_kutusu` ve `zorunlu_okuma` kalktı. İki
/// kutulu eski düzenin testleri ve "iki yolda aynı kayıt isteği"
/// karşılaştırması silindi; kutu artık metinler okunmadan işaretlenmez
/// ([hepsiniOku]; okuma mekaniği `zorunlu_okuma_test`'te).
void main() {
  final l = AppLocalizationsTr();
  // Eski kutularda belge açılmadan etiketin altına "(Önce belgeyi oku)"
  // satırı eklenir; tek Text içinde.
  const eskiRizaCumlesi =
      'Verilerimin yurt dışına aktarılmasına açık rıza veriyorum.\n'
      '(Önce belgeyi oku)';
  const eskiKosulHatasi = 'Devam etmek için yasal koşulları kabul etmelisin.';
  const eskiRizaHatasi =
      'Devam etmek için yurt dışı aktarım rızasını kabul etmelisin.';
  final tekCumle = l.tekOnayCumle(l.tekOnayKosullarBaglanti,
      l.tekOnayKvkkBaglanti, l.tekOnayRizaBaglanti);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RegisterScreen.kayitIstegiTesti = null;
  });
  tearDown(() {
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

  /// Her metni açar ve okuyucuyu "sonuna kadar okundu, onaylandı" ile
  /// kapatır — kutunun kilidi açılsın diye.
  Future<void> hepsiniOku(WidgetTester tester) async {
    final n = find.byType(YasalBelgeSatiri).evaluate().length;
    for (var i = 0; i < n; i++) {
      final satir = find.byType(YasalBelgeSatiri).at(i);
      await tester.ensureVisible(satir);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tap(satir);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(LegalDocScreen))).pop(
          const ZorunluOkumaSonucu(onaylandi: true, sonunaKadarOkundu: true));
      await tester.pumpAndSettle();
    }
  }

  group('tek kutu', () {

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

    testWidgets('metinler okununca kutuya basmak işaretler, ikinci basış '
        'kaldırır', (tester) async {
      await ac(tester);
      await hepsiniOku(tester);
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

    testWidgets('bağlantılar doğru belgeyi zorunlu okumada açar, kutuyu '
        'işaretlemez',
        (tester) async {
      await ac(tester);
      // Önceki testin itişi `pushGuarded` penceresinde (gerçek saat) kalmasın.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tapOnText(find.textRange.ofSubstring(
          l.tekOnayKosullarBaglanti,
          descendentOf: find.text(tekCumle, findRichText: true)));
      await tester.pumpAndSettle();
      var belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
      // Başlık eskiden "Yasal Koşullar & KVKK Aydınlatma"ydı ama sayfa
      // yalnız Koşulları gösteriyordu.
      expect(belge.title, l.yasalBelgeKosullar);
      expect(belge.blocks, same(LegalDocs.terms));
      // Belge zorunlu okumada; dönüşsüz kapanış onay değildir.
      expect(belge.zorunluOkuma, isTrue);
      Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      // KVKK Aydınlatma Metni cümlede AYRI bağlantı.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tapOnText(find.textRange.ofSubstring(l.tekOnayKvkkBaglanti,
          descendentOf: find.text(tekCumle, findRichText: true)));
      await tester.pumpAndSettle();
      belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
      expect(belge.title, l.yasalBelgeKvkk);
      expect(belge.blocks.length, LegalDocs.kvkk.length);
      expect(belge.blocks.first.text, 'KVKK Aydınlatma Metni — sandık');
      expect(belge.zorunluOkuma, isTrue);
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
      // 1.2: "açık rıza" Açık Rıza Metni'ni açar (önceden Gizlilik
      // Politikası'nı "Açık Rıza: Yurt Dışı Veri Aktarımı" başlığıyla).
      expect(belge.title, l.yasalBelgeAcikRiza);
      expect(belge.blocks.length, LegalDocs.acikRiza.length);
      expect(belge.blocks.first.text, 'Açık Rıza Metni — sandık');
      expect(belge.zorunluOkuma, isTrue);
      Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });
  });

  test('onay kaydı: OTP sonrası tek kabulKaydet; bayrak okuması kalmadı', () {
    final otp = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    expect(otp, contains('DisclaimerService.instance.kabulKaydet('));
    expect(otp, isNot(contains('tekOnayKutusu')));
    final servis = ekranKaynagiSync('lib/services/disclaimer_service.dart');
    expect(servis, isNot(contains('tekOnayKutusu')));
    final kayit = ekranKaynagiSync('lib/screens/register_screen.dart');
    // Kapı iki bayrağı eskisi gibi okur.
    expect(kayit, contains('_termsAccepted &&\n      _consentAccepted;'));
    expect(kayit, isNot(contains('tekOnayKutusu')));
  });

  group('dar ekranda taşma yok', () {
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
