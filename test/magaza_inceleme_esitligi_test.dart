import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// App Store Guideline 2.3.1(a) (2026-10-14): Apple, inceleme ortamını
/// tespit edip Remote Config ile farklı davranan uygulamaları "hidden
/// features" diye reddediyor. Kural (CLAUDE.md "Mağaza incelemesi"):
/// uygulama nereden kurulduğunu (TestFlight, sandbox makbuzu, simülatör,
/// mağaza) hiçbir yere bildirmez, buna göre dallanmaz; test kitlesi hesapla
/// seçilir. Bu test kaynağı tarar ki eski `dagitim` sinyali ya da benzeri
/// sessizce geri gelmesin.
void main() {
  // Yorum satırları gerekçe olarak bu adları anabilir; yalnız kod taranır.
  String kodKismi(String metin) => metin
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('//'))
      .join('\n');

  Iterable<File> dosyalar(String kok, String uzanti) => Directory(kok)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(uzanti))
      .where((f) => !f.path.contains('/generated/'));

  test('Dart kodu kurulum kanalını okumaz', () {
    final yasak = RegExp(
        r'installerStore|sandboxReceipt|com\.apple\.testflight|'
        r'appStoreReceipt|isTestFlight|InstallSource|getInstallerPackageName');
    final ihlal = <String>[];
    for (final f in dosyalar('lib', '.dart')) {
      final m = yasak.firstMatch(kodKismi(f.readAsStringSync()));
      if (m != null) ihlal.add('${f.path}: ${m.group(0)}');
    }
    expect(ihlal, isEmpty,
        reason: 'Mağaza incelemesi kuralı: kurulum kanalına göre davranış '
            'yok; test kitlesi hesapla seçilir (RemoteConfigService.hesabiBildir).');
  });

  test('iOS ve Android yerel kodu kurulum kanalını okumaz', () {
    final yasak = RegExp(
        r'appStoreReceiptURL|sandboxReceipt|AppTransaction|'
        r'getInstallerPackageName|getInstallSourceInfo');
    final ihlal = <String>[];
    for (final kok in ['ios', 'android']) {
      if (!Directory(kok).existsSync()) continue;
      for (final uz in ['.swift', '.m', '.kt', '.java']) {
        for (final f in dosyalar(kok, uz)) {
          if (f.path.contains('/Pods/') || f.path.contains('/build/')) {
            continue;
          }
          final m = yasak.firstMatch(kodKismi(f.readAsStringSync()));
          if (m != null) ihlal.add('${f.path}: ${m.group(0)}');
        }
      }
    }
    expect(ihlal, isEmpty);
  });

  test('Remote Config özel sinyali yalnız hesap kimliğidir', () {
    final kaynak = File('lib/services/remote_config_service.dart')
        .readAsStringSync();
    final cagrilar = RegExp(r'setCustomSignals\(\{\s*([^:}]+):')
        .allMatches(kodKismi(kaynak))
        .map((m) => m.group(1)!.trim())
        .toSet();
    expect(cagrilar, {'hesapSinyaliAnahtari'});
    expect(RemoteConfigService.hesapSinyaliAnahtari, 'hesap');
    // Başka dosya sinyal yazmaz.
    for (final f in dosyalar('lib', '.dart')) {
      if (f.path.endsWith('remote_config_service.dart')) continue;
      expect(kodKismi(f.readAsStringSync()).contains('setCustomSignals'),
          isFalse,
          reason: f.path);
    }
  });

  test('hesap sinyali: oturum yoksa boş, varsa kimlik', () {
    expect(RemoteConfigService.hesapSinyali(null), '');
    expect(
        RemoteConfigService.hesapSinyali(
            ' 8F1C2A3B-0000-4000-8000-000000000001 '),
        '8f1c2a3b-0000-4000-8000-000000000001');
  });
}
