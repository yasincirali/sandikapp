import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Kullanıcı bulgusu (2026-09-21): "canlı aktivitelerde logoff + başka
/// müşteriyle login alınırsa önceki adamın portföyüne göre kâr/zarar
/// gösteriyor."
///
/// Gün içi seri önbelleği (`IntradaySeriesCache`) süreç ömrüne bağlı ve
/// kilit ekranı + widget + Bugün kartı tarafından ORTAK kullanılıyor.
/// Çıkışta temizleniyordu ama kullanıcı değişiminde önceki defter bir kare
/// daha yayınlanıp önbelleği yeniden dolduruyordu; yeni kullanıcı 5 dakika
/// boyunca öncekinin serisiyle kendi toplamını kıyaslıyordu. Artık seri
/// sahip damgası taşır (`PortfolioState.ownerId`) ve sahip değişince
/// koşulsuz düşer.
void main() {
  final cache = IntradaySeriesCache.instance;
  final now = DateTime(2026, 9, 21, 14, 0);
  const aSerisi = {1: 100.0, 2: 110.0};

  setUp(cache.clear);
  tearDown(cache.clear);

  test('aynı sahip, taze damga: önbellekten döner', () async {
    cache.seedForTest(series: aSerisi, fetchedAt: now, ownerId: 'A');
    final s = await cache.get(const PortfolioState(ownerId: 'A'),
        now: now.add(const Duration(minutes: 1)));
    expect(s, aSerisi);
    expect(cache.ownerIdForTest, 'A');
  });

  test('sahip değişti: A\'nın serisi B\'ye verilmez', () async {
    cache.seedForTest(series: aSerisi, fetchedAt: now, ownerId: 'A');
    // Damga taze (1 dk) — yalnızca sahip farkı düşürmeli.
    final s = await cache.get(const PortfolioState(ownerId: 'B'),
        now: now.add(const Duration(minutes: 1)));
    expect(s[1], isNull, reason: 'B, A\'nın gün içi serisini görmemeli.');
    expect(s[2], isNull);
  });

  test('sahibi bilinmeyen state (eski yol / test) damgayı bozmaz', () async {
    cache.seedForTest(series: aSerisi, fetchedAt: now, ownerId: 'A');
    final s = await cache.get(const PortfolioState(),
        now: now.add(const Duration(minutes: 1)));
    expect(s, aSerisi);
  });

  test('copyWith sahibi korur — görünüm türevleri damgayı kaybetmez', () {
    const s = PortfolioState(ownerId: 'A');
    expect(s.copyWith(assets: const []).ownerId, 'A');
    expect(s.copyWith(ownerId: 'B').ownerId, 'B');
  });

  test('clear sahibi de siler', () {
    cache.seedForTest(series: aSerisi, fetchedAt: now, ownerId: 'A');
    cache.clear();
    expect(cache.ownerIdForTest, '');
    expect(cache.series, isEmpty);
  });
}
