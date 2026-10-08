import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart' show positionKey;
import 'history_service.dart' show PortfolioHistoryBreakdown;
import 'period_summary_service.dart';

/// Bugünün en çok oynayan pozisyonu — Bugün kartı (sadeleştirme 2, düzen H,
/// kullanıcı seçimi 2026-10-04).
class EnCokOynayan {
  const EnCokOynayan({
    required this.positionKey,
    required this.tur,
    required this.degisimPct,
    required this.degisimTRY,
  });

  final String positionKey;
  final AssetType tur;

  /// Pozisyonun kendi gün içi serisinin iki ucu arasındaki yüzde.
  final double degisimPct;

  /// Aynı iki uç arasındaki tutar farkı (TRY) — pozisyonun bugünkü katkısı.
  final double degisimTRY;

  bool get artida => degisimPct >= 0;
}

/// Gün içi breakdown'dan en çok oynayanı seçer — SAF.
///
/// ## Neden Özet GÜNLÜK'ün kuralıyla birebir
/// Performans › Özet › GÜNLÜK zaten "en iyi / en zayıf" gösteriyor
/// (`PeriodSummaryService.enIyiEnZayif`). Kart başka bir kural kursaydı aynı
/// gün iki ekran iki farklı "en çok oynayan" söylerdi. Aynı pencere
/// (`PeriodSummaryService.pencere`, çizilen seans günü), aynı uç
/// (`uclar`), aynı eleme: gün içinde alım/satım yapılan pozisyon ELENİR —
/// miktar değiştiği için serisi zıplar ve o zıplama oynama sanılırdı.
/// Seçim |yüzde| en büyük olan: Özet'in en iyisi ile en zayıfından mutlak
/// değeri büyük olanı.
///
/// Değişim yuvarlanınca sıfırsa (piyasa kapalı, düz gün) `null`: "en çok
/// oynayan %0,00" bilgi taşımaz, kart o kutuyu çizmez.
EnCokOynayan? enCokOynayanBul(
  PortfolioHistoryBreakdown breakdown, {
  required List<Asset> lotlar,
  required DateTime now,
}) =>
    enCokOynayanlar(breakdown, lotlar: lotlar, now: now, enFazla: 1)
        .firstOrNull;

/// Bugünün en çok oynayanları, |yüzde| büyükten küçüğe — SAF.
///
/// Bugün kartının oynayanlar sırası (benchmark revizesi, kullanıcı seçimi
/// 2026-10-09; Delta'nın "Daily Movers" satırı, en fazla üç çip). Kural
/// [enCokOynayanBul] ile AYNI: aynı pencere, aynı uçlar, gün içi akışlı
/// pozisyon elenir, yuvarlanınca sıfır olan sayılmaz. Tek varlık oynadıysa
/// tek eleman; hiçbiri oynamadıysa boş liste (kart satırı çizmez).
List<EnCokOynayan> enCokOynayanlar(
  PortfolioHistoryBreakdown breakdown, {
  required List<Asset> lotlar,
  required DateTime now,
  int enFazla = 3,
}) {
  if (breakdown.byPosition.isEmpty || enFazla <= 0) return const [];
  final p = PeriodSummaryService.pencere(SummaryPeriod.gunluk, now,
      seansGunu: breakdown.seansGunu);
  final fromMs = p.start.millisecondsSinceEpoch;
  final toMs = p.end.millisecondsSinceEpoch;

  // `PeriodSummaryService._gunIciEnHareketli` ile aynı akış kümesi.
  final akisli = <String>{};
  for (final a in lotlar) {
    final ms = a.addedDate.millisecondsSinceEpoch;
    if (ms < fromMs || ms > toMs) continue;
    if (PeriodSummaryService.flowOf(a) == 0) continue;
    akisli.add(positionKey(a));
  }

  final adaylar = <EnCokOynayan>[];
  breakdown.byPosition.forEach((key, seri) {
    if (akisli.contains(key)) return;
    final u = PeriodSummaryService.uclar(seri, fromMs: fromMs, toMs: toMs);
    if (u == null || u.first <= 0 || u.firstTs == u.lastTs) return;
    final pct = (u.last / u.first - 1) * 100;
    if (pct.abs() < 0.005) return;
    adaylar.add(EnCokOynayan(
      positionKey: key,
      tur: breakdown.positionType[key] ?? AssetType.diger,
      degisimPct: pct,
      degisimTRY: u.last - u.first,
    ));
  });
  // Eşitlikte anahtar sırası: aynı veriyle iki build aynı sırayı versin.
  adaylar.sort((a, b) {
    final c = b.degisimPct.abs().compareTo(a.degisimPct.abs());
    return c != 0 ? c : a.positionKey.compareTo(b.positionKey);
  });
  return adaylar.length > enFazla ? adaylar.sublist(0, enFazla) : adaylar;
}
