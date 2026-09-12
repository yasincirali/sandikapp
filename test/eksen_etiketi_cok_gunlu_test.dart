import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';

/// Gün içi eksende ÇOK GÜNLÜ seri tarih de yazmalı.
///
/// ## Kullanıcı isteği (2026-09-12)
/// "Tüm zaman aralıkları için hafta sonundaysam çizilen son grafik için
/// tarihi bulunduğum an olmalı."
///
/// Ölçüldü: veri katmanı beş dönemde de bugüne ulaşıyor (1H/1A/6A/1Y
/// ızgarada, GÜNLÜK ise `gunIciSagUc` kuyruğuyla). Eksik olan tek şey
/// ETİKETTİ: gün içi etiket koşulsuz `HH:mm` yazıyordu ve kuyruk birden
/// çok günü kapsadığında "18:45"in hangi güne ait olduğu görünmüyordu.
///
/// ## Ölçülen tuzak — `spanGun` gün DEĞİL
/// Gün içi eksende X **dakika** cinsinden. Performans ekranı
/// `meta.max - meta.min` farkını doğrudan `spanGun`a geçiriyordu, yani
/// 1 günlük eksen 1440 "gün" olarak okunuyordu. Eşik dönüştürme olmadan
/// her zaman tetiklenirdi — hafta içi grafiğe de tarih basardı.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final t = DateTime(2026, 9, 12, 18, 45);

  group('gün içi etiket', () {
    test('TEK günlük eksende yalnızca saat', () {
      // Normal hafta içi gün içi grafiği: tarih gereksiz gürültü.
      expect(zamanEtiketi(t, spanGun: 1.0, gunIci: true), '18:45');
      expect(zamanEtiketi(t, spanGun: 0.8, gunIci: true), '18:45');
    });

    test('ÇOK günlü eksende tarih de yazılır', () {
      // Hafta sonu kuyruğu: Cuma→Cumartesi, eksen iki günü kapsar.
      final etiket = zamanEtiketi(t, spanGun: 2.0, gunIci: true);
      expect(etiket.contains('18:45'), isTrue, reason: 'Saat kayıp.');
      expect(etiket.contains('12'), isTrue, reason: 'Gün kayıp.');
      expect(etiket.contains('Eyl'), isTrue, reason: 'Ay kayıp.');
    });

    test('Pazar senaryosu — üç günlük eksen', () {
      final etiket = zamanEtiketi(t, spanGun: 3.0, gunIci: true);
      expect(etiket, '12 Eyl 18:45');
    });

    test('eşik tam 1 günde tarih BASMAZ', () {
      // Sınır davranışı: `> 1` kuralı. Tam bir günlük eksen hâlâ tek
      // gündür.
      expect(zamanEtiketi(t, spanGun: 1.0, gunIci: true), '18:45');
      expect(zamanEtiketi(t, spanGun: 1.01, gunIci: true).contains('Eyl'),
          isTrue);
    });
  });

  group('gün DIŞI etiketler değişmedi — regresyon kapısı', () {
    test('kısa dönem', () {
      expect(zamanEtiketi(t, spanGun: 2, gunIci: false), '12 Eyl 18:45');
    });

    test('orta dönem', () {
      expect(zamanEtiketi(t, spanGun: 30, gunIci: false), '12 Eyl');
    });

    test('uzun dönem', () {
      expect(zamanEtiketi(t, spanGun: 500, gunIci: false), 'Eyl 26');
    });
  });

  test('performans ekranı `spanGun`u DAKİKADAN güne çevirir', () {
    // Kaynak denetimi: dönüştürme olmadan eşik her zaman tetiklenir ve
    // hafta içi grafiğe de tarih basılır. Bu, etiket biçiminden
    // anlaşılmayan sessiz bir hata olurdu.
    final kaynak = File('lib/screens/portfolio_performance_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(kaynak.contains('spanGun: intraday'), isTrue,
        reason: 'Gün içi/dışı ayrımı yok.');
    expect(kaynak.contains('/ 1440.0'), isTrue,
        reason: 'Dakika→gün dönüşümü yok; eşik saçmalar.');
  });
}
