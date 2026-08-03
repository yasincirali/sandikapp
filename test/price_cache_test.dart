import 'package:flutter_test/flutter_test.dart';

/// `PriceService` fiyat önbelleğinin karar mantığı.
///
/// Servisin kendisi ağa çıkıyor; burada test edilen, hangi sembolün
/// önbellekten karşılanıp hangisinin yeniden çekileceğine dair KURAL.
/// `price_service.dart`'taki `fetchQuotes` girişiyle aynı mantık.

const Duration kQuoteTtl = Duration(seconds: 45);

/// Önbellekten karşılanacaklar ile ağa çıkılacakları ayırır.
({List<String> fromCache, List<String> toFetch}) partition({
  required List<String> requested,
  required Map<String, DateTime> cachedAt,
  required DateTime now,
  bool forceRefresh = false,
}) {
  if (forceRefresh) {
    return (fromCache: const [], toFetch: List.of(requested));
  }
  final hit = <String>[];
  final miss = <String>[];
  for (final s in requested) {
    final at = cachedAt[s];
    if (at != null && now.difference(at) <= kQuoteTtl) {
      hit.add(s);
    } else {
      miss.add(s);
    }
  }
  return (fromCache: hit, toFetch: miss);
}

void main() {
  final t0 = DateTime(2026, 8, 3, 12, 0, 0);

  group('fiyat önbelleği', () {
    test('taze giriş ağa çıkmaz', () {
      final r = partition(
        requested: ['THYAO.IS'],
        cachedAt: {'THYAO.IS': t0},
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(r.fromCache, ['THYAO.IS']);
      expect(r.toFetch, isEmpty);
    });

    test('TTL dolunca yeniden çekilir', () {
      final r = partition(
        requested: ['THYAO.IS'],
        cachedAt: {'THYAO.IS': t0},
        now: t0.add(const Duration(seconds: 46)),
      );
      expect(r.fromCache, isEmpty);
      expect(r.toFetch, ['THYAO.IS']);
    });

    test('TTL sınırı dahil sayılır', () {
      final r = partition(
        requested: ['THYAO.IS'],
        cachedAt: {'THYAO.IS': t0},
        now: t0.add(kQuoteTtl),
      );
      expect(r.fromCache, ['THYAO.IS']);
    });

    test('kısmi isabet — yalnızca eksikler çekilir', () {
      // Asıl kazanç bu: portföyün yarısı önbellekteyse yarısı kadar istek.
      final r = partition(
        requested: ['THYAO.IS', 'ASELS.IS', 'USDTRY=X'],
        cachedAt: {
          'THYAO.IS': t0,
          'USDTRY=X': t0.subtract(const Duration(minutes: 5)), // bayat
        },
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(r.fromCache, ['THYAO.IS']);
      expect(r.toFetch, ['ASELS.IS', 'USDTRY=X']);
    });

    test('forceRefresh tüm önbelleği atlar', () {
      // Pull-to-refresh: kullanıcı yenile dediğinde bayat fiyat görmemeli.
      final r = partition(
        requested: ['THYAO.IS', 'ASELS.IS'],
        cachedAt: {'THYAO.IS': t0, 'ASELS.IS': t0},
        now: t0.add(const Duration(seconds: 1)),
        forceRefresh: true,
      );
      expect(r.fromCache, isEmpty);
      expect(r.toFetch, ['THYAO.IS', 'ASELS.IS']);
    });

    test('boş önbellekte her şey çekilir', () {
      final r = partition(
        requested: ['THYAO.IS'],
        cachedAt: const {},
        now: t0,
      );
      expect(r.toFetch, ['THYAO.IS']);
    });

    test('ekranlar arası gidip gelme yeni istek doğurmaz', () {
      // Aynı semboller 45 sn içinde defalarca istenirse tek çekim yeter.
      final cache = {'THYAO.IS': t0, 'ASELS.IS': t0};
      for (final sec in [1, 5, 20, 44]) {
        final r = partition(
          requested: ['THYAO.IS', 'ASELS.IS'],
          cachedAt: cache,
          now: t0.add(Duration(seconds: sec)),
        );
        expect(r.toFetch, isEmpty, reason: '$sec sn sonra ağa çıkılmamalı');
      }
    });
  });
}
