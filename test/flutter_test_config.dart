// `flutter test` bu dosyayı test/ altındaki HER test için otomatik yükler.
import 'dart:async';

import 'package:portfoy_takip/theme/yukleme_isareti.dart';

/// Yükleme işaretinin sonsuz sayacı testlerde kapalı (2026-09-24).
///
/// `pumpAndSettle` ekranda dönen bir sayaç varken asla bitmez; 35 test
/// dosyası ona dayanıyor. Eski GIF widget testinde hiç çözülmediği için
/// sessizce hareketsizdi — bu ayar aynı davranışı açıkça verir. Sayacı
/// sınayan test bayrağı kendi içinde geçici olarak açar.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  YuklemeIsareti.hareketli = false;
  await testMain();
}
