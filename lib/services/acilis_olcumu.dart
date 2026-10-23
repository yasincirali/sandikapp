import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'crash_reporter.dart';

/// Soğuk açılışta "dokunuştan toplama kadar kaç ms" ölçümü (Ar-Ge 23 Eki
/// 08:45 #1; yasin "yap", 2026-10-23).
///
/// ## Neden
/// "Bir bakışta toplam" sandık'ın banka uygulamalarına karşı vaadi; açılış
/// süresi hiç ölçülmüyordu (`AnalyticsService` yalnız açılışın KAYNAĞINI
/// yazıyor). `main.dart`'taki sıralı beklemeleri paralelleştirmek gibi
/// riskli bir değişiklik bu veri gelmeden yapılmaz (müşteri raporu 23 Eki
/// 09:15 #3).
///
/// ## Ne ölçülür
/// Yalnız soğuk açılış: saat `main()`'in ilk satırında başlar, arka
/// plandan dönüş bu sınıfa hiç girmez. Üç an:
/// - **ilk kare** — `runApp` sonrası ilk çizim (geçiş perdesi dahil),
/// - **defter** — portföy satırları elde (sunucudan ya da çevrimdışı
///   önbellekten; hangisi olduğu ayrı parametre, ikisi aynı sayıda
///   karışmasın),
/// - **fiyat** — ilk fiyat turunun bitişi (başarılı ya da hatalı).
///
/// Olay fiyat anında, açılış başına BİR kez gider. Defter gelmeden fiyat
/// gelirse (oturum yok, boş portföy) hiçbir şey gönderilmez.
///
/// ## Ne gönderilmez
/// Kişisel veri yok: milisaniye, platform, iki sabit etiket. Firebase
/// Performance SDK'sı bilerek eklenmedi — yeni bir veri toplama türü olur
/// ve yasal metin ister; Analytics zaten metinde.
class AcilisOlcumu {
  AcilisOlcumu._();
  static final AcilisOlcumu instance = AcilisOlcumu._();

  final Stopwatch _saat = Stopwatch();
  int? _ilkKareMs;
  int? _defterMs;
  String? _defterKaynagi;
  bool _gonderildi = false;

  /// Test: gönderimi yakalar. Üretimde Analytics + Crashlytics.
  @visibleForTesting
  void Function(Map<String, Object> parametreler)? gonderTest;

  /// `main()`'in ilk satırı.
  void basla() {
    if (_saat.isRunning || _gonderildi) return;
    _saat.start();
  }

  void ilkKare() {
    if (!_saat.isRunning) return;
    _ilkKareMs ??= _saat.elapsedMilliseconds;
  }

  void defterHazir({required bool onbellekten}) {
    if (!_saat.isRunning || _defterMs != null) return;
    _defterMs = _saat.elapsedMilliseconds;
    _defterKaynagi = onbellekten ? 'onbellek' : 'sunucu';
  }

  void fiyatHazir({required bool basarili}) {
    if (!_saat.isRunning || _gonderildi) return;
    final defter = _defterMs;
    if (defter == null) return;
    _gonderildi = true;
    _saat.stop();
    final p = parametreler(
      ilkKareMs: _ilkKareMs,
      defterMs: defter,
      fiyatMs: _saat.elapsedMilliseconds,
      defterKaynagi: _defterKaynagi ?? 'sunucu',
      fiyatBasarili: basarili,
      platform: _platform(),
    );
    final test = gonderTest;
    if (test != null) {
      test(p);
      return;
    }
    CrashReporter.arkaPlan(_gonder(p), reason: 'AcilisOlcumu.gonder');
  }

  /// Olayın parametreleri — saf, test edilir. Milisaniyeler 10'a yuvarlanır:
  /// tek tek ms gürültüdür, kova sayısını gereksiz büyütür.
  static Map<String, Object> parametreler({
    required int? ilkKareMs,
    required int defterMs,
    required int fiyatMs,
    required String defterKaynagi,
    required bool fiyatBasarili,
    required String platform,
  }) =>
      {
        if (ilkKareMs != null) 'ilk_kare_ms': _on(ilkKareMs),
        'defter_ms': _on(defterMs),
        'fiyat_ms': _on(fiyatMs),
        'defter_kaynagi': defterKaynagi,
        'fiyat': fiyatBasarili ? 'tamam' : 'hata',
        'platform': platform,
      };

  static int _on(int ms) => (ms / 10).round() * 10;

  static String _platform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {}
    return 'diger';
  }

  Future<void> _gonder(Map<String, Object> p) async {
    // Analytics ertelenmiş başlatmada kurulur (`_initDeferredServices`);
    // fiyat turu ondan önce bitebilir. Beklenmezse olay sessizce düşerdi.
    await AnalyticsService.instance.hazir
        .timeout(const Duration(seconds: 30), onTimeout: () {});
    await AnalyticsService.instance.logAcilisSuresi(p);
    // Yavaş açılışın ardından gelen çökme raporu bağlamıyla görünsün.
    try {
      if (Firebase.apps.isEmpty) return;
      final c = FirebaseCrashlytics.instance;
      for (final k in const ['ilk_kare_ms', 'defter_ms', 'fiyat_ms']) {
        final v = p[k];
        if (v is int) await c.setCustomKey('acilis_$k', v);
      }
    } catch (_) {}
  }

  @visibleForTesting
  void sifirlaTest() {
    _saat
      ..stop()
      ..reset();
    _ilkKareMs = null;
    _defterMs = null;
    _defterKaynagi = null;
    _gonderildi = false;
    gonderTest = null;
  }
}
