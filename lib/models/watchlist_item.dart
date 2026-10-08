import 'asset_categories.dart';
import 'asset_type.dart';

/// Takip listesindeki bir varlık — sahip OLMADIĞIN, yalnızca izlediğin.
///
/// ## Neden `Asset` değil
/// `Asset` miktar (`quantity`) ve alış fiyatı (`purchasePrice`) zorunlu tutar;
/// takip edilen varlıkta ikisi de YOKTUR. Sahte değerlerle bir `Asset` üretmek
/// (`quantity: 1, purchasePrice: currentPrice`) kolay ama tehlikeli olurdu:
/// o nesne yanlışlıkla bir aggregate'e girerse portföy toplamını sessizce
/// bozar. Bu proje bu hata sınıfını iki kez yaşadı (ortak lot havuzlanması,
/// tür dökümünün ayrı veri yolu).
///
/// Ayrı tip + ayrı tablo = takip edilen varlığın toplama girmesi yapısal
/// olarak imkânsız. Bkz. `supabase/migrations/0043_watchlist.sql`.
///
/// **Değişmez:** Bu tip hiçbir portföy hesabına (toplam değer, kâr/zarar, tür
/// dökümü, grafik serisi, leaderboard, Live Activity) girmez.
class WatchlistItem {
  final String id;
  final String userId;

  /// Fiyat çözümü için sembol — `resolveSymbol(ticker, type)` ile aynı yolu
  /// kullanır, yani `assets` tarafıyla birebir aynı sembole çözülür.
  final String ticker;
  final String name;
  final AssetType type;

  /// Altın/döviz alt kategorisi (Çeyrek, Gram, USD…). Olmadan Gram ve Çeyrek
  /// altın aynı kayda düşerdi — `positionKey` ile aynı gerekçe.
  final String? subCategory;

  final String currency;
  final DateTime addedAt;

  /// Canlı fiyat — DB'de TUTULMAZ, çalışma zamanında doldurulur.
  ///
  /// Takip kaydı fiyat saklamaz: saklarsa bayatlar ve hangi anın fiyatı
  /// olduğu belirsizleşir. `PriceService` her açılışta tazeler.
  final double? currentPrice;

  /// Seçili dönemdeki değişim yüzdesi — DB'de TUTULMAZ.
  /// Dönem seçicisi değiştikçe yeniden hesaplanır.
  final double? periodChangePct;

  const WatchlistItem({
    required this.id,
    required this.userId,
    required this.ticker,
    required this.name,
    required this.type,
    required this.currency,
    required this.addedAt,
    this.subCategory,
    this.currentPrice,
    this.periodChangePct,
  });

  /// Aynı varlığın iki kez takip edilmesini engelleyen anahtar.
  ///
  /// `positionKey` ile aynı mantık: tür + sembol + alt kategori. Sunucudaki
  /// unique index (`watchlist_user_asset_uidx`) bunun karşılığıdır — iki taraf
  /// ayrışırsa istemci "zaten var" derken sunucu kabul eder (ya da tersi).
  String get key {
    final sub = anahtarAltKategorisi(subCategory);
    final core = (sub?.trim().isNotEmpty ?? false)
        ? 'sub:${sub!.trim().toUpperCase()}'
        : ticker.trim().toUpperCase();
    return '${type.name}|$core';
  }

  /// Takip satırında, grafikte ve grafik açıklamasında gösterilen kısa ad.
  ///
  /// TEK tanım: satır (`watchlist_screen` `displayLabel`) ve grafik
  /// (`watchlistChartProvider` `chartLabel`) ayrı kopyalar taşıyordu; ikisi de
  /// iç sembolleri ham basıyordu — açıklamada "ALTIN_GRAM", "ALTIN_GREMSE",
  /// "XU100" (2026-09-29 emülatör testi #17). Kural:
  ///   · hisse/fon/kripto → sembolün kendisi (`TEFAS:AFO` → `AFO`,
  ///     `AGHOL.IS` → `AGHOL`): kullanıcının tanıdığı kısaltma bu;
  ///   · altın iç sembolü (`ALTIN_*`), emtia vadelisi (`GC=F`) ve BIST
  ///     endeksi → görünen ad: bu kodlar kullanıcıya hiçbir şey söylemez;
  ///   · kur çifti (`USDTRY=X`) → para kodu (`USD`).
  String get kisaEtiket {
    final t = ticker.trim();
    final sub = subCategory?.trim();
    String ad() {
      if (sub != null && sub.isNotEmpty) return sub;
      return name.trim().isNotEmpty ? name.trim() : t;
    }

    if (t.isEmpty) return ad();
    final buyuk = t.toUpperCase();
    if (buyuk.startsWith('ALTIN_') ||
        buyuk.endsWith('=F') ||
        bistEndeksiMi(t)) {
      return name.trim().isNotEmpty ? name.trim() : ad();
    }
    if (buyuk.endsWith('TRY=X')) return buyuk.replaceAll('TRY=X', '');
    final sade = t.contains(':') ? t.split(':').last : t.replaceAll('.IS', '');
    return sade.length >= 2 ? sade : ad();
  }

  WatchlistItem copyWith({
    double? currentPrice,
    double? periodChangePct,
  }) =>
      WatchlistItem(
        id: id,
        userId: userId,
        ticker: ticker,
        name: name,
        type: type,
        currency: currency,
        addedAt: addedAt,
        subCategory: subCategory,
        currentPrice: currentPrice ?? this.currentPrice,
        periodChangePct: periodChangePct ?? this.periodChangePct,
      );

  factory WatchlistItem.fromMap(Map<String, dynamic> m) => WatchlistItem(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        ticker: (m['ticker'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        type: AssetType.fromString((m['type'] as String?) ?? 'diger'),
        subCategory: m['sub_category'] as String?,
        currency: (m['currency'] as String?) ?? 'TRY',
        addedAt: m['added_at'] != null
            ? DateTime.parse(m['added_at'] as String)
            : DateTime.now(),
      );

  /// Sunucuya yazılacak alanlar. `id` ve `added_at` sunucuda üretilir;
  /// canlı fiyat ve dönem değişimi ASLA yazılmaz (bkz. alan notları).
  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'ticker': ticker,
        'name': name,
        'type': type.name,
        if (subCategory != null && subCategory!.trim().isNotEmpty)
          'sub_category': subCategory,
        'currency': currency,
      };
}
