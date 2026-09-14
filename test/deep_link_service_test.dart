import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/deep_link_service.dart';

/// Dış kaynaklı derin bağlantı köprüsü (3.8).
///
/// Platform kanalı testte yok; köprünün KARARI (hangi URI hangi eyleme)
/// enjekte edilmiş handler ile doğrulanır, `DeepLinkRouter` testleri
/// ayrıştırmayı zaten kilitliyor.
void main() {
  test('sandik://asset/<id> varlık ekranını açar', () {
    final acilan = <String>[];
    final s = DeepLinkService.withHandler(acilan.add);
    expect(s.handle(Uri.parse('sandik://asset/abc-123')), isTrue);
    expect(acilan, ['abc-123']);
  });

  test('widget / live-activity host\'ları BURADA yok sayılır', () {
    // `HomeWidgetService` zaten karşılıyor; çift işleme yok.
    final acilan = <String>[];
    final s = DeepLinkService.withHandler(acilan.add);
    expect(s.handle(Uri.parse('sandik://widget')), isFalse);
    expect(s.handle(Uri.parse('sandik://live-activity')), isFalse);
    expect(acilan, isEmpty);
  });

  test('tanınmayan şema / bozuk yol hiçbir şey yapmaz', () {
    final acilan = <String>[];
    final s = DeepLinkService.withHandler(acilan.add);
    expect(s.handle(Uri.parse('https://example.com/asset/x')), isFalse);
    expect(s.handle(Uri.parse('sandik://asset/a/b')), isFalse);
    expect(s.handle(Uri.parse('sandik://asset')), isFalse);
    expect(acilan, isEmpty);
  });

  test('köprü açılışta kuruluyor (wiring)', () {
    // Servis doğru olsa da main.dart'ta çağrılmazsa dış bağlantılar yine
    // düşmez. Kaynak metni denetlemek bu regresyonu görünür kılar.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('DeepLinkService.instance.init()'), isTrue);
  });

  test('platform tarafı: Android intent-filter ve iOS URL şeması', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:scheme="sandik"'), isTrue);
    expect(manifest.contains('android.intent.action.VIEW'), isTrue);
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('CFBundleURLSchemes'), isTrue);
    expect(plist.contains('<string>sandik</string>'), isTrue);
  });
}
