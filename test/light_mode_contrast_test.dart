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

  group('durum dolgusu (gain/loss) — üstüne onStatus gelir', () {
    // Amber'den farklı olarak gain/loss iki temada TERS parlaklıktadır:
    // light'ta koyu (beyaz ister), dark'ta parlak (koyu ister). Bu yüzden
    // tek bir sabit mürekkep iki temada birden çalışamaz.
    for (final (name, p) in [('light', light), ('dark', dark)]) {
      test('$name: onStatus / gain dolgusu AA geçer', () {
        final cr = _contrast(p.onStatus, p.gain);
        expect(cr, greaterThanOrEqualTo(4.5),
            reason: '$name: ${cr.toStringAsFixed(2)}:1');
      });
      test('$name: onStatus / loss dolgusu AA geçer', () {
        final cr = _contrast(p.onStatus, p.loss);
        expect(cr, greaterThanOrEqualTo(4.5),
            reason: '$name: ${cr.toStringAsFixed(2)}:1');
      });

      // Yanlış token'ların GERÇEKTEN kırık olduğunu doğrula. Bu olmadan
      // yukarıdaki testler, biri onStatus'u text90'a eşitlerse sessizce
      // geçmeye devam ederdi.
      test('$name: text90 durum dolgusunda kalırsa AA\'yı geçemez', () {
        expect(_contrast(p.text90, p.gain), lessThan(4.5));
        expect(_contrast(p.text90, p.loss), lessThan(4.5));
      });

      // `danger` "Sil" gibi geri alınamaz aksiyonları anlatır — en okunur
      // olması gereken ton. Denetimde atlanmıştı: dark #EF4444 METİN olarak
      // yüzey üzerinde 3.86:1 veriyordu.
      test('$name: danger yüzey üstünde okunur', () {
        final cr = _contrast(p.danger, p.surface1);
        expect(cr, greaterThanOrEqualTo(4.5),
            reason: '$name: ${cr.toStringAsFixed(2)}:1');
      });
      test('$name: onStatus / danger dolgusu AA geçer', () {
        final cr = _contrast(p.onStatus, p.danger);
        expect(cr, greaterThanOrEqualTo(4.5),
            reason: '$name: ${cr.toStringAsFixed(2)}:1');
      });
    }
  });

  group('kaynak taraması — yardımcı fonksiyona geçen dolgu/mürekkep', () {
    test('background:/foreground: çifti yüzey metni taşımamalı', () {
      // Bu deseni ilk tarama KAÇIRDI: `_rowAction(background: ..., foreground:
      // ...)` gibi yardımcılarda dolgu ve mürekkep ayrı NAMED ARGÜMAN olarak
      // geçiyor, yan yana yazılmıyor. Kaydırma aksiyonları (Al/Sat/Sil)
      // tam olarak bu yüzden gözden kaçtı — light modda 2.87–3.02:1.
      final offenders = <String>[];
      final bg = RegExp(
        r'background:\s*(?:ctx|context)\.c\.(gain|loss|danger)\b',
      );

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in bg.allMatches(src)) {
          // Aynı çağrının argüman listesinde `foreground:` ne veriyor?
          final win = src.substring(
              m.start, (m.end + 400).clamp(0, src.length));
          final fg = RegExp(
            r'foreground:\s*(?:ctx|context)\.c\.(text90|text58|onAmber)\b',
          ).firstMatch(win);
          if (fg == null) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line — ${m.group(0)} + ${fg.group(0)}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'Renkli dolgu üstüne `onStatus` gelmeli.\n'
              '${offenders.join('\n')}');
    });
  });

  group('kaynak taraması — durum dolgusu üstünde yanlış mürekkep', () {
    test('gain/loss zeminli widget\'ta text90 veya onAmber kullanılmamalı', () {
      // Denetimde (2026-08-10) 5 ihlal bulundu: iki SnackBar, bildirim
      // rozeti, "Onayla" butonu, add_asset bilgi SnackBar'ı. Hepsi light
      // modda 2.89–3.02:1 veriyordu.
      final offenders = <String>[];
      // OPAK dolgu arıyoruz. `context.c.gain.withValues(alpha: 0.18)` gibi
      // soluk tint'ler bu kuralın DIŞINDADIR: onların üstüne doygun `gain`
      // metni gelir ve bu doğru desendir (ilk taramada 12 yanlış alarmın
      // çoğu buydu). Negatif look-ahead ripgrep'te yok ama Dart'ta var.
      final fillPattern = RegExp(
        r'(backgroundColor|foregroundColor|color)\s*:\s*'
        r'context\.c\.(gain|loss)\b(?!\s*\.)',
      );

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in fillPattern.allMatches(src)) {
          // Yalnızca `backgroundColor` bir DOLGU bildirir. Düz `color:` bir
          // ikonun/metnin kendi rengi de olabilir; onu ancak `BoxDecoration`
          // içindeyse dolgu sayarız.
          final isBg = m.group(1) == 'backgroundColor';
          final before = src.substring((m.start - 120).clamp(0, src.length), m.start);
          final inDecoration = before.contains('BoxDecoration(');
          if (!isBg && !inDecoration) continue;

          // Pencere, dolgunun ait olduğu widget çağrısının TAMAMI olmalı.
          // Sabit karakter sayısı iki yönden de yanlıştı: 400 rozet desenini
          // ıskalıyordu, 700 ise SnackBar'ı aşıp alakasız AppBar başlığını
          // yakalıyordu. Ayrıca yalnızca ileri bakmak da yetmez — `content:`
          // çoğu SnackBar'da `backgroundColor:`ten ÖNCE yazılır. O yüzden
          // çevreleyen argüman listesinin iki ucunu da parantezle buluruz.
          //
          // `BoxDecoration` dolgusunda bir seviye YUKARI çıkmak gerekir:
          // decoration'ın kendi parantezi `child:`ten önce kapanır, metin
          // dışarıda kalır. Container(...) seviyesine çıkınca ikisi de aynı
          // pencerede olur.
          int openerOf(int pos) {
            var up = 0;
            for (var j = pos; j >= 0; j--) {
              final ch = src[j];
              if (ch == ')' || ch == ']') up++;
              if (ch == '(' || ch == '[') {
                if (up == 0) return j;
                up--;
              }
            }
            return 0;
          }

          var from = openerOf(m.start);
          if (inDecoration) from = openerOf(from - 1);

          var depth = 1;
          var to = src.length;
          for (var j = from + 1; j < src.length; j++) {
            final ch = src[j];
            if (ch == '(' || ch == '[') depth++;
            if (ch == ')' || ch == ']') {
              depth--;
              if (depth == 0) {
                to = j;
                break;
              }
            }
          }
          final around = src.substring(from, to);
          final bad = RegExp(
            r'(color|foregroundColor)\s*:\s*context\.c\.(text90|onAmber)\b',
          ).firstMatch(around);
          if (bad == null) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line — ${m.group(0)} + ${bad.group(0)}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'gain/loss DOLGU olarak kullanıldığında üstüne '
              '`context.c.onStatus` gelmeli. `text90` yüzey metnidir, '
              '`onAmber` amber içindir — ikisi de renkli dolguda kırılır.\n'
              '${offenders.join('\n')}');
    });
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

  group('kaynak taraması — ham anlamsal renk', () {
    test('Colors.green/red/orange gibi hazır tonlar kullanılmamalı', () {
      // Bunlar temayı takip etmez. `Colors.green` (#4CAF50) light yüzeyde
      // 2.78:1 verirken palet `gain`i 5.37:1 verir (signal_settings'te
      // "ÖNERİLEN" çipi tam olarak bu yüzden okunmuyordu).
      //
      // Şeffaf siyah/beyaz (gölge, perde) bu kuralın dışındadır; onlar
      // renk değil, ışık/gölge katmanıdır.
      final offenders = <String>[];
      final pattern = RegExp(
        r'Colors\.(green|red|orange|blue|purple|teal|pink|yellow)'
        r'(\[\d+\]|\.shade\d+)?\b',
      );

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        // Tema tanımının kendisi ham renk kullanmak ZORUNDA.
        if (e.path.endsWith('sandik.dart') || e.path.endsWith('main.dart')) {
          continue;
        }
        final src = e.readAsStringSync();
        for (final m in pattern.allMatches(src)) {
          final lineStart = src.lastIndexOf('\n', m.start) + 1;
          final line = src.substring(lineStart, m.start);
          if (line.trimLeft().startsWith('//')) continue; // yorum
          final no = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$no — ${m.group(0)}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'Anlamsal renkler palet token\'ından gelmeli '
              '(context.c.gain / .loss / .danger / .info).\n'
              '${offenders.join('\n')}');
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
