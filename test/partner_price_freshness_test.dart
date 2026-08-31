import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Ortağın varlıkları CANLI fiyatla değerlenmeli — DB'deki bayat fiyatla değil.
///
/// **Bug (2026-08-31):** Simülasyon sekmesinde, dönem içinde hiç alım/satım
/// olmamasına rağmen ortağın altını farklı kâr/zarar oranı gösteriyordu.
///
/// **Kök neden:** `refreshPrices` ortak lot'larının `currentPrice`'ını
/// bellekte canlı kotasyonla güncelliyor (RLS yüzünden DB'ye YAZAMAZ), ama
/// hemen ardından `allPartnerAssetsProvider.reload()` çağrılıyordu. O metot
/// `fetchByUser` ile DB'den yeniden çekiyor ve az önce uygulanan fiyatları
/// çöpe atıyordu. DB'deki `current_price` yalnızca varlığın SAHİBİ
/// uygulamayı açtığında güncellenir — yani ortak son ne zaman girdiyse
/// o fiyat kalıyordu.
///
/// **Neden altında görünür:** altın `currentPrice`'ı gram22k × ağırlık katı
/// ile türetilir ve gün içinde hızlı oynar. Grafiğin geçmiş serisi fiyatı
/// kendi geçmiş verisinden hesapladığı için GÜNCELDİ; bayat kalan yalnızca
/// serinin son noktasıydı (canlı toplam, `ownerScopedTotalValue`).
/// Simülasyonda tüm dönem bugünkü net pozisyonla çizildiğinden bu sapma
/// yüzdeye birebir yansıyordu.
///
/// **Neden "alım yokken bile":** hata miktarla değil FİYATLA ilgili.
/// Dönem içinde hiç işlem olmasa da iki taraf farklı `currentPrice`
/// kullandığı için oranlar ayrışıyordu.

Asset _altin({
  required String id,
  required String userId,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  String ticker = 'ALTIN_GRAM',
}) =>
    Asset(
      id: id,
      userId: userId,
      name: 'Gram Altın',
      ticker: ticker,
      type: AssetType.altin,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      subCategory: '22 Ayar',
      purchaseFxRate: 1.0,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 15),
    );

/// `refreshPrices` içindeki ortak fiyatlama döngüsünün aynısı.
void _applyLiveQuotes(
  Map<String, List<Asset>> partnerMap,
  Map<String, double> quotes,
) {
  for (final assets in partnerMap.values) {
    for (final a in assets) {
      if (!a.isManualPrice && a.ticker.isNotEmpty) {
        final p = quotes[a.ticker.toUpperCase()];
        if (p != null) {
          a.currentPrice = p;
          a.lastUpdated = DateTime.now();
        }
      }
    }
  }
}

