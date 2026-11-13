import 'package:flutter/foundation.dart' show compute, immutable, kIsWeb;

import '../models/asset.dart';
import 'inflation_service.dart';
import 'period_summary_service.dart';

/// Aylık getiri tablosu (yıl × ay) — Performans'ın "hangi ay kazandım,
/// hangi ay kaybettim" kartının hesabı (2026-11-11, Premium).
///
/// ## Yeni formül YOK: hücre = dönem özetinin getirisi
/// Her hücre `PeriodSummaryService.piyasaEtkisi(...).pct`tir — Özet'in
/// "Paranın getirisi" yüzdesi (para ağırlıklı, akıştan arındırılmış, payda
/// ortalama sermaye). Ayın içinde para eklemek ya da çekmek yüzdeyi
/// şişirmez/ezmez; bu kural tek yerde durur, tablo onu ay sınırlarında
/// çağırır. Ayrı bir "aylık getiri" formülü yazılsaydı aynı ay Özet'in
/// 1A'sında bir sayı, tabloda başka sayı söylerdi.
///
/// ## Ay penceresi: önceki ayın son ölçümü → ayın son ölçümü
/// Taban, ayın 1'inden ÖNCEKİ son slottur (günlük seride önceki ayın son
/// günü; TÜFE penceresi `seriBaslangici` ile aynı hiza). Ardışık aylar
/// böylece ucu PAYLAŞIR: zincir boşluksuz, ayın ilk gününün hareketi hiçbir
/// aydan düşmez ve yıl bileşiği ölçülen zamanın tamamını kapsar. Taban
/// ayın 1'inden seçilseydi (aylık rapor penceresi) her ay bir günü
/// kaybederdi; tek ayı okuyan rapor için önemsiz, on iki ayı zincirleyen
/// tabloda yılda on iki gün eder.
///
/// Taban önceki aydan da eskiyse (seride delik) zincir kurulmaz: ay kendi
/// ilk ölçümünden başlar. Aksi halde ölçülmemiş haftalar bu ayın hanesine
/// yazılırdı.
///
/// ## Uydurma yok
/// - İçinde ölçüm olmayan ay `null` ("—").
/// - Kullanıcının ilk alımından önceki aylar tabloda hiç yoktur (boş).
/// - Yıl toplamı, o yılın ölçüm aralığındaki HER ay biliniyorsa bileşik
///   (`Π(1 + r) − 1`); arada bir ay bilinmiyorsa `null`. Eksik ayı sıfır
///   sayıp çarpmak, olmamış bir yıl yüzdesi üretirdi.
///
/// ## Yıl toplamı neden bileşik, neden Özet'in 1Y'si değil
/// Tablo satırı on iki hücreyi okur; son sütun o hücrelerin toplamını
/// söylemeli (kullanıcı hücreleri çarpınca aynı sayıyı bulur). Özet'in
/// para ağırlıklı 1Y getirisi akış zamanlamasını yıl ölçeğinde tartar ve
/// bu bileşikten ayrışabilir; ikisi farklı soruların cevabıdır, tablo
/// kendi satırıyla tutarlı kalır.
@immutable
class AylikGetiriTablosu {
  /// Yıl → 12 hücre (Ocak..Aralık), yüzde. `null`: ölçüm yok ya da ay
  /// tablonun aralığı dışında (ilk alımdan önce / gelecek) — ayrımı
  /// [aralikta] yapar.
  final Map<int, List<double?>> aylar;

  /// Yıl → bileşik yıl getirisi (yüzde); bilinmeyen ay varsa `null`.
  final Map<int, double?> yilToplami;

  /// Tablonun ilk ayı (ilk alımın ayı) ve içinde bulunulan ay; ikisi de
  /// ayın 1'i.
  final DateTime ilkAy;
  final DateTime buAy;

  /// Getirisi ölçülen ay sayısı — kart en az 6 ayda görünür.
  final int olculenAySayisi;

  /// Yıl → aynı ayların TÜFE'si ve reel getiri ([aylikGetiriYilReelleri]).
  /// Yalnız TÜFE'si eksiksiz bilinen yıllar; boşsa yıl satırı yalnız
  /// getiriyi yazar.
  final Map<int, AylikGetiriYilReeli> yilReeli;

