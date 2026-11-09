import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı istekleri (2026-09-23):
///
/// - [x] Güncelleme sonrasında da şifre beklememeli (2026-10-13: hiçbir
///   boşluk sonrasında şifre istenmez)
/// - [x] Login sayfasında klavye kapatılabilir olmalı — dışa tıklandığında
/// - [x] Login ekranında Face ID yapıldıysa otomatik login olmalı
void main() {
  group('1) UZUN BOŞLUK oturumu KAPATMAZ (2026-10-13)', () {
    /// yasin'in hata bildirimi (2026-10-13): *"kapalı betada uzun süre
    /// bekleyen session kapanıyor ve login ekranına yönlendiriyor"*.
    ///
    /// Eskiden kilidi kapalı kullanıcı 10 dk arkada kalınca (ya da süreç
    /// arkada öldürülüp damga 10 dk'yı geçmiş bulununca) `logout()` ile
    /// çıkarılıyordu. Artık hiçbir boşluk şifre İSTEMEZ: kilit açıksa
    /// Face ID / ekran kilidi sorulur, kapalıysa hiçbir şey sorulmaz.
    /// Güncelleme ayrımı (`BayatlikKarari.kilit`) kalıyor ama sonucu
    /// `bayat` ile aynıdır; üç değerli karar `kilit_push_surekliligi_test`.
    String boslukSonrasi({
      required Duration gecenSure,
      required bool kilitAcik,
      Duration esik = const Duration(minutes: 10),
    }) {
      if (gecenSure < esik) return 'serbest';
      return kilitAcik ? 'kilit' : 'serbest';
    }

    test('kilit KAPALI: 8 saatlik boşluk bile çıkış yapmaz', () {
      expect(
          boslukSonrasi(gecenSure: const Duration(hours: 8), kilitAcik: false),
          'serbest',
          reason: 'Android süreci arkada öldürüyor — her uzun beklemede '
              'giriş ekranı geliyordu');
    });

    test('kilit AÇIK: uzun boşluk kilitler (token kasada kalır)', () {
      expect(
          boslukSonrasi(gecenSure: const Duration(hours: 8), kilitAcik: true),
          'kilit');
    });

    test('kısa boşluk hiçbir durumda bir şey sormaz', () {
      for (final kilit in [true, false]) {
        expect(
            boslukSonrasi(
                gecenSure: const Duration(minutes: 3), kilitAcik: kilit),
            'serbest');
      }
    });

    test('kaynak: _AuthGate hiçbir zaman aşımı dalında logout ÇAĞIRMAZ', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      // Soğuk açılış dalı: `_staleSessionAtLaunch.then` gövdesi.
      final soguk = tek.indexOf('_staleSessionAtLaunch.then((karar) {');
      final sogukSonu = tek.indexOf('});', soguk);
      expect(soguk, greaterThan(-1));
      expect(tek.substring(soguk, sogukSonu).contains('.logout();'), isFalse,
          reason: 'süreç arkada öldürülünce kullanıcı sessizce çıkarılıyordu');
      // Öne dönüş dalı: `resumed` ile `build` arası.
      final on = tek.indexOf('state == AppLifecycleState.resumed');
      final onSonu = tek.indexOf('Widget build(BuildContext context)', on);
      expect(on, greaterThan(-1));
      expect(tek.substring(on, onSonu).contains('.logout();'), isFalse,
          reason: '10 dk arkada kalan kilitsiz kullanıcı çıkarılıyordu');
      expect(tek.contains('sessionTimedOut'), isFalse,
          reason: 'zaman aşımı çıkışı yok — mesajı da yok');
    });

    test('kaynak: uzun boşluk hesap geçişinin cihaz doğrulamasını düşürür', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('if (bosluk != null && bosluk >= _sessionTimeout) { '
              'HesapGecisi.instance.cihazDogrulandi = false; }'),
          isTrue,
          reason: 'başındaki kişi değişmiş olabilir; geçiş yeniden sorar');
    });

    test('kaynak: sürüm damgası yazılıyor ve okunuyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('PrefKeys.backgroundedAtVersion'), isTrue);
      expect(
          tek.contains('if (simdikiSurum != null && simdikiSurum != eskiSurum) '
              '{ return BayatlikKarari.kilit; }'),
          isTrue);
      expect(tek.contains("return '\${bilgi.version}+\${bilgi.buildNumber}';"),
          isTrue,
          reason: 'build numarası dahil edilmeli (TestFlight)');
    });
  });

  group('1b) Biyometrik açıksa uzun boşluk KİLİTLER', () {
    // Kullanıcı isteği (2026-09-23): *"son login olan hesap biyolojik
    // login işaretlediyse Face ID ile login olunmalı."*

    test('kaynak: RESUMED dalı kilitliyor ve tazelemeleri atlamıyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      final kilit = tek.indexOf('bosluk >= _lockAfter && '
          'ref.read(biometricLockProvider) && '
          'ref.read(authProvider).valueOrNull != null) { '
          'HesapGecisi.instance.cihazDogrulandi = false; '
          'setState(() => _locked = true); }');
      expect(kilit, greaterThan(-1));
      // Eskiden uzun boşluk ayrı daldaydı ve alarm/bildirim merkezi
      // tazelemesine hiç ulaşmıyordu.
      final tazele = tek.indexOf(
          'ref.read(appNotificationProvider.notifier).refresh()', kilit);
      expect(tazele, greaterThan(kilit));
    });

    test('kaynak: SOĞUK AÇILIŞ dalı kilit açıksa kilitliyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('if (ref.read(biometricLockProvider)) { '
              'setState(() => _locked = true); } });'),
          isTrue,
          reason: 'süreç arkada öldürülmüşse bu dala düşülür');
    });

    test('SIRALAMA: tercih kullanıcıya BAĞLANDIKTAN sonra okunur', () {
      // `biometricLockProvider` kişiye özel (`perUser: true`), anahtarı
      // `..._<userId>`. Bağlama yapılmadan okunursa önceki kullanıcının
      // (ya da varsayılanın) değeri gelir ve karar YANLIŞ verilir.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      final bagla = tek.indexOf('setPreferencesUser(user.id);');
      final oku = tek.indexOf('_staleSessionAtLaunch.then(');
      expect(bagla, greaterThan(-1));
      expect(oku, greaterThan(-1));
      expect(bagla, lessThan(oku),
          reason: 'tercih bağlanmadan okunursa yanlış kullanıcının ayarı gelir');
    });
  });

  group('1c) KİLİT ekranından başka hesaba geçilebilir', () {
    // Kullanıcı sorusu (2026-09-23): *"peki başka bir hesaba girmek istersem
    // bu akış nasıl çalışır"*.
    //
    // 1b'deki düzeltme (çıkış yerine kilit) kullanıcıyı HEP kendi oturumuna
    // döndürüyor. Kilit ekranında çıkış yolu yoktu; başka hesaba geçmek için
    // önce Face ID'den geçip Profil'e gitmek gerekiyordu — Face ID
    // çalışmıyorsa hiç mümkün değildi.

    test('kaynak: LockScreen çıkış geri çağrısı ALIR', () {
      final src = ekranKaynagiSync('lib/screens/lock_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      // `FutureOr`: çıkış isteği bitene dek düğme yükleniyor gösterir
      // (tek yükleniyor davranışı, 2026-10-08).
      expect(tek.contains('final FutureOr<void> Function() onCikisYap;'),
          isTrue);
      expect(tek.contains('onPressed: _busy ? null : _cikisiOnayla,'), isTrue,
          reason: 'düğme onay akışına bağlı olmalı');
    });

    test('kaynak: düğme KOŞULSUZ — kullanilamaz kapısının DIŞINDA', () {
      // `lockDisableAndContinue` kasıtlı olarak koşulludur; çıkış değildir.
      final src = ekranKaynagiSync('lib/screens/lock_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      final kapi = tek.indexOf('if (_sonSonuc == BiyometrikSonuc.kullanilamaz)');
      final kapiSonu = tek.indexOf('],', kapi);
      final cikis = tek.indexOf('context.l10n.lockSwitchAccount)');
      expect(kapi, greaterThan(-1));
      expect(cikis, greaterThan(kapiSonu),
          reason: 'çıkış düğmesi koşullu bloğun İÇİNDE kalmamalı');
    });

    test('kaynak: main.dart çıkışı bağlıyor ve oturumu SİLİYOR', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('onCikisYap: () async { '
              'await ref.read(authProvider.notifier).logout();'),
          isTrue,
          reason: 'başka hesaba geçmek oturumun gerçekten kapanmasını ister');
    });

    test('kaynak: soğuk açılış kilit damgası SIFIRLANIYOR', () {
      // `_lockAtLaunchFor` kullanıcı başına "kilit soruldu" damgasıdır.
      // Sıfırlanmazsa sıradaki kullanıcı için karar önceki oturumdan
      // devralınırdı.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('_lockAtLaunchFor = null;'), isTrue);
    });
  });

  group('2) Login: dışa tıklayınca KLAVYE kapanır', () {
    test('GestureDetector boş alanı yakalar', () {
      final src = ekranKaynagiSync('lib/screens/login_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('child: GestureDetector( behavior: '
              'HitTestBehavior.opaque, onTap: () => '
              'FocusScope.of(context).unfocus(),'),
          isTrue,
          reason: 'iOS\'ta form dışına dokunmak klavyeyi kapatır; '
              'kullanıcı bunu bekler');
    });

    test('opaque ŞART — deferToChild boş alanı kaçırır', () {
      // Varsayılan davranış yalnızca ÇOCUĞUN kapladığı piksellerde dokunuş
      // alır; boş alan tam da çocuğun OLMADIĞI yerdir.
      final src = ekranKaynagiSync('lib/screens/login_screen.dart');
      expect(src.contains('HitTestBehavior.opaque'), isTrue);
    });
  });

  group('3) Face ID yapıldıysa OTOMATİK giriş', () {
    test('LockScreen açılışta biyometriği KENDİ İSTER', () {
      // Kullanıcının ayrıca düğmeye basması gerekmez.
      final src = ekranKaynagiSync('lib/screens/lock_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('WidgetsBinding.instance.addPostFrameCallback((_) => '
              '_tryUnlock());'),
          isTrue,
          reason: 'ilk karede otomatik sorulmalı');
    });

    test('başarılı doğrulama KİLİDİ AÇAR', () {
      final src = ekranKaynagiSync('lib/screens/lock_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('if (sonuc.basariliMi) widget.onUnlocked();'), isTrue,
          reason: 'Face ID geçtiyse içeri alınmalı');
    });

    test('oturum Keychain/Keystore\'da — şifre yeniden istenmez', () {
      // Face ID "giriş" değil KİLİT AÇMA'dır; oturum zaten kasada.
      final src = ekranKaynagiSync('lib/services/secure_session_storage.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('class SecureSessionStorage extends LocalStorage'),
          isTrue);
      expect(tek.contains('_vault.read(persistSessionKey)'), isTrue,
          reason: 'token kasadan okunur, SharedPreferences\'tan değil');
    });
  });
}
