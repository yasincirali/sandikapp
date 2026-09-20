import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Arka plan işi `unawaited(...)` ile değil `CrashReporter.arkaPlan(...)` ile
/// bırakılır — ratchet (2026-09-20 süpürmesi, 73 → 0 çıplak çağrı).
///
/// `unawaited()` yalnızca lint'i susturur; future hata ile biterse hata
/// `runZonedGuarded`'a düşer ve ÇÖKME olarak raporlanır (Crashlytics
/// "crash-free users" oranı — mağaza kalite sinyali). `arkaPlan` aynı
/// hatayı non-fatal kaydeder (gerekçe `CrashReporter.arkaPlan` notunda).
///
/// Bilinçli istisnalar (çıplak `unawaited` kalabilir):
///   · `AnalyticsService.*` — `_log` kendi içinde yakalar, hata üretmez.
///   · `.catchError(` taşıyanlar — zaten yakalanmış.
///   · `SystemNavigator.pop`, `slidable?.close`, `showAppSuccess` — UI, ağ yok.
///   · `crash_reporter.dart` — `arkaPlan`'ın kendisi.
void main() {
  test('lib/ içinde çıplak unawaited(...) yok', () {
    const istisna = [
      'AnalyticsService',
      '.catchError(',
      'SystemNavigator',
      'slidable',
      'showAppSuccess',
    ];
    final ihlaller = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final yol = f.path.replaceAll('\\', '/');
      if (yol.contains('/generated/')) continue;
      if (yol.endsWith('services/crash_reporter.dart')) continue;
      final satirlar = f.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i];
        if (s.trimLeft().startsWith('//')) continue;
        if (!s.contains('unawaited(')) continue;
        // Çok satırlı çağrı: ifadenin gövdesi birkaç satır sürebilir.
        final govde = satirlar.skip(i).take(4).join(' ');
        if (istisna.any(govde.contains)) continue;
        ihlaller.add('$yol:${i + 1}');
      }
    }
    expect(
      ihlaller,
      isEmpty,
      reason: 'Arka plan işi için `CrashReporter.arkaPlan(future, reason: ...)` '
          'kullan; hata ÇÖKME değil non-fatal kayıt olsun. '
          'Gerçekten hatasız bir çağrıysa istisna listesine gerekçesiyle ekle.',
    );
  });
}
