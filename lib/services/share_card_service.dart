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
  }) =>
      Share.shareXFiles(
        [XFile.fromData(png, mimeType: 'image/png', name: 'sandik-ozet.png')],
        text: text,
        subject: subject,
      );

  static Future<void> shareText(String text, {required String subject}) =>
      Share.share(text, subject: subject);
}
