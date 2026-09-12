import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Grafik çizgisi ALANIN BAŞINDAN başlamalı — içeriden değil.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12, 1H sekmesi)
/// "1 haftalık grafikte grafik alanının başından başlamalı, diğer zaman
/// aralıkları gibi."
///
/// Ölçüldü, iki ayrı hizasızlık üst üste binmişti:
///
/// 1. `startDate` = "şimdi − 7 gün" → gün ORTASINDA (5 Eyl 22:29). Veri
///    kovaları ise gün başına normalize (5 Eyl 22:00), yani ilk nokta
///    başlangıçtan ÖNCE düşüyor ve X **negatif** oluyordu (−0,02).
///    `minX = 0` onu eksenin solunda bırakıp kırpıyordu.
///
/// 2. Başlangıç gün başına çekilince negatiflik gitti ama bu sefer ilk
///    nokta **X = 0,917**'ye kaydı: eksen 0'dan, veri neredeyse bir gün
///    sonradan başlıyordu. Soldaki fark boş şerit olarak kalıyordu.
///
/// Çözüm iki parçalı: dönem başı gün başına çekiliyor VE eksenin sol ucu
/// verinin ilk noktasına oturtuluyor.
void main() {
  final kaynak = File('lib/screens/portfolio_performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('dönem başı gün başına çekilir', () {
    test('non-intraday `startDate` saat taşımaz', () {
      expect(kaynak.contains('final hamBaslangic = isIntraday'), isTrue,
          reason: 'Ham başlangıç ayrılmamış.');
      expect(
        kaynak.contains(
            'hamBaslangic.year, hamBaslangic.month, hamBaslangic.day)'),
        isTrue,
        reason: 'Başlangıç gün başına çekilmiyor — ilk nokta negatif X\'e '
            'düşer ve kırpılır.',
      );
    });

    test('gün içi dal ETKİLENMEZ', () {
      // Gün içi eksen zaten `seansGunu`nun 00:00'ından başlıyor.
      expect(kaynak.contains('final startDate = isIntraday\n        ? hamBaslangic'),
          isTrue,
          reason: 'Gün içi dal da gün başına çekilmiş — gereksiz.');
    });
  });

  group('eksenin sol ucu veriye oturur', () {
    test('`minX` sabit 0 DEĞİL', () {
      expect(kaynak.contains('double minX = intraday ? 0.0 : ilkVeriX;'), isTrue,
          reason: 'Eksen hâlâ 0\'dan başlıyor — soldaki fark boş şerit '
              'olarak kalır.');
    });

    test('ilk veri noktası hesaplanıyor', () {
      expect(kaynak.contains('final ilkVeriX = veriXs.isEmpty'), isTrue);
      expect(kaynak.contains('reduce((a, b) => a < b ? a : b)'), isTrue,
          reason: 'En küçük X bulunmuyor.');
    });

    test('boş seride ÇÖKMEZ', () {
      // `reduce` boş koleksiyonda fırlatır; kısa devre şart.
      expect(kaynak.contains('veriXs.isEmpty ? 0.0 :'), isTrue,
          reason: 'Boş seri koruması yok.');
    });

    test('gün içi ekseni 0\'dan başlamaya DEVAM eder', () {
      // Gün içi X, seans gününün 00:00\'ından itibaren DAKİKA. 0 doğru
      // sol uçtur; veriye oturtmak grafiği sabahın erken saatlerinden
      // koparırdı.
      expect(kaynak.contains('intraday ? 0.0 :'), isTrue);
    });
  });

  test('REGRESYON: dar aktif segment daraltması korunur', () {
    // Aktif segment dönemin %25\'inden azsa viewport daraltılıyor
    // (yeni alınmış varlık grafiğin ucunda sıkışmasın diye). Bu mantık
    // eksen değişikliğinden sonra da durmalı.
    expect(kaynak.contains('activeSpan < fullSpan * 0.25'), isTrue,
        reason: 'Dar segment daraltması kaldırılmış.');
  });
}
