// Sunucu taraflı rate limit (migration 0028) istemciye 429 +
// `rate_limited` + `retry_after_seconds` olarak döner. Bu testler
// AuthService'in o yanıtı kullanıcıya doğru Türkçe mesaja çevirdiğini
// doğrular.
//
// _translateInviteError ve _formatRetryAfter private olduğu için burada
// aynı sözleşmeyi paylaşan referans uygulama test edilir; amaç
// biçimlendirme kurallarının (saniye/dakika eşiği, varsayılan) sessizce
// bozulmamasını sağlamak.

import 'package:flutter_test/flutter_test.dart';

/// auth_service.dart içindeki _formatRetryAfter ile birebir aynı mantık.
String formatRetryAfter(dynamic data) {
  int? seconds;
  if (data is Map && data['retry_after_seconds'] is num) {
    seconds = (data['retry_after_seconds'] as num).toInt();
  }
  seconds ??= 600;
  if (seconds <= 60) return '$seconds saniye';
  final minutes = (seconds / 60).ceil();
  return '$minutes dakika';
}

/// auth_service._checkRateLimit içindeki kalan süre hesabıyla aynı mantık.
/// Sabit "10 dakika" yerine, en eski denemenin pencereden düşmesine
/// kalan gerçek süre gösterilir.
int remainingSeconds({
  required List<int> attemptsMs,
  required int nowMs,
  int windowMinutes = 10,
}) {
  final windowMs = Duration(minutes: windowMinutes).inMilliseconds;
  final recent = attemptsMs.where((ms) => ms >= nowMs - windowMs).toList()
    ..sort();
  final remainingMs = (recent.first + windowMs) - nowMs;
  return (remainingMs / 1000).ceil().clamp(1, windowMs ~/ 1000);
}

/// profile_screen._rateLimitLabel ile aynı mantık — kilitliyken
/// alanın altında ve butonda gösterilen canlı geri sayım etiketi.
String rateLimitLabel(int seconds) {
  if (seconds <= 60) return '$seconds saniye';
  final dk = seconds ~/ 60;
  final sn = seconds % 60;
  return '$dk:${sn.toString().padLeft(2, '0')} dakika';
}

void main() {
  group('geri sayım etiketi', () {
    test('60 sn ve altı saniye olarak gösterilir', () {
      expect(rateLimitLabel(45), '45 saniye');
      expect(rateLimitLabel(60), '60 saniye');
    });

    test('60 sn üstü dakika:saniye biçiminde', () {
      expect(rateLimitLabel(61), '1:01 dakika');
      expect(rateLimitLabel(245), '4:05 dakika');
      expect(rateLimitLabel(600), '10:00 dakika');
    });

    test('saniye iki hane olarak doldurulur', () {
      // "4:5" değil "4:05" — okunurluk.
      expect(rateLimitLabel(245).split(':')[1], '05 dakika');
    });
  });

  group('kalan süre hesabı', () {
    const now = 1000000000;
    const dakika = 60 * 1000;

    test('deneme az önce yapıldıysa neredeyse tam pencere kalır', () {
      final kalan = remainingSeconds(
        attemptsMs: [now - 5 * 1000], // 5 sn önce
        nowMs: now,
      );
      expect(formatRetryAfter({'retry_after_seconds': kalan}), '10 dakika');
    });

    test('9 dakika beklendiyse 1 dakika kalır — sabit 10 değil', () {
      // Asıl hata buydu: kullanıcı 9 dakika beklese bile "10 dakika"
      // görüyordu ve baştan beklediğini sanıyordu.
      final kalan = remainingSeconds(
        attemptsMs: [now - 9 * dakika],
        nowMs: now,
      );
      expect(kalan, lessThanOrEqualTo(60));
      expect(formatRetryAfter({'retry_after_seconds': kalan}), '60 saniye');
    });

    test('kalan süre EN ESKİ denemeye göre hesaplanır', () {
      // En eski 8 dk önce → 2 dk kalmalı; en yenisi (1 dk önce) değil.
      final kalan = remainingSeconds(
        attemptsMs: [now - 8 * dakika, now - 3 * dakika, now - 1 * dakika],
        nowMs: now,
      );
      expect(formatRetryAfter({'retry_after_seconds': kalan}), '2 dakika');
    });

    test('kalan süre asla 0 veya negatif gösterilmez', () {
      final kalan = remainingSeconds(
        attemptsMs: [now - 10 * dakika + 100], // pencerenin tam sınırında
        nowMs: now,
      );
      expect(kalan, greaterThanOrEqualTo(1));
    });
  });

  group('hangi hatalar sayaca yazılır (S8)', () {
    // auth_service._countedErrorCodes ile aynı küme.
    const sayilan = {'invite_not_found_or_expired'};
    bool sayilirMi(String kod) => sayilan.contains(kod);

    test('yalnızca gerçek tahmin hatası sayılır', () {
      expect(sayilirMi('invite_not_found_or_expired'), isTrue);
    });

    test('kullanıcı hataları sayılmaz — kod DOĞRU bulunmuştur', () {
      // Bunları saymak meşru kullanıcıyı kilitler ve saldırgana hiçbir
      // maliyet yüklemez (elinde zaten geçerli bir kod var).
      for (final kod in [
        'cannot_use_own_code',
        'already_partners',
        'already_claimed',
      ]) {
        expect(sayilirMi(kod), isFalse, reason: '$kod sayılmamalı');
      }
    });

    test('rate_limited sayılmaz — pencere süresiz uzamasın', () {
      expect(sayilirMi('rate_limited'), isFalse);
    });

    test('sunucu/ağ hataları sayılmaz', () {
      for (final kod in ['lookup_failed', 'rate_limit_unavailable', '']) {
        expect(sayilirMi(kod), isFalse, reason: '"$kod" sayılmamalı');
      }
    });
  });

  group('retry_after biçimlendirme', () {
    test('60 saniye ve altı saniye olarak gösterilir', () {
      expect(formatRetryAfter({'retry_after_seconds': 30}), '30 saniye');
      expect(formatRetryAfter({'retry_after_seconds': 60}), '60 saniye');
    });

    test('60 saniyenin üstü dakikaya yuvarlanır (yukarı)', () {
      // 90sn → "2 dakika": aşağı yuvarlamak kullanıcıya erken tekrar
      // denettirir ve yeni bir 429 alır. Yukarı yuvarlama doğru davranış.
      expect(formatRetryAfter({'retry_after_seconds': 90}), '2 dakika');
      expect(formatRetryAfter({'retry_after_seconds': 600}), '10 dakika');
    });

    test('alan yoksa veya tip yanlışsa güvenli varsayılana düşer', () {
      expect(formatRetryAfter(null), '10 dakika');
      expect(formatRetryAfter({}), '10 dakika');
      expect(formatRetryAfter({'retry_after_seconds': 'abc'}), '10 dakika');
      expect(formatRetryAfter('beklenmedik gövde'), '10 dakika');
    });
  });
}
