import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';

/// Almanak düzeni (2026-09-21): yaklaşan olay dönüşüm havuzunda DEĞİL,
/// kartın ayak notunda — kalan gün sayısı her gün değişir, her gün okunur.
void main() {
  BugunKartiVerisi g(DateTime now) => BugunService.hesapla(
        karZararlar: const [1, -1],
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 0,
        now: now,
      );

  test('ufuktaki olay ayak notunda, ikincil havuzda değil', () {
    // 25 Eylül: TÜİK 3 Ekim'e 8 gün — ufuk (10) içinde.
    final v = g(DateTime(2026, 9, 25, 12));
    expect(v.olay?.tur, BugunOlayTuru.tuikAciklamasi);
    expect(v.olay?.gunKaldi, 8);
    expect(v.ikincil.whereType<YaklasanOlaySatiri>(), isEmpty);
  });

  test('ufukta olay yoksa ayak notu yok', () {
    // 14 Eylül: TÜİK 3 Ekim'e 19 gün; ay sonu uzak; tatil yok.
    expect(g(DateTime(2026, 9, 14, 12)).olay, isNull);
  });

  test('yalnızca olay varken kart boş sayılmaz', () {
    final v = BugunService.hesapla(
      karZararlar: const [],
      toplamDeger: 0,
      ozet: null,
      hedefTRY: 0,
      now: DateTime(2026, 9, 25, 12),
    );
    // Hedef satırı her zaman aday; ikincil dolu olsa da olay ayrı alanda.
    expect(v.olay, isNotNull);
    expect(v.bos, isFalse);
  });
}
