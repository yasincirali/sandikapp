import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/ilk_acilis_sirasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Büyüme planı F2 (ilk açılış sırası) ve F11 (kayıt hunisi), 2026-09-29.
///
/// Kapı widget'ı (`_AuthGate`) Supabase + tercih + fiyat turu istediği için
/// testte kurulamaz; karar tablosu saf fonksiyonda (`ilk_acilis_sirasi.dart`)
/// test edilir, kapıya bağlanışı kaynak denetimiyle.
void main() {
  group('kilit teklifi kapısı — bayrak × varlık', () {
    test('bayrak KAPALI: hiçbir durumda ertelenmez (bugünkü davranış)', () {
      for (final varlik in [true, false, null]) {
        expect(
          kilitTeklifiErtelensin(bayrak: false, aktifVarlikVar: varlik),
          isFalse,
          reason: 'aktifVarlikVar=$varlik',
        );
      }
    });

    test('bayrak AÇIK + aktif varlık VAR: teklif gösterilir', () {
      expect(kilitTeklifiErtelensin(bayrak: true, aktifVarlikVar: true),
          isFalse);
    });

    test('bayrak AÇIK + aktif varlık YOK: ertelenir', () {
      expect(kilitTeklifiErtelensin(bayrak: true, aktifVarlikVar: false),
          isTrue);
    });

    test('bayrak AÇIK + portföy BİLİNMİYOR: ertelenir (geri alınamaz olan '
        'yanlış gösterimdir)', () {
      expect(kilitTeklifiErtelensin(bayrak: true, aktifVarlikVar: null),
          isTrue);
    });
  });

  group('kilit teklifi kapısı — main.dart bağlantısı (kaynak)', () {
    final tek =
        ekranKaynagiSync('lib/main.dart').replaceAll(RegExp(r'\s+'), ' ');

    test('erteleme, kilit yöntemi sorgusundan ÖNCE ve teklif dalının içinde',
        () {
      final kosul = tek.indexOf('if (!ref.watch(biometricLockProvider) && '
          '!ref.watch(biometricLockOfferedProvider))');
      final erteleme = tek.indexOf('if (!_kilitTeklifiErtelendi(user.id))');
      final yontem = tek.indexOf('ref.watch(kilitYontemiProvider)');
      expect(kosul, greaterThan(-1));
      expect(erteleme, greaterThan(kosul));
      expect(yontem, greaterThan(erteleme),
          reason: 'ertelenen teklifte splash (yöntem sorgusu) da beklenmemeli');
    });

    test('bayrak kapalıyken portföye bakılmadan false döner', () {
      final fn = tek.substring(tek.indexOf('bool _kilitTeklifiErtelendi('));
      final bayrak = fn.indexOf('if (!bayrak) return false;');
      final portfoy = fn.indexOf('ref.read(portfolioProvider)');
      expect(bayrak, greaterThan(-1));
      expect(portfoy, greaterThan(bayrak));
    });

    test('portföy İZLENMEZ — kayıt anında kök ekran değişmesin', () {
      final fn = tek.substring(tek.indexOf('bool _kilitTeklifiErtelendi('),
          tek.indexOf('Widget _kilitTeklifi('));
      expect(fn.contains('ref.watch('), isFalse,
          reason: 'ilk varlık kaydedildiği an Varlık Ekle açıkken kök '
              'LockOfferScreen\'e dönerdi (işlem ortasında bölme)');
      expect(fn.contains('state.ownerId == userId'), isTrue,
          reason: 'önceki kullanıcının defteri teklif açmasın');
      expect(fn.contains('aktifLotlar('), isTrue,
          reason: 'kapanmış pozisyon "varlık var" sayılmaz');
    });

    test('mandal çıkışta sıfırlanır — yeniden girişte yeniden değerlendirilir',
        () {
      expect(tek.contains('_kilitTeklifiErtelenen = null;'), isTrue);
    });

    test('"bir kez" damgası yalnızca teklif ekranının sonucunda yazılır', () {
      // Erteleme damgalamaz: ertelenen teklif sonraki açılışta gelmeli.
      final fn = tek.substring(tek.indexOf('bool _kilitTeklifiErtelendi('),
          tek.indexOf('Widget _kilitTeklifi('));
      expect(fn.contains('biometricLockOfferedProvider'), isFalse);
    });
  });

  group('kayıt hunisi — home_first_seen (cihaz başına bir kez)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      KayitHunisi.sifirlaTestIcin();
    });

    test('ilk kez: olay gider, cihaz bayrağı yazılır', () async {
      final giden = <String>[];
      final sonuc = await KayitHunisi.anaEkranIlkKez(
          kaydet: (a) async => giden.add(a));
      expect(sonuc, isTrue);
      expect(giden, ['home_first_seen']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(KayitHunisi.anahtar), isTrue);
    });

    test('aynı süreçte ikinci çağrı diske bile gitmez', () async {
      final giden = <String>[];
      await KayitHunisi.anaEkranIlkKez(kaydet: (a) async => giden.add(a));
      final ikinci = await KayitHunisi.anaEkranIlkKez(
          kaydet: (a) async => giden.add(a));
      expect(ikinci, isFalse);
      expect(giden, hasLength(1));
    });

    test('sonraki açılışta (yeni süreç) bayrak varsa gönderilmez', () async {
      SharedPreferences.setMockInitialValues({KayitHunisi.anahtar: true});
      final giden = <String>[];
      final sonuc = await KayitHunisi.anaEkranIlkKez(
          kaydet: (a) async => giden.add(a));
      expect(sonuc, isFalse);
      expect(giden, isEmpty);
    });

    test('olay gönderimi fırlatsa bile kapıya taşmaz', () async {
      final sonuc = await KayitHunisi.anaEkranIlkKez(
          kaydet: (_) async => throw StateError('ağ yok'));
      expect(sonuc, isFalse);
    });
  });

  group('kayıt hunisi — adımlar doğru yerde (kaynak)', () {
    String tek(String yol) =>
        ekranKaynagiSync(yol).replaceAll(RegExp(r'\s+'), ' ');

    test('yedi adımın her biri gönderiliyor', () {
      final yerler = {
        'form_opened': 'lib/screens/register_screen.dart',
        'otp_sent': 'lib/screens/register_screen.dart',
        'otp_verified': 'lib/screens/otp_verification_screen.dart',
        'disclaimer_accepted': 'lib/main.dart',
        'username_set': 'lib/screens/kullanici_adi_screen.dart',
        'tour_done': 'lib/screens/onboarding_screen.dart',
        'home_first_seen': 'lib/services/ilk_acilis_sirasi.dart',
      };
      for (final e in yerler.entries) {
        expect(tek(e.value).contains("'${e.key}'"), isTrue,
            reason: '${e.key} → ${e.value}');
      }
    });

    test('otp_sent kayıt İSTEĞİNDEN sonra — başarısız istek sayılmaz', () {
      final src = tek('lib/screens/register_screen.dart');
      final istek = src.indexOf('await AuthService.instance.register(');
      final olay = src.indexOf("logSignupStep('otp_sent')");
      expect(istek, greaterThan(-1));
      expect(olay, greaterThan(istek));
    });

    test('otp_verified doğrulamadan SONRA; onay olayı yalnız kayıt başarılıysa',
        () {
      final src = tek('lib/screens/otp_verification_screen.dart');
      final dogrulama =
          src.indexOf('await AuthService.instance.verifyRegistrationOtp(');
      expect(src.indexOf("logSignupStep('otp_verified')"),
          greaterThan(dogrulama));
      expect(
          src.contains('if (onayKaydedildi) { unawaited( '
              "AnalyticsService.instance.logSignupStep('disclaimer_accepted'));"),
          isTrue);
    });

    test('username_set yalnız giriş kapısındaki (zorunlu) ad ekranında', () {
      final src = tek('lib/screens/kullanici_adi_screen.dart');
      expect(src.contains('if (zorunlu && s == KullaniciAdiSonuc.uygun)'),
          isTrue,
          reason: 'Ayarlar\'dan ad değiştirmek huninin parçası değil');
    });

    test('home_first_seen build içinde değil, kare sonunda', () {
      final src = tek('lib/main.dart');
      expect(
          src.contains('addPostFrameCallback( (_) => '
              'KayitHunisi.anaEkranIlkKez())'),
          isTrue);
    });
  });
}
