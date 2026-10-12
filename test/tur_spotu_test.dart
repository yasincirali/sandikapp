import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/onboarding_screen.dart';

/// Tur spotu ekrandan taşmaz, uzun hedefte üst kısmı alır (kullanıcı
/// bulgusu 2026-10-12: "Bugün ne oldu" adımında spot ekranı kaplıyor,
/// açıklama kartı üstüne biniyordu).
void main() {
  const mq = MediaQueryData(
    size: Size(390, 844),
    padding: EdgeInsets.only(top: 47, bottom: 34),
  );
  const gorunurYukseklik = 844.0 - 47 - 34;

  test('kısa hedef birebir aynı kalır', () {
    const r = Rect.fromLTWH(16, 200, 358, 120);
    expect(turSpotu(r, mq), r);
  });

  test('ekrandan uzun hedef: üst yarı, görünür alanın içinde', () {
    const r = Rect.fromLTWH(12, 150, 366, 1400);
    final s = turSpotu(r, mq);
    expect(s.top, 150);
    expect(s.height, closeTo(gorunurYukseklik * 0.5, 0.01));
    expect(s.bottom, lessThanOrEqualTo(844 - 34));
  });

  test('üstü ekran dışında kalan hedef güvenli alandan başlar', () {
    const r = Rect.fromLTWH(12, -300, 366, 500);
    final s = turSpotu(r, mq);
    expect(s.top, 47);
    expect(s.bottom, 200);
  });

  test('açıklama kartına en az görünür alanın yarısı kalır', () {
    const r = Rect.fromLTWH(0, 47, 390, 2000);
    final s = turSpotu(r, mq);
    expect((844 - 34) - s.bottom,
        greaterThanOrEqualTo(gorunurYukseklik * 0.5 - 0.01));
  });
}
