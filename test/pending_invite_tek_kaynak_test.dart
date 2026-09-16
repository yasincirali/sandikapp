import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Bekleyen ortaklık istekleri TEK kaynaktan okunur.
///
/// ## Ölçülen arıza (kullanıcı bildirimi, 2026-09-16)
///
/// Kullanıcı bildirimden gelen ortaklık isteğini onaylıyor, geri dönünce
/// istek Profil ekranında DURMAYA devam ediyor; ikinci kez "Onayla"ya
/// basınca **"Bu davet zaten yanıtlanmış"** hatası alıyor.
///
/// ## Kök neden
///
/// İki ekran aynı listeyi AYRI AYRI tutuyordu:
///   - `PartnershipRequestsScreen._pendingInvites` (bildirimden açılan)
///   - `profile_screen._PendingRequestsSectionState._pendingInvites`
///
/// Bildirim yolu (`notification_service._openPartnerInvite`) ikinci ekranı
/// birincinin ÜSTÜNE `push` eder. Üstteki ekranda onay verilince o kendi
/// listesini tazeler, ama alttaki ekranın state'i dokunulmadan kalır:
/// `initState` Navigator geri dönüşünde yeniden çalışmaz ve
/// `ForegroundPoller` yalnızca uygulama ARKA PLANDAN dönünce tetiklenir —
/// ekranlar arası geçişte değil.
///
/// Sonuç: kullanıcı sunucuda artık var olmayan bir daveti gösteren bayat
/// kart görür. Ona basınca sunucu doğru davranıp 409 `already_processed`
/// döner. Yani **hata mesajı arızanın kendisi değil, semptomu** —
/// `accept-invite/index.ts` kabulde `used=true` yazıyor ve liste sorgusu
/// `used=false` filtreliyor, sunucu tarafı zaten tutarlıydı.
///
/// ## Çözüm
///
/// Liste `pendingInvitesProvider`'a taşındı. Her iki ekran aynı state'i
/// izler; biri onayladığında öteki kendiliğinden güncellenir.
void main() {
  final provider = ekranKaynagiSync('lib/providers/auth_provider.dart');
  final istekEkrani =
      ekranKaynagiSync('lib/screens/partnership_requests_screen.dart');
  final profil = ekranKaynagiSync('lib/screens/profile_screen.dart');

  test('paylaşılan provider var', () {
    expect(provider.contains('pendingInvitesProvider'), isTrue);
    expect(provider.contains('class PendingInvitesNotifier'), isTrue);
  });

  test('İKİ ekran da kendi listesini TUTMAZ', () {
    // Arızanın tam imzası: ekranın kendi `_pendingInvites` alanı.
    expect(istekEkrani.contains('List<Map<String, dynamic>> _pendingInvites'),
        isFalse,
        reason: 'Ortaklık istekleri ekranı kendi kopyasını tutmamalı.');
    expect(profil.contains('List<Map<String, dynamic>> _pendingInvites'),
        isFalse,
        reason: 'Profil bölümü kendi kopyasını tutmamalı.');
  });

  test('İKİ ekran da provider\'ı İZLER', () {
    // `watch` şart: `read` ile okuyan ekran öteki onayladığında yeniden
    // çizilmez ve arıza aynen geri gelir.
    expect(istekEkrani.contains('ref.watch(pendingInvitesProvider)'), isTrue);
    expect(profil.contains('ref.watch(pendingInvitesProvider)'), isTrue);
  });

  test('ekranlar listeyi doğrudan servisten ÇEKMEZ', () {
    // Servisi doğrudan çağıran ekran provider'ı atlar; iki kaynak yeniden
    // oluşur.
    expect(istekEkrani.contains('getPendingInvitesForMe'), isFalse);
    expect(profil.contains('getPendingInvitesForMe'), isFalse);
  });

  test('onay ve ret sonrası davet listeden HEMEN düşer', () {
    // `refresh()` bir ağ turu sürüyor; o aralıkta kart ekranda kalıp ikinci
    // kez basılabiliyordu — bildirilen arıza tam orada oluşuyor.
    expect(provider.contains('void kaldir(String inviteId)'), isTrue);
    for (final kaynak in [istekEkrani, profil]) {
      expect(
        'pendingInvitesProvider.notifier).kaldir('.allMatches(kaynak).length,
        2,
        reason: 'Hem kabul hem ret yolunda çağrılmalı.',
      );
    }
  });

  test('provider kullanıcıyı authProvider\'dan okur', () {
    // Ekranlardan `userId` geçilseydi ikinci bir kaynak olurdu ve
    // çıkış/giriş sonrası biri eskiyebilirdi.
    expect(provider.contains('ref.watch(authProvider)'), isTrue);
    expect(profil.contains('_PendingRequestsSection(userId:'), isFalse);
  });

  test('poller güvenlik ağı olarak KALIR', () {
    // Provider ekranlar arası tutarlılığı çözer; poller karşı taraftan
    // gelen YENİ isteği yakalar. İkisi farklı sorun, ikisi de gerekli.
    expect(istekEkrani.contains('ForegroundPoller'), isTrue);
    expect(profil.contains('ForegroundPoller'), isTrue);
  });
}
