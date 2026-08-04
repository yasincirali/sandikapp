import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';

/// Ağ yokken oturumun korunması.
///
/// **Düzeltilen hata:** uçak modunda uygulama kullanıcıyı LoginScreen'e
/// atıyordu. Sebep iki katmandaydı:
///   1. `AuthService.getSessionUser` → `currentUser` yereldir ve ağsız da
///      doludur, ama ardından `getProfile` ağa gidiyor ve fırlatıyordu.
///      `AuthNotifier` `AsyncError` oluyordu.
///   2. `_AuthGate._resolveScreen` → `auth.valueOrNull` `AsyncError`'da
///      `null` döner ve kod doğrudan `LoginScreen`'e düşüyordu.
///
/// Doğru davranış: token geçerli olduğu sürece kullanıcı oturumdadır;
/// "bağlantını kontrol et" gösterilir ve ağ gelince kaldığı yerden devam
/// edilir.
void main() {
  group('AppUser.fromSession — ağ yokken token\'dan minimal kullanıcı', () {
    test('id ve email token\'dan taşınır', () {
      final u = AppUser.fromSession(
        id: 'user-1',
        email: 'test@example.com',
        displayName: 'Yasin',
        createdAt: '2026-01-01T00:00:00Z',
      );
      expect(u.id, 'user-1');
      expect(u.email, 'test@example.com');
      expect(u.displayName, 'Yasin');
    });

    test('displayName yoksa boş kalır — "profil henüz gelmedi" işareti', () {
      final u = AppUser.fromSession(id: 'user-1', email: 'a@b.com');
      expect(u.displayName, isEmpty);
    });

    test('bozuk createdAt fırlatmaz', () {
      final u = AppUser.fromSession(id: 'user-1', createdAt: 'not-a-date');
      expect(u.createdAt, isA<DateTime>());
    });

    test('email null ise boş string — hiçbir yerde null patlaması olmaz', () {
      final u = AppUser.fromSession(id: 'user-1');
      expect(u.email, isEmpty);
    });
  });

  group('auth gate — ağ hatası oturum yokluğu ile karıştırılmamalı', () {
    // Bu kural `_resolveScreen` içinde yaşıyor ve bir widget testi tüm
    // Supabase/Firebase yığınını ayağa kaldırmayı gerektirirdi. Bunun
    // yerine kararın kaynağı olan kod sözleşmesi doğrulanıyor.
    late String mainSrc;
    late String authSrc;

    setUpAll(() {
      mainSrc = File('lib/main.dart').readAsStringSync();
      authSrc = File('lib/services/auth_service.dart').readAsStringSync();
    });

    test('LoginScreen\'e düşmeden önce hasError + yerel oturum kontrolü var',
        () {
      final gateIdx = mainSrc.indexOf('if (user == null) return const LoginScreen');
      expect(gateIdx, greaterThan(-1), reason: 'auth gate bulunamadı');

      final before = mainSrc.substring(0, gateIdx);
      expect(
        before,
        contains('auth.hasError && AuthService.instance.hasLocalSession'),
        reason: 'ağ hatası hâlâ "oturum yok" gibi ele alınıyor — '
            'kullanıcı uçak modunda login ekranına atılır',
      );
    });

    test('getSessionUser profil hatasında oturumu düşürmez', () {
      final start = authSrc.indexOf('Future<AppUser?> getSessionUser()');
      expect(start, greaterThan(-1));
      final body = authSrc.substring(start, start + 700);
      expect(body, contains('catch'));
      expect(body, contains('AppUser.fromSession'),
          reason: 'profil çekilemediğinde token\'daki bilgiyle devam '
              'edilmeli, null dönülmemeli');
    });

    test('hasLocalSession tamamen yerel — ağ çağrısı içermez', () {
      final start = authSrc.indexOf('bool get hasLocalSession');
      expect(start, greaterThan(-1));
      final body = authSrc.substring(start, authSrc.indexOf(';', start));
      expect(body, contains('currentSession'));
      expect(body, isNot(contains('await')));
    });

    test('ağ gelince oturum yeniden denenir (lifecycle)', () {
      expect(
        mainSrc,
        contains('ref.invalidate(authProvider)'),
        reason: 'öne dönüldüğünde oturum tazelenmezse kullanıcı elle '
            '"Tekrar Dene"ye basmak zorunda kalır',
      );
    });
  });

  group('disclaimer — offline\'da kilitlenmemeli', () {
    test('ağ hatasında cihazdaki kalıcı ize düşer, koşulsuz false değil', () {
      final src = File('lib/services/disclaimer_service.dart').readAsStringSync();
      final start = src.indexOf('Future<bool> hasAccepted');
      final body = src.substring(start, src.indexOf('\n  }', start));

      expect(body, contains('_deviceKey'),
          reason: 'ağ hatasında cihaz izine bakılmalı');
      // Onaylamamış kullanıcı için varsayılan hâlâ false olmalı —
      // hukuki kapı zayıflatılmamalı.
      expect(body, contains('?? false'));
    });

    test('onay kaydedilirken cihaza da yazılır', () {
      final src = File('lib/services/disclaimer_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> recordAcceptance');
      final body = src.substring(start, src.indexOf('\n  /// Kullanıcının', start));
      expect(body, contains('setBool(_deviceKey'),
          reason: 'iz yazılmazsa ilk offline açılışta disclaimer tekrar çıkar');
    });
  });
}
