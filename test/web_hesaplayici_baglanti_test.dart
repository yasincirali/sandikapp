// Web hesaplayıcıları birbirine ve ana sayfaya bağlı + JSON-LD (2026-11-11,
// Ar-Ge 2026-11-11_1704 #3).
//
// Neden kilit: sayfalar elle yazılıyor (üreteç yok); yeni hesaplayıcı
// eklenirken "Diğer hesaplayıcılar" satırı öteki sayfalara girmezse sayfa
// yine adasız kalır. Liste [hesaplayicilar] tek yerde; yeni sayfa buraya
// eklenince test hangi sayfaya bağlantının eksik olduğunu söyler.
// FAQPage beklenmez: hiçbir sayfada SSS bölümü yok, uydurma soru yazılmaz.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _taban = 'https://yasincirali.github.io/sandikapp/';
const hesaplayicilar = ['enflasyon', 'altin', 'maliyet', 'temettu'];

void main() {
  for (final kod in hesaplayicilar) {
    group('docs/$kod', () {
      final html = File('docs/$kod/index.html').readAsStringSync();

      test('"Diğer hesaplayıcılar" satırı öteki sayfalara bağlanır', () {
        final m = RegExp(
                r'<nav class="diger" aria-label="Diğer hesaplayıcılar">([\s\S]*?)</nav>')
            .firstMatch(html);
        expect(m, isNotNull, reason: '$kod: satır yok');
        final hrefler = RegExp(r'href="\.\./([a-z]+)/"')
            .allMatches(m!.group(1)!)
            .map((e) => e.group(1))
            .toList();
        expect(hrefler, [
          for (final k in hesaplayicilar)
            if (k != kod) k,
        ]);
      });

      test('WebApplication JSON-LD geçerli, adresi canonical ile aynı', () {
        final m =
            RegExp(r'<script type="application/ld\+json">([\s\S]*?)</script>')
                .firstMatch(html);
        expect(m, isNotNull, reason: '$kod: JSON-LD yok');
        final j = jsonDecode(m!.group(1)!) as Map<String, dynamic>;
        expect(j['@type'], 'WebApplication');
        expect(j['url'], '$_taban$kod/');
        expect(html, contains('<link rel="canonical" href="$_taban$kod/">'));
        expect(j['applicationCategory'], 'FinanceApplication');
        expect(j['inLanguage'], 'tr');
        expect((j['offers'] as Map)['price'], '0');
        expect(html, isNot(contains('"FAQPage"')));
      });
    });
  }

  test('ana sayfa dört hesaplayıcıyı listeler', () {
    final html = File('docs/index.html').readAsStringSync();
    final m = RegExp(r'<nav class="hesaplayicilar"[^>]*>([\s\S]*?)</nav>')
        .firstMatch(html);
    expect(m, isNotNull);
    final hrefler = RegExp(r'href="([a-z]+)/"')
        .allMatches(m!.group(1)!)
        .map((e) => e.group(1))
        .toList();
    expect(hrefler, hesaplayicilar);
  });
}
