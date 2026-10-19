import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../l10n/generated/app_localizations.dart';
import 'crash_reporter.dart';

/// Ana ekran ikonuna uzun basınca açılan kısayollar (2026-10-19).
///
/// ## Neden
/// yasin (müşteri gözüyle rapor, 2026-10-19): "İkon hızlı eylemleri: yap
/// (Varlık ekle, Alarm kur, Arama). Siri ve Spotlight sonraya kalsın."
/// Haber anında uygulamayı açıp sekme aramadan tek dokunuşla işe girilir.
/// "Bugün" bilerek yok: ikona dokunmak zaten onu açar.
/// Siri ve Spotlight aynı gün (yasin, Ar-Ge turu 1: "arkadaşını getir
/// dışındakileri uygula") `SistemEylemleri` ile geldi; Siri eylemleri bu
/// isteğe düşer, ikinci bir yönlendirme yolu yok.
///
/// ## Akış
/// Sistem kısayolu bildirir → [istek] dolar → sekme kabuğu
/// (`MainNavigationScreen`) isteği TÜKETİR ve ekranı açar. Kabuk ağaçta
/// değilse (oturum kapalı, uygulama kilidi açık) istek bekler; kabuk
/// kurulunca uygulanır. Kilit atlatılmaz, giriş ekranının üstüne ekran
/// açılmaz. `MainNavigationScreen.sekmeIstegi` ile aynı desen.
///
/// Simgeler yerel kaynaktır: iOS `Assets.xcassets/hizli_*.imageset`
/// (şablon, sistem boyar), Android `res/drawable/hizli_*.xml` (küçültücü
/// silmesin diye `res/raw/hizli_eylem_keep.xml`).
enum HizliEylem { varlikEkle, alarmKur, arama }

class HizliEylemler {
  HizliEylemler._();

  /// Bekleyen kısayol isteği; tüketen `null`'a çeker.
  static final istek = ValueNotifier<HizliEylem?>(null);

  static const _simge = {
    HizliEylem.varlikEkle: 'hizli_ekle',
    HizliEylem.alarmKur: 'hizli_alarm',
    HizliEylem.arama: 'hizli_arama',
  };

  static bool _kuruldu = false;

  /// Sistemin bildirdiği tür adını isteğe çevirir (saf; test edilir).
  static HizliEylem? cozumle(String? tur) {
    for (final e in HizliEylem.values) {
      if (e.name == tur) return e;
    }
    return null;
  }

  static bool get _destekli =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Dinleyiciyi bir kez kurar ve kısayol başlıklarını o anki dilde yazar.
  /// Soğuk açılışı başlatan kısayol da `initialize` ile gelir. Dil
  /// değişince yeniden çağrılabilir (yalnız başlıklar yenilenir).
  static Future<void> kur(AppLocalizations l) async {
    if (!_destekli) return;
    final qa = const QuickActions();
    try {
      if (!_kuruldu) {
        _kuruldu = true;
        await qa.initialize((tur) {
          final e = cozumle(tur);
          if (e != null) istek.value = e;
        });
      }
      await qa.setShortcutItems([
        ShortcutItem(
          type: HizliEylem.varlikEkle.name,
          localizedTitle: l.addAsset,
          icon: _simge[HizliEylem.varlikEkle],
        ),
        ShortcutItem(
          type: HizliEylem.alarmKur.name,
          localizedTitle: l.createAlert,
          icon: _simge[HizliEylem.alarmKur],
        ),
        ShortcutItem(
          type: HizliEylem.arama.name,
          localizedTitle: l.quickActionSearch,
          icon: _simge[HizliEylem.arama],
        ),
      ]);
    } catch (e, st) {
      // Kısayol yoksa uygulama aynen çalışır; sessiz kalmasın diye bildir.
      CrashReporter.report(e, st, reason: 'HizliEylemler.kur');
    }
  }
}
