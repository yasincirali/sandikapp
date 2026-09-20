import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';

/// Bugün kartının sabit satırları (2026-09-21 sadeleştirme): reel getiri ve
/// haftalık özet eski şeritlerin yerine kartta. Kurallar:
///   · reel her gün SABİT (dönüşüme girmez), veri yoksa yok;
///   · haftalık Pazartesi–Salı sabit, sonra dönüşüm havuzunda.
void main() {
  const reel = ReelGetiriSatiri(nominal: 63.0, inflation: 31.5);

  test('reel getiri: puan farkı ve yön', () {
    expect(reel.fark, closeTo(31.5, 1e-9));
    expect(reel.onde, isTrue);
    expect(const ReelGetiriSatiri(nominal: 20, inflation: 31.5).onde, isFalse);
  });

  test('reel satırı verildiğinde her gün sabit, ikincil havuza girmez', () {
    for (final gun in [21, 22, 23, 24, 25]) {
      final v = BugunService.hesapla(
        karZararlar: const [1, -1],
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, gun, 12),
        reel: reel,
      );
      expect(v.reel, same(reel));
      expect(v.ikincil.whereType<ReelGetiriSatiri>(), isEmpty);
    }
  });

  test('haftalık: Pazartesi ve Salı sabit satır', () {
    for (final gun in [21, 22]) {
      // 21 Eylül 2026 Pazartesi.
      final v = BugunService.hesapla(
        karZararlar: const [1],
        toplamDeger: 1,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, gun, 12),
        haftalikGetiriPct: 1.3,
      );
      expect(v.haftalik?.getiriPct, 1.3);
      expect(v.ikincil.whereType<HaftalikOzetSatiri>(), isEmpty);
    }
  });

  test('haftalık: Çarşamba\'dan sonra dönüşüm havuzunda, kaybolmaz', () {
    var goruldu = false;
    for (final gun in [23, 24, 25, 26, 27]) {
      final v = BugunService.hesapla(
        karZararlar: const [1],
        toplamDeger: 1,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, gun, 12),
        haftalikGetiriPct: 1.3,
      );
      expect(v.haftalik, isNull);
      if (v.ikincil.whereType<HaftalikOzetSatiri>().isNotEmpty) goruldu = true;
    }
    expect(goruldu, isTrue, reason: 'havuz döner; hafta içinde en az bir gün görünür');
  });

  test('veri yoksa satır yok ve kart boş sayılabilir', () {
    final v = BugunService.hesapla(
      karZararlar: const [],
      toplamDeger: 0,
      ozet: null,
      hedefTRY: 0,
      now: DateTime(2026, 9, 22, 12), // seans açık, hareket yok
    );
    expect(v.reel, isNull);
    expect(v.haftalik, isNull);
  });
}
