import 'dart:math' as math;

import 'destek_direnc.dart';

/// Bir fiyat serisinin dönem istatistikleri — varlık sayfasının sayıları.
///
/// ## Neden saf fonksiyon
/// Hesap `build()` içinde yapılsaydı her crosshair karesinde yeniden koşardı
/// (5Y seride ~260 nokta, dönem değişiminde altı seri). Seri geldiğinde bir
/// kez hesaplanır, sonuç saklanır; widget yalnızca okur. Ayrıca kuralların
/// kendisi (yüzde formülü, oynaklığın yıllıklaştırılması, en büyük düşüş)
/// widget kurmadan test edilebilir (`varlik_istatistik_test`).
///
/// ## Uydurma sayı yok
/// Kaynakta olmayan hiçbir değer üretilmez: iki noktadan kısa seride sonuç
/// `null`; oynaklık, yıllıklaştırmayı anlamlı kılacak kadar gözlem yoksa
/// `null` (ekranda "—"). Fiyat kaynağı sözleşmesinin üçüncü maddesi.
class DonemIstatistigi {
  const DonemIstatistigi({
    required this.ilk,
    required this.son,
    required this.yuksek,
    required this.dusuk,
    required this.enBuyukDususPct,
    required this.oynaklikPct,
    this.destekDirenc,
    this.kapsananGun,
  });

  /// Dönem başı (serinin ilk noktası).
  final double ilk;

  /// Dönem sonu (serinin son noktası) — ekrandaki fiyat.
  final double son;

  final double yuksek;
  final double dusuk;

  /// Dönem içindeki zirveden dibe en büyük yüzde kayıp; 0 ya da negatif.
  final double enBuyukDususPct;

  /// Yıllıklaştırılmış oynaklık (%), yeterli gözlem yoksa `null`.
  final double? oynaklikPct;

  /// Dönem serisinden destek/direnç bölgeleri (`destek_direnc.dart`); seri
  /// kısaysa `null`. Bölge hesabı da istatistikle birlikte BİR KEZ yapılır
  /// (build'de değil — CLAUDE.md katmanlama).
  final DestekDirenc? destekDirenc;

  /// Seri dönemin başına ulaşmıyorsa verinin kapsadığı gün sayısı; yeterli
  /// ise (ya da kontrol edilmediyse) `null`. Bkz. [eksikKapsamGunu].
  final int? kapsananGun;

  /// Dönem çipi yüzde yerine "—" yazmalı mı.
  bool get kapsamEksik => kapsananGun != null;

  /// Tutar farkı: son − ilk.
  double get fark => son - ilk;

  /// Dönem değişimi — uygulamanın her yerindeki formül: (son − ilk) / ilk.
  double get degisimPct => ilk > 0 ? (fark / ilk) * 100 : 0.0;

  /// Yuvarlanmış yüzde sıfırsa değişim NÖTR gösterilir; yeşil "kazanç var"
  /// yanılgısı yaratır. Takip listesi satırıyla aynı eşik.
  bool get isFlat => degisimPct.abs() < 0.005;

  /// Bugünkü fiyatın dönem aralığındaki yeri: 0 = dönem dibi, 1 = zirvesi.
  double get konum {
    final aralik = yuksek - dusuk;
    if (aralik.abs() < 1e-12) return 0.5;
    return ((son - dusuk) / aralik).clamp(0.0, 1.0);
  }

  /// Oynaklık için asgari getiri gözlemi. Altında standart sapma gürültüdür.
  static const asgariGozlem = 10;

  /// Oynaklık yalnızca GÜNLÜK ya da daha seyrek seride anlamlıdır. Gün içi
  /// 5 dakikalık seriyi yıllıklaştırmak seans dışı boşlukları yok sayar ve
  /// gerçeğin katları bir sayı üretir.
  static const oynaklikIcinAsgariDonemGun = 30;

  /// Kapsam kontrolünün başladığı dönem. GÜNLÜK ve 1H'de hafta sonu ve
  /// bayram boşluğu dönemin büyük kısmı olabilir; orada "eksik" demek
  /// yanlış alarm olurdu.
  static const kapsamIcinAsgariDonemGun = 30;

