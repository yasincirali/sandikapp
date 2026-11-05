import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// unslop kararları (yasin 5 Kas 2026, "tüm işleri yap"): bölüm başlıkları
/// ve etiketler cümle düzeninde, ağırlık tavanı w600, tur rozetleri sade.
/// Kilit, geri dönüşü yakalar.
void main() {
  test('w800/w900 yalnız oyun sahnelerinde ve toplam kartında', () {
    const istisna = {
      'lib/widgets/yaris_sahnesi.dart',
      'lib/widgets/duello_arenasi.dart',
      'lib/widgets/leaderboard_hero_card.dart',
      'lib/widgets/portfolio_summary_widget.dart',
    };
    final ihlal = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final yol = f.path.replaceAll('\\', '/');
      if (istisna.contains(yol) || yol.contains('/generated/')) continue;
      final k = f.readAsStringSync();
      if (k.contains('FontWeight.w800')) ihlal.add(yol);
    }
    expect(ihlal, isEmpty, reason: 'w800 geri geldi: $ihlal');
  });

  test('.arb metinleri BÜYÜK HARF değil (kısaltmalar hariç)', () {
    final tr = jsonDecode(File('lib/l10n/app_tr.arb').readAsStringSync())
        as Map<String, dynamic>;
    const kisaltma = {
      'BIST 100',
      'BIST',
      'ABD',
      'BES',
      'TÜFE',
      'TÜİK TÜFE',
      'PDF',
      'JSON'
    };
    final buyuk = <String>[];
    tr.forEach((k, v) {
      if (k.startsWith('@') || v is! String || kisaltma.contains(v)) return;
      final harf = v
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .split('')
          .where((c) => c.toLowerCase() != c.toUpperCase())
          .toList();
      if (harf.length >= 3 && harf.every((c) => c == c.toUpperCase())) {
        buyuk.add('$k: $v');
      }
    });
    // TEFAS · {tarih} ve OHLC kısaltma satırı bilinçli.
    buyuk.removeWhere(
        (s) => s.startsWith('xrKaynakTefas') || s.startsWith('chartOhlcLine'));
    expect(buyuk, isEmpty, reason: 'büyük harf metin: $buyuk');
  });

  test('bölüm başlığı w600, harf aralıksız', () {
    final k = File('lib/theme/sandik.dart').readAsStringSync();
    final bas = k.indexOf('class SandikSectionHeader');
    final govde = k.substring(bas, k.indexOf('class ', bas + 10));
    expect(govde, isNot(contains('letterSpacing')));
    expect(govde, contains('FontWeight.w600'));
  });

  test('turda "YENİ" rozeti ve parıltı yok', () {
    final k = File('lib/screens/onboarding_screen.dart').readAsStringSync();
    expect(k, isNot(contains("rozet: 'YENİ'")));
    final bas = k.indexOf('class _Rozet');
    final govde = k.substring(bas);
    expect(govde.substring(0, govde.indexOf('\n}\n')),
        isNot(anyOf(contains('auto_awesome'), contains('Gradient'))));
  });
}