  // `const` değil: [ozet] tembel ve bir kez hesaplanır (aşağıda).
  AylikGetiriTablosu({
    required this.aylar,
    required this.yilToplami,
    required this.ilkAy,
    required this.buAy,
    required this.olculenAySayisi,
    this.yilReeli = const {},
  });

  /// Aynı tablo, yıl satırlarının TÜFE/reel bilgisiyle. Tablo hesabı
  /// (isolate'e gidebilen saf iş) TÜFE'yi beklemez; provider endeksi
  /// ayrıca okuyup buradan ekler.
  AylikGetiriTablosu reelIle(Map<int, AylikGetiriYilReeli> reel) =>
      AylikGetiriTablosu(
        aylar: aylar,
        yilToplami: yilToplami,
        ilkAy: ilkAy,
        buAy: buAy,
        olculenAySayisi: olculenAySayisi,
        yilReeli: reel,
      );

  /// Ay tablonun aralığında mı (ilk alım ayı ≤ ay ≤ bu ay). Aralık dışı
  /// hücre boş çizilir, aralık içinde ölçümsüz hücre "—".
  bool aralikta(int yil, int ay) {
    final a = DateTime(yil, ay);
    return !a.isBefore(ilkAy) && !a.isAfter(buAy);
  }

  /// Yıllar yeniden eskiye (en güncel yıl üstte).
  List<int> get yillar => aylar.keys.toList()..sort((a, b) => b - a);

  /// Kartın alt cümlesi ve iki çerçeveli hücresi ([aylikGetiriOzeti]).
  /// Tembel ve tablo başına bir kez: Performans her tick'te yeniden
  /// çizilir, özet tablo değişmedikçe yeniden taranmaz (hesap `build`'de
  /// değil, modelde).
  late final AylikGetiriOzeti? ozet = aylikGetiriOzeti(this);
}

/// Yıl satırının enflasyon parçası: "· TÜFE %31,0 · reel ▼%14,2".
@immutable
class AylikGetiriYilReeli {
  const AylikGetiriYilReeli({required this.tufe, required this.reel});

  /// O yılın tabloda ölçülen aylarının zincirlenmiş TÜFE'si (yüzde).
  final double tufe;

  /// `(1 + getiri) / (1 + tüfe) − 1`, yüzde.
  final double reel;
}

/// Her yılın TÜFE'si ve reel getirisi (2026-11-12). [endeks]:
/// `InflationService.indexSeries()` (ay başı → TÜFE endeksi; uygulamanın
/// tek TÜFE kaynağı, yeni ağ yok).
///
/// ## Aynı aylar, zincir çarpım
/// Yıl toplamı o yılın tabloda ölçülen aylarının bileşiğidir (kısmi yılda
/// ilk alımın ayından, içinde bulunulan yılda bu aya kadar). TÜFE de
/// TAM o aylardan kurulur: her ayın TÜFE'si `endeks[ay] / endeks[ay−1]`,
/// yıl `Π` — hücre penceresi (önceki ayın sonu → ayın sonu) TÜİK'in aylık
/// değişimiyle aynı hiza. Takvim yılının TÜFE'si kullanılsaydı Haziran'da
/// başlayan kullanıcının yedi aylık getirisi on iki aylık enflasyonla
/// kıyaslanırdı.
///
/// ## Uydurma yok
/// Aylardan birinin (ya da bir önceki ayın) endeksi yoksa yıl HİÇ
/// yazılmaz; eksik ayı sıfır enflasyon saymak reeli şişirirdi. İçinde
/// bulunulan ayın TÜFE'si henüz açıklanmadığı için bu yıl satırı reel
/// yazmaz (açıklanınca kendiliğinden gelir). Yıl toplamı `null`sa da yok:
/// kıyaslanacak getiri yok.
Map<int, AylikGetiriYilReeli> aylikGetiriYilReelleri(
    AylikGetiriTablosu tablo, Map<DateTime, double> endeks) {
  final sonuc = <int, AylikGetiriYilReeli>{};
  if (endeks.isEmpty) return sonuc;
  for (final yil in tablo.aylar.keys) {
    final getiri = tablo.yilToplami[yil];
    if (getiri == null) continue;
    // Tablonun bu yıldaki aralığı bitişiktir (ilk alım ayı → bu ay);
    // zincir ilk ayın öncesinden son aya, delik denetimi ortak yardımcıda
    // (`InflationService.zincirliDegisimPct`; elde tutma satırı da onu
    // kullanır).
    int? ilk;
    int? son;
    for (var m = 1; m <= 12; m++) {
      if (!tablo.aralikta(yil, m)) continue;
      ilk ??= m;
      son = m;
    }
    if (ilk == null || son == null) continue;
    final tufe = InflationService.zincirliDegisimPct(
        endeks, DateTime(yil, ilk - 1), DateTime(yil, son));
    if (tufe == null) continue;
    final reel = InflationService.realReturnPct(getiri, tufe);
    if (!tufe.isFinite || !reel.isFinite) continue;
    sonuc[yil] = AylikGetiriYilReeli(tufe: tufe, reel: reel);
  }
  return sonuc;
}

