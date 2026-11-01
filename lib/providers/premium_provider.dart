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

  /// Bitişe kalan gün, yukarı yuvarlanır (bugün biten "0 gün" demesin);
  /// süresizde null, bitmişte 0.
  int? kalanGun(DateTime simdi) {
    final b = bitis;
    if (b == null) return null;
    if (!b.isAfter(simdi)) return 0;
    return (b.difference(simdi).inHours / 24).ceil().clamp(1, 1 << 30);
  }

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

/// Sunucudaki paywall ayarları (`premium_ayar`, 0172). Remote Config'in
/// `premium_enabled` / `premium_hediye_kesim` anahtarlarının yerini aldı
/// (yasin 2026-11-01: paywall RC bayraklarıyla yönetilmez): kesim hediye
/// SQL'iyle aynı yerde yazılır, acil kapatma tek UPDATE'tir.
class PremiumSunucuAyari {
  const PremiumSunucuAyari({
    this.kapiAcik = false,
    this.hediyeKesim,
    this.acilKapali = false,
  });

  /// Sunucu ücretli içeriği kısıtlıyor mu (bilgi; kilit kararına girmez).
  final bool kapiAcik;

  /// Erken kullanıcı hediyesinin kesimi; verilmediyse null (herkes "eski").
  final DateTime? hediyeKesim;

  /// true → kilitler herkeste askıda, ödeyenin hakkı korunur.
  final bool acilKapali;

  /// Okunamayan ayar = güvenli taraf: kesim bilinmiyor, acil durum yok.
  static const varsayilan = PremiumSunucuAyari();

  static PremiumSunucuAyari satirdan(Map<String, dynamic> m) {
    final kesimHam = m['hediye_kesim'];
    return PremiumSunucuAyari(
      kapiAcik: m['kapi_acik'] == true,
      hediyeKesim:
          kesimHam is String ? DateTime.tryParse(kesimHam)?.toUtc() : null,
      acilKapali: m['acil_kapali'] == true,
    );
  }
}

/// Sunucu ayarını oturum başına bir kez okur; hata → varsayılan +
/// Crashlytics non-fatal (acil kapatma okunamazsa normal kural: kilit).
/// `hediye_kesim` sunucudan gelir ama uygulama kararda KULLANMAZ (hediye
/// kaldırıldı, 2026-11-01; bkz. `kilitlerAskidaProvider`). Oturum yokken
/// varsayılan.
final premiumSunucuAyariProvider =
    FutureProvider<PremiumSunucuAyari>((ref) async {
  if (!ref.watch(paywallVisibleProvider)) return PremiumSunucuAyari.varsayilan;
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return PremiumSunucuAyari.varsayilan;
  try {
    return PremiumSunucuAyari.satirdan(
        await SupabaseService.instance.premiumAyarlari());
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'premiumSunucuAyariProvider');
    return PremiumSunucuAyari.varsayilan;
  }
});

/// Oturumdaki kullanıcının hakları. autoDispose DEĞİL: kalıcı
/// `effectivePremiumProvider` bunu izler; oturum değişince `authProvider`
/// üzerinden yenilenir. Hata → boş liste + Crashlytics non-fatal:
/// okuyamadığımız hak "Premium değil" sayılır (2026-11-01'e kadar hediye
/// güvencesi bunu eski hesapta askıya alıyordu; hediye kalktı, kural tek).
/// Liste süresi geçmiş satırları da içerir (abonelik yönetimi satırı için).
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

/// Hediyesi BİTMİŞ ve başka geçerli hakkı olmayan kullanıcı (paywall
/// incelemesi, 2026-10-20). 90 günlük hediye herkese aynı gün verildiği için
/// aynı günlerde biter; bitişi söylemeyen uygulama "bir sabah kilit"
/// hissi yaratıyordu. Profil bandı ve açılıştaki tek seferlik sayfa bunu
/// okur. Değer bitmiş hediyenin bitişidir (bir kez söyleme anahtarı).
final hediyesiBitmisProvider = Provider<DateTime?>((ref) {
  if (ref.watch(gecerliPremiumHakkiProvider) != null) return null;
  final haklar = ref.watch(premiumHaklariProvider).valueOrNull ?? const [];
  for (final h in haklar) {
    if (h.hediye && h.bitis != null) return h.bitis;
  }
  return null;
});

/// Hediyesi son günlerinde (≤ [esik] gün) olan kullanıcı; yoksa null.
/// Profil satırı "Premium'la devam et" düğmesini bu eşikte gösterir.
const hediyeSonGunlerEsigi = 7;

/// Premium'a özgü özellikler (radar, ekstre AI) görünür mü: paywall açıksa
/// herkese (ücretsizde kilitli), kapalıyken yalnız admin hesabına. Gerekçe
/// `RemoteConfigService.premiumOzellikleriGorunur`.
final premiumOzellikleriGorunurProvider = Provider<bool>((ref) =>
    ref.watch(paywallVisibleProvider) ||
    ref.watch(isPushAdminProvider).valueOrNull == true);

/// Radar ve not içeriği kilitli mi: paywall açık VE kullanıcı Premium değil.
/// Paywall kapalıyken hiçbir şey kilitlenmez (sunucu kapısı `premium_ayar`
/// da kapalı: herkes görür).
final radarKilitliProvider =
    Provider<bool>((ref) => ref.watch(premiumKilitliProvider));
