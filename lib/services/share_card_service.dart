import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Paylaşım kartını PNG'ye çevirip sistem paylaşım sayfasına verir.
///
/// **Neden widget ağacından (`RepaintBoundary.toImage`), `dart:ui` ile
/// elle çizim değil:** kart tipografi ve tema token'larını (DM Sans,
/// `context.t`) aynen kullanmalı; ana ekran widget'ındaki gibi elle çizim
/// ikinci bir "kart görünümü" üretirdi ve iki kopya ayrışırdı. Kullanıcı
/// paylaşmadan önce kartı zaten ekranda GÖRÜYOR (önizleme sayfası) — çizilen
/// ile paylaşılan aynı piksel.
///
/// ## `origin` — iPad'de ZORUNLU (2026-09-16 kök neden)
/// share_plus, iOS'ta paylaşım sayfasını `UIActivityViewController` ile
/// açıyor ve popover sunan cihazlarda (iPad, "iPad için tasarlandı" modunda
/// Mac) **kaynak dikdörtgen verilmezse `FlutterError` fırlatıyor**:
/// "sharePositionOrigin: argument must be set, must be non-zero and within
/// coordinate space of source view". iPhone'da popover yok, aynı çağrı
/// sorunsuz — bu yüzden hata geliştirici telefonunda hiç üretilemedi ama
/// sahada "paylaş butonu hata veriyor" olarak döndü (`share_plus` 10.1.4,
/// `FPPSharePlusPlugin.m` `share:withSubject:…atSource:`). Metin yolu da
/// AYNI kontrolden geçiyor; iki yol da dikdörtgeni taşır. Çağıran taraf
/// dikdörtgeni dokunulan düğmeden üretir (`_ShareSheet`), böylece popover
/// oku da doğru yere bakar.
class ShareCardService {
  const ShareCardService._();

  /// Sosyal medya için yeterli, dosya boyutu makul (~300 KB).
  static const pixelRatio = 3.0;

  static Future<Uint8List> renderPng(GlobalKey boundaryKey) async {
    final obj = boundaryKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) {
      throw StateError('Paylaşım kartı henüz çizilmedi');
    }
    final image = await obj.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('PNG üretilemedi');
    return bytes.buffer.asUint8List();
  }

  /// Görsel + metin birlikte: hedef uygulama görseli almıyorsa (SMS, not)
  /// metin yine iletilir; alıyorsa metin altyazı olur.
  static Future<void> shareImage(
    Uint8List png, {
    required String text,
    required String subject,
    Rect? origin,
  }) =>
      Share.shareXFiles(
        [XFile.fromData(png, mimeType: 'image/png', name: 'sandik-ozet.png')],
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      );

  static Future<void> shareText(
    String text, {
    required String subject,
    Rect? origin,
  }) =>
      Share.share(text, subject: subject, sharePositionOrigin: origin);

  /// Bir widget'ın ekrandaki dikdörtgeni — `sharePositionOrigin` için.
  ///
  /// Render nesnesi yoksa ya da henüz yerleşmediyse `null`: share_plus
  /// null'u "dikdörtgen yok" sayar (iPhone'da sorun değil), sıfır boyutlu
  /// bir dikdörtgense iPad'de yine fırlatırdı.
  static Rect? originOf(BuildContext? context) {
    final obj = context?.findRenderObject();
    if (obj is! RenderBox || !obj.hasSize || obj.size.isEmpty) return null;
    return obj.localToGlobal(Offset.zero) & obj.size;
  }
}
