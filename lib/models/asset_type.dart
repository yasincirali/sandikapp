import 'package:flutter/material.dart';

enum AssetType {
  hisse('Hisse', Icons.show_chart_rounded, Color(0xFFF5A623), 'TRY'),
  fon('Fon', Icons.pie_chart_rounded, Color(0xFFF5C842), 'TRY'),
  doviz('Döviz', Icons.attach_money_rounded, Color(0xFF2D9E6C), 'USD'),
  altin('Altın', Icons.star_rounded, Color(0xFFF5C842), 'TRY'),
  emtia('Emtia', Icons.inventory_2_rounded, Color(0xFF2D7A60), 'USD'),
  diger('Diğer', Icons.more_horiz_rounded, Color(0xFF2D7A60), 'TRY');

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
