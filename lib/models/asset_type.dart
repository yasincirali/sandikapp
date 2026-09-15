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
        AssetType.diger => l.assetTypeOther,
      };

  /// Sembol alanının ipucu — dile göre.
  String tickerHintOf(AppLocalizations l) => switch (this) {
        AssetType.hisse => l.tickerHintStock,
        AssetType.fon => l.tickerHintFund,
        AssetType.doviz => l.tickerHintFx,
        AssetType.altin => l.tickerHintGold,
        AssetType.emtia => l.tickerHintCommodity,
        AssetType.diger => l.tickerHintOther,
      };

  String get tickerHint {
    switch (this) {
      case AssetType.hisse:
        return 'Örn: THYAO.IS, GARAN.IS  (Borsa İstanbul için .IS ekleyin)';
      case AssetType.fon:
        return 'Yahoo Finance kodu yoksa boş bırakın, fiyatı manuel girin';
      case AssetType.doviz:
        return 'Örn: USDTRY=X, EURTRY=X, GBPTRY=X';
      case AssetType.altin:
        return 'Örn: XAUTRY=X (gram altın TL) veya GC=F (ons, USD)';
      case AssetType.emtia:
        return 'Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)';
      case AssetType.diger:
        return 'Yahoo Finance sembolü veya boş bırakın';
    }
  }

  /// Bilinmeyen tür → `diger`. Kaldırılan 'mevduat' (2026-09-14) da buraya
  /// düşer; 0058 migrasyonu eski satırları sunucuda zaten 'diger' yapar.
  static AssetType fromString(String value) => AssetType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AssetType.diger,
      );
}

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
