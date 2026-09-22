import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Ortağın tutarı canlı toplamdan kayboluyordu (kullanıcı bildirimi
/// 2026-09-22, ekran görüntüleriyle).
///
/// ## Belirti
/// Performans › Özet, GÜNLÜK:
///   * Ben      → dönem başı ₺573.064, bugün ₺573.069  (+₺5)
///   * Test     → dönem başı ₺617.553, bugün ₺572.980  (−₺44.573)
///   * Birlikte → dönem başı ₺1.190.617, bugün **₺573.069**  (−₺617.548)
///
/// Birlikte'nin dönem BAŞI doğruydu (573.064 + 617.553 ≈ 1.190.617) ama
/// "bugün" değeri Ben'inkiyle BİREBİR aynıydı — ortağın ₺572.980'i hiç
/// eklenmemişti. Fark da sahte kâr/zarar olarak yazılıyordu.
///
/// ## Neden
/// Dönem başı SERİDEN gelir; seri geçmiş fiyatlardan hesaplandığı için
/// `currentPrice`'a ihtiyaç duymaz. Serinin UCU ise canlı toplama
/// sabitlenir ve canlı toplam lot'un `currentPrice` alanını okur.
///
/// Ortak lot'larının fiyatı RLS yüzünden sunucuya YAZILAMAZ; `refreshPrices`
/// onları yalnızca bellekte günceller. Ama `PartnerAssetsNotifier.build()`
/// `activePartnersProvider`'ı izliyor ve her tetiklendiğinde `fetchByUser`
/// ile DB'den ham lot'ları döndürüp fiyatlı listeyi bayat (çoğu zaman 0)
/// değerle eziyordu. Fiyatı 0'a düşen pozisyon `aggregatePositions`
/// üzerinden toplama girmiyor → ortak yok sayılıyor.
///
/// ## İki katmanlı savunma
///   1. `PartnerAssetsNotifier` fiyatları hatırlar (`_fiyatHafizasi`);
///      `build()` yeniden koşsa da bellekteki ölçülmüş fiyat korunur.
///   2. `ownerScopedTotalValue` fiyatı düşmüş pozisyonu oturumda görülmüş
///      son kotasyondan fiyatlar (`sonFiyat`). Kotasyon hiç görülmemişse
///      pozisyon yine toplama girmez — sıfır UYDURULMAZ
///      (`fiyat_kaynagi.dart` sözleşmesi).
Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double currentPrice,
  AssetType type = AssetType.hisse,
}) =>
    Asset(
      id: '$userId-$ticker-$qty',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 1),
    );

void main() {
  final ben = [
    _lot(userId: 'ben', ticker: 'THYAO', qty: 10, currentPrice: 120),
  ];

  group('fiyatı düşmüş ortak pozisyonu', () {
    // Ortağın lotu DB'den fiyatsız geldi (RLS: sahibi yazabilir).
    final ortakBayat = [
      _lot(userId: 'ortak', ticker: 'ASELS', qty: 5, currentPrice: 0),
    ];
    final birlesik = [...ben, ...ortakBayat];

    test('REGRESYON: sonFiyat olmadan ortak toplamdan düşer', () {
      // Eski davranış — belirtinin ta kendisi.
      final birlikte = ownerScopedTotalValue(lotlarSahibeGore(birlesik));
      final benim = ownerScopedTotalValue(lotlarSahibeGore(ben));
      expect(birlikte, benim,
          reason: 'kök nedenin kanıtı: Birlikte == Ben oluyordu');
    });

    test('son bilinen kotasyonla ortak yeniden görünür', () {
      double? sonFiyat(String t) => t == 'ASELS' ? 140.0 : null;

      final birlikte = ownerScopedTotalValue(lotlarSahibeGore(birlesik),
          sonFiyat: sonFiyat);
      expect(birlikte, 1200.0 + 700.0,
          reason: 'ortağın 5 × ₺140 = ₺700\'ü toplama geri gelmeli');
    });

    test('toplanabilirlik geri kazanıldı', () {
      double? sonFiyat(String t) => t == 'ASELS' ? 140.0 : null;

      final b = ownerScopedTotalValue(lotlarSahibeGore(ben),
          sonFiyat: sonFiyat);
      final o = ownerScopedTotalValue(lotlarSahibeGore(ortakBayat),
          sonFiyat: sonFiyat);
      final birlikte = ownerScopedTotalValue(lotlarSahibeGore(birlesik),
          sonFiyat: sonFiyat);
      expect(b + o, birlikte);
    });

    test('kotasyon YOKSA sıfır uydurulmaz — pozisyon toplama girmez', () {
      double? hicbiri(String t) => null;
      final birlikte = ownerScopedTotalValue(lotlarSahibeGore(birlesik),
          sonFiyat: hicbiri);
      expect(birlikte, 1200.0,
          reason: 'ölçülmemiş fiyat uydurulmaz (fiyat_kaynagi sözleşmesi)');
    });

    test('canlı fiyatı OLAN pozisyon son bilinene düşmez', () {
      // currentPrice > 0 ise sonFiyat hiç sorulmamalı.
      var soruldu = false;
      double? izle(String t) {
        soruldu = true;
        return 999.0;
      }

      final taze = [
        _lot(userId: 'ortak', ticker: 'ASELS', qty: 5, currentPrice: 140),
      ];
      final t = ownerScopedTotalValue(lotlarSahibeGore(taze), sonFiyat: izle);
      expect(t, 700.0);
      expect(soruldu, isFalse,
          reason: 'taze fiyat varken son bilinene düşmek bayat veri olurdu');
    });

    test('ticker\'sız pozisyon (elle fiyatlı) güvenle atlanır', () {
      final tickersiz = [
        _lot(userId: 'ortak', ticker: '', qty: 5, currentPrice: 0),
      ];
      expect(
          ownerScopedTotalValue(lotlarSahibeGore(tickersiz),
              sonFiyat: (_) => 140.0),
          0.0,
          reason: 'sembolü olmayan pozisyona kotasyon eşlenemez');
    });
  });

  test('kaynak: ortak fiyatları build() sırasında korunur', () {
    final src = File('lib/providers/portfolio_provider.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('final Map<String, double> _fiyatHafizasi'), isTrue,
        reason: 'build() bayat DB fiyatını üzerine yazmamalı');
    expect(src.contains('if (a.currentPrice > 0) _fiyatHafizasi[a.id]'), isTrue,
        reason: 'yalnızca ölçülmüş fiyat hatırlanır');
  });

  test('kaynak: build() sembol kotasyonuna da düşer', () {
    // `_fiyatHafizasi` yalnızca `setAssets` sonrası dolar; uygulama yeni
    // açıldığında (refreshPrices henüz koşmadı) boştur. O boşlukta ortak
    // lot'ları yine fiyatsız kalıyordu — sembol kotasyonu ikinci savunma.
    final src = File('lib/providers/portfolio_provider.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('PriceService.instance.sonBilinenFiyat(t)'), isTrue,
        reason: 'hafıza boşken sembol kotasyonundan fiyatlanmalı');
    expect(src.contains('if (t.isEmpty || a.isManualPrice) continue;'), isTrue,
        reason: 'elle fiyatlanan lot piyasa kotasyonuyla ezilmemeli');
  });

  test('kaynak: canlı toplam son bilinen fiyata düşebilir', () {
    final src = File('lib/services/daily_summary.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('sonFiyat: PriceService.instance.sonBilinenFiyat'),
        isTrue);
  });
}
