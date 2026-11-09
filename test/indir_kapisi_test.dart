import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `/indir/` kapısı (docs/indir/index.html) App Store bağlantısı (2026-10-25).
///
/// App Store Connect Kampanyalar raporu utm_*'i saymaz, yalnız `pt` + `ct`
/// okur. Kapı ct/pt'yi YALNIZ `PT` doluyken (ve utm_source varken) ekler;
/// PT boşken bağlantı eskisinin birebir aynısı kalır. ct en fazla 40
/// karakter (ASC sınırı). Sayfanın kendi `<script>`'i node'da sahte
/// DOM ile koşulur; node yoksa (yerel makine) o testler atlanır, CI taşır.
void main() {
  final html = File('docs/indir/index.html')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final betik = RegExp(r'<script>(.*?)</script>', dotAll: true)
      .firstMatch(html)!
      .group(1)!;
  const ptSatiri = "var PT = '';";

  final node = Process.runSync('node', ['--version'], runInShell: true);
  final nodeVar = node.exitCode == 0;

  /// Betiği [arama] ile koşar, iOS düğmesinin son href'ini döner.
  String iosHref(String arama, {String pt = ''}) {
    final kod = betik.replaceFirst(ptSatiri, 'var PT = ${jsonEncode(pt)};');
    final r = Process.runSync('node', [
      '-e',
      'const el={};'
          'function e(id){return el[id]||(el[id]={href:id==="ios"?'
          '"https://apps.apple.com/tr/app/id6786837699":"#",style:{},hidden:true,textContent:""});}'
          'globalThis.document={getElementById:e};'
          'globalThis.location={search:${jsonEncode(arama)},replace(){}};'
          'Object.defineProperty(globalThis,"navigator",{value:{userAgent:"Mozilla/5.0 (Macintosh)"}});'
          'globalThis.setTimeout=function(){};'
          'eval(${jsonEncode(kod)});'
          'process.stdout.write(e("ios").href);',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  test('PT sabiti betiğin başında ve bugün boş', () {
    expect(betik, contains(ptSatiri));
    // ct/pt ekleme PT koşuluna bağlı; koşulsuz ekleme kalıbı yok.
    expect(betik, contains('if (PT && kaynak)'));
    expect(betik, contains('.slice(0, 40)'));
  });

  test('PT boş: yalnız utm, ct/pt yok (eski davranış)', () {
    final h = iosHref('?utm_source=paylasim&utm_campaign=kart&kod=AB12');
    expect(h,
        'https://apps.apple.com/tr/app/id6786837699?utm_source=paylasim&utm_campaign=kart');
    expect(iosHref(''), 'https://apps.apple.com/tr/app/id6786837699');
  }, skip: nodeVar ? false : 'node yok');

  test('PT dolu: ct = kaynak_kampanya, pt eklenir; utm kalır', () {
    final h = iosHref('?utm_source=grafik_paylas&utm_campaign=grafik',
        pt: '123456');
    final u = Uri.parse(h);
    expect(u.queryParameters['utm_source'], 'grafik_paylas');
    expect(u.queryParameters['ct'], 'grafik_paylas_grafik');
    expect(u.queryParameters['pt'], '123456');
    final yalnizKaynak = Uri.parse(iosHref('?utm_source=ortak', pt: '1'));
    expect(yalnizKaynak.queryParameters['ct'], 'ortak');
  }, skip: nodeVar ? false : 'node yok');

  test('PT dolu: ct en fazla 40 karakter; utm_source yoksa eklenmez', () {
    final uzun = Uri.parse(iosHref(
        '?utm_source=${'a' * 30}&utm_campaign=${'b' * 30}',
        pt: '1'));
    expect(uzun.queryParameters['ct']!.length, 40);
    final kaynaksiz = iosHref('?utm_campaign=x', pt: '1');
    expect(kaynaksiz.contains('ct='), isFalse);
    expect(kaynaksiz.contains('pt='), isFalse);
  }, skip: nodeVar ? false : 'node yok');

  test('Android dalı dokunulmadı: bekleme listesi', () {
    expect(betik, contains('sandık Android bekleme listesi'));
  });
}
