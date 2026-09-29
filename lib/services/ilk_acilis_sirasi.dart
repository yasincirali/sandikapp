import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'crash_reporter.dart';

/// İlk açılış sırası (büyüme planı F2) ve kayıt hunisi ölçümü (F11).
///
/// Kapı mantığının kendisi `main.dart` `_AuthGateState.build`'de kalır; bu
/// dosya yalnızca oradan çağrılan SAF kararları ve cihaz bayrağını taşır.
/// Ayrı durmasının nedeni `splashVeriHazir` ile aynı: kapı widget'ı özel
/// (`_AuthGate`) ve Supabase + tercih + fiyat turu istiyor; karar tablosu
/// ise zamanlamadan bağımsız test edilmeli.

/// Kilit TEKLİFİ bu kapı değerlendirmesinde ertelensin mi?
///
/// **Neden (plan F2, 2026-09-29):** teklifin anlattığı kayıp (zaman aşımında
/// çıkış + push kesintisi) boş portföyde gerçek değil — korunacak bir şey
/// yok. Yeni kullanıcı kayıt → yasal onay → tur → teklif sırasında dördüncü
/// ekranda bir izin daha görüyordu; ilk varlığı girmeden önceki her ekran
/// terk riskidir.
///
/// - [bayrak] `lock_offer_after_first_asset` (Remote Config). KAPALIYKEN
///   karar her zaman `false` → kapı BİREBİR eski davranışta.
/// - [aktifVarlikVar] `aktifLotlar(...)` boş değil mi; `null` = portföy
///   henüz bilinmiyor (yükleniyor / hata / emniyet supabı patladı).
///   Bilinmiyorsa ERTELENİR: yanlışlıkla gösterilmemiş teklif sonraki
///   açılışta gelir, yanlışlıkla gösterilmiş teklif ise geri alınamaz.
bool kilitTeklifiErtelensin({
  required bool bayrak,
  required bool? aktifVarlikVar,
}) {
  if (!bayrak) return false;
  return aktifVarlikVar != true;
}

/// Kayıt/ilk açılış hunisinin cihaz bayrağı gerektiren adımı.
abstract final class KayitHunisi {
  /// Cihaz geneli (kişiye özel DEĞİL): "bu kurulumda ana ekran ilk kez
  /// görüldü" sorusu cihaza aittir. Aynı cihazda ikinci hesap açan kullanıcı
  /// huniyi ikinci kez tamamlamış sayılmasın — huni kurulum başına ölçülür.
  @visibleForTesting
  static const anahtar = 'huni_ana_ekran_goruldu';

  /// Süreç içinde tekrar diske gitmemek için; kapı her build'de çağırabilir.
  static bool _buSurecteBakildi = false;

  @visibleForTesting
  static void sifirlaTestIcin() => _buSurecteBakildi = false;

  /// Ana ekran bu cihazda İLK kez görüldüyse `home_first_seen` gönderir.
  ///
  /// Bayrak olay GÖNDERİLMEDEN önce yazılır: yazılamazsa (disk hatası) olay
  /// da gönderilmez — iki kez saymak huniyi şişirir, bir kez eksik saymak
  /// yalnızca bir kullanıcı kaybettirir. Döndürdüğü değer olayın gönderilip
  /// gönderilmediğidir (test için).
  static Future<bool> anaEkranIlkKez({
    Future<void> Function(String adim)? kaydet,
  }) async {
    if (_buSurecteBakildi) return false;
    _buSurecteBakildi = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(anahtar) == true) return false;
      await prefs.setBool(anahtar, true);
      await (kaydet ?? AnalyticsService.instance.logSignupStep)(
          'home_first_seen');
      return true;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'KayitHunisi.anaEkranIlkKez');
      return false;
    }
  }
}
