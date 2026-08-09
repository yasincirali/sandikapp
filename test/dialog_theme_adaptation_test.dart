import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Popup / dialog katmanının temaya uyumu.
///
/// Dialog, bottom sheet, popup menu ve SnackBar kendi `Overlay` katmanlarında
/// çizilir — çağıran ekranın yüzey renklerini DEVRALMAZLAR. Tema tanımı
/// eksikse Flutter'ın varsayılanına düşerler ve uygulama light moddayken
/// koyu (ya da tersi) bir panel açılır.
///
/// Denetimde (2026-08-10) bulunanlar:
///   * `pickSandikDate` sabit `ColorScheme.dark` kuruyordu → tarih seçici
///     light modda bile koyu açılıyordu.
///   * `bottomSheetTheme` / `popupMenuTheme` hiç tanımlı değildi.
///   * `cupertinoOverrideTheme` yoktu → `CupertinoAlertDialog` Material
///     temasını okumadığı için varsayılan palete düşüyordu.
void main() {
  group('palet — dialog yüzeyleri okunabilir', () {
    for (final (name, p) in [
      ('light', SandikPalette.light),
      ('dark', SandikPalette.dark),
    ]) {
      test('$name: dialog yüzeyi ile metin ayrışır', () {
        // surface1 dialog zemini, text90 başlık rengi.
        expect(p.surface1, isNot(equals(p.text90)),
            reason: 'dialog zemini ve metni aynı renk olamaz');
      });

      test('$name: sheet ve ekran zemini ayrışır (kenar görünür)', () {
        expect(p.surface1, isNot(equals(p.background)),
            reason: 'bottom sheet arkasındaki ekrandan ayırt edilebilmeli');
      });
    }

    test('light ve dark yüzeyler birbirinden farklı', () {
      expect(SandikPalette.light.surface1,
          isNot(equals(SandikPalette.dark.surface1)));
      expect(SandikPalette.light.background,
          isNot(equals(SandikPalette.dark.background)));
    });
  });

  group('kaynak taraması — tema tanımları yerinde', () {
    late String mainSrc;

    setUpAll(() {
      mainSrc = File('lib/main.dart').readAsStringSync();
    });

    test('bottomSheetTheme tanımlı', () {
      expect(mainSrc, contains('bottomSheetTheme:'),
          reason: 'showModalBottomSheet çağıranın zeminini devralmaz; tema '
              'yoksa Flutter varsayılanına düşer');
    });

    test('popupMenuTheme tanımlı', () {
      expect(mainSrc, contains('popupMenuTheme:'));
    });

    test('dialogTheme ve snackBarTheme tanımlı', () {
      expect(mainSrc, contains('dialogTheme:'));
      expect(mainSrc, contains('snackBarTheme:'));
    });

    test('cupertinoOverrideTheme tanımlı', () {
      expect(mainSrc, contains('cupertinoOverrideTheme:'),
          reason: 'CupertinoAlertDialog Material temasını okumaz — '
              'bağlanmazsa varsayılan Cupertino paletiyle çizilir');
    });

    test('tema tanımları palet üzerinden beslenir (sabit renk değil)', () {
      // `_buildTheme(SandikPalette p, ...)` içinde `p.` ile okunmalı.
      for (final key in [
        'bottomSheetTheme',
        'popupMenuTheme',
        'dialogTheme',
        'snackBarTheme',
      ]) {
        final idx = mainSrc.indexOf('$key:');
        expect(idx, greaterThan(-1), reason: '$key bulunamadı');
        // Tanımın hemen ardındaki blokta palet referansı olmalı.
        final block = mainSrc.substring(idx, (idx + 420).clamp(0, mainSrc.length));
        expect(block, contains('p.'),
            reason: '$key sabit renk kullanıyor olabilir — palet üzerinden '
                'beslenmeli ki light/dark birlikte çalışsın');
      }
    });
  });

  group('kaynak taraması — sabitlenmiş ColorScheme yok', () {
    test('hiçbir popup builder\'ı ColorScheme.dark/light sabitlemez', () {
      final offenders = <String>[];
      final pattern = RegExp(r'ColorScheme\.(dark|light)\s*\(');

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in pattern.allMatches(src)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line — ${m.group(0)}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Sabit ColorScheme bir panelin temasını dondurur: uygulama '
            'light moddayken o panel koyu açılır. `Theme.of(ctx)` üzerinden '
            '`copyWith` kullan.\n${offenders.join('\n')}',
      );
    });
  });

  group('davranış — bottom sheet temadan beslenir', () {
    testWidgets('modal sheet zemini temanın verdiği renktir', (tester) async {
      const sheetColor = Color(0xFF123456);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          bottomSheetTheme: const BottomSheetThemeData(
            modalBackgroundColor: sheetColor,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(height: 120),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, sheetColor,
          reason: 'sheet zemini tema tanımından gelmeli');
    });
  });
}
