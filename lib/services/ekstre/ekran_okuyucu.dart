import 'package:flutter/services.dart';

import 'ekran_goruntusu.dart';
import 'ekstre_tablosu.dart';

/// Görüntü baytları → metin hücreleri. Cihazdaki OCR'a (iOS Vision, Android
/// ML Kit) dokunan tek dosya; satırları anlamak `ekran_goruntusu.dart`'ta
/// saf Dart'tır. Görüntü cihazdan çıkmaz.
///
/// Yerel taraf: `ios/Runner/AppDelegate.swift` `OcrChannel`,
/// `android/.../MainActivity.kt` `ocrKanaliniKur`. Biçim: her satır
/// `{t, l, u, r, b, k: [{t, l, u, r, b}]}` (piksel, sol üst başlangıç).
const _kanal = MethodChannel('com.sandik.app/ocr');

Future<List<OcrHucre>> ekranGoruntusunuOku(Uint8List bayt) async {
  final List<Object?>? ham;
  try {
    ham = await _kanal.invokeListMethod<Object?>('oku', bayt);
  } on MissingPluginException {
    throw const EkstreOkumaHatasi('Bu cihazda görüntüden metin okunamıyor.');
  } on PlatformException {
    throw const EkstreOkumaHatasi(
      'Görüntü okunamadı. Başka bir ekran görüntüsü dene.',
    );
  }
  return ocrSatirlarindanHucreler([
    for (final s in ham ?? const <Object?>[])
      if (s is Map) OcrSatiri.haritadan(s),
  ]);
}
