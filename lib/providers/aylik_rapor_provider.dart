import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../services/aylik_rapor_ozeti.dart';
import '../services/aylik_rapor_yukleyici.dart';
import '../services/daily_summary.dart';
import 'portfolio_provider.dart';

/// Sahibin etkin defter satırları (aylık rapor + PDF ortak girdisi).
///
/// Yalnız KENDİ lotları: ortak lot'lar başka kullanıcının portföyüdür
/// (`partner_aggregation_invariant`). `isActive` silinmişi eler, kapanmış
/// pozisyonun satışını TUTAR — rapor geçmişi sorar.
List<Asset> aylikRaporLotlari(PortfolioState durum) => [
      for (final a in durum.assets)
        if (a.userId == durum.ownerId && a.isActive) a
    ];

/// Aylık raporun sayısal bölümleri (2026-11-07). `null`: portföy henüz
/// yüklenmedi. Hesap `build()` dışında, burada bir kez.
final aylikRaporOzetiProvider = FutureProvider.autoDispose
    .family<AylikRaporOzeti?, DateTime>((ref, donem) async {
  // Fiyat turu her birkaç dakikada state'i yeniler; ayın serisi ve olay
  // sorguları her turda yeniden koşmasın. Defter değişince (sahip ya da
  // satır sayısı) yeniden hesaplanır.
  ref.watch(portfolioProvider.select((v) => switch (v.valueOrNull) {
        final d? => '${d.ownerId}|${d.assets.length}',
        null => null,
      }));
  final durum = ref.read(portfolioProvider).valueOrNull;
  if (durum == null) return null;
  final lotlar = aylikRaporLotlari(durum);
  return AylikRaporYukleyici.hazirla(
    donem: donem,
    lotlar: lotlar,
    canliToplam: DailySummary.kapsamToplami(durum, lotlar),
  );
});
