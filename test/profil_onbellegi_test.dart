// Açılış profili diskten yürür, ağ arkada tazeler (2026-09-28).
//
// Kilitlenen iki karar:
//  1. Önbellek YALNIZ oturumdaki kullanıcıya aitse kullanılır — aynı
//     cihazda hesap değişince önceki kişinin adı görünmemeli.
//  2. Arka plan tazelemesi yalnız profil DEĞİŞTİYSE state'e yazar; aksi
//     halde authProvider'ı izleyen her provider (portföy dahil) açılışta
//     ikinci kez kurulur.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/services/auth_service.dart';

void main() {
  final profil = AppUser(
    id: 'u1',
    email: 'a@b.c',
    displayName: 'Ayşe',
    createdAt: DateTime.utc(2024, 3, 1, 12),
    onboardingCompleted: true,
  );
  final kayit = jsonEncode(profil.toMap());

  group('profilOnbellektenCoz', () {
    test('aynı kullanıcı → profil', () {
      final u = AuthService.profilOnbellektenCoz(kayit, 'u1')!;
      expect(u.displayName, 'Ayşe');
      expect(u.onboardingCompleted, isTrue);
      expect(AuthNotifier.ayniProfil(u, profil), isTrue);
    });

    test('başka kullanıcı → null (hesap değişimi)', () {
      expect(AuthService.profilOnbellektenCoz(kayit, 'u2'), isNull);
    });

    test('kayıt yok / bozuk → null', () {
      expect(AuthService.profilOnbellektenCoz(null, 'u1'), isNull);
      expect(AuthService.profilOnbellektenCoz('{bozuk', 'u1'), isNull);
      expect(AuthService.profilOnbellektenCoz('{"id":"u1"}', 'u1'), isNull);
    });
  });

  group('ayniProfil', () {
    test('ad değişirse farklı', () {
      final yeni = AppUser(
        id: 'u1',
        email: 'a@b.c',
        displayName: 'Ayşe K.',
        createdAt: profil.createdAt,
        onboardingCompleted: true,
      );
      expect(AuthNotifier.ayniProfil(profil, yeni), isFalse);
    });

    test('onboarding bayrağı değişirse farklı', () {
      expect(
        AuthNotifier.ayniProfil(
            profil, profil.copyWith(onboardingCompleted: false)),
        isFalse,
      );
    });
  });
}
