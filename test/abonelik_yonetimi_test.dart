import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/abonelik_yonetimi.dart';

/// `AbonelikYonetimi.ac()` sözleşmesi (2026-10-23): iOS'ta önce uygulama içi
/// sayfa (kanal `yonet`), kanal yoksa ya da açılmazsa web adresi; Android'de
/// doğrudan Play adresi. Sandbox iptal testi bu yola dayanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<Uri> acilanWeb;
  setUp(() {
    acilanWeb = [];
    AbonelikYonetimi.webAc = (uri) async {
      acilanWeb.add(uri);
      return true;
    };
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(AbonelikYonetimi.kanal, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS: uygulama içi sayfa açıldıysa web adresine gidilmez', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final cagrilar = <String>[];
    messenger.setMockMethodCallHandler(AbonelikYonetimi.kanal, (call) async {
      cagrilar.add(call.method);
      return true;
    });
    expect(await AbonelikYonetimi.ac(), isTrue);
    expect(cagrilar, ['yonet']);
    expect(acilanWeb, isEmpty);
  });

  test('iOS: kanal yoksa (eski derleme) web adresine düşer', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await AbonelikYonetimi.ac(), isTrue);
    expect(acilanWeb.single.host, 'apps.apple.com');
  });

  test('iOS: yerel taraf hata dönerse web adresine düşer', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(AbonelikYonetimi.kanal, (call) async {
      throw PlatformException(code: 'sahne');
    });
    expect(await AbonelikYonetimi.ac(), isTrue);
    expect(acilanWeb.single.host, 'apps.apple.com');
  });

  test('Android: kanal çağrılmaz, Play adresi açılır', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var kanalCagrildi = false;
    messenger.setMockMethodCallHandler(AbonelikYonetimi.kanal, (call) async {
      kanalCagrildi = true;
      return true;
    });
    expect(await AbonelikYonetimi.ac(), isTrue);
    expect(kanalCagrildi, isFalse);
    expect(acilanWeb.single.host, 'play.google.com');
  });
}
