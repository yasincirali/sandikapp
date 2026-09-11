import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/theme_resolution.dart';

/// Uygulama DIŞI yüzeylerin (iOS Live Activity + ana ekran widget'ı) paletine
/// karar veren TEK nokta — ve kararın KALICI hâli.
///
/// ## Neden ayrı bir katman
/// Karar tablosu ([resolveThemeIsLightWith]) baştan beri doğruydu. Bozuk olan
/// kararın NE ZAMAN verildiğiydi: `main.dart`'taki portföy dinleyicisi her
/// state yayınında (fiyat tazeleme, sekme değişimi, varlık ekleme — dakikada
/// birkaç kez) cihaz görünümünü YENİDEN örnekliyordu. Bu üç yoldan birden
/// kilit ekranı renginin kendiliğinden değişmesine yol açıyordu:
///
///   1. **Tercih "Sistem" iken** (ve varsayılan tam olarak bu, bkz.
///      `ThemeModeNotifier.build`) örneklenen değer cihazın o anki
///      görünümüdür. Cihaz "Otomatik" görünümdeyse gün içinde kendiliğinden
///      döner; kullanıcı uygulamada hiçbir şey değiştirmediği hâlde banner
///      renk değiştirir.
///   2. **iOS arka plan anlık görüntüsü:** uygulama arkaya alınırken sistem
///      kareyi TERS görünümde de yakalar ve `platformBrightness` o an ters
///      raporlanır. O sırada bir portföy yayını denk gelirse (fiyat
///      tazeleme arkaya alınırken sıklıkla denk gelir) yanlış değer hem
///      ActivityKit'e hem `live_activity_sessions.summary`'ye YAZILIR.
///   3. **Sunucu bu satırı 5 dakikada bir push'lar** (`push-live-activity`
///      cron'u). Yani bir kez yanlış örneklenmiş bool bir sonraki öne
///      dönüşe kadar kilit ekranında kalır; öne dönüşte düzelir, sonra
///      yine bozulur. Kullanıcı bulgusu — "tema rengi sürekli değişiyor" —
///      tam olarak bu salınımdır.
///
/// ## Değişmez
/// Karar YALNIZCA üç meşru tetikleyiciyle değişir:
///   * kullanıcı tema tercihini değiştirdi (Ayarlar üçlüsü ya da Profil
///     başlığındaki hızlı geçiş — ikisi de aynı provider'ı yazar),
///   * uygulama ÖNPLANDAYKEN cihaz görünümü değişti **ve** tercih "Sistem",
///   * uygulama öne döndü (arkada olan bir sistem değişimi burada yakalanır).
///
/// Bunların dışındaki her okuma son kararı AYNEN döndürür. Karar
/// `SharedPreferences`'a yazılır: süreç yeniden başladığında servis
/// singleton'ları `false` (koyu) varsayılanıyla doğmasın — açık temalı
/// kullanıcı, portföy ilk kez yayınlanana kadar koyu palet görüyordu.
class SurfaceTheme {
  SurfaceTheme._();
  static final instance = SurfaceTheme._();

  /// Tema/bakiye gibi CİHAZ tercihleriyle aynı sınıf: kullanıcı ön eki
  /// almaz (bkz. `preferences_provider._userKey` notu).
  static const prefKey = 'pref_surface_is_light';

  bool _isLight = false;
  ThemeMode? _lastMode;

  /// Uygulama dışı yüzeylerin kullanacağı çözülmüş karar.
  ///
  /// Okumak ASLA yeniden çözmez — tam olarak bu yüzden var.
  bool get isLight => _isLight;

  /// Kararın türetildiği son tercih — TEŞHİS içindir.
  ///
  /// "Sistem" seçiliyken yüzeyin cihazı izlemesi DOĞRU davranıştır; bu
  /// ayrım bilinmeden "tema kendiliğinden değişiyor" bulgusu hatalı
  /// yorumlanır (bkz. `push_diagnostics_screen`). İlk [update] çağrısına
  /// kadar `null`.
  ThemeMode? get lastResolvedMode => _lastMode;

  /// Kalıcı kararı yükler. `main()` içinde, ilk frame'den önce çağrılır.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(prefKey);
      if (stored != null) _isLight = stored;
    } catch (_) {
      // Okunamadıysa varsayılan koyu kalır — bugüne kadarki davranış.
    }
  }

  /// Kararı meşru bir tetikleyiciyle yeniden çözer.
  ///
  /// [trustDeviceBrightness] yalnızca uygulama gerçekten önplandayken
  /// `true` verilmelidir: arka plan anlık görüntüsü sırasında
  /// `platformBrightness` TERS raporlanır ve o değeri kabul etmek paleti
  /// salındıran hatanın ta kendisidir.
  ///
  /// Değer GERÇEKTEN değiştiyse `true` döner; çağıran taraf yüzeyleri
  /// yalnızca o zaman tazeler.
  bool update(
    ThemeMode mode, {
    required bool trustDeviceBrightness,
    Brightness? brightness,
  }) {
    _lastMode = mode;
    final next = decide(
      mode,
      current: _isLight,
      trustDeviceBrightness: trustDeviceBrightness,
      brightness: brightness,
    );
    if (next == _isLight) return false;
    _isLight = next;
    _persist(next);
    return true;
  }

  /// Saf karar tablosu — durum tutmaz, testte doğrudan doğrulanır.
  ///
  /// "Sistem" + güvenilmeyen parlaklık → **son karar korunur**. Burada
  /// cihaz görünümüne düşmek, arka plandaki ters raporu kalıcı hâle
  /// getirirdi.
  @visibleForTesting
  static bool decide(
    ThemeMode mode, {
    required bool current,
    required bool trustDeviceBrightness,
    Brightness? brightness,
  }) {
    if (mode == ThemeMode.system && !trustDeviceBrightness) return current;
    return resolveThemeIsLightWith(
      mode,
      brightness ??
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  void _persist(bool isLight) {
    // Beklenmez: yüzey güncellemesi bir disk yazımını beklemesin. Yazım
    // başarısız olursa karar süreç içinde yine doğrudur; yalnızca bir
    // sonraki açılışta eski değerden başlanır.
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(prefKey, isLight);
      } catch (_) {}
    }());
  }

  /// Süreç içi durumu sıfırlar — singleton olduğu için testler arasında
  /// bir testin kararı sonrakine taşar.
  @visibleForTesting
  void resetForTest() {
    _isLight = false;
    _lastMode = null;
  }
}
