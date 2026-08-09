import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tasarım sistemi sızıntı testi.
///
/// `lib/theme/sandik.dart` tokenları tek kaynaktır. Bir ekranda doğrudan
/// `Color(0xFF…)` veya çıplak `Duration(milliseconds: …)` yazılması tek
/// başına hata vermez — ama zamanla sistem erozyona uğrar ve "aynı yeşilin
/// üç tonu yan yana" durumu geri gelir. Bu test o erozyonu CI'da yakalar.
///
/// Eşikler mevcut duruma göre kalibre edildi ve **yalnızca aşağı inmeli**.
/// Yeni sızıntı eklersen test kırılır; doğru çözüm eşiği yükseltmek değil,
/// tokena taşımaktır. Token'da karşılığı yoksa `sandik.dart`'a ekle.
void main() {
  final libDir = Directory('lib');

  /// `lib/theme/` dışındaki tüm Dart dosyaları — tokenların tanımlandığı
  /// yer doğal olarak ham değer içerir, orası kapsam dışı.
  List<File> sourceFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/theme/'))
      .toList();

  test('hardcoded Color(0x…) sayısı artmamalı', () {
    final pattern = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    final hits = <String>[];

    for (final file in sourceFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Satırda birden fazla olabilir — hepsini say, yoksa aynı satıra
        // eklenen ikinci sızıntı testten kaçar.
        for (var _ in pattern.allMatches(lines[i])) {
          hits.add('${file.path}:${i + 1}');
        }
      }
    }

    // 2026-08-09 denetimi: 80 → 49. Kalanların çoğu kategori renkleri
    // (asset_type.dart) ve hukuki doküman ekranının kendi paleti.
    expect(
      hits.length,
      lessThanOrEqualTo(49),
      reason: 'Yeni hardcoded renk eklenmiş. Sandik.* tokenını kullan '
          'veya token yoksa sandik.dart\'a ekle.\n${hits.join('\n')}',
    );
  });

  test('çıplak Duration(milliseconds: …) sayısı artmamalı', () {
    final pattern = RegExp(r'Duration\(milliseconds:\s*\d+\)');
    final hits = <String>[];

    for (final file in sourceFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (var _ in pattern.allMatches(lines[i])) {
          hits.add('${file.path}:${i + 1}');
        }
      }
    }

    // 2026-08-09 denetimi: 42 → 28. Kalanlar debounce/timeout gibi
    // gerçekten hareket dili dışındaki süreler.
    expect(
      hits.length,
      lessThanOrEqualTo(28),
      reason: 'Yeni çıplak süre eklenmiş. Hareket ise '
          'SandikMotion.press/state/surface kullan.\n${hits.join('\n')}',
    );
  });

  test('implicit animation kullanan her yer curve vermeli', () {
    // Flutter'da AnimatedContainer.curve varsayılanı Curves.linear'dır.
    // Doğrusal hareket fiziksel dünyada yoktur; göz bunu "özensiz" okur.
    // Bu yüzden duration veren her implicit animation curve de vermeli.
    final widget = RegExp(
      r'Animated(Container|Opacity|Padding|Align|DefaultTextStyle|Scale'
      r'|Rotation|Slide|Positioned)\(',
    );
    final offenders = <String>[];

    for (final file in sourceFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!widget.hasMatch(lines[i])) continue;
        // Widget'ın parametre bloğunu kabaca tara (sonraki 8 satır).
        final end = (i + 9).clamp(0, lines.length);
        final block = lines.sublist(i, end).join(' ');
        if (block.contains('duration:') && !block.contains('curve:')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'curve verilmemiş implicit animation var — varsayılan '
          'Curves.linear devreye girer. SandikMotion.enter (giren/durum '
          'değiştiren) veya SandikMotion.move (yer değiştiren) '
          'kullan.\n${offenders.join('\n')}',
    );
  });

  test('amberText ZEMIN olarak kullanilmamali', () {
    // REGRESYON KORUMASI (2026-08-09): `amberText` okunabilirlik icin
    // koyu kahveye (#4A3618) cekildi. O sirada 9 yerde ZEMIN olarak
    // kullaniliyordu (FAB dairesi, secili sekme pill'i, rozet dolgusu) ve
    // uzerlerindeki `onAmber` metin 1.41:1'e dustu -> gorunmez oldu.
    //
    // Kural: zemin -> amberFill (marka amberi), metin/ikon -> amberText.
    final decorationCtx = RegExp(
      r'(BoxDecoration|ShapeDecoration|Container\()',
    );
    final offenders = <String>[];

    for (final file in sourceFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final isBgParam =
            RegExp(r'backgroundColor:\s*context\.c\.amberText').hasMatch(line);
        final isBareColor =
            RegExp(r'^\s*color:\s*context\.c\.amberText,?\s*$')
                .hasMatch(line);
        if (!isBgParam && !isBareColor) continue;

        if (isBgParam) {
          offenders.add('${file.path}:${i + 1}');
          continue;
        }
        // Onceki 5 satirda dekorasyon baglami var mi? (metin baglami yoksa)
        final lo = (i - 5) < 0 ? 0 : i - 5;
        final ctx = lines.sublist(lo, i + 1).join(' ');
        final looksLikeText =
            RegExp(r'TextStyle|copyWith|context\.t\.|Icon\(').hasMatch(ctx);
        if (!looksLikeText && decorationCtx.hasMatch(ctx)) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'amberText bir ZEMIN olarak kullanilmis. Marka dolgusu icin '
          'context.c.amberFill kullan; amberText yalnizca metin/ikon '
          'rengidir.\n${offenders.join('\n')}',
    );
  });
}
