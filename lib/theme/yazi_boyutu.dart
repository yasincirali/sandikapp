// Uygulama içi yazı boyutu (Ayarlar › Görünüm › Yazı boyutu).
//
// Kullanıcı isteği (2026-10-03): "Ayarlar'da punto için bir ayar bulunsun,
// tasarımı bozmayacak sınırlarda büyütüp küçültebilsin."
//
// **Neden cihaz ölçeğinin ÇARPANI, yerine geçen değer değil:** Dynamic Type /
// Android yazı boyutu erişilebilirlik ayarıdır; uygulama ayarı onu ezerse
// cihazda büyük yazı açmış kullanıcı "Normal"de küçük yazı görür. Uygulama
// ayarı cihaz ölçeğinin üstüne ince ayardır. Sarılan ölçek doğrusal
// olmayabilir (Android 14 büyük puntoları daha az büyütür); çarpan onun
// SONUCUNA uygulanır, eğri korunur.
//
// **Neden üst sınır:** büyütme yönünde birleşik ölçek [ustSinir]'ı (1.3×)
// aşmaz — 1.3× kademeli ekranların (ana sayfa kartları, Performans, varlık
// listesi) 360pt genişlikte taşmadan sığdığı en yüksek değer (ekran
// görüntüleriyle doğrulandı, PR "Yazı boyutu ayarı"). Ama sınır cihazın
// KENDİ ölçeğini asla aşağı çekmez: cihazda 1.5× açık kullanıcı "Büyük"
// seçince 1.5×'te kalır, küçülmez. Uygulama ayarı erişilebilirliği
// azaltamaz; yalnızca küçültme yönünde ("Küçük") bilinçli seçimle azaltır.
//
// **Canlı kullanıcı etkilenmez:** varsayılan "Normal" (çarpan 1.0) ve
// "Normal"de cihazın MediaQuery verisi değiştirilmeden geçer
// (`YaziBoyutuKapsami`) — ayarı açmayan kullanıcı için ekran bit bit
// eskisi gibidir.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Ayardaki kademeler. Sıra = kayıtlı indeks (`PrefKeys.yaziBoyutu`);
/// yeniden SIRALAMA kullanıcının kayıtlı seçimini değiştirir, yalnızca sona
/// ekle.
enum YaziBoyutu {
  kucuk(0.9),
  normal(1.0),
  buyuk(1.1),
  cokBuyuk(1.2);

  const YaziBoyutu(this.carpan);

  /// Cihaz ölçeğinin sonucuna uygulanan çarpan.
  final double carpan;

  /// Kayıtlı indeksten kademe; tanınmayan değer (bozuk kayıt, ileride
  /// eklenip geri alınmış kademe) "Normal"e düşer — çökme yok, sürpriz yok.
  static YaziBoyutu indekstenOku(int i) =>
      (i >= 0 && i < values.length) ? values[i] : normal;
}

/// Cihaz ölçeğini [carpan] ile çarpan, büyütmeyi [ustSinir] ile sınırlayan
/// [TextScaler].
@immutable
class KullaniciYaziOlcegi extends TextScaler {
  const KullaniciYaziOlcegi({
    required this.cihaz,
    required this.carpan,
    this.ustSinir = ustSinirVarsayilan,
  });

  /// Büyütme yönünde birleşik ölçeğin tavanı (cihaz ölçeği bunu zaten
  /// aşıyorsa cihaz ölçeği tavandır). Gerekçe dosya başında.
  static const double ustSinirVarsayilan = 1.3;

  final TextScaler cihaz;
  final double carpan;
  final double ustSinir;

  @override
  double scale(double fontSize) {
    final temel = cihaz.scale(fontSize);
    final istenen = temel * carpan;
    if (carpan <= 1.0) return istenen;
    return math.min(istenen, math.max(temel, fontSize * ustSinir));
  }

  // TextScaler sözleşmesi bu (eskimiş) alanı hâlâ istiyor; 14pt gövde
  // metni temsilî boydur (Flutter'ın kendi doğrusal olmayan ölçeğiyle aynı).
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is KullaniciYaziOlcegi &&
      other.cihaz == cihaz &&
      other.carpan == carpan &&
      other.ustSinir == ustSinir;

  @override
  int get hashCode => Object.hash(cihaz, carpan, ustSinir);

  @override
  String toString() => 'KullaniciYaziOlcegi($cihaz × $carpan, ≤$ustSinir)';
}

/// Alt ağacın yazı ölçeğine kullanıcı kademesini uygular.
///
/// `MaterialApp.builder` içinde en dışta durur: her rota, alt sayfa, diyalog
/// ve tanıtım turu aynı ölçeği görür. "Normal"de cihaz verisi aynen geçer.
///
/// **Ağaç şekli kademeden bağımsız:** "Normal"de de `MediaQuery` sarılır.
/// Kademeye göre sarıp sarmamak, Ayarlar'da seçim değişince altındaki
/// Navigator'ı yeniden kurar — kullanıcı Ayarlar'dan ana ekrana atılırdı.
class YaziBoyutuKapsami extends StatelessWidget {
  const YaziBoyutuKapsami(
      {super.key, required this.boyut, required this.child});

  final YaziBoyutu boyut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: boyut == YaziBoyutu.normal
          ? mq
          : mq.copyWith(
              textScaler: KullaniciYaziOlcegi(
                  cihaz: mq.textScaler, carpan: boyut.carpan),
            ),
      child: child,
    );
  }
}

/// Alt ağacı uygulama ayarından MUAF tutar: yalnızca cihazın kendi ölçeği.
///
/// Alt menü için (kullanıcı kuralı 2026-09-28: alt menü değişmez, simetri).
/// Dört eşit sekmenin etiketleri uygulama ayarıyla büyüse "Hesap oluştur"
/// gibi uzun etiketler komşusuna yaslanır ve menü kademeden kademeye
/// başka görünürdü. Cihazın erişilebilirlik ölçeği ise korunur — menü bugün
/// nasıl davranıyorsa öyle davranır.
class CihazYaziOlcegi extends StatelessWidget {
  const CihazYaziOlcegi({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final olcek = mq.textScaler;
    return MediaQuery(
      data: olcek is KullaniciYaziOlcegi
          ? mq.copyWith(textScaler: olcek.cihaz)
          : mq,
      child: child,
    );
  }
}
