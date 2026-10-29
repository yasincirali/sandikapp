/// Yatay tam ekran grafikteki çizimden alarm (0170, yasin 2026-10-29:
/// *"Gösterge ya da çizgiye değdiğinde push gelmesi yapılabilir mi?"*).
///
/// Saf fonksiyonlar; ekran yalnız sonucu kullanır (CLAUDE.md "Katmanlama").
/// Testi `test/cizim_alarmi_test.dart`.
library;

import '../models/asset.dart';
import '../models/asset_type.dart' show alarmFiyatSimgesi;
import '../models/grafik_cizimi.dart';
import '../widgets/alarm_kur_sheet.dart' show alarmSembolu;

/// Grafiğin birimi ile alarmın birimi arasında izin verilen fark. Grafik
/// mumları canlı fiyata hizalı (`canliyaHizala`); TL kote sembolde
/// `canliBirim` ile `Asset.currentPrice` aynı sayıdır. %2'den büyük fark
/// birimlerin ayrı olduğunu söyler (ör. grafik başka ölçekte) → alarm sunulmaz.
const double kCizimBirimToleransi = 0.02;

/// Bu grafikteki çizimden alarm kurulabilirse alarmın sembolü; yoksa `null`.
///
/// ## Neden yalnız TL kote sembol
/// Çizimin fiyatı GRAFİĞİN birimindedir: mumlar TL'ye çevrilip canlı TL
/// fiyata hizalanır ([TamEkranGrafikEkrani.canliBirim] = birim başı TL).
/// Fiyat alarmını ise sunucu sembolün KENDİ kotasyonuyla karşılaştırır
/// (ABD hissesi dolar, EURUSD dolar, endeks puan). TL kote olmayan bir
/// sembolde çizginin TL fiyatını alarma yazmak uydurma bir hedef olurdu;
/// çizimi bugünkü kurla çevirmek de kur oynadıkça çizgiden kayar. Bu yüzden
/// yalnız alarm fiyatı TL olan semboller ([alarmFiyatSimgesi] `₺`: BIST,
/// altın, TL döviz, fon, kripto) — kalanında "Alarm kur" hiç görünmez.
///
/// Ek güvence: varlığın bilinen fiyatı ([Asset.currentPrice]) grafiğin canlı
/// birimiyle [kCizimBirimToleransi] içinde uyuşmalı (bilinmiyorsa — takip
/// listesinden açılan gözlem varlığı — sembol kuralı yeter).
String? cizimAlarmSembolu(Asset varlik, double canliBirim) {
  if (varlik.isManualPrice) return null;
  final sembol = alarmSembolu(varlik.ticker, varlik.subCategory);
  if (sembol == null || alarmFiyatSimgesi(sembol) != '₺') return null;
  if (varlik.currency.trim().toUpperCase() != 'TRY') return null;
  final bilinen = varlik.currentPrice;
  if (bilinen > 0 && canliBirim > 0 &&
      ((canliBirim / bilinen) - 1).abs() > kCizimBirimToleransi) {
    return null;
  }
  return sembol;
}

/// Sunucuya yazılan doğru: (t1, p1) → (t2, p2), duvar saatiyle doğrusal.
typedef CizimDogrusu = ({int t1, double p1, int t2, double p2, bool uzanir});

/// Neden bir çizimden çizgi alarmı kurulamadı (kullanıcıya söylenir).
enum CizimAlarmEngeli {
  /// Trend çizgisi geçmişte bitti: "değdi" denecek yer kalmadı.
  bitti,

  /// Işın geçmişe doğru uzanıyor ya da dikey.
  yonsuz,

  /// Doğru sıfırın altına iniyor (fiyat orada olamaz).
  gecersiz,
}

