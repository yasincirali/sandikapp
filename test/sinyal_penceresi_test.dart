import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Teknik gösterge panelinin fiyat penceresi.
///
/// ## Yakaladığı hata (2026-09-10)
/// Panel 180 gün istiyordu ve göstergeler HİÇBİR varlıkta çizilmiyordu —
/// ekranda kalıcı olarak "fiyat geçmişi şu an çekilemedi" yazıyordu.
/// Kullanıcı bunu bir fonda bildirdi ama ölçüm hisseleri de kapsadığını
/// gösterdi (THYAO 26 nokta, TEFAS:DPP 26 nokta, eşik 30).
///
/// Sebep TEFAS ya da Yahoo değildi — API'ler 125 nokta döndürüyordu.
/// `HistoryService`in çözünürlük merdiveni 180 günü HAFTALIK katmana
/// düşürüyor ve günlük noktaları haftalık kovalara sıkıştırıyordu.
///
/// Panel ise GÜNLÜK seri varsayar: MACD 26, Bollinger 20, ADX 2×14 nokta
/// ister ve bu sayılar GÜN cinsindendir.
///
/// Bu dosya ağa ÇIKMAZ; kuralı merdivenin kendisinden okur.
void main() {
  group('sinyal penceresi', () {
    test('GÜNLÜK katmanda kalır — haftalığa düşmez', () {
      // Asıl değişmez bu. Pencere haftalığa düşerse nokta sayısı ~4'e
      // bölünür ve panel eşiğin altında kalıp hiç çizilmez.
      expect(
        HistoryService.tierForPeriod(kSinyalPenceresiGun),
        ResolutionTier.daily,
        reason: 'Pencere haftalık katmana düştü — göstergeler bir daha '
            'hiçbir varlıkta çizilmez (2026-09-10 hatası).',
      );
    });

    test('180 gün HÂLÂ haftalık — eski değere dönülmediği kanıtı', () {
      // Bu test, yukarıdakinin neden var olduğunu belgeler: 180 gerçekten
      // haftalığa düşüyor, yani hata gerçekti ve pencere geri alınırsa
      // aynı hata geri gelir.
      expect(HistoryService.tierForPeriod(180), ResolutionTier.weekly);
      expect(kSinyalPenceresiGun, lessThan(180));
    });

    test('en uzun göstergeyi rahat besler', () {
      // Günlük katmanda ~0,7 nokta/gün geliyor (hafta sonu + tatil).
      // 90 gün ≈ 63 nokta (ölçüldü: THYAO 63, TEFAS:DPP 64).
      // ADX 2×14 = 28 nokta ister; iki katından fazlası kalmalı.
      final tahminiNokta = (kSinyalPenceresiGun * 0.7).floor();
      expect(tahminiNokta, greaterThan(30),
          reason: 'Panelin 30 nokta eşiğini geçmiyor.');
      expect(tahminiNokta, greaterThanOrEqualTo(56),
          reason: 'En uzun gösterge (ADX, 28) için pay kalmıyor.');
    });

    test('şerit ve panel AYNI pencereyi ister', () {
      // İkisi `HistoryService` önbelleğini paylaşıyor. Farklı pencere
      // isterlerse iki ayrı ağ çağrısı olur ve aynı varlık için FARKLI
      // sinyal gösterebilirler.
      final kaynak = File('lib/screens/performance_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

      // Ham sayı kalmamalı — iki çağrı da sabite bağlı olmalı.
      expect(kaynak.contains('periodDays: 180'), isFalse,
          reason: 'Bir çağrı hâlâ 180 gün istiyor.');
      expect(
        'periodDays: kSinyalPenceresiGun'.allMatches(kaynak).length,
        2,
        reason: 'Şerit ve panelden biri sabite bağlı değil.',
      );
    });
  });
}
