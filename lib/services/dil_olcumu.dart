import 'dart:ui' show Locale, PlatformDispatcher;

import 'analytics_service.dart';

/// Uygulama dili ve telefon dili — iki ayrı kullanıcı özelliği (Ar-Ge 21 Eki
/// 12:45 #1; yasin "şerh düştüklerim dışında yap", 2026-10-21).
///
/// ## Neden
/// Her yeni metin iki .arb'a, gen-l10n'e ve teste giriyor; İngilizce'yi kimin
/// kullandığı bilinmiyordu. 19 Kasım karar turu oranı buradan okur; İngilizce
/// BETA'yı sürdürme ya da dondurma kararı yasin'in.
///
/// İki özellik ayrı (müşteri raporu 21 Eki 13:15): "telefonu İngilizce ama
/// uygulamayı Türkçe kullanıyor" ile "İngilizce'yi gerçekten seçmiş" farkı
/// dondurma kararında önemli. `secim` ise kişinin Ayarlar'daki tercihi
/// (`tr`/`en`/`system`): varsayılanla kalanı seçenden ayırır.
abstract final class DilOlcumu {
  static String? _son;

  /// Seçim null ise (sistem) uygulama cihaz diline uyar; destek yalnız
  /// tr/en, başka dil Türkçe'ye düşer (`supportedLocales`).
  static String uygulamaDili(Locale? secim, Locale cihaz) {
    final dil = secim?.languageCode ?? cihaz.languageCode;
    return dil == 'en' ? 'en' : 'tr';
  }

  static void yaz(Locale? secim, {required String tercih}) {
    final cihaz = PlatformDispatcher.instance.locale;
    final app = uygulamaDili(secim, cihaz);
    final imza = '$app|${cihaz.languageCode}|$tercih';
    if (imza == _son) return;
    _son = imza;
    final a = AnalyticsService.instance;
    a.setUserProperty(name: 'app_locale', value: app);
    a.setUserProperty(name: 'cihaz_dili', value: cihaz.languageCode);
    a.setUserProperty(name: 'dil_secimi', value: tercih);
  }
}
