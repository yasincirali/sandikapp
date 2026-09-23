import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/lock_screen.dart';
import 'package:portfoy_takip/services/biometric_lock_service.dart';

/// Kilit ekranı bir daha DONMAZ.
///
/// Üretim çökmesi (Crashlytics, 2026-09-19):
/// `LocalAuthDarwin.authenticate → BiometricLockService.authenticate →
/// _LockScreenState._tryUnlock`. Servis yalnızca `PlatformException`
/// yakalıyordu; local_auth 3.x ise `LocalAuthException` fırlatıyor ve
/// **kullanıcının "İptal"e basması da bir hata** (`userCanceled`).
///
/// Görünen çökme raporu asıl zararın küçük tarafıydı: `_tryUnlock`'ta
/// `await`ten sonraki `setState` hiç çalışmadığı için `_busy` true kalıyor,
/// "Kilidi aç" düğmesi ölüyordu. Bir kez iptal eden kullanıcı kendi
/// portföyüne giremiyordu.
void main() {
  /// Üretilen Türkçe sözlük: ekranın doğru ANAHTARI kullandığını ve
  /// anahtarın hâlâ o şeyi söylediğini birlikte doğrular.
  final l = AppLocalizationsTr();

  setUp(() => BiometricLockService.resetForTest(_SahteKilit()));
  tearDown(BiometricLockService.resetForTest);

  Future<void> ekraniAc(
    WidgetTester tester, {
    VoidCallback? acildi,
    VoidCallback? kilidiKapat,
    VoidCallback? cikisYapildi,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LockScreen(
        onUnlocked: acildi ?? () {},
        onKilidiKapat: kilidiKapat ?? () {},
        onCikisYap: cikisYapildi ?? () {},
      ),
    ));
    // initState'teki postFrameCallback + doğrulama turu.
    await tester.pumpAndSettle();
  }

  bool acmaDugmesiEtkin(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  testWidgets('iptal sonrası düğme YENİDEN basılabilir (donma yok)',
      (tester) async {
    _SahteKilit.sonuc = BiyometrikSonuc.iptal;
    await ekraniAc(tester);
    expect(acmaDugmesiEtkin(tester), isTrue,
        reason: 'Donma bu iddianın tersiydi: düğme sonsuza dek devre dışı.');
    expect(find.text(l.lockVerifying), findsNothing);
  });

  testWidgets('servis FIRLATSA bile düğme kilitli kalmaz', (tester) async {
    // Servis sözleşmesi "asla fırlatmaz" diyor; ekran buna GÜVENMEMELİ —
    // donmayı üreten şey tam olarak bu güvendi.
    _SahteKilit.firlat = true;
    await ekraniAc(tester);
    expect(acmaDugmesiEtkin(tester), isTrue);
  });

  testWidgets('başarılı doğrulama kilidi açar', (tester) async {
    _SahteKilit.sonuc = BiyometrikSonuc.basarili;
    var acildi = false;
    await ekraniAc(tester, acildi: () => acildi = true);
    expect(acildi, isTrue);
  });

  testWidgets('cihazda kilit yoksa çıkış yolu görünür', (tester) async {
    _SahteKilit.sonuc = BiyometrikSonuc.kullanilamaz;
    var kapatildi = false;
    await ekraniAc(tester, kilidiKapat: () => kapatildi = true);

    expect(find.text(l.lockNoDeviceCredential), findsOneWidget);
    final cikis = find.text(l.lockDisableAndContinue);
    expect(cikis, findsOneWidget,
        reason: 'Ekran kilidi kaldırılmış cihazda "tekrar dene" sonsuza '
            'kadar aynı sonucu verir; kullanıcı kalıcı olarak dışarıda kalır.');
    await tester.tap(cikis);
    await tester.pump();
    expect(kapatildi, isTrue);
  });

  testWidgets('iptal çıkış yolunu AÇMAZ — kilit kilit olarak kalır',
      (tester) async {
    _SahteKilit.sonuc = BiyometrikSonuc.iptal;
    await ekraniAc(tester);
    expect(find.text(l.lockDisableAndContinue), findsNothing,
        reason: 'Vazgeçmek kilidi kapatmanın yolu olamaz.');
  });

  // ── Başka hesaba geçiş (kullanıcı sorusu 2026-09-23) ────────────────────
  //
  // Zaman aşımı artık `logout()` değil KİLİT uyguluyor: kullanıcı hep KENDİ
  // oturumuna dönüyor. Bu iyileştirmenin yan etkisi, başka bir hesaba
  // geçmenin ekrandan yolunun kalmamasıydı — tek çare Face ID'den geçip
  // Profil'den çıkmaktı, ki Face ID çalışmıyorsa o da yoktu.
  group('başka hesapla giriş', () {
    testWidgets('çıkış yolu DOĞRULAMA BEKLERKEN de görünür', (tester) async {
      // `lockDisableAndContinue`ten farkı bu: o yalnızca cihaz kimseyi
      // doğrulayamaz hâldeyken çıkar. Çıkış her durumda erişilebilir
      // olmalı, çünkü kullanılamaz hâlin dışında da (başkasının telefonu,
      // yanlış hesap) sıkışma yaşanır.
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      await ekraniAc(tester);
      expect(find.text(l.lockSwitchAccount), findsOneWidget);
      expect(find.text(l.lockDisableAndContinue), findsNothing,
          reason: 'iki yol karıştırılmamalı — biri kilidi kapatır, '
              'diğeri oturumu');
    });

    testWidgets('ONAY istenir — tek dokunuşla oturum kaybedilmez',
        (tester) async {
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      var cikildi = false;
      await ekraniAc(tester, cikisYapildi: () => cikildi = true);

      await tester.tap(find.text(l.lockSwitchAccount));
      await tester.pumpAndSettle();
      expect(find.text(l.lockSwitchAccountBody), findsOneWidget);
      expect(cikildi, isFalse, reason: 'onaydan ÖNCE çıkış olmamalı');
    });

    testWidgets('VAZGEÇ oturumu korur', (tester) async {
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      var cikildi = false;
      await ekraniAc(tester, cikisYapildi: () => cikildi = true);

      await tester.tap(find.text(l.lockSwitchAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();

      expect(cikildi, isFalse);
      expect(find.text(l.lockTitle), findsOneWidget,
          reason: 'kilit ekranında kalınmalı');
    });

    testWidgets('onaylanınca çıkış ÇAĞRILIR', (tester) async {
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      var cikildi = false;
      await ekraniAc(tester, cikisYapildi: () => cikildi = true);

      await tester.tap(find.text(l.lockSwitchAccount));
      await tester.pumpAndSettle();
      // Onay düğmesi diyalog BAŞLIĞIYLA aynı metni taşır; ikincisi düğme.
      await tester.tap(find.text(l.lockSwitchAccountTitle).last);
      await tester.pumpAndSettle();
      expect(cikildi, isTrue);
    });

    testWidgets('çıkış kilidi AÇMAZ — onUnlocked tetiklenmez', (tester) async {
      // Güvenlik sınırı: çıkış içeri almanın bir yolu olamaz.
      _SahteKilit.sonuc = BiyometrikSonuc.iptal;
      var acildi = false;
      await ekraniAc(tester, acildi: () => acildi = true);

      await tester.tap(find.text(l.lockSwitchAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.lockSwitchAccountTitle).last);
      await tester.pumpAndSettle();
      expect(acildi, isFalse,
          reason: 'oturumu kapatmak portföyü göstermenin yolu değildir');
    });
  });

  group('LocalAuthException eşlemesi', () {
    BiyometrikSonuc cevir(LocalAuthExceptionCode code) =>
        BiometricLockService.kodaGore(LocalAuthException(code: code));

    test('kullanıcı/sistem vazgeçişi iptaldir, hata değil', () {
      expect(cevir(LocalAuthExceptionCode.userCanceled), BiyometrikSonuc.iptal);
      expect(
          cevir(LocalAuthExceptionCode.systemCanceled), BiyometrikSonuc.iptal);
      expect(cevir(LocalAuthExceptionCode.userRequestedFallback),
          BiyometrikSonuc.iptal);
      expect(cevir(LocalAuthExceptionCode.timeout), BiyometrikSonuc.iptal);
    });

    test('cihazda kilit yoksa "kullanılamaz" — tekrar denemek boşuna', () {
      expect(cevir(LocalAuthExceptionCode.noCredentialsSet),
          BiyometrikSonuc.kullanilamaz);
      expect(cevir(LocalAuthExceptionCode.noBiometricsEnrolled),
          BiyometrikSonuc.kullanilamaz);
      expect(cevir(LocalAuthExceptionCode.noBiometricHardware),
          BiyometrikSonuc.kullanilamaz);
    });

    test('geçici engeller "hata" — sonra ya da PIN ile olur', () {
      expect(cevir(LocalAuthExceptionCode.biometricLockout),
          BiyometrikSonuc.hata);
      expect(
          cevir(LocalAuthExceptionCode.temporaryLockout), BiyometrikSonuc.hata);
      expect(cevir(LocalAuthExceptionCode.uiUnavailable), BiyometrikSonuc.hata);
      expect(
          cevir(LocalAuthExceptionCode.unknownError), BiyometrikSonuc.hata);
    });
  });
}

class _SahteKilit extends BiometricLockService {
  _SahteKilit() : super.forTest();

  static BiyometrikSonuc sonuc = BiyometrikSonuc.iptal;
  static bool firlat = false;

  @override
  Future<bool> get available async => true;

  @override
  Future<BiyometrikSonuc> authenticate({String reason = ''}) async {
    if (firlat) {
      firlat = false;
      throw const LocalAuthException(
          code: LocalAuthExceptionCode.unknownError);
    }
    return sonuc;
  }
}
