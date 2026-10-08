import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// "Bugün" kartı — takvim ve dönüşüm kuralları.
void main() {
  group('seans', () {
    test('hafta içi 12:00 açık, 09:30 ve 18:30 kapalı', () {
      expect(BugunService.seansAcikMi(DateTime(2026, 9, 22, 12)), isTrue); // Salı
      expect(BugunService.seansAcikMi(DateTime(2026, 9, 22, 9, 30)), isFalse);
      expect(BugunService.seansAcikMi(DateTime(2026, 9, 22, 18, 30)), isFalse);
    });

    test('hafta sonu ve resmî tatil kapalı', () {
      expect(BugunService.seansAcikMi(DateTime(2026, 9, 20, 12)), isFalse); // Pazar
      expect(BugunService.seansAcikMi(DateTime(2026, 10, 29, 12)), isFalse); // Cumhuriyet
    });

    test('Cuma akşamı → Pazartesi 10:00; sabah erken → aynı gün 10:00', () {
      expect(
        BugunService.sonrakiAcilis(DateTime(2026, 9, 18, 19)),
        DateTime(2026, 9, 21, 10),
      );
      expect(
        BugunService.sonrakiAcilis(DateTime(2026, 9, 22, 8)),
        DateTime(2026, 9, 22, 10),
      );
    });
  });

  group('hesapla', () {
    const DailySummary? ozetYok = null;
    final ozetVar = const DailySummary(
        totalTRY: 100000, changeTRY: 1250, changePct: 1.27, sparkline: []);

    test('ölçülmüş değişim varsa birincil satır odur', () {
      final v = BugunService.hesapla(
        toplamDeger: 100000,
        ozet: ozetVar,
        hedefTRY: 0,
        now: DateTime(2026, 9, 22, 14),
      );
      expect(v.birincil, isA<GunlukDegisimSatiri>());
    });

    test('seri yokken piyasa kapalıysa açılış saati, açıksa satır yok', () {
      final kapali = BugunService.hesapla(
        toplamDeger: 0,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 20, 12), // Pazar
        yalnizcaBorsa: true,
      );
      expect(kapali.birincil, isA<PiyasaKapaliSatiri>());
      expect(kapali.kapaliSoylenir, isTrue);
      final acik = BugunService.hesapla(
        toplamDeger: 0,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 22, 12),
      );
      expect(acik.birincil, isNull);
    });

    test('karışık portföyde "Piyasa kapalı" satırı YOK (2026-10-01)', () {
      // Kullanıcı kararı: altın/kripto hafta sonu da işler; "kapalı"
      // yalnızca tamamen borsa portföyüne söylenir.
      final karisik = BugunService.hesapla(
        toplamDeger: 0,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 20, 12), // Pazar
      );
      expect(karisik.birincil, isNot(isA<PiyasaKapaliSatiri>()));
      expect(karisik.kapaliSoylenir, isFalse);
    });

    // Kullanıcı bulgusu 2026-09-30 (Çarşamba): "hedef belirle kısmı
    // kaybolmuş" — hedef dönüşümle gizleniyordu; tek giriş noktası olduğu
    // için her gün, hedef belirlenmiş de belirlenmemiş de görünmeli.
    test('hedef satırı her gün görünür', () {
      for (final hedefTRY in [0, 1000000]) {
        for (var gun = 21; gun <= 30; gun++) {
          final v = BugunService.hesapla(
            toplamDeger: 500000,
            ozet: ozetVar,
            hedefTRY: hedefTRY,
            now: DateTime(2026, 9, gun, 12),
          );
          expect(v.hedef.hedefTRY, hedefTRY,
              reason: '$gun Eylül, hedef $hedefTRY');
          expect(v.hedef.deger, 500000);
        }
      }
    });

    test('hedef: oran, kalan, ulaşıldı', () {
      const h = HedefSatiri(hedefTRY: 1000000, deger: 766876);
      expect(h.belirlenmedi, isFalse);
      expect(h.oran, closeTo(0.7669, 0.001));
      expect(h.kalan, 233124);
      expect(const HedefSatiri(hedefTRY: 500000, deger: 766876).ulasildi, isTrue);
      expect(const HedefSatiri(hedefTRY: 0, deger: 766876).belirlenmedi, isTrue);
    });
  });
}
