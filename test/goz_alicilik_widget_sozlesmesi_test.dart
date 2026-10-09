import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Göz alıcılık widget/Canlı Etkinlik (2026-10-09), bayrak `goz_alici`.
///
/// Swift ve Kotlin burada derlenmiyor; Dart'ın yazdığı anahtar ile native
/// tarafın okuduğu anahtar tek harf ayrışırsa yeni görünüm sessizce hiç
/// açılmaz. Bu test iki ucu metin olarak kilitler.
void main() {
  String oku(String yol) => File(yol).readAsStringSync();

  test('ana ekran widget anahtarı Dart, iOS ve Android\'de aynı', () {
    const anahtar = "'sandik_goz_alici'";
    expect(oku('lib/services/home_widget_service.dart'), contains(anahtar));
    expect(oku('ios/SandikWidget/SandikHomeWidget.swift'),
        contains('"sandik_goz_alici"'));
    expect(
        oku('android/app/src/main/kotlin/com/sandik/app/SandikWidgetProvider.kt'),
        contains('"sandik_goz_alici"'));
  });

  test('Canlı Etkinlik bayrağı start argümanından özniteliğe geçer', () {
    expect(oku('lib/services/live_activity_service.dart'),
        contains("'gozAlici': RemoteConfigService.instance.gozAlici"));
    final eklenti = oku('ios/Runner/LiveActivityPlugin.swift');
    expect(eklenti, contains('args["gozAlici"] as? Bool ?? false'));
    expect(eklenti, contains('gozAlici: gozAlici'));
    // Eski sürümün açtığı oturum alanı taşımaz: çözümleme toleranslı olmalı.
    expect(oku('ios/SandikWidget/SandikAttributes.swift'),
        contains('decodeIfPresent(Bool.self, forKey: .gozAlici) ?? false'));
  });

  test('günü sürükleyen alanları Dart, eklenti, uzantı ve sunucuda aynı', () {
    // Ayrışan bir anahtar satırı sessizce hiç göstermez (madde 4).
    const alanlar = [
      'surukleyenAd',
      'surukleyenPctText',
      'surukleyenTutarText',
      'surukleyenPozitif',
    ];
    final dart = oku('lib/services/live_activity_service.dart');
    final eklenti = oku('ios/Runner/LiveActivityPlugin.swift');
    final tip = oku('ios/SandikWidget/SandikAttributes.swift');
    final sunucu = oku('supabase/functions/push-live-activity/index.ts');
    for (final a in alanlar) {
      expect(dart, contains("'$a'"), reason: a);
      expect(eklenti, contains('args["$a"]'), reason: a);
      expect(tip, contains('forKey: .$a)'), reason: a);
      expect(sunucu, contains('$a:'), reason: a);
    }
  });
}
