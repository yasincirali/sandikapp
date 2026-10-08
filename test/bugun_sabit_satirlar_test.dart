import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';

/// Bugün kartının sabit satırı (2026-09-21 sadeleştirme): reel getiri eski
/// şeridin yerine kartta, her gün SABİT; veri yoksa yok. (Haftalık satır
/// 2026-10-08'de hesaptan kalktı: H düzeni onu çizmiyordu.)
void main() {
  const reel = ReelGetiriSatiri(nominal: 63.0, inflation: 31.5);

  test('reel getiri: puan farkı ve yön', () {
    expect(reel.fark, closeTo(31.5, 1e-9));
    expect(reel.onde, isTrue);
    expect(const ReelGetiriSatiri(nominal: 20, inflation: 31.5).onde, isFalse);
  });

  test('reel satırı verildiğinde her gün sabit', () {
    for (final gun in [21, 22, 23, 24, 25]) {
      final v = BugunService.hesapla(
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, gun, 12),
        reel: reel,
      );
      expect(v.reel, same(reel));
    }
  });

  test('veri yoksa reel satırı yok', () {
    final v = BugunService.hesapla(
      toplamDeger: 0,
      ozet: null,
      hedefTRY: 0,
      now: DateTime(2026, 9, 22, 12), // seans açık, hareket yok
    );
    expect(v.reel, isNull);
    expect(v.birincil, isNull);
  });
}
