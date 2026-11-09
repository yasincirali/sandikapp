import '../models/asset.dart';
import '../models/position.dart';
import '../providers/hareket_portfoy_degeri_provider.dart'
    show performansSeriDefterleri;
import '../providers/portfolio_provider.dart';
import 'daily_summary.dart';
import 'history_service.dart';
import 'period_summary_service.dart';

/// Performans › Özet'in dönem serisi ve dönem özeti — TEK KAYNAK.
///
/// ## Neden ayrı dosya (Ar-Ge 5 Kas 19:00 #1, müşteri YAP)
/// Ana sayfadaki Bugün kartının "Hafta · Ay · Yıl" segmenti artık kartı
/// yerinde o döneme çeviriyor (eskiden Performans'ı açıyordu). Kartın
/// yazdığı tutar ve yüzde Özet'in aynı dönemde yazdığıyla BİREBİR olmalı
/// (fiyat kaynağı kuralı, "iki merdiven" hata sınıfı). Bunun tek yolu iki
/// yüzeyin aynı pencere, aynı çözünürlük ve aynı motorla çağırmasıdır:
/// Özet'in kanonik serisi (`_ozetSerisiniCek`) de [seri]'yi çağırır.
class DonemOzetiYukleyici {
  DonemOzetiYukleyici._();

  /// Dönemin kanonik serisi: pencere `PeriodSummaryService.pencere`,
  /// çözünürlük `pickForSpan(period.days)` (gerekçe Özet'in `_OzetSerisi`
  /// notunda). GÜNLÜK bu yoldan geçmez; o seri gün içi katmandan gelir.
  static Future<PortfolioHistoryBreakdown> seri(
    SummaryPeriod period,
    List<Asset> seriLotlari, {
    bool simulate = false,
    DateTime? now,
  }) {
    final p = PeriodSummaryService.pencere(period, now ?? DateTime.now());
    return HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: seriLotlari,
      from: p.start,
      to: p.end,
      tier: ResolutionTierMeta.pickForSpan(period.days.toDouble()),
      simulate: simulate,
    );
  }

  /// Kapsam defterinin seri girdisi — Performans'ın tür süzgeçsiz hâliyle
  /// aynı kural (`performansSeriDefterleri`: süren lot + seriye girebilen).
  static List<Asset> seriLotlari(PortfolioState state) => [
        for (final l in performansSeriDefterleri(lotlarSahibeGore(state.assets)))
          ...l,
      ];

  /// Özet'in hesap lotları: kapsamın süren lot'ları (Performans'ta
  /// `targetAssets`, tür süzgeci yok).
  static List<Asset> hesapLotlari(PortfolioState state) =>
      [for (final a in state.assets) if (a.isActive) a];

  /// Seri elde iken dönem özeti — Özet sekmesiyle aynı çağrı (`canliSon`
  /// ve `canliDagilim` canlı kapsam toplamından; Grafik kartının ucuyla
  /// aynı sayı). Seri boşsa `null`: uydurma sayı yok.
  static PeriodSummary? ozet({
    required SummaryPeriod period,
    required PortfolioState state,
    required PortfolioHistoryBreakdown breakdown,
    required DateTime now,
  }) {
    if (period.intraday || breakdown.total.isEmpty) return null;
    final lotlar = hesapLotlari(state);
    final s = PeriodSummaryService.compute(
      period: period,
      assets: lotlar,
      breakdown: breakdown,
      now: now,
      canliSon: DailySummary.kapsamToplami(state, lotlar),
      canliDagilim: DailySummary.kapsamDagilimi(state, lotlar),
    );
    return s.piyasaTRY == null ? null : s;
  }
}
