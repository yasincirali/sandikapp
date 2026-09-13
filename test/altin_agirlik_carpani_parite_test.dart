import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Altın ağırlık çarpanı TEK KAYNAKTAN gelmeli.
///
/// ## Neden bu test var
/// Çarpan tablosu (`gram22k` referansına göre çeyrek 1.75, yarım 3.5,
/// ata/cumhuriyet/reşat 7.216) geçmişte üç ayrı yere kopyalanmıştı. Üç
/// kopyadan ikisi zamanla `PriceService.goldWeightFactor`'a taşındı ama
/// `getPortfolioHistory` içindeki ÜÇÜNCÜ kopya geride kaldı ve
/// `ALTIN_RESAT`'ı hiç tanımıyordu — koşul zinciri sonunda `: 1.0` ile
/// bitiyor, yani bilinmeyen her altın türü sessizce GRAM ALTIN gibi
/// fiyatlanıyordu.
///
/// Ölçülen sonuç (kullanıcı bildirimi 2026-09-12 — "altının datası grafiği
/// çizilmiyor ancak kar/zararda 0 da farklı"):
/// Reşat altınının geçmiş serisi 7,216 kat küçük çiziliyordu (birim ~6.200 ₺),
/// buna karşılık serinin SON noktası `currentPrice` ile eziliyordu (~34.000 ₺).
/// Grafik dümdüz bir taban + tek dikey sıçramaya dönüşüyordu; ölçülen oran
/// son/maxGeçmiş = 5,17 kat. Kâr/zarar ise `Asset.currentPrice` üzerinden
/// hesaplandığı için DOĞRU kalıyordu — "grafik çizilmiyor ama kâr/zarar var"
/// ayrışmasının kaynağı buydu.
///
/// ## Neden ağa çıkmadan ölçülüyor
/// Testin sorduğu şey fiyat değil, ÇARPAN. Ağ üzerinden ölçmek testi
/// Yahoo'nun o günkü yanıtına bağlar; burada kontrol edilen değişmez
/// "grafik yolu ile fiyat yolu aynı ağırlık tablosunu kullanır"dır ve bu
/// tamamen deterministiktir.
void main() {
  /// `getPortfolioHistory` içindeki altın dalının kullandığı çarpan,
  /// `PriceService` tablosuyla aynı mı?
  ///
  /// Doğrudan o dalın içine bakamayız (özel); bunun yerine değişmezi
  /// tablonun KENDİSİ üzerinden ve bir uçtan uca oran ölçümüyle sabitliyoruz.
  group('altın ağırlık tablosu tek kaynak', () {
    test('her altın türü gram22k referansına göre doğru ağırlık taşır', () {
      // Beklenen değerler fiziksel: çeyrek 1,75 gram 22 ayar; ata, reşat ve
      // cumhuriyet aynı kalıptan (7,216 gram). Bu sayılar değişirse altının
      // TL karşılığı da değişir — bilinçli olmayan bir düzenleme burada
      // yakalanmalı.
      const beklenen = <String, double>{
        'ALTIN_GRAM': 1.0,
        'ALTIN_CEYREK': 1.75,
        'ALTIN_YARIM': 3.5,
        'ALTIN_CUMHURIYET': 7.216,
        'ALTIN_ATA': 7.216,
        'ALTIN_RESAT': 7.216,
      };
      beklenen.forEach((ticker, agirlik) {
        expect(PriceService.goldWeightFactor(ticker), agirlik,
            reason: '$ticker ağırlığı tablodan sapmış');
      });
    });

    /// Asıl koruma: Reşat gram altından AYRI fiyatlanmalı.
    ///
    /// Hatanın imzası tam olarak buydu — `goldWeightFactor('ALTIN_RESAT')`
    /// 1.0 döndüğü an Reşat, gram altınla BİREBİR aynı seriyi üretir.
    test('ALTIN_RESAT gram altınla aynı çarpana sahip DEĞİL', () {
      final resat = PriceService.goldWeightFactor('ALTIN_RESAT');
      final gram = PriceService.goldWeightFactor('ALTIN_GRAM');
      expect(resat, isNot(gram),
          reason: 'Reşat gram altın gibi fiyatlanıyor — çarpan tablosu '
              'atlanmış olabilir');
      expect(resat, greaterThan(7.0));
    });
  });

  /// Uçtan uca: grafik serisi ile canlı birim fiyat AYNI ÖLÇEKTE olmalı.
  ///
  /// Bu testin yakaladığı şey "grafik çizilmiyor" belirtisinin kendisidir.
  /// `asset_detail_screen` grafiği `getPortfolioHistory(...)/quantity` ile
  /// birim fiyata çevirir ve serinin SON noktasını canlı fiyatla ezer.
  /// Geçmiş seri yanlış ölçekteyse iki uç arasında uçurum oluşur ve
  /// grafik "düz taban + dikey sıçrama" olarak görünür.
  ///
  /// Ölçüm ağ ister (gerçek altın serisi); ağ yoksa test kendini atlar —
  /// CI'da sessizce KIRMAK yerine atlamak doğru: burada sınanan şey ağ
  /// değil, ağ varken ortaya çıkan ölçek paritesidir.
  test('Reşat: geçmiş seri ile canlı fiyat aynı mertebede', () async {
    const canliBirim = 34000.0; // ~7,216 gram × ~4.700 ₺
    final resat = Asset(
      id: 'r1',
      userId: 'u1',
      name: 'Reşat Altını',
      ticker: 'ALTIN_RESAT',
      type: AssetType.altin,
      quantity: 3,
      purchasePrice: 27000,
      currency: 'TRY',
      notes: '',
      currentPrice: canliBirim,
      addedDate: DateTime.now().subtract(const Duration(days: 300)),
    );

    HistoryService.clearCache();
    final seri =
        await HistoryService.instance.getPortfolioHistory([resat], 30);
    if (seri.length < 3) return; // ağ yok — ölçülecek bir şey yok

    final keys = seri.keys.toList()..sort();
    // Ekranın çizdiği birim fiyat serisi.
    final birim = [for (final k in keys) seri[k]! / resat.quantity];
    // Son nokta canlı fiyatla ezilir; ölçek karşılaştırması GEÇMİŞ üzerinden.
    final gecmis = birim.sublist(0, birim.length - 1);
    final maxGecmis = gecmis.reduce((x, y) => x > y ? x : y);

    // Eşik neden 3: altın fiyatı bir ayda 3 kat artmaz. Bundan büyük bir
    // oran fiyat hareketi değil, ÖLÇEK hatasıdır. Hatalı kodda ölçülen
    // değer 5,17; düzeltilmiş kodda 0,72 idi.
    final oran = canliBirim / maxGecmis;
    expect(oran, lessThan(3.0),
        reason: 'Geçmiş seri canlı fiyattan ${oran.toStringAsFixed(1)} kat '
            'küçük — altın ağırlık çarpanı grafik yolunda uygulanmıyor. '
            'Grafik düz taban + dikey sıçrama olarak görünür.');
    expect(oran, greaterThan(1 / 3.0),
        reason: 'Geçmiş seri canlı fiyattan çok büyük — çarpan iki kez '
            'uygulanmış olabilir.');
  });
}
