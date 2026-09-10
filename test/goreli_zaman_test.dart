import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Sinyal şeridindeki "10 dk önce" ifadesi.
///
/// Kullanıcı isteği (2026-09-10): şerit tasarım örneğindeki gibi göreli
/// zaman okumalı. Ama aynı kullanıcı daha önce "bildirim zaman ve tarihini
/// ekle bunu kaçırmaması lazım" dedi — bu yüzden göreli ifade mutlak
/// tarihin YERİNE değil, YANINA konuldu. Bu dosya göreli tarafı ölçer;
/// mutlak tarihin şeritte durduğunu `sinyal_seridi_gorunum_test.dart`
/// ölçüyor.
///
/// `now` parametre olarak veriliyor — fonksiyon içinde `DateTime.now()`
/// çağrılsaydı eşik dallarının hiçbiri testte deterministik çalışmazdı.
void main() {
  final t0 = DateTime(2026, 9, 10, 12, 0);

  group('eşikler', () {
    test('1 dakikadan yeni → "az önce"', () {
      expect(goreliZaman(t0, t0), 'az önce');
      expect(goreliZaman(t0.subtract(const Duration(seconds: 59)), t0),
          'az önce');
    });

    test('dakika aralığı', () {
      expect(goreliZaman(t0.subtract(const Duration(minutes: 1)), t0),
          '1 dk önce');
      expect(goreliZaman(t0.subtract(const Duration(minutes: 10)), t0),
          '10 dk önce');
      expect(goreliZaman(t0.subtract(const Duration(minutes: 59)), t0),
          '59 dk önce');
    });

    test('saat aralığı', () {
      expect(goreliZaman(t0.subtract(const Duration(minutes: 60)), t0),
          '1 sa önce');
      expect(
          goreliZaman(t0.subtract(const Duration(hours: 23)), t0), '23 sa önce');
    });

    test('gün aralığı', () {
      expect(
          goreliZaman(t0.subtract(const Duration(hours: 24)), t0), '1 gün önce');
      expect(
          goreliZaman(t0.subtract(const Duration(days: 7)), t0), '7 gün önce');
    });
  });

  test('gelecek zaman negatif sayı BASMAZ', () {
    // Sunucu saati cihaz saatinin birkaç saniye önünde olabilir.
    // "-1 dk önce" saçma olurdu.
    final gelecek = t0.add(const Duration(seconds: 30));
    expect(goreliZaman(gelecek, t0), 'az önce');

    final cokGelecek = t0.add(const Duration(hours: 2));
    expect(goreliZaman(cokGelecek, t0), 'az önce');
  });

  test('hiçbir çıktı boş ya da "null" değil', () {
    // Kaba tarama: eşiklerin arasında kalan bir değer sessizce boş
    // dönmemeli.
    for (var dk = 0; dk < 60 * 24 * 3; dk += 37) {
      final metin = goreliZaman(t0.subtract(Duration(minutes: dk)), t0);
      expect(metin.trim(), isNotEmpty, reason: '$dk dk için boş.');
      expect(metin.contains('null'), isFalse, reason: '$dk dk için null.');
      expect(metin.contains('-'), isFalse, reason: '$dk dk için negatif.');
    }
  });
}