/// Tablodaki tek ay ve getirisi (yüzde).
@immutable
class AylikGetiriAyi {
  const AylikGetiriAyi(this.yil, this.ay, this.deger);
  final int yil;
  final int ay;
  final double deger;

  bool ayni(int yil, int ay) => this.yil == yil && this.ay == ay;
}

/// Kartın alt cümlesi (2026-11-12): "20 ayın 14'ünü artıda kapattın. En
/// iyi ay Tem 2026 ▲%6,4, en zor Eki 2025 ▼%6,1." ve çerçeveli iki hücre.
///
/// ## Neden kapanmış aylar
/// İçinde bulunulan ay sayılmaz: ayın 3'ünde "bu ay"ın %−4'ü "en zor ay"
/// ilan edilir, ay sonunda artıda kapanabilir. Cümle "kapattın" der, yalnız
/// biten ayları sayar; tablo hücresi o ayı yine gösterir ("bu ay").
///
/// ## Neden `aylikKiyas` değil
/// Aylık raporun kıyası TEK bir ayı son 12 ay içinde sıralar ("bu ay 9.
/// sırada"); burada soru tablonun tamamı: kaç ay artı, uçlar hangisi.
/// Aynı hücreleri okurlar; "artı" ikisinde de sıfırın üstü.
@immutable
class AylikGetiriOzeti {
  const AylikGetiriOzeti({
    required this.kapanan,
    required this.arti,
    required this.enIyi,
    required this.enZor,
  });

  /// Getirisi ölçülmüş, kapanmış ay sayısı.
  final int kapanan;

  /// Sıfırın üstünde kapanan ay sayısı.
  final int arti;

  final AylikGetiriAyi enIyi;

  /// `null`: tek ay var ya da bütün aylar eşit — "en zor" en iyiyle aynı
  /// hücre olurdu.
  final AylikGetiriAyi? enZor;
}

/// [tablo]'nun özeti; kapanmış ölçülü ay yoksa `null`. Eşit değerlerde
/// en yeni ay seçilir (kullanıcının hatırladığı ay).
AylikGetiriOzeti? aylikGetiriOzeti(AylikGetiriTablosu tablo) {
  AylikGetiriAyi? iyi, zor;
  var kapanan = 0, arti = 0;
  final yillar = tablo.aylar.keys.toList()..sort();
  for (final yil in yillar) {
    final hucreler = tablo.aylar[yil]!;
    for (var m = 1; m <= 12; m++) {
      if (!tablo.aralikta(yil, m)) continue;
      if (tablo.buAy.year == yil && tablo.buAy.month == m) continue;
      final d = hucreler[m - 1];
      if (d == null) continue;
      kapanan++;
      if (d > 0) arti++;
      final a = AylikGetiriAyi(yil, m, d);
      if (iyi == null || d >= iyi.deger) iyi = a;
      if (zor == null || d <= zor.deger) zor = a;
    }
  }
  if (iyi == null || zor == null) return null;
  return AylikGetiriOzeti(
    kapanan: kapanan,
    arti: arti,
    enIyi: iyi,
    enZor: zor.deger == iyi.deger ? null : zor,
  );
}

