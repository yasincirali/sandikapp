import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:portfoy_takip/services/crash_reporter.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

/// VPN açıkken uygulama çalışmıyordu ve kullanıcı bunu anlayamıyordu
/// (kullanıcı bildirimi 2026-09-22).
///
/// ## Neden mesaj VPN'i ANIYOR ama TESPİT ETMİYOR
/// VPN'in yol açtığı arıza istemcide sıradan bir ağ hatası olarak görünür:
/// sağlayıcının DNS'i alan adını çözemez (`Failed host lookup`), çıkış
/// düğümü engellidir (`Connection refused` / timeout), ya da araya giren
/// sertifika TLS'i keser (`HandshakeException`). Hiçbiri "VPN" demez ve
/// aynı imzalar VPN'siz kötü bağlantıda da çıkar.
///
/// Bu yüzden mesaj iki olasılığı birden taşır. VPN'i olmayan kullanıcı için
/// cümlenin ilk yarısı doğru cevaptır; VPN'i olan için ikinci yarısı
/// deneyeceği şeyi söyler. "VPN'inizi kapatın" diye kesin konuşmak, VPN
/// kullanmayan kullanıcıyı yanlış yere bakmaya gönderirdi.
void main() {
  group('bağlantı hataları tek mesaja düşer', () {
    final ornekler = <String, Object>{
      'DNS çözülemedi (VPN DNS\'i)': const SocketException(
          'Failed host lookup: \'xyz.supabase.co\''),
      'bağlantı reddedildi (çıkış düğümü engelli)':
          const SocketException('Connection refused'),
      'ağa ulaşılamıyor': const SocketException('Network is unreachable'),
      'zaman aşımı': TimeoutException('15s'),
      'TLS araya girdi': const HandshakeException(
          'CERTIFICATE_VERIFY_FAILED: self signed certificate'),
      'http istemcisi koptu':
          ClientException('Connection closed before full header was received'),
      'HttpException': const HttpException('Sunucuya ulaşılamadı'),
    };

    ornekler.forEach((ad, hata) {
      test(ad, () {
        expect(baglantiHatasiMi(hata), isTrue, reason: ad);
        expect(friendlyError(hata), kBaglantiHatasiMesaji, reason: ad);
      });
    });
  });

  test('mesaj hem interneti hem VPN\'i söyler', () {
    final m = kBaglantiHatasiMesaji;
    expect(m.toLowerCase(), contains('vpn'));
    expect(m.toLowerCase(), contains('internet'));
    // Kesin teşhis GİBİ konuşmamalı — VPN bir ihtimal olarak geçer.
    expect(m, contains('kullanıyorsan'),
        reason: 'VPN tespit edilmiyor, koşullu söyleniyor');
    // Hitap "sen" (CLAUDE.md i18n kuralı).
    expect(m.contains('kontrol edin') || m.contains('deneyin'), isFalse,
        reason: 'ana dil Türkçe, hitap sen');
  });

  test('ham teknik metin kullanıcıya SIZMAZ', () {
    final m = friendlyError(
        const SocketException('Failed host lookup: \'xyz.supabase.co\''));
    expect(m, isNot(contains('SocketException')));
    expect(m, isNot(contains('supabase')));
    expect(m, isNot(contains('Failed host lookup')));
  });

  group('bağlantı DIŞI hatalar etkilenmedi', () {
    test('biçim hatası kendi mesajını korur', () {
      expect(friendlyError(const FormatException('bad json')),
          'Sunucudan gelen veri okunamadı.');
    });

    test('bilinmeyen hata genel mesaja düşer', () {
      expect(friendlyError(Exception('something odd')),
          'Bir şeyler ters gitti, tekrar dene.');
    });

    test('null hâlâ ayrı', () {
      expect(baglantiHatasiMi(null), isFalse);
      expect(friendlyError(null), 'Bilinmeyen bir hata oluştu.');
    });
  });

  /// İki sınıflandırıcı AYRIŞMAMALI: `CrashReporter.agHatasiMi` "bunu
  /// çökme sayma" der, `baglantiHatasiMi` "kullanıcıya bağlantı mesajı
  /// göster" der. Biri tanıyıp diğeri tanımazsa ya Crashlytics'in sessizce
  /// geçtiği hata ekranda ham `Exception` olarak görünür, ya da kullanıcıya
  /// bağlantı denilen şey çökme olarak raporlanır.
  group('CrashReporter ile aynı aileyi tanır', () {
    final hatalar = <Object>[
      const SocketException('Failed host lookup: \'a.b\''),
      const SocketException('Connection reset by peer'),
      TimeoutException('timeout'),
      const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      ClientException('Connection closed before full header was received'),
      const HttpException('boom'),
    ];

    for (var i = 0; i < hatalar.length; i++) {
      final h = hatalar[i];
      test('#$i ${h.runtimeType}', () {
        expect(baglantiHatasiMi(h), CrashReporter.agHatasiMi(h),
            reason: 'iki sınıflandırıcı ayrışmamalı');
      });
    }
  });

  test('kaynak: auth bağlantı hatasını önekle sarmaz, Crashlytics\'e atmaz',
      () {
    final src = File('lib/services/auth_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('if (baglantiHatasiMi(e)) { throw AuthException(friendlyError(e)); }'),
        isTrue,
        reason:
            'VPN\'de giriş denemesi "Giriş hatası: ..." önekiyle çıkıyordu');
  });
}
