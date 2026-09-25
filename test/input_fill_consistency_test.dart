import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Giriş alanı dolgusu tek kaynaktan gelir (kullanıcı kararı 2026-09-25:
/// "uygulama içi tüm inputfield'larda uygulanmalı").
///
/// Kural `context.inputFill`'de yazılı: dark'ta dolgu yok + hairline çerçeve,
/// light'ta `surface2`. Tema varsayılanı (`inputDecorationTheme`) ve
/// `context.inputDecoration` aynı kuralı izler. Bir ekran kendi
/// `fillColor:`'unu (`overlay`, `surface1`…) verirse o alan bulunduğu
/// zeminde yine "içi farklı renk" görünür — dört kez şikâyet edildi.
///
/// İkinci desen: kendi `Container`'ı dolgu+çerçeve çizen bir kutunun
/// içindeki `TextField` (kenarlığı `InputBorder.none`) `filled: false`
/// demezse tema dolgusu kutunun içinde ikinci bir dikdörtgen çizer.
void main() {
  List<File> kaynaklar() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) {
        final p = f.path.replaceAll(r'\', '/');
        // Tema tanımı (`lib/theme/`, `main.dart` → `_buildTheme`) kuralın
        // kaynağıdır; tarama tüketicileri denetler.
        return !p.contains('lib/theme/') &&
            !p.endsWith('lib/main.dart') &&
            !p.contains('/generated/');
      })
      .toList();

  test('ekranlar kendi fillColor\'unu vermez — yalnız context.inputFill', () {
    final ihlal = <String>[];
    for (final f in kaynaklar()) {
      final satirlar = f.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i].trim();
        if (s.startsWith('//')) continue;
        if (!s.startsWith('fillColor:')) continue;
        if (!s.contains('inputFill')) ihlal.add('${f.path}:${i + 1}  $s');
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Giriş alanı dolgusu tema/`context.inputFill`\'den gelmeli. '
            'Alanı sil ya da `context.inputFill` kullan.\n${ihlal.join('\n')}');
  });

  test('kenarlıksız (kutu içi) TextField tema dolgusunu kapatır', () {
    final ihlal = <String>[];
    for (final f in kaynaklar()) {
      final satirlar = f.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        if (!satirlar[i].contains('border: InputBorder.none')) continue;
        final bas = (i - 12).clamp(0, satirlar.length);
        final son = (i + 12).clamp(0, satirlar.length);
        final blok = satirlar.sublist(bas, son).join('\n');
        if (!blok.contains('filled: false')) {
          ihlal.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Kenarlığı kapatılmış alan bir kutunun içinde demektir; '
            '`filled: false` eklenmezse tema dolgusu kutunun içinde ikinci '
            'bir renk çizer.\n${ihlal.join('\n')}');
  });
}
