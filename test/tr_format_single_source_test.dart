import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Para/tarih biçimlendirme TEK YERDEN geçer — `lib/utils/tr_format.dart`.
///
/// 2026-09 denetimi: 20 ad-hoc `NumberFormat.currency(locale: 'tr_TR' …)`
/// kopyası vardı ve aynı ₺ tutarı için 0/2/3 ondalık arasında değişiyordu;
/// `DateTime(t.year, t.month, t.day)` 38 kez elle yazılmıştı; leaderboard
/// yüzdeleri `12.5%` (İngiliz ayraç) basıyordu. Bu test kopyaların geri
/// gelmesini engeller. Ondalık SAYISI çağıranın kararı olmaya devam eder
/// (`tryFormatter(digits: 3)`), ama locale/sembol/ayraç buradan gelir.
void main() {
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll(r'\', '/').endsWith('utils/tr_format.dart'))
      .toList();

  List<String> hits(RegExp pattern) {
    final out = <String>[];
    for (final f in libFiles()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(lines[i])) out.add('${f.path}:${i + 1}');
      }
    }
    return out;
  }

  test('NumberFormat.currency / NumberFormat(\'#…\') yalnızca tr_format.dart\'ta', () {
    final h = hits(RegExp(r"NumberFormat\.currency\(|NumberFormat\('#"));
    expect(h, isEmpty,
        reason: 'tryFormatter / qtyFormatter / fixedFormatter / fmtTRY kullan:\n'
            '${h.join('\n')}');
  });

  test('DateTime(t.year, t.month, t.day) elle yazılmaz — dayKey(t)', () {
    final h = hits(RegExp(
        r'DateTime\(([A-Za-z_][\w.]*)\.year,\s*\1\.month,\s*\1\.day\)'));
    expect(h, isEmpty, reason: 'dayKey(t) kullan:\n${h.join('\n')}');
  });

  test('UI katmanında toStringAsFixed sayısı artmamalı (ratchet)', () {
    final h = <String>[];
    for (final f in libFiles()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.contains('lib/screens/') && !p.contains('lib/widgets/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('toStringAsFixed')) h.add('$p:${i + 1}');
      }
    }
    // 2026-09-13: 22 → 5. Kalanlar: performance_screen (yüzde ekseni, 4 —
    // comparison_axis_test ile sözleşmeli) ve percent_comparison_chart (1).
    expect(h.length, lessThanOrEqualTo(5),
        reason: 'fmtNum / fmtPct kullan:\n${h.join('\n')}');
  });

  group('yardımcılar', () {
    test('tryFormatter tr ayraçlarıyla ₺ basar', () {
      expect(tryFormatter().format(1234.4), '₺1.234');
      expect(tryFormatter(digits: 2).format(1234.5), '₺1.234,50');
      expect(tryFormatter(digits: 2, symbol: r'$').format(1), r'$1,00');
    });
    test('qtyFormatter trailing sıfır atar, fixedFormatter atmaz', () {
      expect(qtyFormatter().format(1.5), '1,5');
      expect(qtyFormatter(maxDigits: 0).format(1234.0), '1.234');
      expect(fixedFormatter(3).format(1.5), '1,500');
      expect(fixedFormatter(0).format(1234.0), '1.234');
    });
    test('dayKey saati atar, günü korur', () {
      final t = DateTime(2026, 9, 13, 17, 45, 12);
      expect(dayKey(t), DateTime(2026, 9, 13));
      expect(dayKey(t).isAtSameMomentAs(dayKey(DateTime(2026, 9, 13, 1))), isTrue);
    });
  });
}
