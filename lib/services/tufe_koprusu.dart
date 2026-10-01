import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../utils/tr_format.dart' show dayKey;
import 'crash_reporter.dart';
import 'history_service.dart';
import 'period_summary_service.dart';
import 'tuik_takvimi.dart';

/// Reel getiri kartının altındaki köprü satırı: TÜFE penceresinin bittiği
/// günden BUGÜNE kadarki piyasa getirisi.
///
/// ## Neden var (kullanıcı kararı D2, 2026-10-01)
/// Özet › 1Y emülatörde üst kart "1Y · +%23,05", reel getiri kartı
/// "senin getirin +%39,77 · TÜFE %31,51 · +8,3 puan önde" yazıyordu ve
/// kullanıcı bunu çelişki olarak okudu. İkisi de doğru: üst kart BUGÜNE
/// kadar ölçer, reel kart son AÇIKLANMIŞ TÜFE ayının sonuna (31 Ağustos)
/// kadar. Aradaki Eylül (−%5,15) yalnızca üst kartta. Dönem farkı bir
/// notla anlatılıyordu; karar: fark ÖLÇÜLÜP yazılsın — "Ağu sonundan
/// bugüne −%5,15". Kullanıcı farkın nereden geldiğini rakamla görür.
///
/// ## Neden yeni formül yok
/// Getiri `PeriodSummaryService.compute`'tan gelir — `pencereBaslangici`
/// ile pencere dışarıdan verilir, `canliSon` ile sağ uç canlı toplama
/// bağlanır (üst kartla aynı sağ uç). Desen `RealReturnService.piyasaGetirisi`:
/// aynı nakit akışı düzeltmeli hesap, yalnızca uçlar farklı.
@immutable
class TufeKoprusu {
  const TufeKoprusu({required this.pencereSonu, required this.getiriPct});

  /// TÜFE penceresinin portföy serisindeki bitişi
  /// (`InflationWindow.seriBitisi`: son açıklanmış ayın son günü).
  final DateTime pencereSonu;

  /// [pencereSonu] → bugün piyasa getirisi (%).
  final double getiriPct;

  /// Henüz açıklanmamış ilk TÜFE ayı — pencerenin bittiği ayın ertesi.
  DateTime get eksikAy => DateTime(pencereSonu.year, pencereSonu.month + 1);

  /// [eksikAy]'ın açıklanacağı an (`TuikTakvimi`, tek kural).
  DateTime get aciklamaTarihi => TuikTakvimi.aciklamaTarihi(eksikAy);

  /// Pencere sonu ile bugün arasında ölçülecek en az BİR gün var mı?
  ///
  /// Yoksa satır çizilmez: aynı günün "getirisi" ya bir sıfır ya da gün
  /// içi gürültüdür ve "üstteki rakam bu süreyi içeriyor" cümlesi boş
  /// kalırdı. Takvim günü sayılır (saat değil) — TÜFE penceresi bir gün
  /// SONUNU temsil ediyor.
  static bool olculebilir(DateTime pencereSonu, DateTime now) =>
      dayKey(now).difference(dayKey(pencereSonu)).inDays >= 1;

  /// [pencereSonu] → [now] getirisini ölçer. Seri kurulamazsa, pencere
  /// boşsa ya da taban sıfırsa `null` — uydurma sayı yok, satır çizilmez.
  ///
  /// [canliSon]: canlı kapsam toplamı (`DailySummary.kapsamToplami`).
  /// Pencere bugünde bittiği için verilmeli; gerekçe `compute` [canliSon].
  static Future<double?> olc(
    List<Asset> assets, {
    required DateTime pencereSonu,
    required DateTime now,
    double? canliSon,
  }) async {
    if (assets.isEmpty || !olculebilir(pencereSonu, now)) return null;
    try {
      return await _olc(assets, pencereSonu, now, canliSon);
    } catch (e, st) {
      // Satır ikincil: ölçülemezse çizilmez (uydurma sayı yok). Ama sessiz
      // de kalmaz — reel kartın altı bir gün boş kalırsa sebebi görünsün.
      CrashReporter.report(e, st, reason: 'tufe_koprusu_olc');
      return null;
    }
  }

  static Future<double?> _olc(
    List<Asset> assets,
    DateTime pencereSonu,
    DateTime now,
    double? canliSon,
  ) async {
    final tier = ResolutionTierMeta.pickForSpan(
      now.difference(pencereSonu).inDays.toDouble(),
    );
    final bd =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: assets,
      from: pencereSonu,
      to: now,
      tier: tier,
    );
    final ozet = PeriodSummaryService.compute(
      // Dönem kimliği getiriyi etkilemez: pencere `pencereBaslangici` ile
      // dışarıdan verilir, kimlik özete yalnızca etiket olarak geçer
      // (`RealReturnService.piyasaGetirisi` ile aynı seçim).
      period: SummaryPeriod.birYil,
      assets: assets,
      breakdown: bd,
      now: now,
      pencereBaslangici: pencereSonu,
      canliSon: canliSon,
    );
    final pct = ozet.getiriPct;
    return (pct == null || !pct.isFinite) ? null : pct;
  }
}