/// Kartın görünme eşiği: en az bu kadar ayın getirisi ölçülmüş olmalı.
/// Daha kısa geçmişte tablo birkaç hücreden ibaret kalır; dönem çipleri o
/// soruyu zaten cevaplar.
const int aylikGetiriAsgariAy = 6;

/// Ücretsiz kullanıcıya kilitli önizleme gösterilsin mi: ilk alımın ayından
/// bu aya en az [aylikGetiriAsgariAy] ay var. Kilitliyken seri çekilmez
/// (Premium olmayan için beş yıllık seri indirmek boşa ağ); eşik bu yüzden
/// defterden, ölçülen aydan değil. Seri delikli bir defterde önizleme
/// görünüp açılınca kart eşiği tutmayabilir — kilit satırı bir vaat değil,
/// özelliğin adıdır.
bool aylikGetiriOnizlemesiGorunur(List<Asset> lotlar, DateTime simdi) =>
    aylikGetiriAralikAySayisi(lotlar, simdi) >= aylikGetiriAsgariAy;

/// Tablonun aralığındaki ay sayısı: ilk alımın ayından bu aya, ikisi dahil
/// (`AylikGetiriTablosu.aralikta` ile aynı aralık). Seri çekmeden,
/// defterden. Satın alma sonrası sayfa "Aylık getiri tablon: n ay"
/// satırını buradan yazar; beş yıllık seriyi o sayfa için indirmek
/// sayfayı bekletirdi. İlk alım yoksa 0.
int aylikGetiriAralikAySayisi(List<Asset> lotlar, DateTime simdi) {
  final ilk = PeriodSummaryService.ilkAlimTarihi(lotlar);
  if (ilk == null) return 0;
  return (simdi.year * 12 + simdi.month) - (ilk.year * 12 + ilk.month) + 1;
}

/// Tablonun hazır olacağı ay: aralığın [aylikGetiriAsgariAy]'ıncı ayı
/// (ilk alımın ayı + 5). İlk alım yoksa `null`.
///
/// Kart kısa geçmişte "Şubat'ta hazır" der (2026-11-12). İçinde bulunulan
/// ay da ölçülen aylara sayılır (bugüne kadar), bu yüzden tablo o ayın
/// SONUNU beklemez, o ay girince açılır; cümlenin ayı budur. Seri
/// gerekmez: aralık defterden ([aylikGetiriAralikAySayisi] ile aynı uç).
DateTime? aylikGetiriHazirAyi(List<Asset> lotlar) {
  final ilk = PeriodSummaryService.ilkAlimTarihi(lotlar);
  if (ilk == null) return null;
  return DateTime(ilk.year, ilk.month + aylikGetiriAsgariAy - 1);
}

