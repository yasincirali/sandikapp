import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Web sitesinin (docs/, GitHub Pages) arama ve paylaşım kapısı (2026-10-26).
///
/// - `docs/sitemap.xml` `docs/_build_sitemap.py` üretir. Haritadaki her adres
///   gerçek bir `index.html`'e karşılık gelir (404 Search Console'a gitmez) ve
///   dizinlenebilir her sayfa haritadadır (yeni sayfa eklenip betik
///   koşulmazsa burada kırılır). `noindex` sayfa haritaya girmez.
/// - og:image mutlak URL'dir (göreli adresi WhatsApp/X çözmez), docs/ içinde
///   var olan bir dosyayı gösterir ve 1200x630 + <300 KB'dir (WhatsApp 300 KB
///   üstünde önizlemeyi düşürür). Görseller
///   `store_listing/build_store_graphics.py --og` ile üretilir.
void main() {
  const taban = 'https://yasincirali.github.io/sandikapp/';

  String oku(String yol) =>
      File(yol).readAsStringSync().replaceAll('\r\n', '\n');

  /// docs/ içindeki yayın sayfaları: `index.html`, arşiv ve `_` klasörleri
  /// hariç. Betikteki kuralın aynısı.
  Map<String, String> sayfalar() {
    final sonuc = <String, String>{};
    for (final f in Directory('docs').listSync(recursive: true)) {
      if (f is! File) continue;
      final yol = f.path.replaceAll('\\', '/');
      if (!yol.endsWith('/index.html')) continue;
      final parcalar = yol.split('/')..removeAt(0)..removeLast();
      if (parcalar.any((p) =>
          p == 'archive' || p.startsWith('_') || p.startsWith('.'))) {
        continue;
      }
      sonuc[parcalar.map((p) => '$p/').join()] = yol;
    }
    return sonuc;
  }

  bool noindex(String html) {
    final k = html.toLowerCase();
    return k.contains('name="robots"') && k.contains('noindex');
  }

  group('sitemap.xml', () {
    final xml = oku('docs/sitemap.xml');
    final adresler = RegExp(r'<loc>([^<]+)</loc>')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toList();

    test('her adres tabanda ve var olan, dizinlenebilir bir sayfa', () {
      expect(adresler, isNotEmpty);
      final s = sayfalar();
      for (final a in adresler) {
        expect(a.startsWith(taban), isTrue, reason: a);
        final goreli = a.substring(taban.length);
        expect(s.containsKey(goreli), isTrue,
            reason: '$a → docs/${goreli}index.html yok');
        expect(noindex(oku(s[goreli]!)), isFalse,
            reason: '$a noindex taşıyor, haritada olmamalı');
      }
      expect(adresler.toSet().length, adresler.length, reason: 'tekrar var');
    });

    test('dizinlenebilir her sayfa haritada (betik koşulmuş)', () {
      final eksik = sayfalar()
          .entries
          .where((e) => !noindex(oku(e.value)))
          .map((e) => '$taban${e.key}')
          .where((a) => !adresler.contains(a))
          .toList();
      expect(eksik, isEmpty,
          reason: 'python docs/_build_sitemap.py koşulmalı');
    });

    test('ana sayfa, enflasyon ve yasal sayfalar var', () {
      for (final yol in ['', 'enflasyon/', 'privacy/', 'terms/', 'legal/kvkk/']) {
        expect(adresler, contains('$taban$yol'));
      }
    });
  });

  group('paylaşım görseli', () {
    for (final (sayfa, gorsel) in [
      ('docs/index.html', 'img/og-ana.png'),
      ('docs/enflasyon/index.html', 'img/og-enflasyon.png'),
    ]) {
      test('$sayfa: og:image mutlak, var olan 1200x630 dosya', () {
        final html = oku(sayfa);
        String meta(String ad) {
          final m = RegExp('<meta (?:property|name)="${RegExp.escape(ad)}" '
                  'content="([^"]*)"')
              .firstMatch(html);
          expect(m, isNotNull, reason: '$sayfa: $ad yok');
          return m!.group(1)!;
        }

        final url = meta('og:image');
        expect(url, '$taban$gorsel');
        expect(meta('twitter:image'), url);
        expect(meta('twitter:card'), 'summary_large_image');
        expect(meta('og:image:width'), '1200');
        expect(meta('og:image:height'), '630');
        expect(meta('og:image:alt'), isNotEmpty);

        final dosya = File('docs/${url.substring(taban.length)}');
        expect(dosya.existsSync(), isTrue, reason: dosya.path);
        final b = dosya.readAsBytesSync();
        expect(b.length, lessThan(300 * 1024));
        // PNG IHDR: genişlik 16..19, yükseklik 20..23 (big-endian).
        int u32(int i) =>
            (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
        expect(b.sublist(1, 4), 'PNG'.codeUnits);
        expect(u32(16), 1200);
        expect(u32(20), 630);
      });
    }
  });
}
