import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `InkWell(` sayısı yalnızca azalabilir.
///
/// Neden: Ar-Ge 5 Kas 21:10 #2 — iOS'ta Android dalgası (ripple) görünüyordu
/// ve tepki parmak kalkınca geliyordu; aynı uygulamada bazı yüzeyler küçülüp
/// bazıları dalgalanınca basma dili ikiye bölünüyordu. `SandikTappable`
/// dokunur dokunmaz küçülür, iki platformda aynı davranır; yeni dokunma
/// hedefi onu kullanır. Kalan her `InkWell`'in üstünde `// InkWell kalır:`
/// gerekçesi durmalı.
///
/// Tüm ağacı saydığı için `ekranKaynagiSync` değil düz dizin taraması
/// kullanılır; yorum satırları ve gen-l10n çıktısı sayılmaz.
const _izinVerilen = 0;

void main() {
  test('lib/ içindeki InkWell( sayısı artmaz', () {
    final bulunan = <String>[];
    final dosyalar = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            !f.path.replaceAll(r'\', '/').contains('lib/l10n/generated'));
    for (final f in dosyalar) {
      final satirlar = f.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i].trimLeft();
        if (s.startsWith('//')) continue;
        if (s.contains('InkWell(')) bulunan.add('${f.path}:${i + 1}');
      }
    }
    expect(
      bulunan.length,
      lessThanOrEqualTo(_izinVerilen),
      reason: 'Yeni InkWell eklendi; dokunma tepkisi için SandikTappable '
          'kullan (lib/theme/sandik.dart). Bulunanlar:\n'
          '${bulunan.join('\n')}',
    );
  });
}
