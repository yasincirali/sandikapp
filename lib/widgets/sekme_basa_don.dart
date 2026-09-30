import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';

/// Aktif sekmeye yeniden dokununca "başa dön" kanalı.
///
/// ## Neden (animasyon denetimi 2026-10-01)
/// iOS'ta ve Android'de kullanıcının kas hafızası: açık olan sekmeye bir
/// daha dokunmak listeyi en başa götürür. sandık'ta bu dokunuş hiçbir şey
/// yapmıyordu; uzun ana sayfanın dibinden toplam kartına dönmek elle
/// kaydırmak demekti. Ana sayfanın kendi `ScrollController`'ı olduğu için
/// iOS'un durum çubuğu dokunuşu da orada çalışmıyordu.
///
/// Alt menü [yayinla] ile sekme indeksini duyurur; her sekme ekranı
/// [dinle] ile kendi indeksine abone olur ve [basaKaydir] ile kendi
/// denetleyicisini kaydırır. Kaynak (alt menü) ile hedef (sekme ekranı)
/// birbirini tanımaz.
class SekmeBasaDon extends ChangeNotifier {
  SekmeBasaDon._();

  static final kanal = SekmeBasaDon._();

  int? _sekme;

  /// Son dokunulan sekme — yalnız dinleyici çağrısı sırasında anlamlı.
  int? get sekme => _sekme;

  static void yayinla(int sekme) {
    kanal._sekme = sekme;
    kanal.notifyListeners();
  }

  /// [sekme] duyurulunca [f] çağrılır. Dönen fonksiyon aboneliği bırakır.
  static VoidCallback dinle(int sekme, VoidCallback f) {
    void dinleyici() {
      if (kanal._sekme == sekme) f();
    }

    kanal.addListener(dinleyici);
    return () => kanal.removeListener(dinleyici);
  }

  /// [c]'yi en başa kaydırır.
  ///
  /// Uzaktaysa (iki ekran boyundan fazla) önce bir buçuk ekran yakına
  /// atlar, oradan kayar: yirmi ekranlık listeyi baştan sona saniyelerce
  /// kaydırmak "donmuş" hissettirir; kısa, okunur bir hareket yeter.
  /// Süre [SandikMotion.flow], eğri [SandikMotion.cekmece] (hızlı başlar,
  /// yumuşak oturur). Hareketi azalt açıkken doğrudan başa atlar.
  static Future<void> basaKaydir(
      BuildContext context, ScrollController c) async {
    if (!c.hasClients) return;
    final konum = c.position;
    if (konum.pixels <= konum.minScrollExtent) return;
    final sure = SandikMotion.flowOf(context);
    if (sure == Duration.zero) {
      c.jumpTo(konum.minScrollExtent);
      return;
    }
    final ekran = konum.viewportDimension;
    if (konum.pixels > ekran * 2) c.jumpTo(ekran * 1.5);
    await c.animateTo(konum.minScrollExtent,
        duration: sure, curve: SandikMotion.cekmece);
  }
}
