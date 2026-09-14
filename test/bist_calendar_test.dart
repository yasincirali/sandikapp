import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bist_calendar.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Resmî tatil takvimi — kilit ekranı ve widget "Canlı" etiketinin doğruluğu.
///
/// İki değişmez:
/// - listedeki gün KAPALI, arife/28 Ekim öğleden sonra KAPALI;
/// - kapsanmayan yılda dinî bayram BİLİNMEZ ve o gün açık sayılır (eski
///   davranış) — uydurulmuş bir tarih gerçek işlem gününü kapatmasın.
void main() {
  group('BistTakvimi', () {
    test('sabit tarihli ulusal tatiller her yıl kapalı', () {
      for (final y in [2025, 2026, 2031]) {
        expect(BistTakvimi.tatilMi(DateTime(y, 1, 1)), isTrue, reason: '$y-01-01');
        expect(BistTakvimi.tatilMi(DateTime(y, 4, 23)), isTrue);
        expect(BistTakvimi.tatilMi(DateTime(y, 5, 1)), isTrue);
        expect(BistTakvimi.tatilMi(DateTime(y, 5, 19)), isTrue);
        expect(BistTakvimi.tatilMi(DateTime(y, 7, 15)), isTrue);
        expect(BistTakvimi.tatilMi(DateTime(y, 8, 30)), isTrue);
        expect(BistTakvimi.tatilMi(DateTime(y, 10, 29)), isTrue);
        expect(BistTakvimi.yarimGunMu(DateTime(y, 10, 28)), isTrue);
      }
    });

    test('2026 dinî bayramlar ve arifeleri', () {
      // Ramazan 20–22 Mart (arife 19), Kurban 27–30 Mayıs (arife 26).
      for (final d in [20, 21, 22]) {
        expect(BistTakvimi.tatilMi(DateTime(2026, 3, d)), isTrue, reason: '3-$d');
      }
      for (final d in [27, 28, 29, 30]) {
        expect(BistTakvimi.tatilMi(DateTime(2026, 5, d)), isTrue, reason: '5-$d');
      }
      expect(BistTakvimi.yarimGunMu(DateTime(2026, 3, 19)), isTrue);
      expect(BistTakvimi.yarimGunMu(DateTime(2026, 5, 26)), isTrue);
      // Bayramın hemen öncesi ve sonrası açık.
      expect(BistTakvimi.tatilMi(DateTime(2026, 3, 18)), isFalse);
      expect(BistTakvimi.tatilMi(DateTime(2026, 3, 23)), isFalse);
      expect(BistTakvimi.yarimGunMu(DateTime(2026, 3, 18)), isFalse);
    });

    test('kapsanmayan yılda dinî bayram BİLİNMEZ — açık sayılır', () {
      final y = BistTakvimi.sonKapsananYil + 1;
      expect(BistTakvimi.yilKapsaniyor(y), isFalse);
      // 2026'nın tarihleri sonraki yıla taşınmaz (hicri takvim kayar).
      expect(BistTakvimi.tatilMi(DateTime(y, 3, 20)), isFalse);
      expect(BistTakvimi.yarimGunMu(DateTime(y, 3, 19)), isFalse);
    });

    test('sıradan iş günü açık', () {
      expect(BistTakvimi.tatilMi(DateTime(2026, 8, 11)), isFalse);
      expect(BistTakvimi.yarimGunMu(DateTime(2026, 8, 11)), isFalse);
    });
  });

  group('DailySummary.isMarketOpen takvimi uygular', () {
    test('tatil günü seans içinde bile kapalı', () {
      // 29 Ekim 2026 Perşembe, 12:00.
      expect(DailySummary.isMarketOpen(DateTime(2026, 10, 29, 12, 0)), isFalse);
      // 20 Mart 2026 Cuma (Ramazan Bayramı 1. gün).
      expect(DailySummary.isMarketOpen(DateTime(2026, 3, 20, 11, 0)), isFalse);
    });

    test('yarım gün: 12:30 öncesi açık, sonrası kapalı', () {
      // 28 Ekim 2026 Çarşamba.
      expect(DailySummary.isMarketOpen(DateTime(2026, 10, 28, 11, 0)), isTrue);
      expect(DailySummary.isMarketOpen(DateTime(2026, 10, 28, 12, 29)), isTrue);
      expect(DailySummary.isMarketOpen(DateTime(2026, 10, 28, 12, 30)), isFalse);
      expect(DailySummary.isMarketOpen(DateTime(2026, 10, 28, 15, 0)), isFalse);
    });

    test('sıradan iş günü eski kural aynen', () {
      // 11 Ağustos 2026 Salı — mevcut live_activity_session_test ile aynı gün.
      expect(DailySummary.isMarketOpen(DateTime(2026, 8, 11, 10, 0)), isTrue);
      expect(DailySummary.isMarketOpen(DateTime(2026, 8, 11, 18, 9)), isTrue);
      expect(DailySummary.isMarketOpen(DateTime(2026, 8, 11, 18, 10)), isFalse);
      expect(DailySummary.isMarketOpen(DateTime(2026, 8, 11, 9, 59)), isFalse);
    });

    test('hafta sonu takvimden bağımsız kapalı', () {
      expect(DailySummary.isMarketOpen(DateTime(2026, 8, 15, 12, 0)), isFalse);
    });
  });
}
