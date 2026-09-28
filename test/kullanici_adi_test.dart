// Kullanıcı adı (0079, 2026-09-28) — kilitlenen kararlar:
//  1. İstemci biçim kuralı sunucununkiyle AYNI regex (karar sunucuda,
//     istemci yalnız anında gösterir; ayrışırsa ekran "uygun" der, sunucu
//     reddeder).
//  2. Zorunlu ekran yalnız adı gerçekten OLMAYAN profilde açılır; ağsız
//     kurulan eksik profilde ya da 0079 öncesi önbellekte açılmaz.
//  3. Kullanıcı adı görünen addır (sunucu tetikleyicisiyle aynı kural).
//  4. Giriş kapısı yasal onaydan sonra, tanıtım turundan önce.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/kullanici_adi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/screens/kullanici_adi_screen.dart';
import 'package:portfoy_takip/services/auth_service.dart';

import 'helpers/kaynak.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);
  final AppUser user;
  @override
  Future<AppUser?> build() async => user;
}

void main() {
  group('bicimDenetle', () {
    for (final ad in ['yasin', 'Işık', 'Ahmet_1990', 'ay.se', 'abc', 'Çağrı.K']) {
      test('geçer: $ad', () => expect(KullaniciAdi.bicimDenetle(ad), isNull));
    }
    for (final ad in [
      '', 'ab', 'ali veli', '1ali', '_ali', 'ali.', 'al..i', 'al._i',
      'ali-veli', 'Мария', 'a' * 21,
    ]) {
      test('reddedilir: "$ad"', () {
        expect(KullaniciAdi.bicimDenetle(ad), KullaniciAdiSonuc.bicim);
      });
    }
  });

  test('istemci regex sunucu migration\'ıyla aynı', () {
    final sql = File('supabase/migrations/0079_kullanici_adi.sql').readAsStringSync();
    final sunucu = RegExp(r"ad !~ '([^']+)'").firstMatch(sql)!.group(1)!;
    final istemci = File('lib/models/kullanici_adi.dart').readAsStringSync();
    expect(istemci.contains("r'$sunucu'"), isTrue,
        reason: 'Sunucu biçimi: $sunucu');
  });

  group('oneri', () {
    test('ad soyad → noktalı', () {
      expect(KullaniciAdi.oneri('Yasin Dirali'), 'Yasin.Dirali');
    });
    test('biçime uymayan karakterler atılır', () {
      expect(KullaniciAdi.oneri('  Ayşe  (Yılmaz)! '), 'Ayşe.Yılmaz');
    });
    test('uzun ad 20 karaktere kırpılır, ayraçla bitmez', () {
      final o = KullaniciAdi.oneri('Abdurrahman Muhammed Ali');
      expect(o.length, lessThanOrEqualTo(20));
      expect(KullaniciAdi.bicimDenetle(o), isNull);
    });
    test('anlamsız kaynak → boş (öneri yok)', () {
      expect(KullaniciAdi.oneri('12'), '');
      expect(KullaniciAdi.oneri(''), '');
    });
  });

  test('sonucCoz', () {
    expect(KullaniciAdi.sonucCoz('ok'), KullaniciAdiSonuc.uygun);
    expect(KullaniciAdi.sonucCoz('alinmis'), KullaniciAdiSonuc.alinmis);
    expect(KullaniciAdi.sonucCoz('uygunsuz'), KullaniciAdiSonuc.uygunsuz);
    expect(KullaniciAdi.sonucCoz('ayrilmis'), KullaniciAdiSonuc.ayrilmis);
    expect(KullaniciAdi.sonucCoz('profil_yok'), KullaniciAdiSonuc.bilinmiyor);
    expect(KullaniciAdi.sonucCoz(null), KullaniciAdiSonuc.bilinmiyor);
  });

  group('kullaniciAdiGerekli', () {
    final sunucudan = AppUser.fromSupabase({
      'id': 'u1',
      'email': 'a@b.c',
      'display_name': 'Eski Ad',
      'username': null,
    });

    test('sunucu profilinde ad yok → gerekli', () {
      expect(sunucudan.kullaniciAdiGerekli, isTrue);
    });

    test('ad seçilmiş → gerekli değil', () {
      final u = AppUser.fromSupabase({
        'id': 'u1', 'email': 'a@b.c', 'display_name': 'yasin', 'username': 'yasin',
      });
      expect(u.kullaniciAdiGerekli, isFalse);
    });

    test('sunucuda kolon yok (0079 deploy edilmemiş) → sorulmaz', () {
      final u = AppUser.fromSupabase(
          {'id': 'u1', 'email': 'a@b.c', 'display_name': 'Eski Ad'});
      expect(u.kullaniciAdiGerekli, isFalse);
    });

    test('ağsız eksik profil → sorulmaz', () {
      expect(AppUser.fromSession(id: 'u1').kullaniciAdiGerekli, isFalse);
    });

    test('0079 öncesi önbellek (anahtar yok) → sorulmaz, tazeleme karar verir', () {
      final eski = jsonEncode({
        'id': 'u1', 'email': 'a@b.c', 'display_name': 'Ayşe',
        'onboarding_completed': true, 'created_at': 0,
      });
      final u = AuthService.profilOnbellektenCoz(eski, 'u1')!;
      expect(u.eksikProfil, isTrue);
      expect(u.kullaniciAdiGerekli, isFalse);
      // Tazelenen profil farklı sayılır → state'e yazılır.
      expect(AuthNotifier.ayniProfil(u, sunucudan), isFalse);
    });

    test('yeni önbellek adı taşır', () {
      final secilmis = sunucudan.copyWith(username: 'ayse.k');
      final u = AuthService.profilOnbellektenCoz(
          jsonEncode(secilmis.toMap()), 'u1')!;
      expect(u.username, 'ayse.k');
      expect(u.kullaniciAdiGerekli, isFalse);
    });
  });

  test('kullanıcı adı görünen addır', () {
    final u = AppUser(
      id: 'u1', email: 'a@b.c', displayName: 'Eski Ad', createdAt: DateTime(2026),
    ).copyWith(username: 'yeni_ad');
    expect(u.displayName, 'yeni_ad');
    expect(u.username, 'yeni_ad');
  });

  test('giriş kapısı: yasal onaydan sonra, turdan önce; kilit sonrası tekrar', () {
    final main = ekranKaynagiSync('lib/main.dart');
    final yasal = main.indexOf('return DisclaimerAcceptanceScreen(');
    final kapi = main.indexOf('user.kullaniciAdiGerekli && !kilitBekliyor');
    final tur = main.indexOf('return OnboardingScreen(');
    final kilit = main.indexOf('return LockScreen(');
    final ikinci = main.indexOf('if (user.kullaniciAdiGerekli) {');
    expect(yasal, greaterThan(0));
    expect(kapi, greaterThan(yasal));
    expect(tur, greaterThan(kapi));
    expect(ikinci, greaterThan(kilit));
  });

  testWidgets('zorunlu ekran: öneriyle açılır, geri yok, biçim hatası anında', (
    tester,
  ) async {
    final user = AppUser(
      id: 'u1', email: 'a@b.c', displayName: 'Yasin Dirali', createdAt: DateTime(2026),
    );
    // Uygulamada kapı yalnız çözülmüş oturumla açılır; test de öyle kurar.
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _FakeAuth(user))],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(authProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: KullaniciAdiScreen(zorunlu: true)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Yasin.Dirali'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Çıkış yap'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ali veli');
    await tester.pump();
    expect(find.textContaining('harfle başlar'), findsOneWidget);
    // Gecikmeli sunucu sorusu biçim hatasında hiç kurulmaz.
    await tester.pump(const Duration(seconds: 1));
  });
}