  /// Seri dönemin başına ulaşıyor mu (2026-10-23, Ar-Ge #1).
  ///
  /// Neden: yüzde serinin İLK noktasından hesaplanır. 8 aylık bir fonda ya
  /// da yarım gelen bir seride "5Y" çipi aslında 8 ayın getirisini yazıyordu:
  /// başka bir dönemin sayısı, dönem etiketiyle. "Uydurma sayı yasak"
  /// kuralının etiket karşılığı.
  ///
  /// İlk nokta dönem başından dönemin %20'sinden (en az 10 gün) daha geç
  /// başlıyorsa verinin kapsadığı gün sayısını döner; yeterliyse `null`.
  /// Pay, kaynakların dönem başını birkaç gün kaçırmasını (hafta sonu,
  /// bayram, haftalık seride ilk mumun konumu) eksik saymasın diye var.
  static int? eksikKapsamGunu({
    required int ilkTs,
    required int periodDays,
    required DateTime simdi,
  }) {
    if (periodDays < kapsamIcinAsgariDonemGun) return null;
    const gunMs = 86400000;
    final bas = simdi.millisecondsSinceEpoch - periodDays * gunMs;
    final pay = math.max(periodDays * 0.2, 10.0) * gunMs;
    if (ilkTs - bas <= pay) return null;
    final kapsanan =
        ((simdi.millisecondsSinceEpoch - ilkTs) / gunMs).floor();
    return math.max(kapsanan, 1);
  }

  /// [seri]: `epoch ms → fiyat`. [periodDays]: seçili dönem. [simdi]
  /// verilirse kapsam kontrolü yapılır ([eksikKapsamGunu]).
  static DonemIstatistigi? hesapla(
    Map<int, double> seri, {
    required int periodDays,
    DateTime? simdi,
  }) {
    final ts = [
      for (final e in seri.entries)
        if (e.value.isFinite && e.value > 0) e.key,
    ]..sort();
    if (ts.length < 2) return null;

    final fiyat = [for (final t in ts) seri[t]!];

    var yuksek = fiyat.first, dusuk = fiyat.first;
    var zirve = fiyat.first, enBuyukDusus = 0.0;
    for (final p in fiyat) {
      if (p > yuksek) yuksek = p;
      if (p < dusuk) dusuk = p;
      if (p > zirve) zirve = p;
      final dusus = (p - zirve) / zirve * 100;
      if (dusus < enBuyukDusus) enBuyukDusus = dusus;
    }

    return DonemIstatistigi(
      ilk: fiyat.first,
      son: fiyat.last,
      yuksek: yuksek,
      dusuk: dusuk,
      enBuyukDususPct: enBuyukDusus,
      oynaklikPct: periodDays >= oynaklikIcinAsgariDonemGun
          ? yillikOynaklik(ts, fiyat)
          : null,
      destekDirenc: DestekDirenc.hesapla(fiyat, fiyat.last),
      kapsananGun: simdi == null
          ? null
          : eksikKapsamGunu(
              ilkTs: ts.first, periodDays: periodDays, simdi: simdi),
    );
  }

  /// Log getirilerin standart sapması × √(yıllık gözlem sayısı).
  ///
  /// **Yıllık gözlem sayısı veriden ölçülür**, sabit 252 değil. Seri
  /// sıklığı dönemden gelir (`ResolutionTierMeta.pickForSpan`: 1A günlük,
  /// 6A ve 1Y haftalık); ayrıca BIST hafta sonu işlem görmez, kripto görür.
  /// Sabit √252 haftalık seride oynaklığı √5 kat şişirir, kriptoda ise
  /// hafta sonunu yok sayardı. "Bu seride bir yılda kaç gözlem var"
  /// sorusunun cevabı her üç durumu da doğru ölçekler.
  static double? yillikOynaklik(List<int> ts, List<double> fiyat) {
    final n = fiyat.length - 1;
    if (n < asgariGozlem) return null;
    final spanYil =
        (ts.last - ts.first) / const Duration(days: 365).inMilliseconds;
    if (spanYil <= 0) return null;

    final getiriler = [
      for (var i = 1; i < fiyat.length; i++) math.log(fiyat[i] / fiyat[i - 1]),
    ];
    final ort = getiriler.reduce((a, b) => a + b) / n;
    var kare = 0.0;
    for (final g in getiriler) {
      kare += (g - ort) * (g - ort);
    }
    final sapma = math.sqrt(kare / (n - 1));
    final yillikGozlem = n / spanYil;
    return sapma * math.sqrt(yillikGozlem) * 100;
  }
}
