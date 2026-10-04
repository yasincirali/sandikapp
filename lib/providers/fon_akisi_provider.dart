import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crash_reporter.dart';
import '../services/fon_akisi.dart';
import '../services/hisse_hacmi.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';

/// Para akışı kartı bayrağı — `balina_radari_acik` (varsayılan KAPALI).
///
/// Provider olarak sarıldı ki widget testi bayrağı override edebilsin
/// (emsal: `fonKarnesiAcikProvider`).
final balinaRadariAcikProvider =
    Provider<bool>((ref) => RemoteConfigService.instance.balinaRadariAcik);

/// Bir fonun para akışı özeti. Hesap `build()` dışında, burada bir kez.
///
/// `null` = kart çizilmez: veri yok, veri bayat ya da okuma başarısız.
/// Hata sessiz DEĞİL — Crashlytics'e non-fatal gider; kullanıcıya hata
/// gösterilmez çünkü kart ek bilgidir, fiyatı ya da pozisyonu etkilemez
/// (fon karnesiyle aynı karar).
///
/// autoDispose + 30 dk tutma: sunucu veriyi günde dört kez yeniliyor;
/// varlık sayfasına girip çıkmak her seferinde iki sorgu atmasın. `null`
/// sonuç tutulmaz, sonraki açılış yeniden dener.
final fonAkisiProvider =
    FutureProvider.autoDispose.family<FonAkisOzeti?, String>((ref, kod) async {
  final simdi = DateTime.now();
  final baslangic = simdi.subtract(akisSorguPenceresi);
  try {
    final svc = SupabaseService.instance;
    final (gunSatirlari, olaySatirlari) = await (
      svc.fonAkisGunleri(kod, baslangic: baslangic),
      svc.balinaOlaylari('TEFAS:$kod', baslangic: baslangic),
    ).wait;
    final ozet = fonAkisOzeti(
      gunSatirlari.map(FonAkisGunu.satirdan).nonNulls.toList(),
      olaySatirlari.map(FonBalinaOlayi.satirdan).nonNulls.toList(),
      simdi: simdi,
    );
    if (ozet != null) {
      final link = ref.keepAlive();
      final zamanlayici = Timer(const Duration(minutes: 30), link.close);
      ref.onDispose(zamanlayici.cancel);
    }
    return ozet;
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'fonAkisiProvider');
    return null;
  }
});

/// Bir BIST hissesinin hacim özeti (Balina B2). Kararlar `fonAkisiProvider`
/// ile aynı: `null` = kart çizilmez, hata Crashlytics'e non-fatal, 30 dk tutma.
final hisseHacmiProvider =
    FutureProvider.autoDispose.family<HacimOzeti?, String>((ref, sembol) async {
  final simdi = DateTime.now();
  final baslangic = simdi.subtract(hacimSorguPenceresi);
  try {
    final svc = SupabaseService.instance;
    final (gunSatirlari, olaySatirlari) = await (
      svc.hisseHacimGunleri(sembol, baslangic: baslangic),
      svc.hacimOlaylari(sembol, baslangic: baslangic),
    ).wait;
    final ozet = hacimOzeti(
      gunSatirlari.map(HacimGunu.satirdan).nonNulls.toList(),
      olaySatirlari.map(HacimOlayi.satirdan).nonNulls.toList(),
      simdi: simdi,
    );
    if (ozet != null) {
      final link = ref.keepAlive();
      final zamanlayici = Timer(const Duration(minutes: 30), link.close);
      ref.onDispose(zamanlayici.cancel);
    }
    return ozet;
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'hisseHacmiProvider');
    return null;
  }
});

/// Bir coinin alıcı baskısı / hacim özeti (Balina B3). Kararlar
/// `hisseHacmiProvider` ile aynı; anahtar uygulamadaki ticker ('KRIPTO:BTC').
final kriptoBaskiProvider =
    FutureProvider.autoDispose.family<HacimOzeti?, String>((ref, ticker) async {
  final simdi = DateTime.now();
  final baslangic = simdi.subtract(hacimSorguPenceresi);
  try {
    final svc = SupabaseService.instance;
    final (gunSatirlari, olaySatirlari) = await (
      svc.kriptoHacimGunleri(ticker, baslangic: baslangic),
      svc.kriptoHacimOlaylari(ticker, baslangic: baslangic),
    ).wait;
    final ozet = hacimOzeti(
      gunSatirlari.map(HacimGunu.satirdan).nonNulls.toList(),
      olaySatirlari.map(HacimOlayi.satirdan).nonNulls.toList(),
      simdi: simdi,
    );
    if (ozet != null) {
      final link = ref.keepAlive();
      final zamanlayici = Timer(const Duration(minutes: 30), link.close);
      ref.onDispose(zamanlayici.cancel);
    }
    return ozet;
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'kriptoBaskiProvider');
    return null;
  }
});
