import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

enum AssetType {
  // Kategori renkleri — Sandık marka ailesine sadık, canlı ama karakteri
  // bozmayan sıcak/nötr tonlar. Her kategori grafikte ve etikette birbirinden
  // kolay ayırt edilebilir olmalı; gain/loss (yeşil/kırmızı) semantik
  // renkleriyle çakışmamalı.
  hisse('Hisse', Icons.show_chart_rounded, Sandik.amber, 'TRY'),      // Amber — marka CTA
  fon('Fon', Icons.pie_chart_rounded, Sandik.info, 'TRY'),           // Sky blue — nötr/finansal
  doviz('Döviz', Icons.attach_money_rounded, Color(0xFF7EC8A9), 'USD'),     // Soft mint — gain'den ayrık
  altin('Altın', Icons.star_rounded, Sandik.gold, 'TRY'),            // Gold — altın karakteri
  emtia('Emtia', Icons.inventory_2_rounded, Color(0xFFC97B4F), 'USD'),      // Copper — emtia sıcaklığı
  // Orkide — mevcut altı renge ve gain/loss'a uzak (2026-09-25 kripto planı).
  // Varsayılan para birimi TRY: fiyat sunucuda TL paritesinden (ya da
  // USDT × USDTTRY) hesaplanır, maliyet de TL girilir (Türkiye'de alımların
  // çoğu TL paritesinden). Sıra `diger`'in ÖNÜNDE: `values` döngüleri
  // (filtre çipi, tür dökümü) "Diğer"i hep sonda gösteriyor.
  kripto('Kripto', Icons.currency_bitcoin_rounded, Color(0xFFD47FC4), 'TRY'),
  diger('Diğer', Icons.more_horiz_rounded, Color(0xFF8D7BE0), 'TRY');      // Soft violet — nötr, ayrık

  const AssetType(
      this.label, this.icon, this.color, this.defaultCurrency);

  final String label;
  final IconData icon;

  /// Kategori rengi — DOLGU ve nokta/şerit için. Metin ya da ikon olarak
  /// kullanılacaksa [onSurface].
  final Color color;
  final String defaultCurrency;

  /// Light zeminde ikon/metin olarak okunabilen ton.
  ///
  /// Kategori renkleri koyu marka zemini için seçildi; light zeminde yedisi
  /// de AA altında kalıyordu (ölçüm 2026-08-09: altın 1,52:1). Arkasında
  /// %12-15 alfa dolgu olan rozetlerde bu sorun değil, ama çıplak ikon ve
  /// tür etiketi metninde okunmuyordu. Ton aynı, yalnızca açıklık kısılır —
  /// kategori kimliği (amber = hisse, mavi = fon) korunur.
  /// `asset_type_light_contrast_test` her türü light `surface1` üstünde
  /// ≥ 4,5:1'e bağlar.
  Color onSurface(BuildContext context) =>
      context.isLight ? onLightSurface : color;

  /// [onSurface]'in light dalı — test edilebilsin diye `BuildContext`'siz.
  Color get onLightSurface {
    // 0,28: amber/gold gibi sıcak, parlak tonların light zeminde 4,5:1'e
    // ulaştığı en yüksek açıklık (0,32'de altın 4,03:1 kalıyordu).
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(hsl.lightness > 0.28 ? 0.28 : hsl.lightness)
        .toColor();
  }

  /// Ekranda görünen tür adı — dile göre (3.20).
  ///
  /// [label] TÜRKÇE kalır ve DEĞİŞMEZ: bildirim/özet metinleri, paylaşım
  /// kartı ve sunucu tarafı onu kullanıyor; ayrıca alt kategori
  /// karşılaştırmalarında (`_subCategory == g.label`) veri değeri gibi
  /// davranıyor. Görüntüleme yüzeyleri bunu çağırır.
  String labelOf(AppLocalizations l) => switch (this) {
        AssetType.hisse => l.assetTypeStock,
        AssetType.fon => l.assetTypeFund,
        AssetType.doviz => l.assetTypeFx,
        AssetType.altin => l.assetTypeGold,
        AssetType.emtia => l.assetTypeCommodity,
        AssetType.kripto => l.assetTypeCrypto,
        AssetType.diger => l.assetTypeOther,
      };

