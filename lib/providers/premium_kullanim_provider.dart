import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/remote_config_service.dart';
import 'portfolio_provider.dart' show kotaAnahtarlariProvider;
import 'portfoy_provider.dart';
import 'preferences_provider.dart';
import 'price_alert_provider.dart';
import 'seviye_alarmi_provider.dart';
import 'watchlist_provider.dart';
import 'yuzde_alarmi_provider.dart';

/// Profil abonelik satırının altındaki "Premium'la kullandıkların" satırının
/// kalemleri (Ar-Ge 14 Kas #2).
///
/// Neden: satır yalnız tarih söylüyordu; yenileme öncesi "neye ödüyorum"
/// sorusu cevapsızdı. Cevap kullanıcının KENDİ sayılarıdır: yalnız ücretsiz
/// sınırı aşan ya da yalnız Premium'da olan kalemler. Sıfır olan yazılmaz,
/// hiçbiri yoksa satır yok (uydurma sayı yasak; "0 gösterge alarmı" değer
/// değil gürültü).
enum PremiumKalem { varlik, takip, fiyatAlarmi, gostergeAlarmi, cizgiAlarmi, portfoy }

typedef PremiumKullanim = ({PremiumKalem kalem, int sayi});

/// Saf karar. Sınırlar ÜCRETSİZ planınkiler (Premium'daki "sınırsız" değil):
/// soru "Premium bitse hangisi sınırın üstünde kalır".
///
/// - Varlık ve takip: sayı sınırı aşıyorsa.
/// - Fiyat alarmı: ücretsiz tavan dört alarm türünün TOPLAMINA uygulanır
///   (`etkinAlarmlariSay`, sunucuda 0181). Toplam tavanı aşıyorsa fiyat ve
///   yüzde alarmlarının sayısı yazılır; gösterge/çizgi zaten ayrı kalemdir,
///   iki kez sayılmasın.
/// - Gösterge ve çizgi alarmı: yalnız Premium'da kurulur, sıfırdan büyükse.
/// - Portföy: Ana dahil birden fazlaysa; [portfoy] null = çoklu portföy bu
///   kullanıcıya görünmüyor, kalem hiç düşünülmez.
List<PremiumKullanim> premiumKullanimKalemleri({
  required int varlik,
  required int varlikSiniri,
  required int takip,
  required int takipSiniri,
  required int fiyatAlarmi,
  required int toplamAlarm,
  required int alarmSiniri,
  required int gostergeAlarmi,
  required int cizgiAlarmi,
  int? portfoy,
}) =>
    [
      if (varlik > varlikSiniri) (kalem: PremiumKalem.varlik, sayi: varlik),
      if (takip > takipSiniri) (kalem: PremiumKalem.takip, sayi: takip),
      if (toplamAlarm > alarmSiniri && fiyatAlarmi > 0)
        (kalem: PremiumKalem.fiyatAlarmi, sayi: fiyatAlarmi),
      if (gostergeAlarmi > 0)
        (kalem: PremiumKalem.gostergeAlarmi, sayi: gostergeAlarmi),
      if (cizgiAlarmi > 0) (kalem: PremiumKalem.cizgiAlarmi, sayi: cizgiAlarmi),
      if (portfoy != null && portfoy > 1)
        (kalem: PremiumKalem.portfoy, sayi: portfoy),
    ];

/// Sayım burada, `build()` içinde değil. Paywall kapalıyken ya da Premium
/// erişimi olmayan (bitmiş) kullanıcıda boş: "Premium'la kullandıkların"
/// yalnız Premium'u süren biri için doğru cümle. Sayımlar mevcut kapıların
/// saydığıyla aynı: varlık `kotaAnahtarlari` (addAsset kapısı), alarmlar
/// model `isActive` (alarm tavanı). Henüz yüklenmemiş liste 0 sayılır
/// (bilinmeyen sayı satıra girmez, yüklenince satır güncellenir).
final premiumKullanimProvider = Provider<List<PremiumKullanim>>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return const [];
  if (!ref.watch(effectivePremiumProvider)) return const [];
  final rc = RemoteConfigService.instance;
  int etkin<T>(List<T>? l, bool Function(T) aktif) =>
      (l ?? const []).where(aktif).length;
  final fiyat = etkin(ref.watch(priceAlertsProvider).valueOrNull,
      (a) => a.isActive);
  final yuzde = etkin(ref.watch(yuzdeAlarmlariProvider).valueOrNull,
      (a) => a.isActive);
  final gosterge = etkin(ref.watch(gostergeAlarmlariProvider).valueOrNull,
      (a) => a.isActive);
  final cizgi = etkin(ref.watch(cizimAlarmlariProvider).valueOrNull,
      (a) => a.isActive);
  final portfoy = ref.watch(cokluPortfoyGorunurProvider)
      ? (ref.watch(portfoylerProvider).valueOrNull?.length ?? 0) + 1
      : null;
  return premiumKullanimKalemleri(
    varlik: ref.watch(kotaAnahtarlariProvider)?.length ?? 0,
    varlikSiniri: rc.freeAssetLimit,
    takip: ref.watch(watchlistProvider).valueOrNull?.length ?? 0,
    // Paywall açıkken ücretsiz takip sınırı ayrı anahtar
    // (`watchlistLimitProvider` gerekçesi).
    takipSiniri: rc.paywallWatchlistLimit,
    fiyatAlarmi: fiyat + yuzde,
    toplamAlarm: fiyat + yuzde + gosterge + cizgi,
    alarmSiniri: rc.freePriceAlertLimit,
    gostergeAlarmi: gosterge,
    cizgiAlarmi: cizgi,
    portfoy: portfoy,
  );
});
