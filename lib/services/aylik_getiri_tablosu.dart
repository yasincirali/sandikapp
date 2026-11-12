import 'package:flutter/foundation.dart' show compute, immutable, kIsWeb;

import '../models/asset.dart';
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

  const AylikGetiriTablosu({
    required this.aylar,
    required this.yilToplami,
    required this.ilkAy,
    required this.buAy,
    required this.olculenAySayisi,
  });

  /// Ay tablonun aralığında mı (ilk alım ayı ≤ ay ≤ bu ay). Aralık dışı
  /// hücre boş çizilir, aralık içinde ölçümsüz hücre "—".
  bool aralikta(int yil, int ay) {
    final a = DateTime(yil, ay);
    return !a.isBefore(ilkAy) && !a.isAfter(buAy);
  }

  /// Yıllar yeniden eskiye (en güncel yıl üstte).
  List<int> get yillar => aylar.keys.toList()..sort((a, b) => b - a);
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
    final int? tabanTs =
        (i > 0 && ts[i - 1] >= oncekiAyMs) ? ts[i - 1] : null;
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