/// Saf hesap. [seri]: portföy toplam serisi (ts → TRY; Özet'in serisiyle
/// aynı motor). [lotlar]: akış defteri (Özet'in `targetAssets`'i).
/// [simdi]: içinde bulunulan ay "bu ay" olarak bugüne kadar ölçülür.
/// İlk alım yoksa `null`.
AylikGetiriTablosu? aylikGetiriTablosu({
  required Map<int, double> seri,
  required List<Asset> lotlar,
  required DateTime simdi,
}) {
  final ilkAlim = PeriodSummaryService.ilkAlimTarihi(lotlar);
  if (ilkAlim == null) return null;
  final ilkAy = DateTime(ilkAlim.year, ilkAlim.month);
  final buAy = DateTime(simdi.year, simdi.month);
  if (ilkAy.isAfter(buAy)) return null;

  // Anahtarlar bir kez sıralanır; her ay yalnız kendi dilimini
  // `piyasaEtkisi`'ne verir (o da `uclar` içinde dilimi sıralar). Tüm
  // seriyi her ay yeniden sıralamak 60 ayda 60 tam sıralama ederdi.
  final ts = [
    for (final e in seri.entries)
      if (e.value > 0) e.key
  ]..sort();

  final aylar = <int, List<double?>>{};
  var olculen = 0;
  for (var ay = ilkAy;
      !ay.isAfter(buAy);
      ay = DateTime(ay.year, ay.month + 1)) {
    final hucreler =
        aylar.putIfAbsent(ay.year, () => List<double?>.filled(12, null));
    final basMs = ay.millisecondsSinceEpoch;
    final suren = ay == buAy;
    final son = suren ? simdi : DateTime(ay.year, ay.month + 1, 0, 23, 59, 59);
    final sonMs = son.millisecondsSinceEpoch;
    final oncekiAyMs = DateTime(ay.year, ay.month - 1).millisecondsSinceEpoch;

    // Taban: ayın 1'inden önceki son slot, önceki ayın içindeyse.
    final i = _ilkBuyukEsit(ts, basMs);
    final int? tabanTs = (i > 0 && ts[i - 1] >= oncekiAyMs) ? ts[i - 1] : null;
    // Ay içinde en az bir ölçüm şart: yoksa ay "—".
    if (i >= ts.length || ts[i] > sonMs) continue;
    final dilimBas = tabanTs ?? ts[i];
    final dilim = <int, double>{
      for (var k = tabanTs == null ? i : i - 1;
          k < ts.length && ts[k] <= sonMs;
          k++)
        ts[k]: seri[ts[k]]!,
    };
    final pe = PeriodSummaryService.piyasaEtkisi(
      seri: dilim,
      lotlar: lotlar,
      start: DateTime.fromMillisecondsSinceEpoch(dilimBas),
      end: son,
    );
    final pct = pe?.pct;
    if (pct == null || !pct.isFinite) continue;
    hucreler[ay.month - 1] = pct;
    olculen++;
  }

  bool aralikta(int yil, int ay) {
    final a = DateTime(yil, ay);
    return !a.isBefore(ilkAy) && !a.isAfter(buAy);
  }

  return AylikGetiriTablosu(
    aylar: aylar,
    yilToplami: {
      for (final yil in aylar.keys)
        yil: _yilBilesigi(aylar[yil]!, (m) => aralikta(yil, m)),
    },
    ilkAy: ilkAy,
    buAy: buAy,
    olculenAySayisi: olculen,
  );
}

double? _yilBilesigi(List<double?> hucreler, bool Function(int ay) aralikta) {
  var carpan = 1.0;
  var herhangi = false;
  for (var m = 1; m <= 12; m++) {
    if (!aralikta(m)) continue;
    final r = hucreler[m - 1];
    if (r == null) return null;
    carpan *= 1 + r / 100;
    herhangi = true;
  }
  if (!herhangi) return null;
  final v = (carpan - 1) * 100;
  return v.isFinite ? v : null;
}

