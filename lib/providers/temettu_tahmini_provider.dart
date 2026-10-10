import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/remote_config_service.dart';
import '../services/temettu_gecmisi.dart';
import '../services/temettu_tahmini.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// Kullanıcının KENDİ bugünkü BIST hisseleri için 12 aylık temettü tahmini
/// (Premium, 2026-10-10). Hesap saf `temettuTahmini`'nde; burası yalnız
/// pozisyonları kurar ve olayları çeker (`TemettuGecmisiService`, sembol
/// başına 6 saat önbellek — fiyat turu yeniden ağa çıkarmaz).
///
/// Bugünkü mülkiyet sorusu → `aktifLotlar` (CLAUDE.md "Kapanmış
/// pozisyon"); ortağın lotları girmez. Sembol kararı yalnız
/// `FiyatKaynagi.temettuSembolu` (fiyat kaynağı sözleşmesi madde 1).
final temettuTahminiProvider =
    FutureProvider.autoDispose<TemettuTahmini>((ref) async {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  final lotlar = ref.watch(portfolioProvider
      .select((s) => s.valueOrNull?.assets ?? const []));
  if (uid == null) {
    return TemettuTahmini(satirlar: const [], aylik: List.filled(12, 0));
  }
  final pozisyonlar = aggregatePositions(
      aktifLotlar(lotlar.where((a) => a.userId == uid)).toList());
  final girdiler = await Future.wait([
    for (final p in pozisyonlar)
      if (FiyatKaynagi.temettuSembolu(p.representative) case final sembol?)
        TemettuGecmisiService.instance.olaylariCek(sembol).then((olaylar) =>
            TahminGirdisi(
              ad: p.representative.name,
              sembol: sembol,
              lot: p.totalQuantity,
              olaylar: olaylar,
            )),
  ]);
  return temettuTahmini(
    girdiler,
    stopaj: RemoteConfigService.instance.temettuStopajOrani,
    simdi: DateTime.now(),
  );
});