/// Trend çizgisi / ışını, "şu andan sonra grafikte görünen doğru"ya çevirir.
///
/// ## Neden dönüşüm (grafikle aynı doğru)
/// Grafik geçmişi MUM İNDEKSİYLE çizer (hafta sonu, gece yer kaplamaz),
/// son mumdan sonrasını ise mum süresi ([aralikMs]) adımıyla — yani duvar
/// saatine göre doğrusal — uzatır (`GrafikOlcegi.zamanIndeksi`). Çizginin
/// eğimi bu yüzden "mum başına" sabittir; sunucuya zamana göre eğim yazmak
/// için şu anki konum ve mum başı eğim [aralikMs]'ye bölünür. Alarm hep
/// "şimdi ve sonrası"nı sorduğu için yalnız bu bölge yeter. Bilinen sınır:
/// seans dışı saatler (gece, hafta sonu) geldiğinde grafik onları sıkıştırır,
/// alarm sıkıştırmaz — gün içi aralıkta çizilen dik bir ışın birkaç gün
/// sonra grafikteki çizgiden ayrışabilir (bildirim seviyenin sayısını yazar).
///
/// [indeks] grafiğin zaman → mum indeksi eşlemesi (`zamanIndeksi`).
/// Sonuç ya doğru ya engel; kutu ve yatay türler buraya gelmez (`null`).
({CizimDogrusu? dogru, CizimAlarmEngeli? engel})? cizimAlarmDogrusu(
  GrafikCizimi c, {
  required double Function(int t) indeks,
  required int aralikMs,
  required int simdiMs,
}) {
  if (c.tur != CizimTuru.trend && c.tur != CizimTuru.isin) return null;
  final b = c.b;
  if (b == null || aralikMs <= 0) return (dogru: null, engel: CizimAlarmEngeli.yonsuz);
  final ia = indeks(c.a.t), ib = indeks(b.t);
  if (!ia.isFinite || !ib.isFinite || (ib - ia).abs() < 1e-9) {
    return (dogru: null, engel: CizimAlarmEngeli.yonsuz);
  }
  final egim = (b.p - c.a.p) / (ib - ia); // mum başına
  double deger(double i) => c.a.p + egim * (i - ia);
  final simdiI = indeks(simdiMs);

  final int t1;
  final double i1;
  final int t2;
  final double p2;
  final bool uzanir;
  if (c.tur == CizimTuru.isin) {
    // Işın a'dan b yönüne uzar; geçmişe doğru bakan ışın gelecekte yoktur.
    if (ib < ia) return (dogru: null, engel: CizimAlarmEngeli.yonsuz);
    final basladi = simdiI >= ia;
    i1 = basladi ? simdiI : ia;
    t1 = basladi ? simdiMs : c.a.t;
    t2 = t1 + aralikMs;
    p2 = deger(i1) + egim;
    uzanir = true;
  } else {
    final sol = ia <= ib ? c.a : b;
    final sag = ia <= ib ? b : c.a;
    final solI = ia <= ib ? ia : ib, sagI = ia <= ib ? ib : ia;
    if (simdiI >= sagI) return (dogru: null, engel: CizimAlarmEngeli.bitti);
    final basladi = simdiI >= solI;
    i1 = basladi ? simdiI : solI;
    t1 = basladi ? simdiMs : sol.t;
    t2 = sag.t;
    p2 = sag.p;
    uzanir = false;
    if (t2 <= t1) return (dogru: null, engel: CizimAlarmEngeli.bitti);
  }
  final p1 = deger(i1);
  if (!(p1 > 0) || !(p2 > 0) || !p1.isFinite || !p2.isFinite) {
    return (dogru: null, engel: CizimAlarmEngeli.gecersiz);
  }
  return (
    dogru: (t1: t1, p1: p1, t2: t2, p2: p2, uzanir: uzanir),
    engel: null,
  );
}

/// Çizimin biçim imzası: alarm kurulduğu andaki çizimle bugünkü çizim farklı
/// mı (taşındı mı). Kimlik girmez, yalnız biçim.
String cizimImzasi(GrafikCizimi c) => [
      c.tur.name,
      c.a.t,
      c.a.p,
      c.b?.t ?? '',
      c.b?.p ?? '',
    ].join('|');
