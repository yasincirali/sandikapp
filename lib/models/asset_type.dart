import 'package:flutter/material.dart';

enum AssetType {
  hisse('Hisse', Icons.show_chart_rounded, Color(0xFF2196F3), 'TRY'),
  fon('Fon', Icons.pie_chart_rounded, Color(0xFF9C27B0), 'TRY'),
  doviz('Döviz', Icons.attach_money_rounded, Color(0xFF4CAF50), 'USD'),
  altin('Altın', Icons.star_rounded, Color(0xFFCCA919), 'TRY'),
  emtia('Emtia', Icons.inventory_2_rounded, Color(0xFFFF9800), 'USD'),
  diger('Diğer', Icons.more_horiz_rounded, Color(0xFF9E9E9E), 'TRY');

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
      case AssetType.diger:
        return 'Yahoo Finance sembolü veya boş bırakın';
    }
  }

  static AssetType fromString(String value) => AssetType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AssetType.diger,
      );
}
