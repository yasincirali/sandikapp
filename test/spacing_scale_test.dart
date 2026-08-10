import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Boşluk ölçeği denetimi — **cırcır (ratchet)** testi.
///
/// Denetimde (2026-08-10) 878 boşluk kullanımı sayıldı ve %63'ü
/// `SandikSpace` ölçeğinin dışındaydı. Ama bu rastgelelik değildi: 12, 10,
/// 14, 6 değerleri tek başına 369 kullanımdı — yani fiilen 2pt adımlı bir
/// ölçek vardı, resmî ölçek (4pt adım) onu karşılamıyordu.
///
/// Ölçek gerçeğe uyduruldu (ara adımlar eklendi). Bu test **mevcut
/// durumu dondurur**: yeni ölçek-dışı değer eklenemez, ama var olan
/// kullanımları toplu değiştirmeye de zorlamaz.
///
/// Neden toplu değişim yapılmadı: 555 çağrı yerini ölçeğe zorlamak görsel
/// yerleşimi piksel piksel kaydırır. Riski yüksek, faydası tartışmalı.
/// Ölçeği veriye uydurmak aynı tutarlılığı sıfır görsel değişiklikle verir.
///
/// **Eşik düşerse azalt.** Bu sayı yalnızca aşağı gitmeli.
void main() {
  // Ölçek: SandikSpace'teki tüm değerler.
  const scale = <int>{2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 48};

  /// Tema tanımının kendisi ham sayı kullanmak zorunda.
  bool skip(String path) =>
      path.endsWith('sandik.dart') || path.endsWith('main.dart');

  List<({String file, int line, int value})> collect() {
    final out = <({String file, int line, int value})>[];
    final patterns = <RegExp>[
      RegExp(r'SizedBox\(\s*(?:height|width):\s*(\d+)(?:\.0)?\s*[,)]'),
      RegExp(r'EdgeInsets\.all\(\s*(\d+)(?:\.0)?\s*\)'),
    ];

    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (skip(e.path)) continue;
      final src = e.readAsStringSync();
      for (final p in patterns) {
        for (final m in p.allMatches(src)) {
          final v = int.parse(m.group(1)!);
          // Çok büyük değerler boşluk değil, boyut kısıtıdır (örn. 300pt
          // grafik yüksekliği) — ölçek onları kapsamaz.
          if (v > 48) continue;
          if (scale.contains(v)) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          out.add((file: e.path, line: line, value: v));
        }
      }
    }
    return out;
  }

  test('ölçek dışı boşluk sayısı artmamalı', () {
    // 2026-08-10 ölçümü: ölçek genişletildikten SONRA kalan tam sayı.
    // Boşluk bırakılmadı — gevşek eşik cırcırı işlevsiz kılar.
    // Kalanlar: 3 (×14), 28 (×13), 18 (×9), 22, 36, 40, 44, 46, 1, 5.
    const esik = 48;

    final offenders = collect();

    expect(
      offenders.length,
      lessThanOrEqualTo(esik),
      reason: 'Ölçek dışı boşluk sayısı $esik idi, şimdi '
          '${offenders.length}. Yeni boşluklar `SandikSpace` içinden '
          'seçilmeli (2/4/6/8/10/12/14/16/20/24/32/48).\n'
          '${offenders.take(15).map((o) => "${o.file}:${o.line} — ${o.value}").join("\n")}',
    );
  });

  test('ölçek 2pt adımlı ve tutarlı', () {
    final sorted = scale.toList()..sort();
    for (final v in sorted) {
      expect(v % 2, 0, reason: '$v tek sayı — ölçek 2pt adımlı olmalı.');
    }
    // Ölçeğin kendisi kaynakta gerçekten tanımlı mı?
    final src = File('lib/theme/sandik.dart').readAsStringSync();
    for (final v in sorted) {
      expect(
        RegExp(r'static const double \w+ = ' + v.toString() + r'\s*;')
            .hasMatch(src),
        isTrue,
        reason: '$v ölçekte sayılıyor ama SandikSpace içinde tanımlı değil.',
      );
    }
  });
}
