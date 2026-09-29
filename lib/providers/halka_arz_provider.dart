// Halka arz takvimi provider'ları (F6).
//
// Bayrak, saat ve servis ayrı provider: widget testleri bunları override
// ederek bayrağı kapatır, "bugün"ü sabitler ve ağsız servis verir.
// `RemoteConfigService` debug'da bayrağı açık döndürdüğü için testte
// kapalı kolu başka türlü sınamak mümkün değil.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/halka_arz.dart';
import '../services/halka_arz_service.dart';
import '../services/remote_config_service.dart';

final halkaArzEtkinProvider = Provider<bool>(
  (ref) => RemoteConfigService.instance.ipoCalendarEnabled,
);

final halkaArzServiceProvider =
    Provider<HalkaArzService>((ref) => HalkaArzService.instance);

final halkaArzSaatProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ekranın okuduğu hazır görünüm: gruplama burada, `build()` içinde değil.
class HalkaArzGorunumu {
  const HalkaArzGorunumu({
    required this.gruplar,
    required this.kaynak,
    required this.guncelleme,
  });

  final Map<HalkaArzDurumu, List<HalkaArz>> gruplar;
  final HalkaArzKaynagi kaynak;
  final DateTime? guncelleme;

  bool get bos => gruplar.isEmpty;
}

final halkaArzGorunumuProvider =
    FutureProvider.autoDispose<HalkaArzGorunumu>((ref) async {
  final servis = ref.watch(halkaArzServiceProvider);
  final simdi = ref.watch(halkaArzSaatProvider)();
  final liste = await servis.yukle();
  return HalkaArzGorunumu(
    gruplar: halkaArzGruplari(liste.kayitlar, simdi),
    kaynak: liste.kaynak,
    guncelleme: liste.guncelleme,
  );
});
