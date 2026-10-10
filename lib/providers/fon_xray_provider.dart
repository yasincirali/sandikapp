import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/crash_reporter.dart';
import '../services/fon_dagilimi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/portfoy_xray.dart';
import '../services/price_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart' show rcEtkinlesmeProvider;

/// Fon X-Ray görünür mü (Premium tek anahtarı, yasin 2026-10-09): paywall
/// açıkken herkese (ücretsizde kilitli), kapalıyken yalnız admin. Karar
/// `RemoteConfigService.premiumOzellikleriGorunur`'da; burası RC
/// etkinleşince yeniden okur ve widget testinin override edebileceği tek
/// nokta (emsal `fonKarnesiAcikProvider`). Paywall kapalıyken canlıdaki
/// kullanıcı hiçbir X-Ray yüzeyi görmez.
final fonXrayGorunurProvider = Provider<bool>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  return RemoteConfigService.instance.premiumOzellikleriGorunur;
});

/// Katman A (KAP kalemleri + örtüşme) açık mı — bayrak `fon_xray_kalem`,
/// varsayılan KAPALI. Görünürlük ayrıca [fonXrayGorunurProvider]'a bağlı.
final fonXrayKalemAcikProvider = Provider<bool>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  return RemoteConfigService.instance.fonXrayKalem;
});

/// Bir fonun TEFAS sınıf dağılımı. `null` = kart çizilmez: veri yok
/// (TEFAS'ta dağılım yayımlamayan fon, RLS boş döndü) ya da okuma
/// başarısız. Hata sessiz DEĞİL — Crashlytics'e non-fatal; kullanıcıya hata
/// gösterilmez, kart ek bilgidir (fon karnesi / para akışı kararı).
///
/// autoDispose + 30 dk tutma: sunucu günde bir yazıyor; varlık sayfasına
/// girip çıkmak her seferinde sorgu atmasın. `null` tutulmaz.
final fonDagilimiProvider =
    FutureProvider.autoDispose.family<FonDagilimi?, String>((ref, kod) async {
  try {
    final l = await SupabaseService.instance.fonDagilimlari([kod]);
    final d = l.where((x) => x.fonKodu == kod).firstOrNull;
    if (d != null) _tut(ref);
    return d;
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'fonDagilimiProvider');
    return null;
  }
});

/// Bir fonun en yeni KAP kalem listesi (Katman A). Bayrak kapalıyken
/// sunucuya hiç gidilmez.
final fonKalemleriProvider =
    FutureProvider.autoDispose.family<FonKalemleri?, String>((ref, kod) async {
  if (!ref.watch(fonXrayKalemAcikProvider)) return null;
  try {
    final l = await SupabaseService.instance.fonKalemleri([kod]);
    final k = l.where((x) => x.fonKodu == kod).firstOrNull;
    if (k != null) _tut(ref);
    return k;
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'fonKalemleriProvider');
    return null;
  }
});

void _tut(Ref ref) {
  final link = ref.keepAlive();
  final zamanlayici = Timer(const Duration(minutes: 30), link.close);
  ref.onDispose(zamanlayici.cancel);
}

/// Kullanıcının KENDİ bugünkü pozisyonları — X-Ray'in girdisi.
///
/// Bugünkü mülkiyet sorusu → `aktifLotlar` (CLAUDE.md "Kapanmış
/// pozisyon"); ortağın lotları girmez (`temettuTahminiProvider` ile aynı
/// süzgeç). Ayrı provider: ekran fiyat turunda yeniden kurulurken sunucu
/// okuması (aşağıda) yalnız fon KODLARI değişince tekrarlanır.
final xrayPozisyonlariProvider = Provider.autoDispose<List<Position>>((ref) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  final lotlar = ref.watch(
      portfolioProvider.select((s) => s.valueOrNull?.assets ?? const []));
  if (uid == null) return const [];
  return aggregatePositions(
      aktifLotlar(lotlar.where((a) => a.userId == uid)).toList());
});

/// Tutulan fonların kodları, sıralı ve `,` ile birleşik. Metin olarak
/// tutulur ki fiyat turunda (lotlar yeni nesne, kodlar aynı) sunucu okuması
/// tekrarlanmasın — Riverpod eşit değerde bağımlıları uyandırmaz.
final xrayFonKodlariProvider = Provider.autoDispose<String>((ref) {
  final kodlar = <String>{
    for (final p in ref.watch(xrayPozisyonlariProvider))
      if (fonKoduOf(tur: p.representative.type, ticker: p.representative.ticker)
          case final k?)
        k,
  }.toList()
    ..sort();
  return kodlar.join(',');
});

typedef XrayFonVerisi = ({
  Map<String, FonDagilimi> dagilimlar,
  Map<String, FonKalemleri> kalemler,
});

/// Fonların sunucu satırları (TEFAS dağılımı; bayrak açıksa KAP kalemleri).
/// Hata çağırana gider: Portföy X-Ray ekranı `SandikErrorView` gösterir —
/// tam ekranın tek işi bu veri; sessizce "hepsi X-Ray dışı" demek yanlış
/// olurdu.
final xrayFonVerisiProvider =
    FutureProvider.autoDispose<XrayFonVerisi>((ref) async {
  final birlesik = ref.watch(xrayFonKodlariProvider);
  final kalemAcik = ref.watch(fonXrayKalemAcikProvider);
  final kodlar = birlesik.isEmpty ? const <String>[] : birlesik.split(',');
  if (kodlar.isEmpty) {
    return (
      dagilimlar: const <String, FonDagilimi>{},
      kalemler: const <String, FonKalemleri>{},
    );
  }
  final svc = SupabaseService.instance;
  final (d, k) = await (
    svc.fonDagilimlari(kodlar),
    kalemAcik ? svc.fonKalemleri(kodlar) : Future.value(<FonKalemleri>[]),
  ).wait;
  return (
    dagilimlar: {for (final x in d) x.fonKodu: x},
    kalemler: {for (final x in k) x.fonKodu: x},
  );
});

/// Portföy X-Ray. Hesap saf `portfoyXray`'de; burası pozisyonları, TL
/// değerini ve fonların sunucu satırlarını birleştirir (senkron: fiyat
/// turunda yalnız yeniden HESAPLAR, sunucuya gitmez).
///
/// TL değer `PortfolioState.toTRY` ile; fiyatı turda düşmüş pozisyon
/// oturumdaki son kotasyona düşer — ana sayfa toplamıyla (`totalValue`,
/// `ownerScopedTotalValue`) AYNI kural; iki yüzey aynı portföyü farklı
/// toplamasın.
final portfoyXrayProvider =
    Provider.autoDispose<AsyncValue<PortfoyXray>>((ref) {
  final veri = ref.watch(xrayFonVerisiProvider);
  final pozisyonlar = ref.watch(xrayPozisyonlariProvider);
  final durum = ref.watch(portfolioProvider).valueOrNull;
  final toTRY = durum?.toTRY ?? identityToTRY;
  final sonFiyat = PriceService.instance.sonBilinenFiyat;
  return veri.whenData((v) => portfoyXray(
        pozisyonlar: pozisyonlar,
        dagilimlar: v.dagilimlar,
        kalemler: v.kalemler,
        deger: (p) {
          final a = p.asDisplayAsset();
          if (a.currentPrice > 0) return toTRY(a.totalValue, a.currency);
          final f = sonFiyat(a.ticker.trim());
          return f == null || f <= 0 ? null : toTRY(a.quantity * f, a.currency);
        },
      ));
});
