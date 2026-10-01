import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';

import 'helpers/kaynak.dart';

/// Gün içi seri HER yerde aynı (kullanıcı kararı 2026-10-02).
///
/// Bugün kartı ile Performans › Günlük "Ben" kapsamında bir nabız boyunca
/// ayrışıyordu (+₺66 / +₺40, 27 sn): Performans kendi çekimini yapıyor,
/// gün başı her çekimde canlı kotasyondan türetildiği için iki çekim
/// farklı açılış üretiyordu. Ortakta görülmüyordu — orada iki yüzey de
/// aynı yoldan çekiyordu. Artık tek kaynak `IntradaySeriesCache`: aynı
/// küme → aynı yuva → aynı nesne.

Asset _asset(String id, {String owner = 'u'}) => Asset(
      id: id,
      userId: owner,
      name: id,
      ticker: id,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: DateTime(2026, 3, 14),
    );

void main() {
  final simdi = DateTime(2026, 10, 2, 14, 0);
  final cache = IntradaySeriesCache.instance;
  var cekim = 0;

  setUp(() {
    cache.clear();
    HistoryService.clearCache();
    cekim = 0;
    // Her çekim sayılır; seri boş döner (ağ yok) — kimlik karşılaştırması
    // için nesne yeter.
    HistoryService.seriCekici = (s, r, i) async {
      cekim++;
      return const [];
    };
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    cache.clear();
  });

  group('aynı küme → aynı yuva', () {
    test('Ben (get) ve Performans (breakdown) aynı nesneyi alır', () async {
      final defter = [_asset('a'), _asset('b')];
      final state = PortfolioState(assets: defter, ownerId: 'u');
      await cache.get(state, now: simdi);
      final once = cekim;
      final perf = await cache.breakdown(
          state.activeAssets.toList(),
          ownerId: 'u',
          now: simdi.add(const Duration(seconds: 2)),
          azamiYas: const Duration(seconds: 30),
          zorla: true);
      expect(cekim, once, reason: 'kartın 2 sn önceki çekimine katılmalı');
      final kart = await cache.breakdown(state.activeAssets.toList(),
          ownerId: 'u', now: simdi.add(const Duration(seconds: 3)));
      expect(identical(perf, kart), isTrue);
      expect(cache.yuvaSayisiForTest, 1);
    });

    test('anahtar sıraya değil kümeye bağlı', () {
      expect(IntradaySeriesCache.anahtar([_asset('b'), _asset('a')]),
          IntradaySeriesCache.anahtar([_asset('a'), _asset('b')]));
    });

    test('farklı küme (ortak, tür filtresi) ayrı yuva', () async {
      final ben = [_asset('a')];
      final ortak = [_asset('p1', owner: 'p')];
      await cache.breakdown(ben, ownerId: 'u', now: simdi);
      await cache.breakdown(ortak, ownerId: 'u', now: simdi);
      await cache.breakdown([...ben, ...ortak], ownerId: 'u', now: simdi);
      expect(cache.yuvaSayisiForTest, 3);
    });
  });

  group('zorla eşiği: aynı nabzın istekleri birleşir', () {
    test('10 sn\'den taze seri zorla ile yeniden çekilmez', () async {
      final a = [_asset('a')];
      final ilk = await cache.breakdown(a, ownerId: 'u', now: simdi);
      final son = await cache.breakdown(a,
          ownerId: 'u', now: simdi.add(const Duration(seconds: 9)), zorla: true);
      expect(cekim, 1);
      expect(identical(ilk, son), isTrue, reason: 'aynı nabız, aynı nesne');
    });
    test('eşik aşılınca zorla yeniden çeker (nabız yolu)', () async {
      final a = [_asset('a')];
      final ilk = await cache.breakdown(a, ownerId: 'u', now: simdi);
      final son = await cache.breakdown(a,
          ownerId: 'u', now: simdi.add(const Duration(seconds: 29)), zorla: true);
      // Ağ sayımı `HistoryService`'in seri önbelleğine takılır (ikinci
      // istek önbellekten döner); iddia "yeni nesne kuruldu"dur.
      expect(identical(ilk, son), isFalse, reason: 'eşik aşıldı, yeniden kuruldu');
    });
    test('eşik bir nabızdan kısa — sonraki nabzı tutmaz', () {
      expect(IntradaySeriesCache.zorlaEsigi < const Duration(seconds: 30),
          isTrue);
    });
  });

  group('kapılar yuva başına', () {
    test('sahip değişince yalnızca o yuva düşer ve yeniden çekilir', () async {
      final a = [_asset('a')];
      final ilk = await cache.breakdown(a, ownerId: 'A', now: simdi);
      final son = await cache.breakdown(a, ownerId: 'B', now: simdi);
      expect(identical(ilk, son), isFalse,
          reason: 'başkasının serisi bu deftere ait değil — yeniden kuruldu');
      expect(cache.ownerIdForTest == 'A', isFalse);
    });
    test('clear her yuvayı boşaltır', () async {
      await cache.breakdown([_asset('a')], ownerId: 'u', now: simdi);
      await cache.breakdown([_asset('b')], ownerId: 'u', now: simdi);
      cache.clear();
      expect(cache.yuvaSayisiForTest, 0);
      expect(cache.series, isEmpty);
    });
  });

  group('kaynak: gün içi seriyi önbellek dışından çeken yüzey kalmadı', () {
    test('Performans ve Bugün yükleyicisi HistoryService\'e doğrudan gitmez',
        () {
      for (final yol in [
        'lib/screens/portfolio_performance/seriler.dart',
        'lib/services/bugun_yukleyici.dart',
      ]) {
        final src = ekranKaynagiSync(yol);
        expect(src.contains('getPortfolioHistoryHourlyBreakdown('), isFalse,
            reason: '$yol gün içi seriyi IntradaySeriesCache\'ten okumalı');
        expect(src.contains('IntradaySeriesCache.instance'), isTrue);
      }
    });
    test('tek çekim noktası önbellekte', () {
      final src = ekranKaynagiSync('lib/services/daily_summary.dart');
      expect(
          'getPortfolioHistoryHourlyBreakdown('.allMatches(src).length, 1);
    });
  });
}
