import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bist_hisseleri.dart';
import 'crash_reporter.dart';
import 'supabase_service.dart';

/// Seçilebilir BIST hisseleri — sunucu kataloğu, cihaz önbelleği, gömülü
/// liste sırasıyla.
///
/// ── Neden (yasin, 2026-10-10) ──────────────────────────────────────────────
/// "Eksik varlık olmasını istemiyorum, borsada işlem gören tüm hisseler
/// olmalı." Gömülü liste her halka arzda bir sürüm bekliyordu. Sunucu
/// listeyi her sabah borsadan tazeler (`bist_hisse`, 0139); burası onu
/// okur ve cihazda saklar. Hisse seçicisi, arama, karşılaştırma ve içe
/// aktarma tanıması listeyi YALNIZ buradan alır.
///
/// ── Düşme sırası ───────────────────────────────────────────────────────────
/// 1. Sunucu (oturum açıkken, en çok [tazelikSuresi]'de bir).
/// 2. Cihaz önbelleği (son başarılı sunucu yanıtı; çevrimdışı/soğuk açılış).
/// 3. Gömülü [bist100StocksMap] — hiçbiri yoksa, eski davranış birebir.
/// Sunucu yanıtı [asgariHisse]'den kısaysa (bozuk/yarım) yok sayılır.
///
/// Fiyat buradan GELMEZ: katalog yalnız "hangi kod var, adı ne" der;
/// fiyat kaynağı sözleşmesi (`fiyat_kaynagi.dart`) değişmez.
class BistHisseKatalogu extends ChangeNotifier {
  BistHisseKatalogu({
    Future<Map<String, String>> Function()? sunucu,
    DateTime Function()? saat,
  })  : _sunucu = sunucu ?? (() => SupabaseService.instance.bistHisseleri()),
        _saat = saat ?? DateTime.now;

  static final BistHisseKatalogu instance = BistHisseKatalogu();

  /// Önbellek anahtarı. Biçim: `{"t": ISO-8601, "h": {"THYAO.IS": "ad"}}`.
  static const onbellekAnahtari = 'bist_hisse_katalogu_v1';

  /// Borsada ~630 kâğıt var; bundan kısa liste yarım yanıttır.
  static const asgariHisse = 450;

  /// Sunucu günde bir tazeliyor; açılışta yarım günden eskiyse sorulur.
  static const tazelikSuresi = Duration(hours: 12);

  final Future<Map<String, String>> Function() _sunucu;
  final DateTime Function() _saat;

  Map<String, String> _hisseler = bist100StocksMap;
  DateTime? _zaman;
  Future<void>? _suren;
  bool _onbellekOkundu = false;

  /// Bugün seçilebilir hisseler, `'THYAO.IS'` → ad.
  Map<String, String> get hisseler => _hisseler;

  /// Liste her değiştiğinde artar; arama dizini buna bakıp yeniden kurulur.
  int surum = 0;

  /// [kod] (`THYAO` ya da `THYAO.IS`) bir BIST hisse kodu mu — bugünkü
  /// katalogda ya da eski (kodu değişmiş) listede. İçe aktarma tanıması
  /// içindir: 2024 ekstresindeki KOZAL satırı hâlâ hisse satırıdır.
  bool kodMu(String kod) {
    final u = kod.toUpperCase();
    final k = u.endsWith('.IS') ? u : '$u.IS';
    return _hisseler.containsKey(k) || bistKoduMu(k);
  }

  /// Önbelleği okur, gerekirse sunucuya sorar. Eşzamanlı çağrılar aynı
  /// işi bekler; hata sessizce gömülü/önbellekteki listede bırakır
  /// (Crashlytics'e non-fatal).
  Future<void> yukle({bool zorla = false}) =>
      _suren ??= _yukle(zorla).whenComplete(() => _suren = null);

  Future<void> _yukle(bool zorla) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!_onbellekOkundu) {
        _onbellekOkundu = true;
        _onbellektenUygula(prefs.getString(onbellekAnahtari));
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BistHisseKatalogu.onbellek');
    }

    final z = _zaman;
    if (!zorla && z != null && _saat().difference(z) < tazelikSuresi) return;

    try {
      final sunucu = await _sunucu();
      if (sunucu.length < asgariHisse) return;
      _zaman = _saat();
      _uygula(sunucu);
      await prefs?.setString(
        onbellekAnahtari,
        jsonEncode({'t': _zaman!.toIso8601String(), 'h': sunucu}),
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BistHisseKatalogu.sunucu');
    }
  }

  void _onbellektenUygula(String? ham) {
    if (ham == null) return;
    try {
      final j = jsonDecode(ham) as Map<String, dynamic>;
      final h = (j['h'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
      if (h.length < asgariHisse) return;
      _zaman = DateTime.tryParse(j['t'] as String? ?? '');
      _uygula(h);
    } catch (_) {
      // Bozuk önbellek: gömülü listeyle devam; sonraki sunucu yanıtı ezer.
    }
  }

  void _uygula(Map<String, String> yeni) {
    if (mapEquals(yeni, _hisseler)) return;
    _hisseler = Map.unmodifiable(yeni);
    surum++;
    notifyListeners();
  }

  @visibleForTesting
  void uygulaTest(Map<String, String> h) => _uygula(h);

  @visibleForTesting
  void sifirlaTest() {
    _hisseler = bist100StocksMap;
    _zaman = null;
    _suren = null;
    _onbellekOkundu = false;
    surum++;
  }
}
