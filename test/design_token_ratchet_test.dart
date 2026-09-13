import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `design_token_leak_test`'in kör kaldığı iki sızıntı için ratchet.
///
/// 2026-09 denetimi: o test `Color(0x…)` ve çıplak `Duration` sayıyor ama
/// `Colors.*` (89 satır) ve ham `fontSize:` (181 satır, 17 farklı boyut)
/// tamamen görünmezdi. Eşikler bugünkü sayıya kalibre edildi ve YALNIZCA
/// aşağı iner. Yeni sızıntı eklersen test kırılır; çözüm eşiği yükseltmek
/// değil `context.c.*` / `context.t.*`'ye taşımaktır.
void main() {
  List<File> files() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/theme/'))
      .toList();

  List<String> linesMatching(RegExp pattern) {
    final out = <String>[];
    for (final f in files()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) out.add('${f.path}:${i + 1}');
      }
    }
    return out;
  }

  test('ham Colors.* satır sayısı artmamalı', () {
    final hits = linesMatching(RegExp(r'Colors\.[a-zA-Z]'));
    // 2026-09-13: 89 (performance_screen 16, portfolio_performance 15, main 11).
    expect(hits.length, lessThanOrEqualTo(89),
        reason: 'context.c.* kullan:\n${hits.join('\n')}');
  });

  test('ham fontSize: satır sayısı artmamalı', () {
    final hits = linesMatching(RegExp(r'fontSize:'));
    // 2026-09-13: 181. Hedef: 7 kademeli ölçek → context.t.* (Faz 2).
    expect(hits.length, lessThanOrEqualTo(181),
        reason: 'context.t.* kullan (ya da SandikTypography ölçeğine ekle):\n'
            '${hits.join('\n')}');
  });
}
