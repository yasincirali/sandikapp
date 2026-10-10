import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ortak_paylasimi.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfoy_provider.dart';
import 'preferences_provider.dart';

/// Ortak portföy paylaşımı (0135) — sağlayıcılar.
///
/// Yalnız SAHİP tarafı: benim ortaklarıma yazdığım seçimler. Ortak, kendisi
/// hakkındaki seçimi göremez (yasin 2026-10-10: "ortağım portföylerim
/// olduğunu bilmemeli"); sunucu onun için paylaşılmayan lotları hiç
/// göndermez, istemci paylaşılanları tek havuzda gösterir
/// (`SupabaseService.fetchOrtakLotlari`). Ana sayfa kartı ve ortak
/// görünümü bu yüzden hiçbir not taşımaz.
///
/// Çoklu portföy görünmüyorsa (bayrak kapalı, paywall kapalı ve admin
/// değil, demo) BOŞ: tablo okunmaz (0135 sunucuda olmayabilir).
class OrtakPaylasimlariNotifier extends AsyncNotifier<List<OrtakPaylasimi>> {
  @override
  Future<List<OrtakPaylasimi>> build() async {
    if (!ref.watch(cokluPortfoyGorunurProvider)) return const [];
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];
    // Ortaklık değişince (yeni ortak, ayrılma) yeniden oku. Kimlik
    // listesiyle: `activePartnersProvider` her 30 sn'lik tazelemede yeni
    // liste nesnesi üretir (bkz. `PartnerAssetsNotifier._fiyatHafizasi`).
    ref.watch(activePartnersProvider
        .select((l) => [for (final u in l) u.id].join(',')));
    return SupabaseService.instance.fetchOrtakPaylasimlari(user.id);
  }

  /// Seçimi kaydeder ve listeyi günceller. Hata yukarı çıkar (sayfa
  /// düğmesi gösterir).
  Future<void> kaydet(OrtakPaylasimi p) async {
    await SupabaseService.instance.upsertOrtakPaylasimi(p);
    final eski = state.valueOrNull ?? const [];
    state = AsyncData([
      for (final x in eski)
        if (!(x.sahipId == p.sahipId && x.ortakId == p.ortakId)) x,
      p,
    ]);
  }
}

final ortakPaylasimlariProvider =
    AsyncNotifierProvider<OrtakPaylasimlariNotifier, List<OrtakPaylasimi>>(
        OrtakPaylasimlariNotifier.new);

/// Benim [ortakId]'ye gösterdiklerim. Satır yoksa "hepsi". Liste henüz
/// okunmadıysa ya da okunamadıysa `null`: "Hepsi" yazmak, kısıtlı bir
/// seçimi yanlışlıkla "her şey görünüyor" diye gösterirdi.
final benimPaylasimimProvider =
    Provider.family<OrtakPaylasimi?, String>((ref, ortakId) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return null;
  final liste = ref.watch(ortakPaylasimlariProvider).valueOrNull;
  if (liste == null) return null;
  return liste.firstWhere(
    (p) => p.sahipId == uid && p.ortakId == ortakId,
    orElse: () => OrtakPaylasimi.hepsi(sahipId: uid, ortakId: ortakId),
  );
});

/// Ortak paylaşım seçimi bu kullanıcıya GÖSTERİLİR mi: çoklu portföy
/// görünür, en az bir adlandırılmış portföy var (yalnız Ana varken seçecek
/// bir şey yok) ve en az bir ortak var. Değiştirmek Premium ister
/// ([ortakPaylasimKilitliProvider]); görmek istemez.
final ortakPaylasimSecimiVarProvider = Provider<bool>((ref) {
  if (!ref.watch(cokluPortfoyGorunurProvider)) return false;
  final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
  if (liste.isEmpty) return false;
  final ortaklar = ref.watch(partnersProvider).valueOrNull ?? const [];
  return ortaklar.isNotEmpty;
});

/// Seçimi DEĞİŞTİRMEK Premium ister (yasin 2026-10-10: "yeni ekranlar ve
/// özellikler paywall arkasında"). Paywall kapalıyken kilit yok (admin
/// görür, herkes kullanır). Premium biten kullanıcının mevcut seçimi
/// SUNUCUDA geçerli kalır — gizlenen portföy, abonelik bitti diye ortağa
/// açılmaz; yalnız yeni değişiklik kilitlenir.
final ortakPaylasimKilitliProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  return !ref.watch(effectivePremiumProvider);
});
