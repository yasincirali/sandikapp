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

  group('yaklaşan olaylar', () {
    test('ayın 1\'inde TÜİK 2 gün sonra', () {
      final o = BugunService.yaklasanOlaylar(DateTime(2026, 9, 1, 9));
      final tuik = o.firstWhere((e) => e.tur == BugunOlayTuru.tuikAciklamasi);
      expect(tuik.gunKaldi, 2);
    });

    test('ayın 3\'ü 10:00 geçince TÜİK gelecek aya kayar ve ufuk dışı kalır', () {
      final o = BugunService.yaklasanOlaylar(DateTime(2026, 9, 3, 11));
      expect(o.where((e) => e.tur == BugunOlayTuru.tuikAciklamasi), isEmpty);
    });

    test('ay sonu son üç günde görünür', () {
      final o = BugunService.yaklasanOlaylar(DateTime(2026, 9, 29));
      expect(o.any((e) => e.tur == BugunOlayTuru.aySonu && e.gunKaldi == 1), isTrue);
    });

    test('BIST tatili hafta içine düşünce listede', () {
      final o = BugunService.yaklasanOlaylar(DateTime(2026, 10, 26)); // Pzt → 29 Ekim Perş.
      expect(o.any((e) => e.tur == BugunOlayTuru.bistTatili && e.gunKaldi == 3), isTrue);
    });
  });

  group('hesapla', () {
    const DailySummary? ozetYok = null;
    final ozetVar = const DailySummary(
        totalTRY: 100000, changeTRY: 1250, changePct: 1.27, sparkline: []);

    test('ölçülmüş değişim varsa birincil satır odur', () {
      final v = BugunService.hesapla(
        karZararlar: [10, -5],
        toplamDeger: 100000,
        ozet: ozetVar,
        hedefTRY: 0,
        now: DateTime(2026, 9, 22, 14),
      );
      expect(v.birincil, isA<GunlukDegisimSatiri>());
    });

    test('seri yokken piyasa kapalıysa açılış saati, açıksa satır yok', () {
      final kapali = BugunService.hesapla(
        karZararlar: const [],
        toplamDeger: 0,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 20, 12), // Pazar
      );
      expect(kapali.birincil, isA<PiyasaKapaliSatiri>());
      final acik = BugunService.hesapla(
        karZararlar: const [],
        toplamDeger: 0,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 22, 12),
      );
      expect(acik.birincil, isNull);
    });

    test('içgörüler günden güne döner, aynı gün sabittir', () {
      BugunKartiVerisi g(int gun) => BugunService.hesapla(
            karZararlar: [1, 2, -3],
            toplamDeger: 500000,
            ozet: ozetVar,
            hedefTRY: 1000000,
            now: DateTime(2026, 9, gun, 12),
          );
      final a = g(22), b = g(23), a2 = g(22);
      expect(a.ikincil.length, BugunService.ikincilSayisi);
      expect(a.ikincil.first.runtimeType, isNot(b.ikincil.first.runtimeType));
      expect(a.ikincil.first.runtimeType, a2.ikincil.first.runtimeType);
    });

    test('aylık özet yalnızca ayın ilk üç günü', () {
      BugunKartiVerisi g(int gun) => BugunService.hesapla(
            karZararlar: const [1],
            toplamDeger: 1,
            ozet: ozetYok,
            hedefTRY: 0,
            now: DateTime(2026, 9, gun, 12),
          );
      expect(g(1).aylik?.ay, DateTime(2026, 8, 1));
      expect(g(3).aylik, isNotNull);
      expect(g(4).aylik, isNull);
    });

    test('hedef: oran, kalan, ulaşıldı', () {
      const h = HedefSatiri(hedefTRY: 1000000, deger: 766876);
      expect(h.belirlenmedi, isFalse);
      expect(h.oran, closeTo(0.7669, 0.001));
      expect(h.kalan, 233124);
      expect(const HedefSatiri(hedefTRY: 500000, deger: 766876).ulasildi, isTrue);
      expect(const HedefSatiri(hedefTRY: 0, deger: 766876).belirlenmedi, isTrue);
    });

    test('yeşil oran ömürlük kâr/zarardan sayılır', () {
      final v = BugunService.hesapla(
        karZararlar: [5, 0, -2, 9],
        toplamDeger: 1,
        ozet: ozetYok,
        hedefTRY: 0,
        now: DateTime(2026, 9, 22, 12),
      );
      final y = v.ikincil.whereType<YesilOranSatiri>();
      // Dönüşümde o gün görünmeyebilir; adayın kendisi doğru olmalı.
      final hepsi = [
        for (var d = 1; d <= 3; d++)
          ...BugunService.hesapla(
            karZararlar: [5, 0, -2, 9],
            toplamDeger: 1,
            ozet: ozetYok,
            hedefTRY: 0,
            now: DateTime(2026, 9, 21 + d, 12),
          ).ikincil.whereType<YesilOranSatiri>(),
      ];
      expect(y.isNotEmpty || hepsi.isNotEmpty, isTrue);
      final s = (y.isNotEmpty ? y : hepsi).first;
      expect(s.yesil, 2);
      expect(s.toplam, 4);
    });
  });
}
