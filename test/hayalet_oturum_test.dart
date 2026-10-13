import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/kaynak.dart';

/// yasin'in hata bildirimi (2026-10-13): *"login ekranında yanlış şifre
/// girilmesine rağmen giriş yapıyor"*.
///
/// Yol: çıkış, gotrue'nun arkada süren token yenilemesiyle yarışınca
/// yenileme oturumu geri yazıyordu (hayalet oturum). Uygulama giriş
/// ekranını gösterirken istemcide geçerli oturum duruyordu; yanlış şifre
/// `AsyncError` üretince `_AuthGate` bunu "çevrimdışı" sanıp yeniden
/// deniyor ve hayaletle içeri alıyordu. Bkz. `AuthService` "Çıkış bekçisi".
void main() {
  final cikis = DateTime(2026, 10, 13, 12);

  bool hayalet(AuthChangeEvent olay, String? uid,
          {String? cikan = 'u1', Duration sonra = const Duration(seconds: 3)}) =>
      AuthService.hayaletYenilemeMi(
        olay: olay,
        oturumUid: uid,
        cikanUid: cikan,
        cikisZamani: cikis,
        simdi: cikis.add(sonra),
      );

  group('çıkış bekçisi', () {
    test('çıkıştan hemen sonra AYNI hesabın yenilemesi hayalettir', () {
      expect(hayalet(AuthChangeEvent.tokenRefreshed, 'u1'), isTrue);
    });

    test('başka hesabın yenilemesi değil (hesap geçişi)', () {
      expect(hayalet(AuthChangeEvent.tokenRefreshed, 'u2'), isFalse);
    });

    test('gerçek yeniden giriş (signedIn) hayalet sayılmaz', () {
      expect(hayalet(AuthChangeEvent.signedIn, 'u1'), isFalse);
    });

    test('pencere dışında hayalet sayılmaz', () {
      expect(
          hayalet(AuthChangeEvent.tokenRefreshed, 'u1',
              sonra: const Duration(minutes: 5)),
          isFalse);
    });

    test('bekçi kurulmamışsa (çıkış yok) hiçbir şey hayalet değil', () {
      expect(hayalet(AuthChangeEvent.tokenRefreshed, 'u1', cikan: null),
          isFalse);
    });

    test('kaynak: logout bekçiyi signOut ÖNCESİ kurar', () {
      final tek = ekranKaynagiSync('lib/services/auth_service.dart')
          .replaceAll(RegExp(r'\s+'), ' ');
      final kur = tek.indexOf('_bekciyiKur(uid);');
      final cik = tek.indexOf('call: () => _client.auth.signOut(),');
      expect(kur, greaterThan(-1));
      expect(cik, greaterThan(kur),
          reason: 'yenileme signOut sırasında da dönebilir');
    });
  });

  group('başarısız giriş hiçbir oturuma kapı açmaz', () {
    test('kaynak: e-posta ve sosyal giriş hatası yerel oturumu temizler', () {
      final tek = ekranKaynagiSync('lib/providers/auth_provider.dart')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
          RegExp(r'AuthService\.instance\.hayaletOturumuTemizle\(\)')
              .allMatches(tek)
              .length,
          2,
          reason: 'login() ve loginWithSocial() hata dalları');
      final hata = tek.indexOf('if (state.hasError) {');
      expect(hata, greaterThan(-1));
      expect(tek.indexOf('hayaletOturumuTemizle', hata), greaterThan(hata));
    });
  });
}
