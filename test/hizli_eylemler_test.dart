import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/hizli_eylemler.dart';

/// İkon kısayolları (2026-10-19): sistemin bildirdiği tür adı isteğe döner,
/// kabuk isteği tüketir; simgeler iki platformda da yerinde.
void main() {
  test('tür adı isteğe çözülür, bilinmeyen yok sayılır', () {
    expect(HizliEylemler.cozumle('varlikEkle'), HizliEylem.varlikEkle);
    expect(HizliEylemler.cozumle('alarmKur'), HizliEylem.alarmKur);
    expect(HizliEylemler.cozumle('arama'), HizliEylem.arama);
    expect(HizliEylemler.cozumle('bugun'), isNull);
    expect(HizliEylemler.cozumle(null), isNull);
  });

  test('sekme kabuğu isteği dinler, tüketir ve bırakır', () {
    final s = File('lib/screens/main_navigation_screen.dart').readAsStringSync();
    expect(s, contains('HizliEylemler.istek.addListener(_hizliEylemGeldi)'));
    expect(s, contains('HizliEylemler.istek.removeListener(_hizliEylemGeldi)'));
    expect(s, contains('HizliEylemler.istek.value = null'));
    for (final e in HizliEylem.values) {
      expect(s, contains('case HizliEylem.${e.name}:'));
    }
  });

  test('simge kaynakları iki platformda var ve küçültücüden korunuyor', () {
    final keep =
        File('android/app/src/main/res/raw/hizli_eylem_keep.xml').readAsStringSync();
    for (final ad in ['hizli_ekle', 'hizli_alarm', 'hizli_arama']) {
      expect(File('android/app/src/main/res/drawable/$ad.xml').existsSync(), isTrue);
      expect(keep, contains('@drawable/$ad'));
      expect(
          File('ios/Runner/Assets.xcassets/$ad.imageset/Contents.json')
              .existsSync(),
          isTrue);
    }
  });
}
