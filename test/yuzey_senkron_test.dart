import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

import 'helpers/kaynak.dart';

/// Beş yüzey senkron (kullanıcı kararı 2026-10-02): ana sayfa toplam
/// varlık, Bugün kartı, Performans › GÜNLÜK, widget ve Live Activity aynı
/// anda aynı rakamı göstermeli.
///
/// Ölçülen ayrışmalar ve kapattıkları:
///   1. Ana sayfa toplamı fiyatı düşmüş pozisyonu dışarıda bırakıyordu,
///      diğerleri son kotasyona düşüyordu → `totalValue` == `liveTotalTRY`.
///   2. Bir yüzey taze seri çekince diğerleri ≤ 30 sn eski seride kalıyordu
///      (açılışta widget +₺335 / Performans +₺148) → `IntradaySeriesCache
///      .surum` sinyali; kart, Performans, widget ve Live Activity dinler.
///   3. Sekmeye dönüşte nabız beklenmiyordu → görünürlük dinleyicisi.
///   4. Gün başı referansı her turda yuvarlamayla oynuyordu → gün içinde
///      sabit (`gunluk_referans_sabit_test`).
Asset _lot(String id, {double fiyat = 110}) => Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: '$id.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

void main() {
  tearDown(() {
    PriceService.instance.sonBilinenFiyatlariTemizle();
    IntradaySeriesCache.instance.clear();
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
  });

  test('ana sayfa toplamı == Bugün/widget/Live Activity toplamı '
      '(fiyatı düşmüş pozisyon dahil)', () {
    PriceService.instance.testIcinKotasyonYaz('BBB.IS', 50);
    final state = PortfolioState(
      assets: [_lot('AAA'), _lot('BBB', fiyat: 0)],
      ownerId: 'u',
    );
    expect(state.totalValue, DailySummary.liveTotalTRY(state));
    expect(state.totalValue, 10 * 110 + 10 * 50);
  });

  test('yeni seri yazılınca sürüm artar ve hangi yuva olduğu bilinir',
      () async {
    HistoryService.seriCekici = (s, r, i) async => const [];
    final c = IntradaySeriesCache.instance;
    final once = c.surum.value;
    final lotlar = [_lot('AAA')];
    await c.breakdown(lotlar,
        ownerId: 'u', now: DateTime(2026, 10, 2, 14));
    expect(c.surum.value, once + 1);
    expect(c.sonGuncellenen, IntradaySeriesCache.anahtar(lotlar));
    // Önbellekten dönen okuma sürüm ARTIRMAZ (dinleyici döngüsü yok).
    await c.breakdown(lotlar,
        ownerId: 'u', now: DateTime(2026, 10, 2, 14, 0, 5));
    expect(c.surum.value, once + 1);
  });

  group('kaynak: her yüzey sinyali dinler', () {
    test('Bugün kartı, Performans ve widget/Live Activity güncelleyicisi', () {
      final kart = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      expect(kart.contains('IntradaySeriesCache.instance.surum.addListener(_seriGeldi)'),
          isTrue);
      expect(kart.contains('surum.removeListener(_seriGeldi)'), isTrue);
      final perf =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(
          perf.contains(
              'IntradaySeriesCache.instance.surum.addListener(_gunIciSeriGeldi)'),
          isTrue);
      expect(perf.contains('surum.removeListener(_gunIciSeriGeldi)'), isTrue);
      final main = ekranKaynagiSync('lib/main.dart');
      expect(
          main.contains(
              'IntradaySeriesCache.instance.surum.addListener(_gunIciSeriGeldi)'),
          isTrue);
      expect(main.contains('LiveActivityService.instance.sync(snapshot'),
          isTrue);
      expect(main.contains('c.sonGuncellenen != c.benAnahtari'), isTrue,
          reason: 'widget ve kilit ekranı yalnız kişisel yuvayı yazar');
    });

    test('ana sayfa toplamı son kotasyon yedeğini alır', () {
      final p = ekranKaynagiSync('lib/providers/portfolio_provider.dart');
      expect(
          p.replaceAll(RegExp(r'\s+'), ' ').contains(
              'double get totalValue => ownerScopedTotalValue(lotlarSahibeGore(assets), toTRY: toTRY, sonFiyat: PriceService.instance.sonBilinenFiyat);'),
          isTrue);
    });
  });
}
