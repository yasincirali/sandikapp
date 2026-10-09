import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crash_reporter.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';

/// Sunucudaki Premium hakkı (0116 `premium_haklari`, 2026-10-05).
///
/// ## Neden sunucu
/// Ücretli içerik (Balina F2 notları) sunucuda RLS ile korunuyor; "Premium
/// mu" sorusunun cevabı da orada. Cihazdaki `premiumUnlockedProvider` test
/// anahtarı olarak kalır (Ayarlar'daki geliştirici anahtarı ve bugünkü
/// sahte satın alma onu açıyor); RevenueCat bağlanınca webhook sunucu
/// satırını yazar ve istemci yalnız bunu okur.
///
/// ## Eski davranış birebir
/// `paywall_enabled` kapalıyken HİÇ sorgu atılmaz ve sonuç boştur: Premium
/// sistemi yok sayılır (bkz. `effectivePremiumProvider`).
class PremiumHakki {
  const PremiumHakki({
    required this.kaynak,
    required this.bitis,
    this.urun,
    this.magaza,
    this.iptalEdildi = false,
  });

  /// 'revenuecat' | 'erken_kullanici' | 'manuel'.
  final String kaynak;

  /// `null` = süresiz (yalnız manuel).
  final DateTime? bitis;
  final String? urun;
  final String? magaza;
  final bool iptalEdildi;

  bool gecerli(DateTime simdi) => bitis == null || bitis!.isAfter(simdi);

  bool get hediye => kaynak == 'erken_kullanici';

  /// Ürün kimliğinde 'yillik' / 'annual' geçiyorsa yıllık.
  bool get yillik {
    final u = (urun ?? '').toLowerCase();
    return u.contains('yil') || u.contains('annual') || u.contains('year');
  }

  static PremiumHakki? satirdan(Map<String, dynamic> r) {
    final kaynak = r['kaynak'] as String?;
    if (kaynak == null) return null;
    final bitisHam = r['bitis'];
    final bitis = bitisHam == null ? null : DateTime.tryParse('$bitisHam');
    if (bitisHam != null && bitis == null) return null;
    return PremiumHakki(
      kaynak: kaynak,
      bitis: bitis,
      urun: r['urun'] as String?,
      magaza: r['magaza'] as String?,
      iptalEdildi: r['iptal_edildi'] == true,
    );
  }
}

/// Oturumdaki kullanıcının hakları. autoDispose DEĞİL: kalıcı
/// `effectivePremiumProvider` bunu izler; oturum değişince `authProvider`
/// üzerinden yenilenir. Hata → boş liste + Crashlytics non-fatal: okuyamadığımız hak "Premium değil" sayılır (kilit görünür,
/// satın alma ekranı açılır); bu, ücretli içeriği yanlışlıkla açmaktan
/// daha güvenli taraf.
final premiumHaklariProvider = FutureProvider<List<PremiumHakki>>((ref) async {
  if (!ref.watch(paywallVisibleProvider)) return const [];
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return const [];
  try {
    final satirlar = await SupabaseService.instance.premiumHaklari();
    return satirlar.map(PremiumHakki.satirdan).nonNulls.toList();
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'premiumHaklariProvider');
    return const [];
  }
});

/// Geçerli hak (abonelik önce, sonra hediye, sonra manuel); yoksa null.
final gecerliPremiumHakkiProvider = Provider<PremiumHakki?>((ref) {
  final haklar = ref.watch(premiumHaklariProvider).valueOrNull ?? const [];
  final simdi = DateTime.now();
  const sira = ['revenuecat', 'erken_kullanici', 'manuel'];
  final gecerli = haklar.where((h) => h.gecerli(simdi)).toList()
    ..sort((a, b) => sira.indexOf(a.kaynak).compareTo(sira.indexOf(b.kaynak)));
  return gecerli.isEmpty ? null : gecerli.first;
});

/// Premium'a özgü özellikler (radar, ekstre AI) görünür mü: paywall açıksa
/// herkese (ücretsizde kilitli), kapalıyken yalnız admin hesabına. Gerekçe
/// `RemoteConfigService.premiumOzellikleriGorunur`.
final premiumOzellikleriGorunurProvider = Provider<bool>((ref) =>
    ref.watch(paywallVisibleProvider) ||
    ref.watch(isPushAdminProvider).valueOrNull == true);

/// Radar ve not içeriği kilitli mi: paywall açık VE kullanıcı Premium değil.
/// Paywall kapalıyken hiçbir şey kilitlenmez (sunucu kapısı `premium_ayar`
/// da kapalı: herkes görür).
final radarKilitliProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  return !ref.watch(effectivePremiumProvider);
});
