import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Light/dark tema kontrast değişmezleri.
///
/// Kullanıcı şikâyeti (2026-08-10): Yarış ekranında seçili dönem sekmesi ve
/// "Zirvedeki Portföyler" kupa rozeti light modda koyu bir blok olarak
/// çıkıyordu.
///
/// Kök neden: rozet gradient'leri elle `[gold, amberText]` yazılmıştı. Bu
/// ikisi METİN token'ıdır ve light palette'te ikisi de aynı koyu kahvedir
/// (#4A3618) — gradient tek renge çöküyor, üstündeki koyu `onAmber` yazı
/// 1.41:1'e düşüyordu (WCAG AA eşiği 4.5:1).
///
/// Buradaki testler hem palet değişmezini hem de "dolgu yerine metin token'ı
/// kullanma" hatasının koda geri girmesini engeller.

/// WCAG 2.1 bağıl parlaklık.
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// İki rengin kontrast oranı (1..21).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg]'yi [alpha] opaklıkla [bg] üzerine düzleştirir.
///
/// `Color.r/g/b` 0..1 aralığındadır (0..255 değil) — 255 çarpanı kanalların
/// TAMAMINA uygulanmalı, yalnızca arka plana değil.
Color _flatten(Color fg, double alpha, Color bg) => Color.fromARGB(
      255,
      ((fg.r * alpha + bg.r * (1 - alpha)) * 255).round().clamp(0, 255),
      ((fg.g * alpha + bg.g * (1 - alpha)) * 255).round().clamp(0, 255),
      ((fg.b * alpha + bg.b * (1 - alpha)) * 255).round().clamp(0, 255),
    );

void main() {
  const light = SandikPalette.light;
  const dark = SandikPalette.dark;

  group('amber dolgu — her iki temada okunabilir', () {
    for (final (name, p) in [('light', light), ('dark', dark)]) {
      test('$name: onAmber / amberFill AA geçer', () {
        final cr = _contrast(p.onAmber, p.amberFill);
        expect(cr, greaterThanOrEqualTo(4.5),
            reason: 'amber dolgu üzerine gelen metin okunmalı — $name: '
                '${cr.toStringAsFixed(2)}:1');
      });

      test('$name: amberGradient her iki ucunda da onAmber okunur', () {
        // Gradient'in en kötü ucu belirleyicidir; ortalama değil.
        for (final stop in p.amberGradient.colors) {
          // Yarı saydam durak, altındaki yüzeye düzleşir.
          final solid = stop.a < 1.0
              ? _flatten(stop, stop.a, p.surface1)
              : stop;
          final cr = _contrast(p.onAmber, solid);
          expect(cr, greaterThanOrEqualTo(4.5),
              reason: 'gradient durağı okunmuyor — $name: '
                  '${cr.toStringAsFixed(2)}:1');
        }
      });
    }
  });

  group('metin token\'ları yüzey üzerinde okunur', () {
    for (final (name, p) in [('light', light), ('dark', dark)]) {
      test('$name: amberText / surface1', () {
        expect(_contrast(p.amberText, p.surface1), greaterThanOrEqualTo(4.5));
      });
      test('$name: gold / surface1', () {
        expect(_contrast(p.gold, p.surface1), greaterThanOrEqualTo(4.5));
      });
      test('$name: text90 ve text58 / surface1', () {
        expect(_contrast(p.text90, p.surface1), greaterThanOrEqualTo(4.5));
        expect(_contrast(p.text58, p.surface1), greaterThanOrEqualTo(4.5));
      });
      test('$name: gain/loss / surface1 (kâr-zarar en kritik veri)', () {
        expect(_contrast(p.gain, p.surface1), greaterThanOrEqualTo(4.5));
        expect(_contrast(p.loss, p.surface1), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('madalya rozetleri — rakam her iki uçta okunur', () {
    const medals = <String, (Color, Color)>{
      'altın': (Sandik.medalGold, Sandik.medalGoldDark),
      'gümüş': (Sandik.medalSilver, Sandik.medalSilverDark),
      'bronz': (Sandik.medalBronze, Sandik.medalBronzeDark),
    };

    for (final entry in medals.entries) {
      test('${entry.key}: onAmber gradient\'in iki ucunda da AA geçer', () {
        final (lo, hi) = entry.value;
        for (final bg in [lo, hi]) {
          final cr = _contrast(light.onAmber, bg);
          expect(cr, greaterThanOrEqualTo(4.5),
              reason: '${entry.key} madalyada sıra numarası okunmuyor — '
                  '${cr.toStringAsFixed(2)}:1');
        }
      });
    }
  });

  group('kaynak taraması — amber dolgu üstünde sabit metin', () {
    test('amber zeminli buton/rozetlerde Colors.black* kullanılmamalı', () {
      // `amberText`/`gold` METİN token'ıdır; light'ta koyulaşır. Onları
      // DOLGU olarak kullanıp üstüne sabit `Colors.black87` koymak light
      // modda 1.75:1 veriyordu (charts temettü butonu, OTP ikonu).
      // Doğrusu: dolgu `amberFill`, içerik `onAmber`.
      final offenders = <String>[];
      final pattern = RegExp(
        r'(background|backgroundColor|foreground|color)\s*:\s*Colors\.black\w*',
      );

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in pattern.allMatches(src)) {
          // Gölge/scrim/barrier meşrudur: onlar `withValues(alpha:)` ile
          // yarı saydam kullanılır ve zemin rengi değil perde rengidir.
          final tail = src.substring(
              m.end, (m.end + 40).clamp(0, src.length));
          if (tail.contains('withValues') || tail.contains('withOpacity')) {
            continue;
          }
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line — ${m.group(0)}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Opak `Colors.black*` tema ile değişmez. Amber/marka zemin '
            'üstündeki içerik için `context.c.onAmber`, genel metin için '
            '`context.c.text90/58` kullan.\n${offenders.join('\n')}',
      );
    });
  });

  group('kaynak taraması — çöken gradient deseni', () {
    test('hiçbir yerde [gold, amberText] gradient\'i yazılmamalı', () {
      final offenders = <String>[];

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        // Boşluk/satır sonu toleranslı: `colors: [ ...gold, ...amberText ]`
        final pattern = RegExp(
          r'colors:\s*\[\s*[^\]]*\.gold\s*,\s*[^\]]*\.amberText\s*[,\s]*\]',
          multiLine: true,
        );
        for (final m in pattern.allMatches(src)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '`gold` ve `amberText` METİN token\'larıdır; light temada '
            'ikisi de aynı koyu tondur ve gradient tek bloğa çöker. Dolgu '
            'için `context.c.amberGradient` kullan.\n${offenders.join('\n')}',
      );
    });
  });
}
