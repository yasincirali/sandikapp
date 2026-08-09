import 'package:flutter/material.dart';

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
  mevduat('Vadeli Mevduat', Icons.savings_rounded, Color(0xFF6BB77B), 'TRY'), // Bank green — güvenli/pasif getiri
  diger('Diğer', Icons.more_horiz_rounded, Color(0xFF8D7BE0), 'TRY');      // Soft violet — nötr, ayrık

  const AssetType(
      this.label, this.icon, this.color, this.defaultCurrency);

  final String label;
  final IconData icon;
  final Color color;
  final String defaultCurrency;

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
      case AssetType.mevduat:
        return 'Vadeli mevduat için ticker gerekmez';
      case AssetType.diger:
        return 'Yahoo Finance sembolü veya boş bırakın';
    }
  }

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
