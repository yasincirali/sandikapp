import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/lock_offer_screen.dart';
import 'package:portfoy_takip/services/biometric_lock_service.dart';

import 'helpers/kaynak.dart';

/// Biyometrik kilit TEKLİFİ (kullanıcı kararı, 2026-09-23):
/// *"biyometrik kilidi olmayan müşteride çıkış yapılmayacağı eklemesi
/// gerektiği güvenlik için önerildiği gösterilmeli, default olarak
/// biyometrik kilidi önerip onaylattırılmalı"*.
///
/// Teklif bir ÖNERİDİR, kapı değil: reddedilebilir ve reddedildiğinde
/// tekrar sorulmaz. Ama reddin bedeli görünür olmalı — kilitsiz
/// kullanıcıda zaman aşımı `logout()` uyguluyor ve bu push token'ını da
/// siliyor.
void main() {
  final l = AppLocalizationsTr();

  setUp(() {
    // Statik alanlar testler arası SIZAR — her testte sıfırla, yoksa
    // sıra değişince sahte geçen/kalan testler doğar.
    _SahteKilit.sonuc = BiyometrikSonuc.basarili;
    _SahteKilit.destekli = true;
    _SahteKilit.firlat = false;
    _SahteKilit.cagrildi = false;
    BiometricLockService.resetForTest(_SahteKilit());
  });
  tearDown(BiometricLockService.resetForTest);

  Future<void> ekraniAc(
    WidgetTester tester, {
    VoidCallback? kabul,
    VoidCallback? ret,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LockOfferScreen(
        onKabul: kabul ?? () {},
        onRet: ret ?? () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('gerekçe GÖRÜNÜR', () {
    testWidgets('üç fayda da yazılı — özellikle oturum ve bildirim',
        (tester) async {
      await ekraniAc(tester);
      // Kullanıcının asıl derdi bu ikisiydi: çıkış yapılması ve
      // push'un kesilmesi. Mahremiyet üçüncü sırada, çünkü kilidi
      // kapalı kullanıcı onu zaten kabul etmiş sayılır.
      expect(find.text(l.lockOfferBenefitStay), findsOneWidget);
      expect(find.text(l.lockOfferBenefitPush), findsOneWidget);
      expect(find.text(l.lockOfferBenefitPrivacy), findsOneWidget);
    });

    testWidgets('gövde metinleri NEDENİ söylüyor, sadece başlık değil',
        (tester) async {
      await ekraniAc(tester);
      expect(find.text(l.lockOfferBenefitStayBody), findsOneWidget);
      expect(find.text(l.lockOfferBenefitPushBody), findsOneWidget);
    });

    testWidgets('sonradan açılabileceği söyleniyor — dayatma değil',
        (tester) async {
      await ekraniAc(tester);
      expect(find.text(l.lockOfferLater), findsOneWidget);
    });
  });

  group('kabul yolu', () {
    testWidgets('DOĞRULAMA başarılıysa kabul çağrılır', (tester) async {
      _SahteKilit.sonuc = BiyometrikSonuc.basarili;
      var kabul = false;
      await ekraniAc(tester, kabul: () => kabul = true);

      await tester.tap(find.text(l.lockOfferAccept));
      await tester.pumpAndSettle();
      expect(kabul, isTrue);
    });

    testWidgets('doğrulama İPTAL edilirse tercih AÇILMAZ', (tester) async {
      // Ayarlar'daki açma akışıyla aynı kural: doğrulamadan tercihi
      // açmak kullanıcıyı açamayacağı bir kilit ekranına düşürürdü.
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      var kabul = false;
      var ret = false;
      await ekraniAc(tester, kabul: () => kabul = true, ret: () => ret = true);

      await tester.tap(find.text(l.lockOfferAccept));
      await tester.pumpAndSettle();
      expect(kabul, isFalse, reason: 'doğrulanmadan kilit açılmamalı');
      expect(ret, isFalse,
          reason: 'iptal "hayır" değil — kullanıcı fikrini değiştirebilir');
      expect(find.text(l.lockOfferAccept), findsOneWidget,
          reason: 'ekranda kalmalı');
    });

    testWidgets('cihaz DESTEKLEMİYORSA ret sayılır, kullanıcı takılmaz',
        (tester) async {
      _SahteKilit.destekli = false;
      var ret = false;
      await ekraniAc(tester, ret: () => ret = true);

      await tester.tap(find.text(l.lockOfferAccept));
      await tester.pumpAndSettle();
      expect(ret, isTrue,
          reason: 'Face ID olmayan cihazda teklif ekranında kilitlenmemeli');
    });

    testWidgets('servis FIRLATSA bile düğme kilitli kalmaz', (tester) async {
      // `LockScreen`in donma hatasının aynısı burada da olmasın
      // (üretim çökmesi 2026-09-19): `try/finally` YAPISAL koruma.
      _SahteKilit.firlat = true;
      await ekraniAc(tester);
      await tester.tap(find.text(l.lockOfferAccept));
      await tester.pumpAndSettle();
      final dugme =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(dugme.onPressed, isNotNull,
          reason: 'hata sonrası tekrar denenebilmeli');
    });
  });

  group('ret yolu', () {
    testWidgets('"Şimdi değil" ret çağırır, doğrulama İSTEMEZ',
        (tester) async {
      var ret = false;
      await ekraniAc(tester, ret: () => ret = true);
      await tester.tap(find.text(l.lockOfferDecline));
      await tester.pumpAndSettle();
      expect(ret, isTrue);
      expect(_SahteKilit.cagrildi, isFalse,
          reason: 'reddeden kullanıcıya Face ID sorulmamalı');
    });
  });

  group('akışa bağlı', () {
    test('kaynak: teklif kilidi AÇIK olana gösterilmez', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('if (!ref.watch(biometricLockProvider) && '
              '!ref.watch(biometricLockOfferedProvider))'),
          isTrue,
          reason: 'kilidi zaten açık olana teklif anlamsız');
    });

    test('kaynak: kabul sırası — önce tercih, sonra damga', () {
      // Ters sırada ve arada çökme olursa kullanıcı hem kilitsiz kalır
      // hem de teklifi bir daha görmez.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      final tercih =
          tek.indexOf('await ref.read(biometricLockProvider.notifier).set(true);');
      final damga = tek.indexOf(
          'await ref.read(biometricLockOfferedProvider.notifier).set(true);');
      expect(tercih, greaterThan(-1));
      expect(damga, greaterThan(tercih),
          reason: 'damga tercihten SONRA yazılmalı');
    });

    test('kaynak: RET de damgalanır — tekrar sorulmaz', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('onRet: () async { await ref.read('
              'biometricLockOfferedProvider.notifier).set(true);'),
          isTrue,
          reason: 'her açılışta sormak dayatma olurdu');
    });

    test('kaynak: zaman aşımı çıkışı teklifi YENİDEN açar', () {
      // Kaybı bizzat yaşamış kullanıcıya kararını yeniden sormak
      // dayatma değil: ilk "şimdi değil" sonucunu görmeden verilmişti.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains(
              'ref.read(biometricLockOfferedProvider.notifier).set(false)'),
          isTrue);
    });

    test('kaynak: çıkış SESSİZ değil — neden söyleniyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('_zamanAsimiBildir();'), isTrue);
      expect(tek.contains('context.l10n.sessionTimedOut'), isTrue,
          reason: 'kullanıcı şifre ekranını arıza sanıyordu');
    });

    test('tercih KİŞİYE ÖZEL — ikinci hesap kendi kararını verir', () {
      final src = ekranKaynagiSync('lib/providers/preferences_provider.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('_BoolPrefNotifier(PrefKeys.biometricLockOffered, '
              'false, perUser: true)'),
          isTrue);
      expect(tek.contains('biometricLockOfferedProvider,'), isTrue,
          reason: 'kullanıcıya özel tercih listesine girmeli');
    });
  });
}

class _SahteKilit extends BiometricLockService {
  _SahteKilit() : super.forTest();

  static BiyometrikSonuc sonuc = BiyometrikSonuc.basarili;
  static bool destekli = true;
  static bool firlat = false;
  static bool cagrildi = false;

  @override
  Future<bool> get available async => destekli;

  @override
  Future<BiyometrikSonuc> authenticate({String reason = ''}) async {
    cagrildi = true;
    if (firlat) {
      firlat = false;
      throw const LocalAuthException(
          code: LocalAuthExceptionCode.unknownError);
    }
    return sonuc;
  }
}
