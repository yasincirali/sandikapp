import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../models/ortak_paylasimi.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfoy_provider.dart';
import 'preferences_provider.dart';

/// Ortak portföy paylaşımı (0135) — sağlayıcılar.
///
/// Tek okuma iki yönü getirir: benim ortaklarıma yazdığım seçimler
/// ([benimPaylasimimProvider]) ve ortaklarımın bana yaptığı seçimler
/// ([ortakKisitliProvider], ana ekran notu için).
///
/// Bayrak (`coklu_portfoy`) kapalıyken ya da demoda BOŞ: tablo okunmaz
/// (0135 sunucuda olmayabilir), hiçbir yeni yüzey çizilmez. Okuma yalnız
/// BAYRAĞA bağlı, Premium görünürlüğüne değil: ortağı kısıtlı paylaşan
/// ücretsiz kullanıcı da "yalnız paylaştıkları" notunu görmeli (yoksa
/// kısmi toplamı ortağının bütün varlığı sanar). Seçim yüzeyi ise
/// [ortakPaylasimSecimiVarProvider] ile çoklu portföy görünürlüğüne bağlı.
/// Ortak tarafındaki süzme bundan bağımsız olarak RLS'te.
class OrtakPaylasimlariNotifier extends AsyncNotifier<List<OrtakPaylasimi>> {
  @override
  Future<List<OrtakPaylasimi>> build() async {
    ref.watch(rcEtkinlesmeProvider);
    if (DemoModu.aktif || !RemoteConfigService.instance.cokluPortfoy) {
      return const [];
    }
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

/// [ortakId] bana yalnız BAZI portföylerini mi gösteriyor. Ana ekran
/// kartının ortak/Birlikte görünümündeki "yalnız paylaştıkları" notu.
final ortakKisitliProvider = Provider.family<bool, String>((ref, ortakId) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return false;
  final liste = ref.watch(ortakPaylasimlariProvider).valueOrNull ?? const [];
  return liste.any((p) => p.sahipId == ortakId && p.ortakId == uid && p.kisitli);
});

/// Ortak paylaşım seçimi bu kullanıcıya sunulur mu: çoklu portföy görünür,
/// en az bir adlandırılmış portföy var (yalnız Ana varken seçecek bir şey
/// yok) ve en az bir ortak var.
final ortakPaylasimSecimiVarProvider = Provider<bool>((ref) {
  if (!ref.watch(cokluPortfoyGorunurProvider)) return false;
  final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
  if (liste.isEmpty) return false;
  final ortaklar = ref.watch(partnersProvider).valueOrNull ?? const [];
  return ortaklar.isNotEmpty;
});
