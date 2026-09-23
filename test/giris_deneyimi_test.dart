import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı istekleri (2026-09-23):
///
/// - [x] Güncelleme sonrasında da şifre beklememeli
/// - [x] Login sayfasında klavye kapatılabilir olmalı — dışa tıklandığında
/// - [x] Login ekranında Face ID yapıldıysa otomatik login olmalı
void main() {
  group('1) GÜNCELLEME sonrası şifre İSTENMEZ', () {
    /// `_AuthGateState._readStaleSessionAtLaunch` ile AYNI kural.
    ///
    /// Zaman aşımı bir GÜVENLİK özelliğidir: cihaz başkasının eline geçerse
    /// 10 dakika sonra oturum düşer. Ama güncelleme de aynı belirtiyi
    /// üretiyordu — kullanıcı cihazın başındayken:
    ///
    ///   1. Uygulama arkaya alınır → damga yazılır
    ///   2. Mağaza güncellemeyi kurar → süreç öldürülür
    ///   3. Kullanıcı açar → 10 dk geçmişse ŞİFRE İSTENİR
    ///
    /// Gece kurulan otomatik güncellemelerde aradaki süre SAATLERDİR.
    ///
    /// **Bu grup ŞİFRE sorusunu ölçer, kilidi değil (2026-09-23).**
    /// Güncelleme artık `BayatlikKarari.kilit` döner: oturum korunur,
    /// yalnızca Face ID istenir. Şifre hiçbir güncelleme yolunda
    /// istenmez — asıl istek buydu. Üç değerli kararın tamamı
    /// `kilit_push_surekliligi_test.dart` içinde.
    bool oturumDusurulsunMu({
      required Duration gecenSure,
      required String? eskiSurum,
      required String? simdikiSurum,
      Duration timeout = const Duration(minutes: 10),
    }) {
      if (eskiSurum != null &&
          simdikiSurum != null &&
          simdikiSurum != eskiSurum) {
        return false; // güncelleme — terk ediş değil, oturum DÜŞMEZ
      }
      return gecenSure >= timeout;
    }

    test('sürüm DEĞİŞTİYSE uzun boşluk oturumu düşürmez', () {
      expect(
          oturumDusurulsunMu(
            gecenSure: const Duration(hours: 8), // gece güncellemesi
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.7+8',
          ),
          isFalse,
          reason: 'kullanıcı cihazın başında — güncelleme şifre istememeli');
    });

    test('AYNI sürümde uzun boşluk oturumu DÜŞÜRÜR (güvenlik korunur)', () {
      expect(
          oturumDusurulsunMu(
            gecenSure: const Duration(hours: 8),
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.6+7',
          ),
          isTrue,
          reason: 'gerçek terk ediş — cihaz başkasının elinde olabilir');
    });

    test('kısa boşluk hiçbir durumda düşürmez', () {
      for (final (eski, yeni) in [
        ('1.1.6+7', '1.1.6+7'),
        ('1.1.6+7', '1.1.7+8'),
      ]) {
        expect(
            oturumDusurulsunMu(
              gecenSure: const Duration(minutes: 3),
              eskiSurum: eski,
              simdikiSurum: yeni,
            ),
            isFalse);
      }
    });

    test('BUILD numarası da sayılır — TestFlight güncellemeleri', () {
      // fastlane her TestFlight yüklemesinde yalnızca build'i artırıyor.
      // Sadece `version` karşılaştırılsaydı bunlar "aynı sürüm" sanılırdı.
      expect(
          oturumDusurulsunMu(
            gecenSure: const Duration(hours: 2),
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.6+8', // aynı version, yeni build
          ),
          isFalse,
          reason: 'TestFlight güncellemesi de güncellemedir');
    });

    test('sürüm OKUNAMAZSA güvenli tarafa düşülür', () {
      expect(
          oturumDusurulsunMu(
            gecenSure: const Duration(hours: 8),
            eskiSurum: '1.1.6+7',
            simdikiSurum: null, // PackageInfo hata verdi
          ),
          isTrue,
          reason: 'karar verilemiyorsa zaman aşımı uygulanır');
    });

    test('eski damga YOKSA (ilk kurulum) eski davranış', () {
      expect(
          oturumDusurulsunMu(
            gecenSure: const Duration(hours: 8),
            eskiSurum: null,
            simdikiSurum: '1.1.6+7',
          ),
          isTrue);
    });

    test('kaynak: sürüm damgası yazılıyor ve okunuyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('PrefKeys.backgroundedAtVersion'), isTrue,
          reason: 'sürüm damgası olmadan güncelleme ayırt edilemez');
      expect(
          tek.contains('if (simdikiSurum != null && simdikiSurum != eskiSurum) '
              '{ return BayatlikKarari.kilit; }'),
          isTrue,
          reason: 'sürüm değiştiyse oturum korunmalı — çıkış değil kilit');
      expect(tek.contains("return '\${bilgi.version}+\${bilgi.buildNumber}';"),
          isTrue,
          reason: 'build numarası dahil edilmeli (TestFlight)');
    });
  });

  group('1b) ZAMAN AŞIMI: biyometrik açıksa ÇIKIŞ DEĞİL KİLİT', () {
    // Kullanıcı isteği (2026-09-23): *"Cihaz/müşteri eşleşmesi varsa ve
    // son login olan hesap biyolojik login işaretlediyse Face ID ile login
    // olunmalı."*
    //
    // `logout()` Supabase oturumunu SİLER — token kasadan kalkar ve Face ID
    // onu geri getiremez. Kilit ise token'ı yerinde bırakır; Face ID açar.

    /// İki daldaki (resumed + soğuk açılış) kuralın özeti.
    String zamanAsimiDavranisi({
      required bool biyometrikAcik,
      required bool oturumVar,
    }) {
      if (biyometrikAcik && oturumVar) return 'kilit';
      return 'cikis';
    }

    test('biyometrik AÇIK → KİLİT (token kasada kalır)', () {
      expect(
          zamanAsimiDavranisi(biyometrikAcik: true, oturumVar: true), 'kilit',
          reason: 'Face ID ile geri dönebilmek için token SİLİNMEMELİ');
    });

    test('biyometrik KAPALI → ÇIKIŞ (eski davranış korunur)', () {
      expect(
          zamanAsimiDavranisi(biyometrikAcik: false, oturumVar: true), 'cikis',
          reason: 'kilit yoksa uygulama korumasız kalırdı');
    });

    test('oturum YOKSA kilitlenecek bir şey de yok', () {
      expect(
          zamanAsimiDavranisi(biyometrikAcik: true, oturumVar: false), 'cikis');
    });

    test('kaynak: RESUMED dalı kilitliyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('final biyometrikAcik = ref.read(biometricLockProvider); '
              'if (biyometrikAcik && ref.read(authProvider).valueOrNull != null) '
              '{ setState(() => _locked = true); } else {'),
          isTrue,
          reason: 'zaman aşımı biyometrik açıkken çıkış yapmamalı');
    });

    test('kaynak: SOĞUK AÇILIŞ dalı da kilitliyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('if (ref.read(biometricLockProvider)) { '
              'setState(() => _locked = true); } else { '
              'ref.read(authProvider.notifier).logout(); }'),
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
      expect(tek.contains('final VoidCallback onCikisYap;'), isTrue);
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
