import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../demo/demo_modu.dart';
import '../models/ozel_gosterge.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'premium_provider.dart' show premiumOzellikleriGorunurProvider;

/// Kendi göstergeni yaz (0141) — kullanıcının gösterge betikleri.
///
/// ## Kim görür (yeni bayrak YOK)
/// EMA/Mum ile aynı kapı (`grafik_katmanlari.dart`): tek anahtar
/// `paywall_enabled` (`premiumOzellikleriGorunurProvider`). Kapalıyken yalnız
/// admin görür ve tablo yalnız onun için okunur; mağazadaki kullanıcıda hiçbir
/// istek gitmez, grafik birebir eskisi. Kilit (Premium değil) ekranda
/// `premiumKilitliProvider`; yazma sunucuda da `premium_icerik_gorebilir()`.
class OzelGostergelerNotifier extends AsyncNotifier<List<OzelGosterge>> {
  static const _uuid = Uuid();

  @override
  Future<List<OzelGosterge>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null || DemoModu.aktif) return const [];
    if (!ref.watch(premiumOzellikleriGorunurProvider)) return const [];
    return SupabaseService.instance.fetchOzelGostergeler(user.id);
  }

  List<OzelGosterge> get _liste => state.valueOrNull ?? const [];

  bool get doldu => _liste.length >= OzelGosterge.azamiSayi;

  /// Yeni gösterge; grafikte açık başlar (kullanıcı onu görmek için yazdı).
  Future<OzelGosterge> ekle({required String ad, required String kod}) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) throw StateError('Oturum yok.');
    if (doldu) throw StateError('En fazla ${OzelGosterge.azamiSayi} gösterge.');
    if (!OzelGosterge.adGecerli(ad)) throw ArgumentError.value(ad, 'ad');
    final g = OzelGosterge(
      id: _uuid.v4(),
      userId: user.id,
      ad: ad.trim(),
      kod: kod,
      olusturuldu: DateTime.now(),
    );
    await SupabaseService.instance.insertOzelGosterge(g);
    state = AsyncData([..._liste, g]);
    return g;
  }

  Future<void> kaydet(OzelGosterge g) async {
    if (!OzelGosterge.adGecerli(g.ad)) throw ArgumentError.value(g.ad, 'ad');
    await SupabaseService.instance.updateOzelGosterge(g);
    state = AsyncData([for (final x in _liste) x.id == g.id ? g : x]);
  }

  /// Grafikte aç/kapa — iyimser: anahtar anında döner, yazım düşerse geri
  /// alınır (TASARIM_DILI §4 "iyimser güncellemeler" istisnası).
  Future<void> grafikteAyarla(String id, bool acik) async {
    final onceki = _liste;
    final g = onceki.firstWhere((x) => x.id == id);
    state = AsyncData(
        [for (final x in onceki) x.id == id ? x.kopya(grafikte: acik) : x]);
    try {
      await SupabaseService.instance.updateOzelGosterge(g.kopya(grafikte: acik));
    } catch (_) {
      state = AsyncData(onceki);
      rethrow;
    }
  }

  Future<void> sil(String id) async {
    await SupabaseService.instance.deleteOzelGosterge(id);
    state = AsyncData([
      for (final x in _liste)
        if (x.id != id) x
    ]);
  }
}

final ozelGostergelerProvider =
    AsyncNotifierProvider<OzelGostergelerNotifier, List<OzelGosterge>>(
        OzelGostergelerNotifier.new);
