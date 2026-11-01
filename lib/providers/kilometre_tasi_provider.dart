import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/birikim_serisi.dart';
import '../services/daily_summary.dart';
import '../services/milestone_repository.dart';
import '../services/milestone_service.dart';
import '../services/remote_config_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// Sunucuda kayıtlı (geçilmiş) eşikler, `kind:value`.
///
/// Yalnız kullanıcıya bağlı: portföyü izleseydi her fiyat tikinde sunucuya
/// sorgu giderdi. Oturum içinde yeni geçilen eşik zaten bugünkü hesapta
/// ([kilometreTaslariProvider]) görünür; kayıt bir sonraki açılışta gelir.
///
/// Okuma hatası boş küme sayılır: şerit yalnız bugünkü hesabı gösterir,
/// rozet uydurmaz.
final kayitliKilometreTaslariProvider =
    FutureProvider<Set<String>>((ref) async {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return const {};
  final k = await MilestoneRepository.instance.fetchReached(uid);
  return k.contains('__hata__') ? const {} : k;
});

/// Profil rozet şeridinin verisi (Ar-Ge 1 Kas 20:45 #1, yasin "önerini
/// uygula": ücretsiz). `null` → şerit çizilmez (oturum yok, portföy boş
/// ya da kilometre taşları kapalı).
///
/// Girdi kutlamayla AYNI (`main.dart` `_kilometreTasiKontrol`): aynı
/// varlık listesi, canlı toplam ve birikim serisi (bayrak, yalnız kendi
/// lotları). Şerit kutlamayı TETİKLEMEZ ve kayıt yazmaz; yalnız gösterir.
final kilometreTaslariProvider =
    Provider<({List<Milestone> kazanilan, Milestone? siradaki})?>((ref) {
  if (!RemoteConfigService.instance.milestonesEnabled) return null;
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return null;
  final state = ref.watch(portfolioProvider).valueOrNull;
  if (state == null || state.activeAssets.isEmpty) return null;

  final now = DateTime.now();
  final seri = RemoteConfigService.instance.birikimSerisi
      ? BirikimSerisiService.hesapla([
          for (final a in state.assets)
            if (a.userId == uid) a
        ], now: now)
      : null;
  final total = DailySummary.liveTotalTRY(state);
  final bugun = MilestoneService.evaluate(
    assets: state.assets,
    totalTRY: total,
    now: now,
    seri: seri,
  );
  final kayitli =
      ref.watch(kayitliKilometreTaslariProvider).valueOrNull ?? const {};
  return MilestoneService.koleksiyon(
      kayitli: kayitli, bugun: bugun, totalTRY: total);
});
