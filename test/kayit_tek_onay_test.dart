import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
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
/// karşılaştırması silindi. Aynı gün okuma sadeleştirme (kutu 1.1): kutu
/// Koşulların kabulü + 18+ + Gizlilik/KVKK ile "bilgilendirildim"; açık
/// rıza İÇERMEZ (Açık Rıza Metni'nin sonunda verilir). Kutu metinlere
/// kilitli değil; üç belge adı cümlede salt okunur bağlantı.
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
      l.tekOnayGizlilikBaglanti, l.tekOnayKvkkBaglanti);

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

  /// Kutunun karesi (cümlede belge bağlantıları var; ortasına dokunmak
  /// bağlantıya denk gelebilir).
  Finder kare() => find.descendant(
      of: find.byType(YasalOnayKutusu),
      matching: find.byType(AnimatedContainer));

  /// Okunacak her metni (Açık Rıza, uyarı) açar ve okuyucuyu "sonuna kadar
  /// okundu, onaylandı" ile kapatır.
  Future<void> okunacaklariOku(WidgetTester tester) async {
    Finder satirlar() => find.byWidgetPredicate(
        (w) => w is YasalBelgeSatiri && w.bekleyenEtiketi != null);
    final n = satirlar().evaluate().length;
    expect(n, 2);
    for (var i = 0; i < n; i++) {
      final satir = satirlar().at(i);
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
      // Kutu 1.1: Koşullar kabul, 18+, Gizlilik ve KVKK bilgilendirme.
      expect(
          tekCumle,
          'Kullanım Koşulları\'nı kabul ediyorum ve 18 yaşından büyüğüm. '
          'Gizlilik Politikası ve KVKK Aydınlatma Metni ile '
          'bilgilendirildim.');
      expect(find.text('v${YasalMetinKatalogu.kutuSurumu}'), findsOneWidget);
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

    testWidgets(
        'kutu metinlere KİLİTLİ DEĞİL: okumadan işaretlenir, ikinci basış '
        'kaldırır; okumak kutuyu işaretlemez', (tester) async {
      await ac(tester);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      await tester.tap(kare());
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(kare());
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      // Açık rızayı vermek (metnin sonunda) kutuyu işaretlemez.
      await okunacaklariOku(tester);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets(
        'cümledeki üç bağlantı doğru belgeyi SALT OKUNUR açar (onay '
        'düğmesi yok), kutuyu işaretlemez', (tester) async {
      await ac(tester);
      for (final (baglanti, baslik, bloklar, ilk) in [
        (
          l.tekOnayKosullarBaglanti,
          l.yasalBelgeKosullar,
          LegalDocs.terms,
          'Kullanım Koşulları — sandık'
        ),
        (
          l.tekOnayGizlilikBaglanti,
          l.yasalBelgeGizlilik,
          LegalDocs.privacy,
          'Gizlilik Politikası — sandık'
        ),
        (
          l.tekOnayKvkkBaglanti,
          l.yasalBelgeKvkk,
          LegalDocs.kvkk,
          'KVKK Aydınlatma Metni — sandık'
        ),
      ]) {
        // `pushGuarded` çift dokunma penceresi gerçek saatle (500 ms) işler.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 600)));
        await tester.tapOnText(find.textRange.ofSubstring(baglanti,
            descendentOf: find.text(tekCumle, findRichText: true)));
        await tester.pumpAndSettle();
        final belge =
            tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
        expect(belge.title, baslik);
        expect(belge.blocks.length, bloklar.length);
        expect(belge.blocks.first.text, ilk);
        // Bilgilendirme/kabul belgesi: okuma şartı ve belge sonu onayı yok.
        expect(belge.zorunluOkuma, isFalse, reason: baslik);
        expect(find.byType(OkumaIpucu), findsNothing);
        Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_rounded), findsNothing);
      }
      // Cümlede "açık rıza" bağlantısı yok.
      expect(tekCumle.toLowerCase(), isNot(contains('açık rıza')));
    });
  });

  test('onay kaydı: OTP sonrası tek kabulKaydet; bayrak okuması kalmadı', () {
    final otp = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    expect(otp, contains('DisclaimerService.instance.kabulKaydet('));
    expect(otp, isNot(contains('tekOnayKutusu')));
    final servis = ekranKaynagiSync('lib/services/disclaimer_service.dart');
    expect(servis, isNot(contains('tekOnayKutusu')));
    final kayit = ekranKaynagiSync('lib/screens/register_screen.dart');
    // "Kayıt ol": okunacak metinler (Açık Rıza, uyarı) + kutu.
    expect(kayit, contains('_belgelerTamam &&\n      _kutuIsaretli;'));
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
