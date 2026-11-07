/// 52 haftalık aralık (Ar-Ge 2026-11-07 12:30 #1, ücretsiz).
///
/// Soru: "Bu varlık yılın dibinde mi, tepesinde mi?" Muadillerde (Midas,
/// bankalar, Yahoo) temel bilgi; burada YENİ KAYNAK YOK: varlık sayfasının
/// 1Y dönem serisi (`FiyatKaynagi` → `HistoryService`, ekrandaki fiyatla
/// aynı birim ölçek) kullanılır, ağa ek istek çıkmaz.
///
/// İki adım, çünkü hesap `build()` içinde yapılmaz (CLAUDE.md katmanlama):
///   1. [YillikUclar.hesapla] seriyi BİR KEZ tarar (seri gelince, state'e);
///   2. [YillikUclar.bugunle] canlı fiyatı ekler (sabit süre, build'de
///      güvenli) — canlı fiyat seriden sık değişir, tarama tekrarlanmaz.
///
/// Uydurma sayı yok (fiyat kaynağı sözleşmesi 3): sıfır/negatif/sonsuz
/// nokta seriye girmez; iki geçerli nokta yoksa ya da aralık düzse sonuç
/// `null`, satır hiç çizilmez.
library;

/// Seri bir yılı kapsıyor sayılırken dönem başından ne kadar geç
/// başlayabilir: 1Y serisi haftalık katmandan gelir (ilk nokta dönem
/// başından ~7 gün sonra olabilir) ve tatil haftaları boş geçer.
const int yillikKapsamToleransGun = 21;

/// Yıldan kısa seride "Son N ay" en az bu kadar ay ister; daha kısası
/// "yıllık" bir şey söylemez (zaten dönem aralığı çubuğu o kısa dönemi
/// gösteriyor).
const int yillikAsgariAy = 1;

/// Ortalama ay uzunluğu (gün) — kapsamı aya çevirmek için.
const double _ayGun = 30.44;

/// Serinin son bir yıldaki uçları — canlı fiyattan bağımsız kısım.
class YillikUclar {
  const YillikUclar({
    required this.dusuk,
    required this.yuksek,
    required this.sonDeger,
    this.ay,
  });

  /// Serinin en düşük / en yüksek değeri (canlı fiyat hariç).
  final double dusuk;
  final double yuksek;

  /// Serinin son noktası — canlı fiyat bilinmezse "bugün" bu sayılır.
  final double sonDeger;

  /// `null` = seri yılı kapsıyor ("Yıllık aralık"); sayı = seri yalnız son
  /// N ayı kapsıyor ("Son N ay").
  final int? ay;

  /// [seri]: zaman damgası (ms) → birim fiyat. [simdi] testte sabitlenir.
  static YillikUclar? hesapla(Map<int, double> seri, {required DateTime simdi}) {
    final pencereBasi = DateTime(simdi.year - 1, simdi.month, simdi.day)
        .millisecondsSinceEpoch;
    final simdiMs = simdi.millisecondsSinceEpoch;
    double? dusuk;
    double? yuksek;
    int? ilkTs;
    int? sonTs;
    double son = 0;
    for (final e in seri.entries) {
      final v = e.value;
      if (e.key < pencereBasi || e.key > simdiMs) continue;
      if (!v.isFinite || v <= 0) continue;
      dusuk = dusuk == null || v < dusuk ? v : dusuk;
      yuksek = yuksek == null || v > yuksek ? v : yuksek;
      if (ilkTs == null || e.key < ilkTs) ilkTs = e.key;
      if (sonTs == null || e.key >= sonTs) {
        sonTs = e.key;
        son = v;
      }
    }
    if (dusuk == null || yuksek == null || ilkTs == null || ilkTs == sonTs) {
      return null;
    }
    final kapsananGun = (simdiMs - ilkTs) / Duration.millisecondsPerDay;
    final yilGun = (simdiMs - pencereBasi) / Duration.millisecondsPerDay;
    int? ay;
    if (kapsananGun < yilGun - yillikKapsamToleransGun) {
      ay = (kapsananGun / _ayGun).floor();
      if (ay < yillikAsgariAy) return null;
    }
    return YillikUclar(dusuk: dusuk, yuksek: yuksek, sonDeger: son, ay: ay);
  }

  /// Canlı fiyatla aralık. Canlı fiyat aralığın dışındaysa (seri haftalık,
  /// bugün yeni zirve) uçlar onu kapsar — çubuktaki nokta yine içeride.
  YillikAralik? bugunle(double bugunkuFiyat) {
    final bugun =
        bugunkuFiyat.isFinite && bugunkuFiyat > 0 ? bugunkuFiyat : sonDeger;
    final d = bugun < dusuk ? bugun : dusuk;
    final y = bugun > yuksek ? bugun : yuksek;
    // Dip = zirve: "₺X — ₺X" hiçbir şey söylemez (dönem çubuğuyla aynı kural).
    if (y - d <= 1e-9 * y.abs()) return null;
    return YillikAralik(dusuk: d, yuksek: y, bugun: bugun, ay: ay);
  }
}

/// Ekrana giden aralık: uçlar, bugün ve konum.
class YillikAralik {
  const YillikAralik({
    required this.dusuk,
    required this.yuksek,
    required this.bugun,
    this.ay,
  });

  final double dusuk;
  final double yuksek;
  final double bugun;

  /// Bkz. [YillikUclar.ay].
  final int? ay;

  /// 0 = en düşük, 1 = en yüksek.
  double get konum => ((bugun - dusuk) / (yuksek - dusuk)).clamp(0.0, 1.0);

  /// Cümle hangi uca göre kurulur: yarının üstündeyse zirveden uzaklık
  /// ("en yükseğinin %8 altında"), altındaysa dipten ("en düşüğünün %12
  /// üstünde"). Yakın uç kullanıcının sorduğu şeydir.
  bool get yuksegeYakin => konum >= 0.5;

  /// Zirveden yüzde uzaklık (≥ 0).
  double get yuksektenUzaklikPct => (yuksek - bugun) / yuksek * 100;

  /// Dipten yüzde uzaklık (≥ 0).
  double get dusuktenUzaklikPct => (bugun - dusuk) / dusuk * 100;

  /// Yakın uca uzaklık ekranda (bir ondalıkla) %0,0 yazacak kadar küçükse
  /// cümle "en yükseğinde / en düşüğünde" der; "%0,0 altında" tuhaf okunur.
  bool get uctaMi =>
      (yuksegeYakin ? yuksektenUzaklikPct : dusuktenUzaklikPct) < 0.05;
}
