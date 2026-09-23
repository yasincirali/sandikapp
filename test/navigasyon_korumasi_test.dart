import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Navigasyon kuralı — 2026-09-23 denetimi F21.
///
/// CLAUDE.md: "`Navigator.push` yerine `adaptiveRoute` (iOS geçişi) ve
/// `pushGuarded` (çift dokunma koruması). `MaterialPageRoute` doğrudan
/// kullanılmaz." Denetimde portföy satırı (ve giriş/kayıt ekranları) ham
/// `CupertinoPageRoute` + korumasız `Navigator.push` kullanıyordu: satıra
/// hızlı iki dokunuş aynı detay ekranını iki kez açıyor, Android'de de iOS
/// geçişi veriyordu.
///
/// İki kural taranır:
///  1. `lib/screens` + `lib/widgets` içinde ham `MaterialPageRoute` /
///     `CupertinoPageRoute` YOK — rota yalnızca `adaptiveRoute`'tan gelir.
///  2. Korumasız `Navigator.push` / `Navigator.of(context).push` yalnızca
///     aşağıdaki gerekçeli yerlerde kalır; sayılar yalnızca AZALABİLİR.
void main() {
  List<File> kaynaklar() => [
        for (final d in ['lib/screens', 'lib/widgets'])
          ...Directory(d)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];

  Iterable<String> kodSatirlari(File f) => f
      .readAsLinesSync()
      .where((s) => !s.trimLeft().startsWith('//'));

  test('ekran/widget katmanında ham MaterialPageRoute/CupertinoPageRoute yok',
      () {
    final desen = RegExp(r'\b(Material|Cupertino)PageRoute\b');
    final ihlal = <String>[
      for (final f in kaynaklar())
        for (final s in kodSatirlari(f))
          if (desen.hasMatch(s)) '${f.path}: ${s.trim()}',
    ];
    expect(ihlal, isEmpty,
        reason: 'Rota `adaptiveRoute` ile kurulmalı, dokunuşla açılıyorsa '
            '`pushGuarded` ile itilmeli.');
  });

  test('korumasız push yalnızca gerekçeli yerlerde (ratchet)', () {
    // Gerekçeler:
    //  · home_screen (4): bildirim listesi önce kendini `pop` ediyor, sonra
    //    hedefe gidiyor — liste kapandığı için ikinci dokunuş olamaz.
    //  · paywall_screen / recap_screen (1'er): `static show` yardımcıları;
    //    dokunuştan değil akıştan (limit aşımı, yıl sonu) çağrılıyor ve
    //    `pushGuarded`'ın 350 ms penceresi meşru bir açılışı yutabilirdi.
    const tavan = <String, int>{
      'lib/screens/home_screen.dart': 4,
      'lib/screens/paywall_screen.dart': 1,
      'lib/screens/recap_screen.dart': 1,
    };
    final desen = RegExp(r'Navigator\.(of\([^)]*\)\.)?push(<[^>]+>)?\(');
    final sayim = <String, int>{};
    for (final f in kaynaklar()) {
      final yol = f.path.replaceAll(r'\', '/');
      for (final s in kodSatirlari(f)) {
        final n = desen.allMatches(s).length;
        if (n > 0) sayim[yol] = (sayim[yol] ?? 0) + n;
      }
    }
    for (final e in sayim.entries) {
      expect(e.value, lessThanOrEqualTo(tavan[e.key] ?? 0),
          reason: '${e.key}: ${e.value} korumasız push. Dokunuşla açılan '
              'ekran `pushGuarded(context, adaptiveRoute(...))` ile itilir.');
    }
  });

  test('portföy satırı detayı pushGuarded + adaptiveRoute ile açar', () {
    final src = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect(
      RegExp(r'onTap: \(p\) => pushGuarded\(\s*context,\s*adaptiveRoute<void>\(')
          .hasMatch(src),
      isTrue,
    );
  });
}
