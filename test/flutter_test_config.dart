// `flutter test` bu dosyayı test/ altındaki HER test için otomatik yükler.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart' show pushGuardSifirla;
import 'package:portfoy_takip/theme/yukleme_isareti.dart';

/// Yükleme işaretinin sonsuz sayacı testlerde kapalı (2026-09-24).
///
/// `pumpAndSettle` ekranda dönen bir sayaç varken asla bitmez; 35 test
/// dosyası ona dayanıyor. Eski GIF widget testinde hiç çözülmediği için
/// sessizce hareketsizdi — bu ayar aynı davranışı açıkça verir. Sayacı
/// sınayan test bayrağı kendi içinde geçici olarak açar.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  YuklemeIsareti.hareketli = false;
  // NOT: 2026-10-04 bayraklarını testlerde kapatan `testKapali` listesi
  // 2026-10-05'te bayraklarla birlikte kalktı; testler kalıcı davranışı
  // sınar.
  // pushGuarded'ın çift dokunma penceresi gerçek saatle ölçülür ve süreç
  // boyunca yaşar; ardışık iki widget testi 500 ms içinde koşunca ikincinin
  // push'u sessizce düşüyordu (CI, kapanis_rapor_kilit_test, 2026-11-23).
  setUp(pushGuardSifirla);
  await testMain();
}
