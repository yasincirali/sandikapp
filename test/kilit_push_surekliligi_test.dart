import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// **Kilit push'u KESMEZ** (kullanıcı kararı, 2026-09-23):
/// *"son login olan userın pushları kesilmemeli bu bizim önümüzü keser"*.
///
/// ## Neden kırılgan
/// `logout()` push token'ını SUNUCUDAN siler
/// (`RemotePushService.stop()` → `deletePushToken`). Bu kasıtlıdır:
/// çıkmış kullanıcının bildirimleri telefona düşmeye devam ederse, aynı
/// telefonu kullanan başkası onun portföy hareketlerini görür.
///
/// Ama bu, zaman aşımını `logout()` ile çözen her yolun push'u da
/// öldürdüğü anlamına gelir. Kilit bu yüzden var: oturum yerinde kalır,
/// yalnızca perde iner.
///
/// Bu davranış şu an DOĞRU ama kazara doğru — hiçbir test "kilit yolu
/// push'a dokunmaz" demiyordu. Birisi ileride kilit dalına temizlik
/// amacıyla `stop()` eklerse bildirimler sessizce susardı ve bunu ancak
/// kullanıcı fark ederdi.
void main() {
  group('push yalnızca GERÇEK çıkışta durur', () {
    test('stop() çağrıları sayılı ve hepsi çıkış/oturum-yok dalında', () {
      // Sayı ARTARSA bu test kasıtlı olarak kırılır: yeni bir `stop()`
      // eklendiğinde hangi dalda olduğu elle doğrulanmalı.
      final auth = ekranKaynagiSync('lib/providers/auth_provider.dart');
      final main = ekranKaynagiSync('lib/main.dart');

      final authStop = RegExp(r'RemotePushService\.instance\.stop\(\)')
          .allMatches(auth)
          .length;
      final mainStop = RegExp(r'RemotePushService\.instance\.stop\(\)')
          .allMatches(main)
          .length;

      expect(authStop, 2,
          reason: 'auth_provider: yalnızca logout() ve deleteAccount()');
      expect(mainStop, 2,
          reason: 'main: yalnızca userId==null ve push kullanılamaz dalı');
    });

    test('KİLİT dalları push servisine HİÇ dokunmaz', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');

      // Kilitleyen üç ifade — hiçbirinin yanında push durdurma olmamalı.
      // `setState(() => _locked = true)` ile aynı ifadede `stop` geçerse
      // birisi kilit yoluna temizlik eklemiş demektir.
      final kilitler = RegExp(r'setState\(\(\) => _locked = true\)')
          .allMatches(tek)
          .length;
      expect(kilitler, greaterThanOrEqualTo(3),
          reason: 'resumed + soğuk açılış + güncelleme dalı');

      // Kaba ama etkili: `_locked = true` ile `RemotePushService` aynı
      // 200 karakterlik pencerede görünmemeli.
      for (final m
          in RegExp(r'setState\(\(\) => _locked = true\)').allMatches(tek)) {
        final bas = (m.start - 100).clamp(0, tek.length);
        final son = (m.end + 100).clamp(0, tek.length);
        expect(tek.substring(bas, son).contains('RemotePushService'), isFalse,
            reason: 'kilit dalında push durdurma var — bildirimler susar');
      }
    });

    test('GÜNCELLEME dalı logout ÇAĞIRMAZ (push korunur)', () {
      // Güncelleme sonrası `logout()` çağrılsaydı kullanıcı hem şifre
      // girerdi hem de push token'ı silinirdi — iki kayıp birden.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      final dal = tek.indexOf('if (karar == BayatlikKarari.kilit)');
      expect(dal, greaterThan(-1), reason: 'güncelleme dalı bulunamadı');
      final dalSonu = tek.indexOf('return; }', dal);
      expect(dalSonu, greaterThan(dal));
      expect(tek.substring(dal, dalSonu).contains('logout()'), isFalse,
          reason: 'güncelleme dalında çıkış olmamalı');
    });
  });

  group('BayatlikKarari üç sonucu da ayırır', () {
    /// `_readStaleSessionAtLaunch` ile AYNI kural.
    String karar({
      required Duration gecenSure,
      required String? eskiSurum,
      required String? simdikiSurum,
      Duration timeout = const Duration(minutes: 10),
    }) {
      if (gecenSure < timeout) return 'serbest';
      if (eskiSurum != null &&
          simdikiSurum != null &&
          simdikiSurum != eskiSurum) {
        return 'kilit';
      }
      return 'bayat';
    }

    test('güncelleme → KİLİT (şifre değil Face ID)', () {
      // Kullanıcı isteği (2026-09-23): *"güncelleme falan geldiğinde de
      // yeniden şifre sormak yerine yine face id ile login yaptırılabilir"*.
      expect(
          karar(
            gecenSure: const Duration(hours: 8),
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.7+8',
          ),
          'kilit',
          reason: 'eskiden "serbest"ti — hiçbir şey sorulmuyordu');
    });

    test('aynı sürümde uzun boşluk → BAYAT (gerçek terk ediş)', () {
      expect(
          karar(
            gecenSure: const Duration(hours: 8),
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.6+7',
          ),
          'bayat');
    });

    test('kısa boşluk → SERBEST (sürüm fark etmez)', () {
      for (final yeni in ['1.1.6+7', '1.1.7+8']) {
        expect(
            karar(
              gecenSure: const Duration(minutes: 3),
              eskiSurum: '1.1.6+7',
              simdikiSurum: yeni,
            ),
            'serbest');
      }
    });

    test('TestFlight build bump\'ı da güncellemedir', () {
      expect(
          karar(
            gecenSure: const Duration(hours: 2),
            eskiSurum: '1.1.6+7',
            simdikiSurum: '1.1.6+8',
          ),
          'kilit');
    });

    test('sürüm okunamazsa BAYAT — güvenli taraf', () {
      expect(
          karar(
            gecenSure: const Duration(hours: 8),
            eskiSurum: '1.1.6+7',
            simdikiSurum: null,
          ),
          'bayat');
    });

    test('kaynak: enum üç değeri de taşıyor ve güncelleme kilit dönüyor', () {
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(src.contains('enum BayatlikKarari {'), isTrue);
      for (final deger in ['serbest,', 'kilit,', 'bayat,']) {
        expect(src.contains('  $deger'), isTrue, reason: '$deger eksik');
      }
      expect(
          tek.contains('if (simdikiSurum != null && simdikiSurum != eskiSurum) '
              '{ return BayatlikKarari.kilit; }'),
          isTrue,
          reason: 'güncelleme artık "hiçbir şey sorma" değil');
    });

    test('kaynak: kilit KAPALIYSA güncelleme hiçbir şey sormaz', () {
      // Asıl istek buydu: *"güncelleme sonrasında da şifre beklememeli"*.
      // Kilidi kapalı kullanıcıya güncelleme sonrası şifre sormak o
      // isteği geri almak olurdu.
      final src = ekranKaynagiSync('lib/main.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('if (karar == BayatlikKarari.kilit) { '
              'if (ref.read(biometricLockProvider)) { '
              'setState(() => _locked = true); } return; }'),
          isTrue,
          reason: 'kilit kapalıysa dal sessizce geçilmeli');
    });
  });
}
