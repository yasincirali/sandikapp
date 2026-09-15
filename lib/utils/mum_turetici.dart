/// Mum (candlestick) türetici — tek değerli bir seriden OHLC kovaları.
///
/// ## Neden türetiliyor, çekilmiyor
/// Portföy serisi her zaman dilimi için TEK değer tutar (`Map<int, double>`:
/// o andaki toplam portföy değeri). Bir portföyün "açılış / en yüksek / en
/// düşük / kapanış"ı hiçbir sağlayıcıdan gelmez; ancak elimizdeki noktaları
/// zaman kovalarına bölüp her kovanın ilk / en büyük / en küçük / son
/// değerini alarak ÜRETİLİR. Bu, TradingView'in daha kaba bir zaman
/// diliminde çizdiği mumla aynı cebirdir (5 dk'lık barlardan 30 dk'lık mum).
///
/// ## Dürüstlük sınırı
/// Kova içindeki en yüksek/en düşük, kovadaki NOKTALARIN uçlarıdır — iki
/// nokta arasında yaşanmış ama örneklenmemiş bir tepe görünmez. Gün içi
/// 5 dk'lık örnekleme için bu fark ihmal edilebilir; günlük kapanışlardan
/// haftalık mum türetildiğinde ise mumun fitili günlük kapanışların uçlarıdır,
/// gün içi uçlar değil. Menüdeki etiket bu yüzden "Mum" — "OHLC" değil.
///
/// ## Kova seçimi
/// Amaç ~[hedefAdet] mum, her mumda en az [asgariNokta] nokta. Kova
/// "hoş" boyutlardan seçilir (5 dk … 1 ay) ki mumlar takvimle hizalansın:
/// 30 dk'lık mum :00 ve :30'da başlar, günlük mum gece yarısında, haftalık
/// mum Pazartesi'de. Kova hizası [kovaBaslangici] ile yerel saatte alınır.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

import 'tr_format.dart';

/// Tek bir mum. [x] kovanın BAŞLANGIÇ anı (ms) — çubuk gibi sola hizalı
/// değil, kova ortasına çizilir (bkz. [merkezX]).
class Mum {
  const Mum({
    required this.x,
    required this.kovaMs,
    required this.acilis,
    required this.enYuksek,
    required this.enDusuk,
    required this.kapanis,
    required this.noktaSayisi,
  });

  final double x;
  final double kovaMs;
  final double acilis;
  final double enYuksek;
  final double enDusuk;
  final double kapanis;
  final int noktaSayisi;

  double get merkezX => x + kovaMs / 2;
  bool get yukselen => kapanis >= acilis;
  bool get doji => (kapanis - acilis).abs() < 1e-12;
}

const double _dk = 60 * 1000;
const double _saat = 60 * _dk;
const double _gun = 24 * _saat;

/// Takvimle hizalanabilen kova boyutları (ms), küçükten büyüğe.
///
/// 1 ay için 30 gün kullanılıyor: `mumlariTuret` aylık kovayı takvim ayına
/// oturtur (aşağıya bak); bu sayı yalnızca SEÇİM eşiği.
const List<double> mumKovaAdaylari = [
  5 * _dk,
  15 * _dk,
  30 * _dk,
  1 * _saat,
  2 * _saat,
  4 * _saat,
  1 * _gun,
  7 * _gun,
  30 * _gun,
];

/// Görünen aralık ve nokta sayısına göre kova (ms).
///
/// Kural: kova en az `asgariNokta × ortalamaAralık` olmalı (tek noktalı mum
/// düz bir çizgi = bilgi yok); bu eşiği geçen adaylar arasından
/// `span / hedefAdet`'e LOGARİTMİK olarak en yakın olan seçilir. "İlk büyük
/// aday" kuralı 1 günlük 288 noktayı 1 saate (24 mum) atıyordu; 30 dk (48
/// mum) 36 dk'lık hedefe daha yakın. Aralık ya da nokta yoksa en küçük aday.
double mumKovasiSec({
  required double spanMs,
  required int noktaSayisi,
  int hedefAdet = 40,
  int asgariNokta = 2,
}) {
  if (!spanMs.isFinite || spanMs <= 0 || noktaSayisi <= 0) {
    return mumKovaAdaylari.first;
  }
  final ortalamaAralik = spanMs / noktaSayisi;
  final asgariKova = asgariNokta * ortalamaAralik;
  final hedefKova = spanMs / hedefAdet;

  double? secilen;
  double enIyiFark = double.infinity;
  for (final aday in mumKovaAdaylari) {
    if (aday < asgariKova) continue;
    final fark = (math.log(aday) - math.log(hedefKova)).abs();
    if (fark < enIyiFark) {
      enIyiFark = fark;
      secilen = aday;
    }
  }
  return secilen ?? mumKovaAdaylari.last;
}

/// Kovanın YEREL takvime hizalı başlangıcı.
///
/// Gün ve altı: gün başından itibaren kova katları (30 dk → :00/:30; 4 sa →
/// 00/04/08…). Hafta: Pazartesi 00:00. Ay: ayın 1'i. Yerel saat, çünkü
/// kullanıcı grafiği yerel saatle okuyor ve gün içi mumlar seans saatleriyle
/// hizalanmalı.
DateTime kovaBaslangici(DateTime t, double kovaMs) {
  final gunBasi = dayKey(t);
  if (kovaMs >= 30 * _gun) return DateTime(t.year, t.month, 1);
  if (kovaMs >= 7 * _gun) {
    // weekday: Pazartesi = 1.
    return gunBasi.subtract(Duration(days: t.weekday - 1));
  }
  if (kovaMs >= _gun) return gunBasi;
  final gunIciMs = t.difference(gunBasi).inMilliseconds.toDouble();
  final kat = (gunIciMs / kovaMs).floor();
  return gunBasi.add(Duration(milliseconds: (kat * kovaMs).round()));
}