void main() {
  group('ortak varlıkları canlı fiyatla değerlenir', () {
    test('canlı kotasyon ortağın altınına UYGULANIR', () {
      // DB'deki bayat fiyat 4000; canlı fiyat 5000.
      final partnerMap = {
        'p1': [
          _altin(
              id: 'p1-altin',
              userId: 'p1',
              qty: 10,
              buyPrice: 3000,
              currentPrice: 4000),
        ],
      };
      _applyLiveQuotes(partnerMap, {'ALTIN_GRAM': 5000});

      expect(partnerMap['p1']!.first.currentPrice, 5000,
          reason: 'ortak lot canlı fiyatı almalı');
    });

    test('BAYAT fiyat kâr/zarar oranını saptırır — hatanın ölçüsü', () {
      // Aynı altın, aynı maliyet, aynı miktar. Tek fark: fiyat tazeliği.
      final benim = _altin(
          id: 'me', userId: 'me', qty: 10, buyPrice: 4000, currentPrice: 5000);
      final ortakBayat = _altin(
          id: 'p1', userId: 'p1', qty: 10, buyPrice: 4000, currentPrice: 4000);

      final benimPct = aggregatePositions([benim]).single.gainLossPercentage;
      final bayatPct =
          aggregatePositions([ortakBayat]).single.gainLossPercentage;

      expect(benimPct, closeTo(25, 0.001));
      expect(bayatPct, closeTo(0, 0.001));
      expect(benimPct == bayatPct, isFalse,
          reason: 'bayat fiyat farkı — kullanıcının gördüğü hata buydu');
    });

    test('fiyat tazelendikten sonra iki taraf AYNI oranı verir', () {
      // Aynı ürün, aynı maliyet: fiyat eşitlenince oran da eşitlenmeli.
      final benim = _altin(
          id: 'me', userId: 'me', qty: 10, buyPrice: 4000, currentPrice: 5000);
      final ortakMap = {
        'p1': [
          _altin(
              id: 'p1',
              userId: 'p1',
              qty: 7, // miktar farklı olabilir — ORAN etkilenmemeli
              buyPrice: 4000,
              currentPrice: 4000),
        ],
      };
      _applyLiveQuotes(ortakMap, {'ALTIN_GRAM': 5000});

      final benimPct = aggregatePositions([benim]).single.gainLossPercentage;
      final ortakPct =
          aggregatePositions(ortakMap['p1']!).single.gainLossPercentage;

      expect(benimPct, closeTo(25, 0.001));
      expect(ortakPct, closeTo(25, 0.001));
      expect(benimPct, closeTo(ortakPct, 0.0001),
          reason: 'aynı ürün + aynı maliyet + taze fiyat → aynı oran');
    });

    test('canlı toplam değer de tazelenmiş fiyatı kullanır', () {
      // `ownerScopedTotalValue` grafiğin SON noktasını belirler; bayat
      // fiyatta bu nokta düşük kalıyor ve simülasyon yüzdesini saptırıyordu.
      final ortakMap = {
        'p1': [
          _altin(
              id: 'p1',
              userId: 'p1',
              qty: 10,
              buyPrice: 3000,
              currentPrice: 4000),
        ],
      };
      expect(ownerScopedTotalValue([ortakMap['p1']!]), closeTo(40000, 0.01));

      _applyLiveQuotes(ortakMap, {'ALTIN_GRAM': 5000});
      expect(ownerScopedTotalValue([ortakMap['p1']!]), closeTo(50000, 0.01),
          reason: 'son nokta canlı fiyattan hesaplanmalı');
    });

    test('refreshPrices ortak listesini DB\'den yeniden ÇEKMEZ', () async {
      // Bağlantı (wiring) koruması. Yukarıdaki testler fiyatlama mantığının
      // doğru olduğunu kanıtlar, ama asıl hata mantıkta değil SIRADAYDI:
      // fiyatlar uygulanıyor, sonra `reload()` onları DB'den gelen bayat
      // veriyle eziyordu. Bu regresyon birim testiyle görünmez — sabotajla
      // ölçüldü, bu yüzden kaynak metni denetleniyor.
      final src = await File(
        'lib/providers/portfolio_provider.dart',
      ).readAsString();

      // `refreshPrices` gövdesini izole et (sonraki metoda kadar).
      final start = src.indexOf('Future<void> refreshPrices(');
      expect(start, greaterThan(-1), reason: 'refreshPrices bulunamadı');
      final after = src.indexOf('\n  Future<void> _saveSnapshot', start);
      final govde = src.substring(start, after > 0 ? after : src.length);

      expect(
        govde.contains('allPartnerAssetsProvider.notifier).reload()'),
        isFalse,
        reason: 'refreshPrices içinde reload() çağrılırsa canlı fiyatlar '
            'DB\'den gelen bayat veriyle ezilir — ortağın altını yanlış '
            'kâr/zarar gösterir.',
      );
      expect(
        govde.contains('setAssets(partnerAssetsMap)'),
        isTrue,
        reason: 'fiyatlanmış liste doğrudan yazılmalı',
      );
    });

    test('manuel fiyatlı ortak varlığı EZİLMEZ', () {
      // Kullanıcı fiyatı elle girdiyse canlı kotasyon onu ezmemeli.
      final manuel = Asset(
        id: 'p1-manuel',
        userId: 'p1',
        name: 'Özel',
        ticker: 'ALTIN_GRAM',
        type: AssetType.altin,
        quantity: 1,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: true,
        purchaseFxRate: 1.0,
        currentPrice: 123,
        addedDate: DateTime(2026, 1, 15),
      );
      final map = {
        'p1': [manuel]
      };
      _applyLiveQuotes(map, {'ALTIN_GRAM': 5000});
      expect(manuel.currentPrice, 123, reason: 'manuel fiyat korunmalı');
    });
  });
}
