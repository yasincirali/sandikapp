// Web hesaplayıcıları birbirine ve ana sayfaya bağlı + JSON-LD (2026-11-11,
// Ar-Ge 2026-11-11_1704 #3).
//
// Neden kilit: sayfalar elle yazılıyor (üreteç yok); yeni hesaplayıcı
// eklenirken "Diğer hesaplayıcılar" satırı öteki sayfalara girmezse sayfa
// yine adasız kalır. Liste [hesaplayicilar] tek yerde; yeni sayfa buraya
// eklenince test hangi sayfaya bağlantının eksik olduğunu söyler.
// FAQPage yalnız sayfada görünür bir SSS bölümü (`<section class="sss">`)
// varsa ve her soru/cevap o bölümde BİREBİR yazıyorsa kabul edilir
// (2026-11-11, Ar-Ge 1804 #5): Google görünmeyen soruyu işaretlemeyi kural
// dışı sayar; uydurma soru yazılmaz.
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

      final ldler = RegExp(
              r'<script type="application/ld\+json">([\s\S]*?)</script>')
          .allMatches(html)
          .map((m) => jsonDecode(m.group(1)!) as Map<String, dynamic>)
          .toList();

      test('WebApplication JSON-LD geçerli, adresi canonical ile aynı', () {
        final uygulamalar =
            ldler.where((j) => j['@type'] == 'WebApplication').toList();
        expect(uygulamalar, hasLength(1), reason: '$kod: JSON-LD yok');
        final j = uygulamalar.single;
        expect(j['url'], '$_taban$kod/');
        expect(html, contains('<link rel="canonical" href="$_taban$kod/">'));
        expect(j['applicationCategory'], 'FinanceApplication');
        expect(j['inLanguage'], 'tr');
        expect((j['offers'] as Map)['price'], '0');
        expect(
            ldler.every((j) =>
                j['@type'] == 'WebApplication' || j['@type'] == 'FAQPage'),
            isTrue);
      });

      test('FAQPage yalnız görünür SSS bölümüyle ve aynı metinle', () {
        final sssler = ldler.where((j) => j['@type'] == 'FAQPage').toList();
        if (sssler.isEmpty) {
          expect(html, isNot(contains('"FAQPage"')));
          return;
        }
        expect(sssler, hasLength(1));
        final bolum = RegExp(r'<section class="sss"[^>]*>([\s\S]*?)</section>')
            .firstMatch(html);
        expect(bolum, isNotNull,
            reason: '$kod: FAQPage var ama sayfada görünür SSS bölümü yok');
        final gorunen = bolum!
            .group(1)!
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll('&amp;', '&')
            .replaceAll(RegExp(r'\s+'), ' ');
        final sorular = sssler.single['mainEntity'] as List;
        expect(sorular, isNotEmpty);
        for (final q in sorular.cast<Map<String, dynamic>>()) {
          expect(q['@type'], 'Question');
          expect(gorunen, contains(q['name'] as String));
          final cevap = (q['acceptedAnswer'] as Map)['text'] as String;
          expect(gorunen, contains(cevap));
        }
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