int _ilkBuyukEsit(List<int> ts, int hedef) {
  var lo = 0, hi = ts.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (ts[mid] < hedef) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Bu iş büyüklüğünün (ay × lot) altında hesap senkron koşar.
///
/// Seri birleştirmenin eşiğiyle aynı desen ve aynı büyüklük
/// (`portfoyBirlesimIsolateEsigi`): her ay `piyasaEtkisi` defteri birkaç
/// kez tarar (katkı, temettü, akış kümesi). 5 yıllık × 500 lotluk defter
/// 30.000 adımı geçer; orada hesap isolate'e gider ki Performans'ın dönem
/// geçişi takılmasın. Küçük girdide isolate kurma + defteri kopyalama
/// kazancı aşar.
const int aylikGetiriIsolateEsigi = 30000;

typedef _Girdi = ({Map<int, double> seri, List<Asset> lotlar, DateTime simdi});

AylikGetiriTablosu? _girdidenHesapla(_Girdi g) =>
    aylikGetiriTablosu(seri: g.seri, lotlar: g.lotlar, simdi: g.simdi);

/// [aylikGetiriTablosu]'nun ana iş parçacığını uzun tutmayan sarmalı.
/// Sonuç iki yolda birebir aynıdır (aynı saf fonksiyon).
Future<AylikGetiriTablosu?> aylikGetiriTablosuHesapla({
  required Map<int, double> seri,
  required List<Asset> lotlar,
  required DateTime simdi,
}) async {
  final g = (seri: seri, lotlar: lotlar, simdi: simdi);
  final ilk = PeriodSummaryService.ilkAlimTarihi(lotlar) ?? simdi;
  final aySayisi =
      (simdi.year * 12 + simdi.month) - (ilk.year * 12 + ilk.month) + 1;
  // Web'de isolate yok (`compute` orada da senkron); eşik altı senkron.
  if (kIsWeb || aySayisi * lotlar.length < aylikGetiriIsolateEsigi) {
    return _girdidenHesapla(g);
  }
  return compute(_girdidenHesapla, g);
}

/// Uzun seri: eski kısım haftalık, son yıl günlük çözünürlükten.
///
/// `HistoryService`'in günlük katmanı bir yıl geriye iner (Yahoo `1y`);
/// daha eskisi yalnız haftalık. Tablo ay sınırlarını olabildiğince doğru
/// görmeli: günlük seri nerede başlıyorsa oradan sonrası günlük, öncesi
/// haftalık. Değerler aynı motordan geldiği için ölçekleri aynıdır.
Map<int, double> uzunSeriyiBirlestir({
  required Map<int, double> haftalik,
  required Map<int, double> gunluk,
}) {
  final gunlukDolu = [
    for (final e in gunluk.entries)
      if (e.value > 0) e.key
  ];
  if (gunlukDolu.isEmpty) return haftalik;
  final sinir = gunlukDolu.reduce((a, b) => a < b ? a : b);
  return {
    for (final e in haftalik.entries)
      if (e.key < sinir) e.key: e.value,
    ...gunluk,
  };
}

/// Aylık raporun kişisel kıyas satırı (2026-11-12, Ar-Ge 12 Kas #7):
/// "Son 12 ayda 8 ay artıdaydın; bu ay 12 ay içinde 9. sırada".
///
/// ## Neden
/// Rapor ayı tek başına anlatıyordu; düşüş ayında kullanıcı o ayı tek
/// gerçek sanar. Kendi geçmişiyle bağlam (başkasıyla kıyas değil) kayıptan
/// kaçınmayı yumuşatır, iyi ayda da ilerlemeyi gösterir. Satır renk
/// taşımaz, cümle taşır.
///
/// ## Yeni formül YOK
/// Hücreler [AylikGetiriTablosu]'nun (Performans'ın aylık getiri kartı)
/// kendisi. Pencere: [donem] dahil geriye 12 takvim ayı; ölçülmeyen ay
/// sayılmaz, cümlenin "son N ay"ı ölçülen ay sayısıdır.
@immutable
class AylikKiyas {
  const AylikKiyas({
    required this.olculen,
    required this.arti,
    required this.sira,
    required this.enIyi,
    required this.enZayif,
  });

  /// Penceredeki ölçülen ay sayısı (≤ 12).
  final int olculen;

  /// Getirisi sıfırın üstünde kapanan ay sayısı.
  final int arti;

  /// Bu ayın sırası: 1 + kendisinden yüksek ay sayısı (eşitler aynı sıra).
  final int sira;
  final bool enIyi;

  /// Kendisinden düşük ay yok (ve en iyi değil).
  final bool enZayif;
}

/// [tablo]'dan [donem]'in kıyası. `null`: ayın hücresi yok ya da penceredeki
/// ölçülen ay [aylikGetiriAsgariAy]'dan az (kart eşiğiyle aynı; birkaç
/// aylık sıra bir şey söylemez).
AylikKiyas? aylikKiyas(AylikGetiriTablosu tablo, DateTime donem) {
  double? hucre(DateTime a) {
    if (!tablo.aralikta(a.year, a.month)) return null;
    final yil = tablo.aylar[a.year];
    return yil == null ? null : yil[a.month - 1];
  }

  final bu = hucre(donem);
  if (bu == null) return null;
  final degerler = <double>[
    for (var i = 0; i < 12; i++)
      if (hucre(DateTime(donem.year, donem.month - i)) case final v?) v,
  ];
  if (degerler.length < aylikGetiriAsgariAy) return null;
  final yuksek = degerler.where((v) => v > bu).length;
  final dusuk = degerler.where((v) => v < bu).length;
  return AylikKiyas(
    olculen: degerler.length,
    arti: degerler.where((v) => v > 0).length,
    sira: yuksek + 1,
    enIyi: yuksek == 0,
    enZayif: yuksek > 0 && dusuk == 0,
  );
}
