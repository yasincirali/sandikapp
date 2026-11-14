/// Performans › "Türe göre · fiyat etkisi" kartının kalibrasyon kuralı.
///
/// Tür serilerinin toplamı üst kartın uçlarını her zaman birebir tutmaz:
/// üst kartın son noktası canlı toplamla ezilir, tür serileri ham gelir.
/// Aradaki küçük artık satırlara ağırlıklarınca dağıtılır ki Σ satır üst
/// kartı tutsun (bkz. `_TypeBreakdownCard._calibrate`).
///
/// ## Fiyatı oynamayan satır oynamaz (kullanıcı bildirimi 2026-11-14)
/// Cumartesi "Bugün"de Fon, BES ve Mevduat aynı −%0,34 ile zararda
/// görünüyordu; üçü de hafta sonu fiyatlanmaz. Sebep tek çarpanlı
/// kalibrasyondu: başka kaynaktan ölçülen altın satırının (gün başı
/// kotasyon referansı, 2026-11-10) üst kartla farkı, çarpan aracılığıyla
/// fiyatı hiç değişmemiş satırlara da yayılıyordu. Kural:
///   1. Kendi değeri değişmeyen satır ölçeklenmez; artık yalnız oynayan
///      satırlara dağıtılır.
///   2. Üst karttan farklı kaynakla ölçülen satır ([TurDokumuSatiri.sabit])
///      ölçeklenmez; toplama üst kartın gördüğü değerle ([toplamda]) girer,
///      böylece kaynak farkı başka satırlara taşınmaz.
///   3. Çarpan 1'den %2'den fazla uzaksa kalibre edilmez (çapraz bulaşma
///      sınırı, eski kural).
library;

typedef TurDokumuUc = ({double first, double last});

class TurDokumuSatiri {
  /// Satırın gösterdiği uçlar.
  final TurDokumuUc deger;

  /// Üst kartın bu satır için gördüğü uçlar; yalnız [sabit] satırda
  /// [deger]'den farklı olabilir.
  final TurDokumuUc toplamda;

  /// Üst karttan farklı kaynakla ölçüldü: ölçeklenmez.
  final bool sabit;

  const TurDokumuSatiri(this.deger, {TurDokumuUc? toplamda, this.sabit = false})
      : toplamda = toplamda ?? deger;
}

/// Değeri bu kadar TL'den az değişen satır "oynamadı" sayılır.
const double turDokumuOynamaEsigi = 0.005;

bool turDokumuOynadi(TurDokumuUc u) =>
    (u.last - u.first).abs() >= turDokumuOynamaEsigi;

/// Oynayan, sabit olmayan satırlara uygulanacak çarpanlar.
({double kFirst, double kLast}) turDokumuCarpanlari(
  List<TurDokumuSatiri> satirlar, {
  required double ustFirst,
  required double ustLast,
  double maxSapma = 0.02,
}) {
  double sabitF = 0, sabitL = 0, oynayanF = 0, oynayanL = 0;
  for (final s in satirlar) {
    if (s.sabit || !turDokumuOynadi(s.deger)) {
      sabitF += s.toplamda.first;
      sabitL += s.toplamda.last;
    } else {
      oynayanF += s.deger.first;
      oynayanL += s.deger.last;
    }
  }
  double k(double ust, double sabit, double oynayan) {
    if (oynayan.abs() <= 0.01) return 1.0;
    final c = (ust - sabit) / oynayan;
    if (!c.isFinite || (c - 1).abs() > maxSapma) return 1.0;
    return c;
  }

  return (
    kFirst: k(ustFirst, sabitF, oynayanF),
    kLast: k(ustLast, sabitL, oynayanL),
  );
}
