import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Her altın türü uçtan uca TANIMLI olmalı: ekleme çipi → iç sembol →
/// truncgil anahtarı → yedek ağırlık → sunucu eşleri.
///
/// ## Neden bu test var (2026-09-25)
/// "Normal gram altın yok" (kullanıcı). Tür listesi genişletilirken bir
/// halkayı atlamak sessizdir: sembol `_truncgilGoldKeys`'te yoksa fiyat
/// Yahoo yedeğine düşer, `_goldWeights`'te yoksa çarpan 1.0 olur ve çeyrek
/// gibi bir sikke GRAM fiyatıyla görünür (Reşat'ın 2026-09-12 hatası, bkz.
/// `altin_agirlik_carpani_parite_test`). Sunucu eşleri (`GOLD_KEYS`,
/// `GOLD_WEIGHTS`) eksikse alarm ve sinyal o türü hiç görmez.
void main() {
  final altinTurleri =
      GoldSubCategory.values.where((g) => g != GoldSubCategory.ons).toList();

  final priceSrc = File('lib/services/price_service.dart').readAsStringSync();
  final dartAnahtar = _blok(priceSrc, '_truncgilGoldKeys');
  final dartAgirlik = _blok(priceSrc, '_goldWeights');
  final tsAnahtar = _blok(
    File('supabase/functions/_shared/live_prices.ts').readAsStringSync(),
    'GOLD_KEYS',
  );
  final tsAgirlik = _blok(
    File('supabase/functions/_shared/price_history.ts').readAsStringSync(),
    'GOLD_WEIGHTS',
  );
  final milestoneSrc =
      File('lib/services/milestone_service.dart').readAsStringSync();

  test('24 ayar gram altın listede ve 22 ayardan AYRI sembolde', () {
    expect(GoldSubCategory.gr24.label, 'Gram Altın (24 Ayar)');
    expect(goldTickerMap[GoldSubCategory.gr24.label], 'ALTIN_GRAM24');
    // Eski kayıtlar ALTIN_GRAM ile duruyor — anlamı 22 ayar kalmalı.
    expect(goldTickerMap[GoldSubCategory.gr22.label], 'ALTIN_GRAM');
    expect(dartAnahtar['ALTIN_GRAM'], 'YIA');
    expect(dartAnahtar['ALTIN_GRAM24'], 'GRA',
        reason: 'GRA 24 ayardır — 24 ayar ürün için doğru anahtar.');
  });

  for (final g in altinTurleri) {
    test('${g.label}: sembol, truncgil anahtarı, ağırlık, sunucu eşi', () {
      final ticker = goldTickerMap[g.label];
      expect(ticker, isNotNull, reason: 'goldTickerMap eksik');
      expect(ticker, startsWith('ALTIN_'));
      expect(dartAnahtar, contains(ticker),
          reason: '_truncgilGoldKeys eksik → fiyat yedeğe düşer');
      expect(dartAgirlik, contains(ticker),
          reason: '_goldWeights eksik → çarpan sessizce 1.0');
      expect(tsAnahtar[ticker], dartAnahtar[ticker],
          reason: 'live_prices.ts GOLD_KEYS istemciyle aynı olmalı');
      expect(tsAgirlik[ticker], dartAgirlik[ticker],
          reason: 'price_history.ts GOLD_WEIGHTS istemciyle aynı olmalı');
      expect(milestoneSrc, contains("'$ticker':"),
          reason: 'kilometre taşı etiketi eksik');
      expect(PriceService.goldWeightFactor(ticker!).toString(),
          dartAgirlik[ticker]);
      // Birim: gram ürünler 'gr', sikkeler 'piece'.
      expect(g.unitType, anyOf('gr', 'piece'));
    });
  }

  test('sikkeler gram altından ağır, ayarlar oranında', () {
    double w(GoldSubCategory g) =>
        PriceService.goldWeightFactor(goldTickerMap[g.label]!);
    expect(w(GoldSubCategory.gr24), closeTo(24 / 22, 1e-3));
    expect(w(GoldSubCategory.gr18), closeTo(18 / 22, 1e-3));
    expect(w(GoldSubCategory.gr14), closeTo(14 / 22, 1e-3));
    expect(w(GoldSubCategory.tam), greaterThan(w(GoldSubCategory.yarim)));
    expect(w(GoldSubCategory.besli), greaterThan(w(GoldSubCategory.ikibucuk)));
  });

  group('CSV alt tür çıkarımı', () {
    test('iç sembol birebir tanınır', () {
      for (final g in altinTurleri) {
        expect(altinAltTuru(goldTickerMap[g.label]!), g, reason: g.label);
      }
    });

    test('metinden tanınır; bilinmeyen 22 ayar gram', () {
      expect(altinAltTuru('ALTIN ÇEYREK'), GoldSubCategory.ceyrek);
      expect(altinAltTuru('ATA BEŞLİ ALTIN'), GoldSubCategory.besli);
      expect(altinAltTuru('YARIM ALTIN'), GoldSubCategory.yarim);
      expect(altinAltTuru('24 AYAR ALTIN'), GoldSubCategory.gr24);
      expect(altinAltTuru('ALTIN'), GoldSubCategory.gr22);
    });

    test('gram satırı fiyat servisinin tanıdığı sembolle kaydedilir', () {
      // Eskiden `ALTIN_GR22` üretiliyordu: hiçbir kaynağın tanımadığı sembol.
      final r = CsvImportService.normalizeTicker('ALTIN', AssetType.altin);
      expect(r.ticker, 'ALTIN_GRAM');
    });
  });
}

/// `ad = ... { 'A': 'B', ... }` / `ad: ... = { A: 1.0, ... }` bloğunu
/// anahtar → değer (string) haritasına çevirir. Yorum satırları atlanır.
Map<String, String> _blok(String kaynak, String ad) {
  // `ad` hemen ardından `=` ya da `:` gelmeli — yorumdaki geçişler
  // (`_goldWeights`) yanlış bloğu yakalamasın.
  final m = RegExp('\\b$ad\\s*[=:][^{]*\\{([\\s\\S]*?)\\};')
      .firstMatch(kaynak);
  if (m == null) return {};
  final govde = m
      .group(1)!
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  final rx = RegExp(r"""^\s*'?([A-Z0-9_]+)'?\s*:\s*'?([A-Z0-9.]+)'?""",
      multiLine: true);
  return {for (final x in rx.allMatches(govde)) x.group(1)!: x.group(2)!};
}
