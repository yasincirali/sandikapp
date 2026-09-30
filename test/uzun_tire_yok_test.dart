import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kullanıcıya görünen metinde uzun tire (—) ve ayraç olarak orta tire (–)
/// yok (taste-skill denetimi, kullanıcı kararı 2026-10-01).
///
/// Uzun tire "yapay zekâ metni" izi olarak okunuyor; cümle nokta, virgül,
/// noktalı virgül ya da iki noktayla kurulur, aralık kısa çizgiyle yazılır
/// (`{start} - {end}`, `3-20 karakter`).
///
/// Bilinçli istisnalar:
///   · Tek başına `'—'`: "değer yok" işareti. Finans ekranında `-` EKSİ
///     okunur; boş hücreye `-` yazmak "zarar" diye yanlış okutur.
///   · Hukuki metin ekranı (metin avukat onaylı, biçimi ona ait) ve
///     geliştirici teşhis ekranı (yalnız admin görür).
///   · `debugPrint` / `Exception` iç metinleri (kullanıcı görmez).
void main() {
  const tireler = ['—', '–'];

  test('.arb metinlerinde uzun/orta tire yok', () {
    for (final dil in ['tr', 'en']) {
      final arb = jsonDecode(File('lib/l10n/app_$dil.arb').readAsStringSync())
          as Map<String, dynamic>;
      final bulunan = [
        for (final e in arb.entries)
          if (!e.key.startsWith('@') &&
              e.value is String &&
              tireler.any((t) => (e.value as String).contains(t)))
            e.key,
      ];
      expect(bulunan, isEmpty, reason: 'app_$dil.arb: $bulunan');
    }
  });

  test('lib/ kullanıcı metinlerinde uzun/orta tire yok', () {
    const haric = {
      'lib/screens/legal_doc_screen.dart',
      'lib/screens/push_diagnostics_screen.dart',
    };
    final literal = RegExp(
        r"'(?:[^'\\]|\\.)*'" '|' r'"(?:[^"\\]|\\.)*"');
    final bulunan = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final yol = f.path.replaceAll(r'\', '/');
      if (!yol.endsWith('.dart') || yol.contains('/generated/')) continue;
      if (haric.contains(yol)) continue;
      final satirlar = f.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i];
        final t = s.trimLeft();
        if (t.startsWith('//')) continue;
        if (s.contains('debugPrint(') || s.contains('Exception(')) continue;
        for (final m in literal.allMatches(s)) {
          final metin = m.group(0)!;
          if (metin == "'—'" || metin == '"—"') continue;
          if (tireler.any(metin.contains)) bulunan.add('$yol:${i + 1}');
        }
      }
    }
    expect(bulunan, isEmpty, reason: bulunan.join('\n'));
  });

  test('tanıtım sayfasının görünen metninde uzun/orta tire yok', () {
    final html = File('docs/index.html').readAsStringSync();
    final gorunen = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    for (final t in tireler) {
      expect(gorunen.contains(t), isFalse, reason: 'docs/index.html: "$t"');
    }
    // Güvenlik iddiası gizlilik politikasıyla aynı olmalı: uçtan uca
    // şifreleme YOK (TLS aktarım + AES-256 saklama).
    expect(gorunen.toLowerCase().contains('uçtan uca'), isFalse);
  });
}
