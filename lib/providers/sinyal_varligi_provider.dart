import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../services/crash_reporter.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';

/// Ücretsiz planda sinyal bildirimi TEK varlıkta (yasin, 2026-10-08:
/// "sinyal 1 varlıkta ücretsiz, 2. varlık için Premium istesin").
///
/// Kapı bildirimi kısar, ekrandaki göstergeleri değil: varlık ekranındaki
/// panel cihazda hesaplanır ve herkes görmeye devam eder; Premium'un değeri
/// "her varlığın sinyali cebine gelir". Seçim sunucuda (`sinyal_varlik_
/// secimi`, 0126) tek satırdır, çünkü push kararını sunucu verir.
///
/// Eşleşme anahtarı (tür, büyük harf ticker) — `analyze-signals`'taki kapı
/// ile birebir. Bir lot id'si değil: aynı varlığın her alımı aynı sinyali
/// paylaşır, satıp yeniden alınca seçim kaybolmaz.
typedef SinyalVarligi = ({AssetType tur, String ticker});

String sinyalVarlikAnahtari(AssetType tur, String ticker) =>
    '${tur.name}|${ticker.trim().toUpperCase()}';

/// Sunucunun sinyal ürettiği türler (`analyze-signals` → `ANALYZABLE`).
const kSinyalTurleri = {
  AssetType.hisse,
  AssetType.fon,
  AssetType.bes,
  AssetType.altin,
  AssetType.doviz,
  AssetType.emtia,
  AssetType.kripto,
  AssetType.eurobond,
};

bool sinyalUretilir(Asset a) =>
    kSinyalTurleri.contains(a.type) &&
    !a.isManualPrice &&
    a.ticker.trim().isNotEmpty;

/// Etkin sinyal varlığı — sunucudaki kuralın istemci eşi (saf fonksiyon).
///
/// Seçim, kullanıcının hâlâ tuttuğu sinyal üreten bir varlığa denk geliyorsa
/// odur. Denk gelmiyorsa (hiç seçmedi ya da sattı) EN ESKİ eklenen varlık
/// (eşitlikte küçük id): kullanıcıyı hiç sinyalsiz bırakmak, ücretsiz
/// planın sözünü ("bir varlıkta sinyal") tutmamak olurdu.
SinyalVarligi? etkinSinyalVarligi(
    Iterable<Asset> kendiLotlari, SinyalVarligi? secim) {
  final adaylar = [
    for (final a in aktifLotlar(kendiLotlari))
      if (a.isBuy && sinyalUretilir(a)) a,
  ];
  if (adaylar.isEmpty) return null;
  if (secim != null) {
    final k = sinyalVarlikAnahtari(secim.tur, secim.ticker);
    if (adaylar.any((a) => sinyalVarlikAnahtari(a.type, a.ticker) == k)) {
      return secim;
    }
  }
  adaylar.sort((a, b) {
    final t = a.addedDate.compareTo(b.addedDate);
    return t != 0 ? t : a.id.compareTo(b.id);
  });
  final ilk = adaylar.first;
  return (tur: ilk.type, ticker: ilk.ticker.trim().toUpperCase());
}

/// Kapı açık mı: paywall açık, Premium değil, sınır > 0.
final sinyalVarlikKapisiAcikProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  if (ref.watch(effectivePremiumProvider)) return false;
  return RemoteConfigService.instance.freeSignalAssets > 0;
});

/// Kullanıcının sunucudaki seçimi (yoksa null). Kapı kapalıyken okunmaz:
/// paywall açılmadan tabloya istek gitmez.
class SinyalVarligiNotifier extends AsyncNotifier<SinyalVarligi?> {
  @override
  Future<SinyalVarligi?> build() async {
    if (!ref.watch(sinyalVarlikKapisiAcikProvider)) return null;
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return null;
    try {
      final r = await SupabaseService.instance.fetchSinyalVarligi(user.id);
      if (r == null) return null;
      final tur = AssetType.values.where((t) => t.name == r.tur).firstOrNull;
      if (tur == null) return null;
      return (tur: tur, ticker: r.ticker);
    } catch (e, st) {
      // Okunamazsa yedek kurala düşülür (en eski varlık) — sunucu da aynı
      // yere düşer; ekran yine doğru varlığı gösterir.
      _bildir(e, st, 'sinyal_varlik_secimi okuma');
      return null;
    }
  }

  /// Sinyali bu varlığa taşır. Hata çağırana fırlar (düğme gösterir).
  Future<void> tasi(Asset a) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final ticker = a.ticker.trim().toUpperCase();
    await SupabaseService.instance
        .setSinyalVarligi(userId: user.id, tur: a.type.name, ticker: ticker);
    state = AsyncData((tur: a.type, ticker: ticker));
  }

  static void _bildir(Object e, StackTrace st, String neden) {
    CrashReporter.arkaPlan(
      FirebaseCrashlytics.instance
          .recordError(e, st, reason: neden, fatal: false),
      reason: 'sinyal_varligi_provider.recordError',
    );
  }
}

final sinyalVarligiProvider =
    AsyncNotifierProvider<SinyalVarligiNotifier, SinyalVarligi?>(
  SinyalVarligiNotifier.new,
);

/// Ekranın sorduğu tek şey: kapı açıksa bildirimin gittiği varlık.
/// Kapı kapalıyken null (her varlık bildirim alır).
final etkinSinyalVarligiProvider = Provider<SinyalVarligi?>((ref) {
  if (!ref.watch(sinyalVarlikKapisiAcikProvider)) return null;
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return null;
  final lotlar = ref.watch(portfolioProvider).valueOrNull?.assets ?? const [];
  return etkinSinyalVarligi(
    lotlar.where((a) => a.userId == user.id),
    ref.watch(sinyalVarligiProvider).valueOrNull,
  );
});