  /// Sembol alanının ipucu — dile göre.
  String tickerHintOf(AppLocalizations l) => switch (this) {
        AssetType.hisse => l.tickerHintStock,
        AssetType.fon => l.tickerHintFund,
        AssetType.doviz => l.tickerHintFx,
        AssetType.altin => l.tickerHintGold,
        AssetType.emtia => l.tickerHintCommodity,
        AssetType.kripto => l.tickerHintCrypto,
        AssetType.diger => l.tickerHintOther,
      };

  /// Bilinmeyen tür → `diger`. Kaldırılan 'mevduat' (2026-09-14) da buraya
  /// düşer; 0058 migrasyonu eski satırları sunucuda zaten 'diger' yapar.
  static AssetType fromString(String value) => AssetType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AssetType.diger,
      );
}

/// Kripto sembol öneki — `assets.ticker` = `KRIPTO:BTC`.
///
/// `TEFAS:` gibi: kaynak sembolden okunur ve Yahoo'ya DÜŞMEZ. Fiyatı sunucu
/// çeker (`kripto_fiyat`, 0074); sunucudaki karşılığı
/// `supabase/functions/_shared/kripto.ts` `KRIPTO_ONEKI`.
const String kriptoOneki = 'KRIPTO:';

final RegExp _kriptoKodDeseni = RegExp(r'^[A-Z0-9]{2,15}$');

/// `KRIPTO:btc` → `BTC`; kripto sembolü değilse `null`.
String? kriptoKodu(String ticker) {
  final s = ticker.trim().toUpperCase();
  if (!s.startsWith(kriptoOneki)) return null;
  final kod = s.substring(kriptoOneki.length);
  return _kriptoKodDeseni.hasMatch(kod) ? kod : null;
}

/// `BTC` → `KRIPTO:BTC`.
String kriptoSembolu(String kod) => '$kriptoOneki${kod.trim().toUpperCase()}';

// Döviz kodu → para sembolü
const _currencySymbols = <String, String>{
  'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥',
  'CHF': '₣', 'CAD': 'C\$', 'AUD': 'A\$', 'CNY': '¥',
  'RUB': '₽', 'SAR': '﷼', 'AED': 'د', 'TRY': '₺',
  'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr', 'PLN': 'zł',
  'HUF': 'Ft', 'CZK': 'Kč', 'RON': 'lei', 'INR': '₹',
  'KRW': '₩', 'BRL': 'R\$', 'MXN': 'M\$', 'ZAR': 'R',
  'SGD': 'S\$', 'HKD': 'HK\$', 'NZD': 'NZ\$',
};

/// Ticker'dan döviz kodunu çıkarır.
/// "USDTRY=X" → "USD", "EURTRY=X" → "EUR"
String? _extractCurrencyCode(String ticker, String currency) {
  final clean = ticker.replaceAll('=X', '').replaceAll('.IS', '').trim().toUpperCase();
  if (clean.length >= 3) {
    final code = clean.substring(0, 3);
    if (code != 'TRY' && _currencySymbols.containsKey(code)) return code;
  }
  final cur = currency.toUpperCase();
  if (cur != 'TRY' && _currencySymbols.containsKey(cur)) return cur;
  return null;
}

/// Döviz varlığı için para sembolü döndürür.
/// Ticker öncelikli: "USDTRY=X" → "\$", "EURTRY=X" → "€"
String? currencySymbolFor(String ticker, String currency) {
  final code = _extractCurrencyCode(ticker, currency);
  return code != null ? _currencySymbols[code] : null;
}