/// Kovanın bitişi (bir sonraki kovanın başlangıcı).
DateTime kovaBitisi(DateTime baslangic, double kovaMs) {
  if (kovaMs >= 30 * _gun) {
    return DateTime(baslangic.year, baslangic.month + 1, 1);
  }
  return baslangic.add(Duration(milliseconds: kovaMs.round()));
}

/// Noktaları (x = epoch ms, y = değer) mumlara böler.
///
/// Girdi x'e göre artan olmalı — değilse sıralanır. Her kova, içindeki
/// noktaların (ilk, maks, min, son) dörtlüsü; boş kova ÜRETİLMEZ (tatil,
/// piyasa kapalı). Aylık kovada `x` takvim ayının başıdır ve `kovaMs` o
/// ayın gerçek uzunluğudur (28–31 gün) — mum merkezi ay ortasına düşer.
List<Mum> mumlariTuret(List<FlSpot> spots, {required double kovaMs}) {
  if (spots.isEmpty || !kovaMs.isFinite || kovaMs <= 0) return const [];
  final sirali = List<FlSpot>.of(spots)..sort((a, b) => a.x.compareTo(b.x));

  final out = <Mum>[];
  DateTime? kovaBas;
  DateTime? kovaBit;
  double acilis = 0, enYuksek = 0, enDusuk = 0, kapanis = 0;
  var adet = 0;

  void kapat() {
    final bas = kovaBas;
    final bit = kovaBit;
    if (bas == null || bit == null || adet == 0) return;
    out.add(Mum(
      x: bas.millisecondsSinceEpoch.toDouble(),
      kovaMs: (bit.millisecondsSinceEpoch - bas.millisecondsSinceEpoch)
          .toDouble(),
      acilis: acilis,
      enYuksek: enYuksek,
      enDusuk: enDusuk,
      kapanis: kapanis,
      noktaSayisi: adet,
    ));
  }

  for (final s in sirali) {
    if (!s.x.isFinite || !s.y.isFinite) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(s.x.round());
    if (kovaBit == null || !t.isBefore(kovaBit)) {
      kapat();
      kovaBas = kovaBaslangici(t, kovaMs);
      kovaBit = kovaBitisi(kovaBas, kovaMs);
      acilis = s.y;
      enYuksek = s.y;
      enDusuk = s.y;
      kapanis = s.y;
      adet = 0;
    }
    if (s.y > enYuksek) enYuksek = s.y;
    if (s.y < enDusuk) enDusuk = s.y;
    kapanis = s.y;
    adet++;
  }
  kapat();
  return out;
}

/// Performans ekranının KENDİ X uzayından mum türetir.
///
/// Ekran X'i epoch ms DEĞİL, dönem başından itibaren ölçülür: gün içi seride
/// DAKİKA, diğer dönemlerde KESİRLİ GÜN (`seriler.dart`). [mumlariTuret] ve
/// [mumKovasiSec] ise epoch ms bekler. 2026-09-15'e kadar ekran noktaları
/// dönüştürmeden veriyordu: 0–720 "ms" 1970'in ilk dakikasına düşüyor, tek
/// mum üretiliyor ve merkezi görünür aralığın çok dışında kalıyordu —
/// kullanıcı "mum çalışmıyor" diye bildirdi. Saf fonksiyonların testleri ms
/// ile beslendiği için hata yakalanmamıştı; regresyon testi artık bu
/// fonksiyonda.
///
/// Dönüşüm tek yerde: girdi ve çıktı EKRAN uzayında. Dönen mumların [Mum.x]
/// ve [Mum.kovaMs] alanları ekran birimindedir (dakika ya da gün) — alan adı
/// ne derse desin.
///
/// [baslangicMs] ekran X'inin sıfır noktası (dönem başı, epoch ms).
/// [birimMs] bir ekran biriminin ms karşılığı: gün içi 60 000, diğerleri
/// 86 400 000.
List<Mum> mumlariGrafikUzayinda(
  List<FlSpot> spots, {
  required double baslangicMs,
  required double birimMs,
  int hedefAdet = 40,
}) {
  if (spots.length < 2 || !birimMs.isFinite || birimMs <= 0) return const [];
  final epoch = [
    for (final s in spots)
      if (s.x.isFinite && s.y.isFinite)
        FlSpot(baslangicMs + s.x * birimMs, s.y),
  ]..sort((a, b) => a.x.compareTo(b.x));
  if (epoch.length < 2) return const [];

  final kova = mumKovasiSec(
    spanMs: epoch.last.x - epoch.first.x,
    noktaSayisi: epoch.length,
    hedefAdet: hedefAdet,
  );
  return [
    for (final m in mumlariTuret(epoch, kovaMs: kova))
      Mum(
        x: (m.x - baslangicMs) / birimMs,
        kovaMs: m.kovaMs / birimMs,
        acilis: m.acilis,
        enYuksek: m.enYuksek,
        enDusuk: m.enDusuk,
        kapanis: m.kapanis,
        noktaSayisi: m.noktaSayisi,
      ),
  ];
}
