/// Borsa İstanbul'un kapalı olduğu günler — resmî tatil takvimi.
///
/// `DailySummary.isMarketOpen` yalnızca hafta sonunu eliyordu; tatil
/// gününde kilit ekranı ve ana ekran widget'ı gün boyu "Canlı" deyip sabit
/// bir rakam gösteriyordu (TECHNICAL_DEBT "Live Activity: resmî tatil
/// takvimi"). Kayıt, yanlış listenin listesizlikten kötü olduğunu söylüyordu:
/// gerçek bir işlem gününü kapalı saymak kullanıcıya veriyi hiç göstermez.
/// Bu yüzden iki kural:
///
/// 1. **Yalnızca kesin bilinen günler.** Sabit tarihli ulusal tatiller her
///    yıl aynıdır. Dinî bayramlar hicri takvime göre kayar; onlar SADECE
///    Resmî Gazete'de ilan edilmiş yıllar için listelenir ([sonKapsananYil]).
///    Kapsanmayan yılda dinî bayram BİLİNMEZ ve o günler açık sayılır —
///    yani eski davranışa (hafta sonu filtresi) düşülür, uydurulmaz.
/// 2. **Yarım günler** (bayram arifeleri, 28 Ekim) öğleden sonra kapalıdır;
///    BIST bu günlerde 12:30'da kapanır.
///
/// Sunucu tarafında bir "işlem günü" tablosu kurulursa bu liste oradan
/// beslenir; o güne kadar tek kaynak burasıdır ve push sinyalleri hâlâ
/// takvimi bilmez (yalnızca gösterim yüzeyleri).
class BistTakvimi {
  const BistTakvimi._();

  /// Dinî bayram tarihlerinin girildiği son yıl. Her Aralık ayında bir
  /// sonraki yılın ilanı gelince güncellenir (bkz. TECHNICAL_DEBT).
  static const sonKapsananYil = 2026;

  /// Yarım gün kapanışı (dakika, gün başından).
  static const yarimGunKapanisDk = 12 * 60 + 30;

  /// Sabit tarihli tam gün tatiller — `(ay, gün)`. Her yıl geçerli.
  static const _sabitTamGun = <(int, int)>[
    (1, 1), // Yılbaşı
    (4, 23), // Ulusal Egemenlik ve Çocuk Bayramı
    (5, 1), // Emek ve Dayanışma Günü
    (5, 19), // Atatürk'ü Anma, Gençlik ve Spor Bayramı
    (7, 15), // Demokrasi ve Millî Birlik Günü
    (8, 30), // Zafer Bayramı
    (10, 29), // Cumhuriyet Bayramı
  ];

  /// Sabit tarihli yarım günler — 28 Ekim öğleden sonra.
  static const _sabitYarimGun = <(int, int)>[(10, 28)];

  /// Dinî bayramlar — yıl → tam gün tarihleri. Kaynak: Resmî Gazete'de
  /// ilan edilen takvim; takvim (ay, gün) çiftleri.
  ///
  /// 2026: Ramazan Bayramı 20–22 Mart (arife 19 Mart), Kurban Bayramı
  /// 27–30 Mayıs (arife 26 Mayıs).
  static const _diniTamGun = <int, List<(int, int)>>{
    2026: [(3, 20), (3, 21), (3, 22), (5, 27), (5, 28), (5, 29), (5, 30)],
  };

  /// Dinî bayram arifeleri — öğleden sonra kapalı.
  static const _diniYarimGun = <int, List<(int, int)>>{
    2026: [(3, 19), (5, 26)],
  };

  static bool _icerir(List<(int, int)> liste, DateTime t) =>
      liste.any((g) => g.$1 == t.month && g.$2 == t.day);

  /// Bu yılın dinî bayramları listede var mı? Yoksa o günler açık sayılır.
  static bool yilKapsaniyor(int yil) => _diniTamGun.containsKey(yil);

  /// Tam gün kapalı mı? Hafta sonu BURADA sayılmaz — çağıran zaten eliyor.
  static bool tatilMi(DateTime t) =>
      _icerir(_sabitTamGun, t) ||
      _icerir(_diniTamGun[t.year] ?? const [], t);

  /// Öğleden sonra kapalı yarım gün mü?
  static bool yarimGunMu(DateTime t) =>
      _icerir(_sabitYarimGun, t) ||
      _icerir(_diniYarimGun[t.year] ?? const [], t);
}
