import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';

/// Web ortalama maliyet hesaplayıcısı (`docs/maliyet/index.html`, müşteri
/// raporu 7 Kas 22:30 #4) uygulamanın Hızlı Al ters hesabıyla AYNI sayıyı
/// söyler.
///
/// Sayfa JavaScript'tir, testte koşturulamaz; bu yüzden iki yoldan
/// kilitlenir: (1) sayfadaki örneğin `data-*` değerleri
/// `hedefOrtalamaIcinAdet` (0 ondalık, tam adet) ile aynı sonucu verir;
/// (2) betikteki formül ve kapı (fiyat < hedef < ortalama) uygulamanınkiyle
/// aynı ifadedir. Ayrıca: fiyat ve harici kaynak yok, tavsiye notu ve
/// kampanya etiketli bağlantı var, uzun tire ve ünlem yok, site haritasında.
void main() {
  final html = File('docs/maliyet/index.html').readAsStringSync();

  test('örnek uygulamanın ters hesabıyla aynı', () {
    final m =
        RegExp(r'<p id="ornek" data-adet="([0-9.]+)" data-ort="([0-9.]+)" '
                r'data-fiyat="([0-9.]+)" data-hedef="([0-9.]+)" '
                r'data-sonuc="([0-9]+)">')
            .firstMatch(html);
    expect(m, isNotNull);
    double d(int i) => double.parse(m!.group(i)!);
    final n = hedefOrtalamaIcinAdet(
      eldeki: d(1),
      ortalama: d(2),
      fiyat: d(3),
      hedef: d(4),
      ondalik: 0,
    );
    expect(n, d(5));
    // Metin örnekle aynı sayıları yazar.
    final metin = html.substring(m!.end, html.indexOf('</p>', m.end));
    for (final s in [
      m.group(1)!,
      m.group(2)!,
      m.group(3)!,
      m.group(4)!,
      m.group(5)!
    ]) {
      expect(metin, contains(s));
    }
  });

  test('betikteki formül ve kapı uygulamanınkiyle aynı', () {
    expect(html, contains('if (hedef >= ort) return'));
    expect(html, contains('if (hedef <= fiyat) return'));
    expect(html, contains('var n = eldeki * (ort - hedef) / (hedef - fiyat);'));
    expect(html, contains('Math.ceil(n - 1e-6)'));
  });

  test('fiyat yok, harici kaynak yok, tavsiye notu ve etiketli bağlantı', () {
    expect(RegExp(r'<script[^>]+src=').hasMatch(html), isFalse);
    expect(
        RegExp(r'''(src|href)="https?://(?!apps\.apple\.com|yasincirali\.github\.io)''')
            .hasMatch(html),
        isFalse);
    expect(html, contains('utm_medium=maliyet'));
    expect(html, contains('Yatırım tavsiyesi değildir.'));
    expect(html, isNot(contains('–')));
    expect(html, isNot(contains('—')));
    expect(html.toLowerCase(), isNot(contains('en iyi')));
    // Ünlem yalnız betikteki `!` işleçlerinde; görünen metinde yok.
    final gorunen = html
        .substring(html.indexOf('<body>'), html.indexOf('<script>'))
        .replaceAll(RegExp(r'<[^>]*>'), '');
    expect(gorunen, isNot(contains('!')));
  });

  test('site haritasında', () {
    expect(File('docs/sitemap.xml').readAsStringSync(),
        contains('https://yasincirali.github.io/sandikapp/maliyet/'));
  });
}
