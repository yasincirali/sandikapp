/// Performans › "Türe göre · fiyat etkisi" kartının kalibrasyon kuralı.
///
/// Tür serilerinin toplamı üst kartın uçlarını her zaman birebir tutmaz:
/// üst kartın son noktası canlı toplamla ezilir, tür serileri ham gelir,
/// GÜNLÜK altın satırı kotasyonun gün başı referansından ölçülür
/// (2026-11-10). Aradaki artık satırlara dağıtılır.
///
/// ## Σ satır == üst kart, her zaman (yasin 2026-11-14)
/// "Günlük kâr zararda gösterilen değer ve aşağıdaki varlığa göre dağılım
/// totalde aynı değeri göstermeli." Eski %2 sınırı (çarpan uzaksa kalibre
/// etme) toplamı tutmayan bir döküm bırakabiliyordu; kaldırıldı.
///
/// ## Fiyatı oynamayan satır oynamaz (kullanıcı bildirimi 2026-11-14)
/// Cumartesi "Bugün"de Fon, BES ve Mevduat aynı −%0,34 ile zararda
/// görünüyordu; üçü de hafta sonu fiyatlanmaz. Tek çarpan artığı fiyatı
/// hiç değişmemiş satırlara da yayıyordu. Artık artık yalnız kendi değeri
/// oynayan satırlara, ağırlıklarınca dağıtılır. Hiçbir satır oynamamışsa
/// (artık yalnız canlı toplam farkıdır) eski kural: hepsine.
library;

typedef TurDokumuUc = ({double first, double last});

/// Değeri bu kadar TL'den az değişen satır "oynamadı" sayılır.
const double turDokumuOynamaEsigi = 0.005;

bool turDokumuOynadi(TurDokumuUc u) =>
    (u.last - u.first).abs() >= turDokumuOynamaEsigi;

/// Satırlara uygulanacak çarpanlar. [yalnizOynayan] doğruysa oynamayan
/// satırlar ölçeklenmez; yanlışsa hepsi aynı çarpanla ölçeklenir.
({double kFirst, double kLast, bool yalnizOynayan}) turDokumuCarpanlari(
  List<TurDokumuUc> satirlar, {
  required double ustFirst,
  required double ustLast,
}) {
  double sabitF = 0, sabitL = 0, oynayanF = 0, oynayanL = 0;
  for (final s in satirlar) {
    if (turDokumuOynadi(s)) {
      oynayanF += s.first;
      oynayanL += s.last;
    } else {
      sabitF += s.first;
      sabitL += s.last;
    }
  }
  final yalnizOynayan = oynayanF.abs() > 0.01 && oynayanL.abs() > 0.01;
  double k(double ust, double sabit, double oynayan) {
    final payda = yalnizOynayan ? oynayan : oynayan + sabit;
    final pay = yalnizOynayan ? ust - sabit : ust;
    if (payda.abs() <= 0.01) return 1.0;
    final c = pay / payda;
    return c.isFinite && c > 0 ? c : 1.0;
  }

  return (
    kFirst: k(ustFirst, sabitF, oynayanF),
    kLast: k(ustLast, sabitL, oynayanL),
    yalnizOynayan: yalnizOynayan,
  );
}
