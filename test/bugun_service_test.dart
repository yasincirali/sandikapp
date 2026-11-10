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

  group('tatil öncesi notu', () {
    TatilOncesiSatiri? not(DateTime t) => BugunService.tatilOncesiSatiri(t);

    test('30 Ara: not yok — 31 Ara açık (takvimde yarım gün değil)', () {
      expect(not(DateTime(2026, 12, 30, 11)), isNull);
    });

    test('31 Ara: yarın Yılbaşı → sonraki işlem günü 4 Ocak Pazartesi', () {
      for (final saat in [9, 11, 15, 19]) {
        final n = not(DateTime(2026, 12, 31, saat))!;
        expect(n.arife, isFalse);
        expect(n.sonrakiIslemGunu, DateTime(2027, 1, 4));
        expect(n.sonrakiIslemGunu!.weekday, DateTime.monday);
      }
    });

    test(
        '2027 Ramazan arifesi: sabah 12:30 kapanışı, öğleden sonra yarın kapalı',
        () {
      final sabah = not(DateTime(2027, 3, 8, 9))!;
      expect(sabah.arife, isTrue);
      expect(sabah.kapanis, DateTime(2027, 3, 8, 12, 30));
      expect(not(DateTime(2027, 3, 8, 12, 29))!.arife, isTrue);
      final ogle = not(DateTime(2027, 3, 8, 12, 30))!;
      expect(ogle.arife, isFalse);
      // Bayram 9–11 Mart (Salı–Perşembe) → Cuma.
      expect(ogle.sonrakiIslemGunu, DateTime(2027, 3, 12));
    });

    test('28 Ekim: sabah arife, öğleden sonra 30 Ekim Cuma', () {
      expect(not(DateTime(2026, 10, 28, 10, 15))!.arife, isTrue);
      expect(not(DateTime(2026, 10, 28, 13))!.sonrakiIslemGunu,
          DateTime(2026, 10, 30));
    });

    test('tatil içinde, hafta sonu öncesinde ve sıradan günde not yok', () {
      expect(not(DateTime(2027, 3, 10, 9)), isNull); // bayram içi
      expect(not(DateTime(2026, 12, 25, 9)), isNull); // Cuma → Cumartesi
      // Cuma 14 May 2027: ertesi gün Cumartesi (arife hafta sonuna düşüyor).
      expect(not(DateTime(2027, 5, 14, 9)), isNull);
      expect(not(DateTime(2026, 9, 22, 9)), isNull);
    });

    test('takvimin kapsamadığı yılda not yok', () {
      // 30 Ağustos 2028 Zafer Bayramı (Çarşamba) — sabit tatil ama 2028'in
      // dinî bayramları bilinmiyor; "sonraki işlem günü" uydurulmaz.
      expect(not(DateTime(2028, 8, 29, 9)), isNull);
    });

    test('hesapla: karışık portföyde not taşınır', () {
      final v = BugunService.hesapla(
        toplamDeger: 0,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 12, 31, 19),
      );
      expect(v.takvimNotu?.sonrakiIslemGunu, DateTime(2027, 1, 4));
    });

    test('hesapla: kapalı satırı tatil sonrası açılışı söylüyorsa not çıkmaz',
        () {
      final aksam = BugunService.hesapla(
        toplamDeger: 0,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 12, 31, 19),
        yalnizcaBorsa: true,
      );
      expect(aksam.birincil, isA<PiyasaKapaliSatiri>());
      expect(aksam.takvimNotu, isNull);
      // Açılış öncesi: kapalı satırı bugün 10:00'ı söyler, not tamamlar.
      final sabah = BugunService.hesapla(
        toplamDeger: 0,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 12, 31, 8),
        yalnizcaBorsa: true,
      );
      expect(sabah.birincil, isA<PiyasaKapaliSatiri>());
      expect(sabah.takvimNotu, isNotNull);
    });
  });
}
