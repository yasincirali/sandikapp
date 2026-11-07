import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Web altın gram hesaplayıcısı (`docs/altin/index.html`) uygulamayla AYNI
/// ağırlıkları söyler (Ar-Ge 7 Kas 18:06 #2).
///
/// Sayfa fiyatsızdır; tek iddiası ağırlıktır. Uygulama çeyreği 1,75 gr
/// sayıp web 1,754 derse arama ile gelen kullanıcı uygulamada başka sayı
/// görür. Tablodaki `data-carpan` sayfanın tek kaynağıdır (form onu okur);
/// burada `PriceService.goldWeightFactor` ile, birim `GoldSubCategory`
/// ile ve görünen hücreler `altinGramKarsiligi` + `fmtGram` ile kıyaslanır.
void main() {
  final html = File('docs/altin/index.html').readAsStringSync();
  final satir = RegExp(r'<tr data-kod="([A-Z0-9_]+)" data-carpan="([0-9.]+)" '
      r'data-birim="(adet|gram)"><th scope="row">[^<]+</th>'
      r'<td>[^<]+</td><td>([^<]+) gr</td><td>([^<]+) gr</td></tr>');
  final satirlar = satir.allMatches(html).toList();

  // Uygulamanın altın türleri (ons hariç: ağırlık tablosunda yok).
  final uygulama = {
    for (final g in GoldSubCategory.values)
      if (g != GoldSubCategory.ons) goldTickerMap[g.label]!: g.unitType,
  };

  test('her uygulama türü sayfada, sayfada fazlası yok', () {
    expect(satirlar.map((m) => m.group(1)).toSet(), uygulama.keys.toSet());
    expect(satirlar.length, uygulama.length, reason: 'tekrarlanan satır');
  });

  for (final m in satirlar) {
    final kod = m.group(1)!;
    test('$kod: çarpan, birim ve görünen hücreler uygulamayla aynı', () {
      expect(double.parse(m.group(2)!), PriceService.goldWeightFactor(kod));
      expect(m.group(3), uygulama[kod] == 'gr' ? 'gram' : 'adet');
      final k = PriceService.altinGramKarsiligi(kod, 1)!;
      expect(m.group(4), fmtGram(k.gram));
      expect(m.group(5), fmtGram(k.has));
    });
  }

  test('fiyat yok, harici kaynak yok, mağaza bağlantısı etiketli', () {
    expect(html, isNot(contains('₺')));
    expect(RegExp(r'<script[^>]+src=').hasMatch(html), isFalse);
    expect(
        RegExp(r'''(src|href)="https?://(?!apps\.apple\.com|yasincirali\.github\.io)''')
            .hasMatch(html),
        isFalse);
    expect(html, contains('utm_medium=altin'));
    expect(html, isNot(contains('\u2013')));
    expect(html, isNot(contains('\u2014')));
  });

  test('site haritasında', () {
    expect(File('docs/sitemap.xml').readAsStringSync(),
        contains('https://yasincirali.github.io/sandikapp/altin/'));
  });
}
