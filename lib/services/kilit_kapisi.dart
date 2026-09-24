import 'package:flutter/foundation.dart';

/// Uygulama kilitliyken (biyometrik kilit ekranı) ekran açan istekleri
/// bekleten kapı.
///
/// **Neden:** bildirim dokunuşu kök navigatöre `push` eder; kilit ise
/// yalnızca KÖK rotayı değiştirir. Kilitliyken gelen dokunuş hedef ekranı
/// kilidin ÜSTÜNE açıyordu — Face ID sorulmadan portföy görünüyordu
/// (2026-09-23 denetimi F2). Kilitliyken istek bekletilir, kilit açılınca
/// bir kez çalışır.
class KilitKapisi {
  final kilitli = ValueNotifier<bool>(false);
  VoidCallback? _bekleyen;

  /// Kilitliyse [calistir]'ı kilit açılışına erteler ve `true` döner;
  /// kilitli değilse hiçbir şey yapmaz, `false` döner (çağıran devam eder).
  ///
  /// Yalnızca SON istek tutulur: art arda dokunulan bildirimlerde kullanıcı
  /// en son dokunduğu ekranı bekler, üst üste yığılmış ekranları değil.
  bool ertele(VoidCallback calistir) {
    if (!kilitli.value) return false;
    final ilkBekleyen = _bekleyen == null;
    _bekleyen = calistir;
    if (ilkBekleyen) {
      void dinle() {
        if (kilitli.value) return;
        kilitli.removeListener(dinle);
        final bekleyen = _bekleyen;
        _bekleyen = null;
        bekleyen?.call();
      }

      kilitli.addListener(dinle);
    }
    return true;
  }
}
