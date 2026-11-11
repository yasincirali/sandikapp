import 'asset.dart';
import 'position.dart';

/// Bir pozisyonun portföydeki payı (0–1): "Portföyündeki payı %12"
/// (Ar-Ge 11 Kas 19:04 #7).
///
/// ## Neden
/// Varlığın ağırlığı yalnız Portföy halkasında görünüyordu; varlık
/// sayfasında, Al/Sat kararının hemen önünde "bu pozisyon benim için ne
/// kadar büyük" sorusunun cevabı yoktu. Yalnız oran yazılır — "fazla",
/// "riskli" gibi yorum yok (yatırım tavsiyesi gibi okunmasın). Ücretsiz:
/// tek oran temel bilgidir (Ar-Ge kararı; Premium kararı müşteri thread'inin).
///
/// ## Halkayla AYNI hesap
/// Payda Portföy halkasının toplamıdır (`turDagilimi`, portfolio_screen):
/// defter `aggregatePositions` ile açık pozisyonlara indirgenir, her
/// pozisyonun görüntü varlığı `toTRY(totalValue, currency)` ile TL'ye
/// çevrilir. Satılmış pozisyon girmez (CLAUDE.md "Kapanmış pozisyon":
/// bugünkü mülkiyet → [aktifLotlar]). Mevduat ve BES halkada olduğu için
/// paydada da vardır; mevduat pozisyonunun kendi payı da yazılır.
///
/// [degerTRY] pozisyonun bugünkü TL değeri (varlık sayfasında
/// `pnl.currentValueTRY`, aynı `toTRY`). [defter] o sahibin (ve çoklu
/// portföyde o portföyün) ham lot defteri. Değer ya da toplam ≤ 0 ise
/// `null` → satır çizilmez; uydurma oran yazılmaz. Kur farkı ya da eski
/// önbellek yüzünden pay 1'i aşarsa 1'e kırpılır.
double? portfoyPayi({
  required double degerTRY,
  required Iterable<Asset> defter,
  required double Function(double tutar, String paraBirimi) toTRY,
}) {
  if (!(degerTRY > 0)) return null;
  var toplam = 0.0;
  for (final p in aggregatePositions(aktifLotlar(defter))) {
    final a = p.asDisplayAsset();
    toplam += toTRY(a.totalValue, a.currency);
  }
  if (!(toplam > 0)) return null;
  return (degerTRY / toplam).clamp(0.0, 1.0);
}
