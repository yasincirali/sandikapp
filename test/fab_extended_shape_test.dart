import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tema FAB'ı `CircleBorder` yapıyor (main.dart). Uzatılmış FAB
/// (`FloatingActionButton.extended`) o şekli de alır ve simge/yazı dairenin
/// dışına taşar — Fiyat Alarmları ekranında yaşandı (2026-09-21, ekran
/// görüntüsü). Her uzatılmış FAB kendi stadyum şeklini vermeli.
void main() {
  test('her FloatingActionButton.extended stadyum şekli veriyor', () {
    final ihlaller = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync().replaceAll('\r\n', '\n');
      var i = src.indexOf('FloatingActionButton.extended(');
      while (i >= 0) {
        final govde = src.substring(i, (i + 700).clamp(0, src.length));
        if (!govde.contains('StadiumBorder(')) {
          ihlaller.add('${f.path.replaceAll('\\', '/')}:${'\n'.allMatches(src.substring(0, i)).length + 1}');
        }
        i = src.indexOf('FloatingActionButton.extended(', i + 1);
      }
    }
    expect(ihlaller, isEmpty,
        reason: 'Uzatılmış FAB tema dairesini miras alır; `shape: const '
            'StadiumBorder()` ver.');
  });
}
