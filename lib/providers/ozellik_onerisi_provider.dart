import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/leaderboard_service.dart';
import '../services/ozellik_onerisi.dart';
import '../services/remote_config_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';
import 'price_alert_provider.dart';
import 'veri_kalitesi_provider.dart';
import 'watchlist_provider.dart';

/// Çağıranın Zirve rızası (tek satır okuma). Yalnız Zirve önerisi sırası
/// gelince izlenir; hata → null (öneri susar).
final zirveRizamProvider = FutureProvider<bool?>(
    (ref) => LeaderboardService.instance.fetchZirveRizasi());

/// Gösterilecek özellik önerisi (`ozellik_onerisi.dart`) ya da null.
///
/// "Bilgi eksik" satırı görünürken öneri yok: ana ekranda aynı anda tek
/// dürtü; eksik veri düzeltmek her öneriden önce gelir.
final ozellikOnerisiProvider = Provider<OzellikOnerisi?>((ref) {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return null;
  final eksikler = ref.watch(veriEksikleriProvider);
  if (veriSeridiGorunur(eksikler, ref.watch(veriKalitesiKapatilanProvider))) {
    return null;
  }
  final lotlar = ref.watch(
      portfolioProvider.select((s) => s.valueOrNull?.assets ?? const []));
  final varlik = aktifLotlar(lotlar.where((a) => a.userId == uid)).length;
  final partners = ref.watch(partnersProvider);
  final kapatilan = ref.watch(ozellikOnerisiKapatilanProvider);
  final son = ref.watch(ozellikOnerisiSonKapatmaProvider);
  final zirveAcik = RemoteConfigService.instance.globalLeaderboardEnabled;
  final simdi = ref.watch(veriKalitesiSaatProvider)();

  OzellikOnerisi? karar(bool? zirveRizasi) => siradakiOneri(
        varlikSayisi: varlik,
        alarmSayisi: ref.watch(priceAlertsProvider).valueOrNull?.length,
        takipSayisi: ref.watch(watchlistProvider).valueOrNull?.length,
        ortakSayisi:
            partners.hasValue ? ref.watch(activePartnersProvider).length : null,
        zirveAcik: zirveAcik,
        zirveRizasi: zirveRizasi,
        kapatilanlar: kapatilan,
        sonKapatma: son > 0 ? DateTime.fromMillisecondsSinceEpoch(son) : null,
        simdi: simdi,
      );

  // Rıza sorgusu yalnız sıra Zirve'ye gelirse: önce rızayı "yok" sayarak
  // karar ver; çıkan Zirve değilse ağa hiç gidilmez.
  final ilk = karar(false);
  if (ilk != OzellikOnerisi.zirve) return ilk;
  return karar(ref.watch(zirveRizamProvider).valueOrNull);
});
