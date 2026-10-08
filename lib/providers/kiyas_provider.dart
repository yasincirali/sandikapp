import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fiyat_kaynagi.dart';
import '../services/kiyas_service.dart';
import '../services/kiyas_yukleyici.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;

/// Kıyas serileri — DÖNEME bağlı, kullanıcının portföyüne değil.
///
/// Anahtar yalnızca dönem: ekran 30 sn'de bir yeniden çizilir ve canlı uç
/// her seferinde değişir; seriler bunlardan bağımsızdır ve yeniden
/// çekilmemelidir. 15 dk tutulur — `HistoryService` seri önbelleğinin
/// ömrü (`_cacheTtl`); daha uzun tutmak bayat seri, daha kısa tutmak boşa
/// istek olurdu. Boş sonuç (ağ yok) tutulmaz, sonraki açılış yeniden dener.
final kiyasSerileriProvider = FutureProvider.autoDispose
    .family<Map<KiyasVarligi, Map<int, double>>, SummaryPeriod>(
        (ref, period) async {
  final s = await KiyasYukleyici.serileriGetir(period);
  if (s.isNotEmpty) {
    final link = ref.keepAlive();
    final zamanlayici = Timer(const Duration(minutes: 15), link.close);
    ref.onDispose(zamanlayici.cancel);
  }
  return s;
});

/// Kartın özeti. Hesap `build()` dışında, burada yapılır (saf ve ucuz:
/// akış sayısı kadar ikili arama). Seriler yüklenirken `AsyncLoading`,
/// kullanıcının getirisi yoksa `data(null)`.
final kiyasProvider = Provider.autoDispose
    .family<AsyncValue<KiyasOzeti?>, KiyasGirdisi>((ref, girdi) => ref
        .watch(kiyasSerileriProvider(girdi.period))
        .whenData((seriler) => KiyasService.ozet(girdi, seriler)));
