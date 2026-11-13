/// Gösterge alarmı satırında göstergenin ŞU ANKİ değeri (Ar-Ge 14 Kas 02:03
/// #5): "EMA50 ₺4.212 · %1,4 kaldı". Fiyat ve çizgi alarmı "ne kadar
/// kaldı" diyordu, gösterge alarmı demiyordu; kişi yakın mı uzak mı
/// olduğunu görmek için grafiği açıyordu.
///
/// **Sunucuyla aynı tanım** (`_shared/gosterge_alarmi.ts`): günlük
/// kapanışlar, bugünün (TR günü) yarım çubuğu atılır, canlı fiyat son nokta
/// olur; EMA tam geçmiş üzerinden (tohum ilk periyodun ortalaması,
/// [TechnicalAnalysisService.emaSeries] — varlık grafiğindeki EMA çizgisiyle
/// aynı fonksiyon), Bollinger (20, 2σ) nüfus sapmasıyla. Satırdaki sayı
/// push'un karar verdiği sayıdan sapmasın diye pencere de aynı (son 730 gün).
///
/// **Uydurma yok** (fiyat kaynağı sözleşmesi madde 3): seri yoksa, kısaysa,
/// bayatsa (son kapanış 7 günden eski) ya da canlı fiyat bilinmiyorsa
/// `null`; satır eskisi gibi kalır.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/seviye_alarmi.dart';
import 'history_service.dart';
import 'technical_analysis_service.dart';

/// TR günü (UTC+3, yaz saati yok): sunucunun `istanbulGunu` eşi.
int _trGunu(int ms) =>
    (ms + const Duration(hours: 3).inMilliseconds) ~/
    const Duration(days: 1).inMilliseconds;

/// Günlük noktalar + canlı fiyat → hesaba girecek kapanış dizisi
/// (sunucu `canliIleKapanislar`). Saf.
List<double>? gostergeKapanislari(
    List<(int, double)> noktalar, double canli, DateTime simdi) {
  if (!canli.isFinite || canli <= 0) return null;
  final simdiMs = simdi.millisecondsSinceEpoch;
  final bugun = _trGunu(simdiMs);
  final pencereBasi = simdiMs - const Duration(days: 730).inMilliseconds;
  final gecmis = [
    for (final (t, v) in noktalar)
      if (v.isFinite && v > 0 && t <= simdiMs && t >= pencereBasi &&
          _trGunu(t) < bugun)
        (t, v)
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (gecmis.isEmpty) return null;
  if (simdiMs - gecmis.last.$1 > const Duration(days: 7).inMilliseconds) {
    return null;
  }
  return [for (final p in gecmis) p.$2, canli];
}

/// Göstergenin son değeri; veri yetmiyorsa `null` (sunucu
/// `gostergeSeviyesi`). Saf.
double? gostergeSeviyesi(GostergeKodu g, List<double> kapanislar) {
  double? son(List<double> seri) {
    if (seri.isEmpty) return null;
    final v = seri.last;
    return v.isFinite ? v : null;
  }

  double? bant(double carpan) {
    const periyot = 20;
    final orta = son(TechnicalAnalysisService.smaSeries(kapanislar, periyot));
    if (orta == null) return null;
    final pencere = kapanislar.sublist(kapanislar.length - periyot);
    final varyans =
        pencere.fold<double>(0, (a, p) => a + (p - orta) * (p - orta)) /
            periyot;
    return orta + carpan * math.sqrt(varyans);
  }

  return switch (g) {
    GostergeKodu.ema20 => son(TechnicalAnalysisService.emaSeries(kapanislar, 20)),
    GostergeKodu.ema50 => son(TechnicalAnalysisService.emaSeries(kapanislar, 50)),
    GostergeKodu.ema200 =>
      son(TechnicalAnalysisService.emaSeries(kapanislar, 200)),
    GostergeKodu.sma20 => son(TechnicalAnalysisService.smaSeries(kapanislar, 20)),
    GostergeKodu.bbUst => bant(2),
    GostergeKodu.bbAlt => bant(-2),
  };
}

/// Sembolün günlük serisi, sembol başına BİR kez çekilir: fiyat turu
/// (portföy/takip tazelenmesi) seriyi yeniden istemez. Önbellek ve
/// tekilleştirme [HistoryService.seriCek]'te; kaynak kararı
/// [FiyatKaynagi.gostergeAlarmSerisi]'nde (yeni sembol merdiveni yok).
/// Kapsam dışı sembolde boş liste.
final gostergeSerisiProvider =
    FutureProvider.family<List<(int, double)>, String>((ref, sembol) async {
  final seri = FiyatKaynagi.gostergeAlarmSerisi(sembol);
  if (seri == null) return const [];
  return HistoryService.instance
      .seriCek(seri, FiyatKaynagi.gostergeAlarmSerisiAraligi(seri));
});

/// Bir gösterge alarmının satırı için anahtar: sembol + gösterge + o anki
/// canlı fiyat. Fiyat değişince yalnız hesap (birkaç yüz noktalık EMA)
/// yeniden koşar; seri [gostergeSerisiProvider]'dan, çekilmez.
typedef GostergeDegeriAnahtari = ({
  String sembol,
  GostergeKodu gosterge,
  double canli,
});

/// Göstergenin şu anki değeri; seri gelmediyse ya da hesap yoksa `null`.
final gostergeDegeriProvider = Provider.autoDispose
    .family<double?, GostergeDegeriAnahtari>((ref, k) {
  final noktalar = ref.watch(gostergeSerisiProvider(k.sembol)).valueOrNull;
  if (noktalar == null || noktalar.isEmpty) return null;
  final kapanislar = gostergeKapanislari(noktalar, k.canli, DateTime.now());
  if (kapanislar == null) return null;
  return gostergeSeviyesi(k.gosterge, kapanislar);
});
