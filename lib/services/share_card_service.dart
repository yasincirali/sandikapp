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
///
/// ## `Share.*` çağrılarının TEK kapısı burasıdır
/// Aynı hata iki kez sahadan döndü çünkü paylaşım üç ayrı yerden
/// çağrılıyordu ve dikdörtgen kuralı yalnızca birinde vardı: ortak daveti
/// (`profile_screen`) ve veri dışa aktarımı (`data_export_service`) doğrudan
/// `Share.share` / `Share.shareXFiles` çağırıyordu — dikdörtgensiz, ortak
/// davetinde ayrıca `catch`siz. iPad'de fırlayan hata kimsenin yakalamadığı
/// bir future'dan zone handler'ına düşüp ÇÖKME olarak kaydediliyordu
/// (Crashlytics: `MethodChannelShare.share → _ShareSheetState._metin`).
/// Artık her paylaşım bu sınıftan geçer; `paylasim_tek_kapi_test` başka
/// dosyada `Share.` görürse kırılır.
///
/// ## Dikdörtgen yoksa yedek (2026-11-14, yasin: "portföyü dışa aktar pdf
/// ve excel çalışmıyor, hata alıyor")
/// Portföy dökümü 31 Ekim'de Ayarlar'dan Raporlar alt sayfasına taşınınca
/// dokunulan satır sayfayla birlikte kapanıyordu; çağrı `origin: null` ile
/// geliyordu. "iPhone'da popover yok" varsayımı da artık tutmuyor: iOS 26
/// `UIActivityViewController`'a iPhone'da da `popoverPresentationController`
/// veriyor ve share_plus aynı kontrolden hatayı döndürüyor. Kural tek
/// kapıda: dikdörtgen gelmezse, boşsa ya da ekran dışına taşıyorsa
/// [guvenliKaynak] ekranın ortasında küçük bir dikdörtgen verir. Çağıranın
/// dikdörtgeni varsa popover oku yine dokunulan yere bakar.
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
    // Dosya adı paylaşıma göre: tam ekran grafik "sandik-thyao-grafik.png"
    // verir (2026-10-29); özet kartları eski adla kalır.
    String dosyaAdi = 'sandik-ozet.png',
  }) =>
      Share.shareXFiles(
        [XFile.fromData(png, mimeType: 'image/png', name: dosyaAdi)],
        text: text,
        subject: subject,
        sharePositionOrigin: _kaynak(origin),
      );

  static Future<void> shareText(
    String text, {
    required String subject,
    Rect? origin,
  }) =>
      Share.share(text, subject: subject, sharePositionOrigin: _kaynak(origin));

  /// Hazır bir dosyayı paylaşır (veri dışa aktarımı).
  ///
  /// `XFile` burada kurulur ki çağıran taraf `share_plus`'ı hiç tanımasın —
  /// dikdörtgen kuralını atlamanın yolu kalmaz.
  static Future<void> shareFile(
    String path, {
    required String mimeType,
    required String subject,
    String? text,
    Rect? origin,
  }) =>
      Share.shareXFiles(
        [XFile(path, mimeType: mimeType)],
        text: text,
        subject: subject,
        sharePositionOrigin: _kaynak(origin),
      );

  /// Birden çok hazır dosyayı TEK paylaşım sayfasıyla paylaşır (yıllık
  /// rapor PDF + Excel; e-postada iki ek). [dosyalar]: (yol, MIME).
  static Future<void> shareFiles(
    List<(String, String)> dosyalar, {
    required String subject,
    String? text,
    Rect? origin,
  }) =>
      Share.shareXFiles(
        [for (final (yol, mime) in dosyalar) XFile(yol, mimeType: mime)],
        text: text,
        subject: subject,
        sharePositionOrigin: _kaynak(origin),
      );

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

  static Rect? _kaynak(Rect? origin) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return origin;
    final v = views.first;
    return guvenliKaynak(origin, v.physicalSize / v.devicePixelRatio);
  }

  /// share_plus'a giden dikdörtgen: [origin] boş değilse ve [ekran]
  /// içindeyse aynen, değilse ekranın ortasında 2×2 pt. Ekran ölçüsü
  /// bilinmiyorsa (sıfır) [origin] olduğu gibi döner. Saf, test edilir.
  static Rect? guvenliKaynak(Rect? origin, Size ekran) {
    if (ekran.isEmpty) return origin;
    final cerceve = Offset.zero & ekran;
    if (origin != null &&
        !origin.isEmpty &&
        cerceve.contains(origin.topLeft) &&
        cerceve.contains(origin.bottomRight - const Offset(0.01, 0.01))) {
      return origin;
    }
    return Rect.fromCenter(center: cerceve.center, width: 2, height: 2);
  }
}
