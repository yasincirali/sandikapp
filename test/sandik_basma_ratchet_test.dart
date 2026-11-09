import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `SandikBasma(` lib/'de sıfır kalır.
///
/// Neden: Ar-Ge 5 Kas 22:40 #3 — iki ayrı basma bileşeni vardı
/// (`SandikTappable` ve `SandikBasma`); ikisi aynı ölçekle küçülüyor ama
/// titreşim ve semantik davranışları farklıydı, hangi yüzeyin seçili hâl ve
/// etiket taşıdığı rastgeleleşmişti. Solma artık `SandikTappable(soluk:
/// true)`; sınıf silindi. Geri gelirse basma dili yeniden ikiye bölünür.
///
/// Tüm ağacı saydığı için `ekranKaynagiSync` değil düz dizin taraması
/// kullanılır; yorum satırları ve gen-l10n çıktısı sayılmaz.
void main() {
  test('lib/ içinde SandikBasma( yok', () {
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
        if (s.contains('SandikBasma(')) bulunan.add('${f.path}:${i + 1}');
      }
    }
    expect(
      bulunan,
      isEmpty,
      reason: 'SandikBasma geri geldi; solarak basılan yüzey için '
          'SandikTappable(soluk: true) kullan (lib/theme/sandik.dart). '
          'Bulunanlar:\n${bulunan.join('\n')}',
    );
  });
}
