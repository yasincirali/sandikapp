/// Yatay tam ekran grafiğin saf geometrisi: ölçek, zaman ↔ mum indeksi,
/// çizim isabeti, mıknatıs. Flutter widget'ı bilmez; testi
/// `test/tam_ekran_grafik_test.dart`.
///
/// Hesap `build()` içinde değil burada (CLAUDE.md "Katmanlama"); ekran
/// yalnız sonuçları çizer.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../models/grafik_cizimi.dart';
import '../../models/ohlc.dart';

/// Görünen pencere — mum indeksi biriminde (kesirli). `son` sağ kenardır;
/// son mumun sağında boşluk bırakılabilir (TradingView gibi).
typedef GrafikGorunumu = ({double bas, double son});

/// Bir çizimin ekranda yakalanan parçası: gövde (`tutamak == null`) ya da
/// uç noktalardan biri (`'a'`/`'b'`).
typedef CizimIsabeti = ({int indeks, String? tutamak});

class GrafikOlcegi {
  GrafikOlcegi({
    required this.zamanlar,
    required this.aralikMs,
    required this.gorunum,
    required this.genislik,
    required this.fiyatAlani,
    required this.dusuk,
    required this.yuksek,
  });

  /// Mumların açılış anları (epoch ms), artan.
  final List<int> zamanlar;

  /// Bir mumun süresi — son mumdan sonrası ve ilk mumdan öncesi bununla
  /// uzatılır (çizim geleceğe uzanabilir).
  final int aralikMs;
  final GrafikGorunumu gorunum;

  /// Çizim alanının genişliği (fiyat ekseni hariç).
  final double genislik;

  /// Fiyat bölgesinin yüksekliği (hacim şeridi altında kalır).
  final double fiyatAlani;
  final double dusuk;
  final double yuksek;

  double get birim => genislik / (gorunum.son - gorunum.bas);

  double x(double i) => (i - gorunum.bas) * birim;
  double i(double x) => gorunum.bas + x / birim;
  double y(double p) => (yuksek - p) / (yuksek - dusuk) * fiyatAlani;
  double p(double y) => yuksek - y / fiyatAlani * (yuksek - dusuk);

  /// Zamanın (kesirli) mum indeksi. Mumlar arasında doğrusal; ilk mumdan
  /// önce ve son mumdan sonra [aralikMs] adımıyla uzar. Hafta sonu ve gece
  /// boşlukları böylece ekranda yer kaplamaz, çizim yine doğru mumda durur.
  double zamanIndeksi(int t) => zamanIndeksiBul(zamanlar, aralikMs, t);

  /// [zamanIndeksi]'nin tersi.
  int indeksZamani(double i) {
    final z = zamanlar;
    if (z.isEmpty) return 0;
    if (i <= 0) return (z.first + i * aralikMs).round();
    final n = z.length - 1;
    if (i >= n) return (z.last + (i - n) * aralikMs).round();
    final k = i.floor();
    return (z[k] + (i - k) * (z[k + 1] - z[k])).round();
  }

  Offset ekranda(CizimNoktasi n) => Offset(x(zamanIndeksi(n.t)), y(n.p));

  CizimNoktasi veride(Offset o) => CizimNoktasi(
      indeksZamani(i(o.dx)), p(o.dy.clamp(0, fiyatAlani).toDouble()));
}

/// [GrafikOlcegi.zamanIndeksi]'nin ölçeksiz hâli: açılış görünümü ölçek
/// kurulmadan önce de zamanı mum indeksine çevirebilsin.
double zamanIndeksiBul(List<int> z, int aralikMs, int t) {
  if (z.isEmpty) return 0;
  if (t <= z.first) return (t - z.first) / aralikMs;
  if (t >= z.last) return z.length - 1 + (t - z.last) / aralikMs;
  var lo = 0, hi = z.length - 1;
  while (hi - lo > 1) {
    final m = (lo + hi) >> 1;
    if (z[m] <= t) {
      lo = m;
    } else {
      hi = m;
    }
  }
  return lo + (t - z[lo]) / (z[hi] - z[lo]);
}

/// Bildirimden açılan çizginin açılış görünümü (yasin 2026-10-29: "çizgiyi
/// izleyebilelim"). Sağ kenar varsayılandaki gibi bugün; çizginin başı
/// ([cizimIndeksi]) pencerenin solundaysa pencere oraya kadar (3 mum pay)
/// genişler ki çizginin geçmişteki parçası ve bugünkü değeri birlikte
/// görünsün. Zaten görünüyorsa varsayılan aynen döner. Genişlik sınırı
/// [gorunumuSinirla]'da (en çok tüm veri).
GrafikGorunumu odakliGorunum(GrafikGorunumu v, double cizimIndeksi) {
  if (!cizimIndeksi.isFinite || cizimIndeksi >= v.bas + 2) return v;
  return (bas: cizimIndeksi - 3, son: v.son);
}

/// Çizimin [g] penceresinde kalan parçasının fiyat aralığı; pencerede
/// parçası yoksa `null`. [indeks] zamanı mum indeksine çevirir.
///
/// Neden (e2e 2026-10-29): bildirimden açılan yatay çizgi ₺228,30'daydı,
/// fiyat ekseni yalnız görünen mumları (~260–315) kapsıyordu; çizgi seçili
/// ama ekran dışındaydı, uzaklaştırmak da getirmiyordu. Ekran odak çizimini
/// bu aralıkla eksene katar. Yalnız pencerede GÖRÜNEN parça sayılır: geçmişte
/// bitmiş uzun bir trend çizgisinin uzak ucu ölçeği ezmesin.
({double lo, double hi})? cizimFiyatAraligi(
    GrafikCizimi c, double Function(int t) indeks, GrafikGorunumu g) {
  final b = c.b;
  if (c.tur.tekNokta || b == null) return (lo: c.a.p, hi: c.a.p);
  if (c.tur == CizimTuru.kutu) {
    return (lo: math.min(c.a.p, b.p), hi: math.max(c.a.p, b.p));
  }
  final ia = indeks(c.a.t), ib = indeks(b.t);
  if (ia == ib) return (lo: math.min(c.a.p, b.p), hi: math.max(c.a.p, b.p));
  double deger(double i) => c.a.p + (b.p - c.a.p) * (i - ia) / (ib - ia);
  var s0 = math.min(ia, ib), s1 = math.max(ia, ib);
  if (c.tur == CizimTuru.isin) {
    // Işın a'dan b yönüne sonsuza uzar.
    if (ib > ia) {
      s1 = double.infinity;
    } else {
      s0 = double.negativeInfinity;
    }
  }
  final x0 = math.max(s0, g.bas), x1 = math.min(s1, g.son);
  if (x0 > x1) return null;
  final v0 = deger(x0), v1 = deger(x1);
  if (!v0.isFinite || !v1.isFinite) return null;
  return (lo: math.min(v0, v1), hi: math.max(v0, v1));
}

/// Açılış görünümü: son ~[genislik]/9 mum, sağda 4 mum boşluk.
GrafikGorunumu varsayilanGorunum(int mumSayisi, double genislik) {
  final adet = math.max(30, math.min(mumSayisi, (genislik / 9).round()));
  return (bas: mumSayisi - adet - 0.5, son: mumSayisi + 3.5);
}

/// Yakınlaştırma ve kaydırmanın sınırı: en az 12 mum, en çok tüm veri +20;
/// son mum ekranın en az %30'una kadar sola kayabilir, veri bitince sağa
/// kaymaz.
GrafikGorunumu gorunumuSinirla(GrafikGorunumu g, int mumSayisi) {
  final genis =
      (g.son - g.bas).clamp(12.0, math.max(12.0, mumSayisi + 20.0)).toDouble();
  final son = math.min(mumSayisi + genis * 0.6, math.max(genis * 0.3, g.son));
  return (bas: son - genis, son: son);
}

/// Eksen için "güzel" adım (1, 2, 2,5, 5 × 10ⁿ) — [hedef] çizgiye yakın.
double guzelAdim(double aralik, int hedef) {
  if (!(aralik > 0) || hedef <= 0) return 1;
  final ham = aralik / hedef;
  final us = math.pow(10, (math.log(ham) / math.ln10).floor()).toDouble();
  for (final k in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (k * us >= ham) return k * us;
  }
  return 10 * us;
}

/// [a]'dan [b]'ye doğru, [alan]ın kenarına kadar uzatılmış uç.
Offset isinUcu(Offset a, Offset b, Size alan) {
  final d = b - a;
  if (d.distance < 1e-6) return b;
  var k = 1e9;
  if (d.dx > 0) k = math.min(k, (alan.width - a.dx) / d.dx);
  if (d.dx < 0) k = math.min(k, -a.dx / d.dx);
  if (d.dy > 0) k = math.min(k, (alan.height - a.dy) / d.dy);
  if (d.dy < 0) k = math.min(k, -a.dy / d.dy);
  if (k < 1) k = 1;
  return a + d * k;
}

double _parcaUzakligi(Offset p, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2)
      .clamp(0.0, 1.0)
      .toDouble();
  return (p - (a + d * t)).distance;
}

/// Uç noktayı yakalama yarıçapı ve gövde toleransı (pt). Parmak ucu ~44pt;
/// yarısından biraz az, komşu çizimler birbirini yutmasın.
const double kTutamakYaricapi = 18;
const double kGovdeToleransi = 14;

/// [nokta]da hangi çizim var? Uç noktası öncelikli; üst üste binen
/// gövdelerde en son çizilen (üstte görünen) kazanır, belirgin biçimde
/// daha yakın olan eski çizim yine seçilir — TradingView gibi.
CizimIsabeti? cizimIsabeti(
    List<GrafikCizimi> cizimler, GrafikOlcegi o, Offset nokta, Size alan) {
  ({int indeks, String? tutamak, double u})? en;
  for (var k = 0; k < cizimler.length; k++) {
    final c = cizimler[k];
    final a = o.ekranda(c.a);
    final b = c.b == null ? a : o.ekranda(c.b!);
    if (c.tur != CizimTuru.yatay) {
      for (final (ad, h) in [('a', a), if (!c.tur.tekNokta) ('b', b)]) {
        final u = (nokta - h).distance;
        if (u < kTutamakYaricapi && (en == null || u < en.u)) {
          en = (indeks: k, tutamak: ad, u: u);
        }
      }
    }
    final double u;
    switch (c.tur) {
      case CizimTuru.trend:
        u = _parcaUzakligi(nokta, a, b);
      case CizimTuru.isin:
        u = _parcaUzakligi(nokta, a, isinUcu(a, b, alan));
      case CizimTuru.yatay:
        u = (nokta.dy - a.dy).abs();
      case CizimTuru.yatayIsin:
        u = nokta.dx >= a.dx - 8 ? (nokta.dy - a.dy).abs() : double.infinity;
      case CizimTuru.kutu:
        final r = Rect.fromPoints(a, b);
        u = r.contains(nokta)
            ? math.min(
                math.min(nokta.dx - r.left, r.right - nokta.dx),
                math.min(math.min(nokta.dy - r.top, r.bottom - nokta.dy),
                    kGovdeToleransi - 4))
            : [
                _parcaUzakligi(nokta, r.topLeft, r.topRight),
                _parcaUzakligi(nokta, r.topRight, r.bottomRight),
                _parcaUzakligi(nokta, r.bottomRight, r.bottomLeft),
                _parcaUzakligi(nokta, r.bottomLeft, r.topLeft),
              ].reduce(math.min);
    }
    if (u < kGovdeToleransi &&
        (en == null || (en.tutamak != null ? u + 2 < en.u : u <= en.u + 4))) {
      en = (indeks: k, tutamak: null, u: u);
    }
  }
  return en == null ? null : (indeks: en.indeks, tutamak: en.tutamak);
}

/// Mıknatıs yarıçapı (pt): bu kadar yakındaki açılış/yüksek/düşük/kapanışa
/// yapışır, uzaktaysa serbest nokta.
const double kMiknatisYaricapi = 26;

/// Mıknatıs açıkken [ekran] noktasının veri karşılığı: en yakın mumun
/// OHLC değerlerinden dikeyde en yakını [kMiknatisYaricapi] içindeyse o,
/// değilse serbest nokta.
CizimNoktasi miknatisla(List<OhlcBar> mumlar, GrafikOlcegi o, Offset ekran) {
  final serbest = o.veride(ekran);
  if (mumlar.isEmpty) return serbest;
  final bi = o.i(ekran.dx).round().clamp(0, mumlar.length - 1);
  final m = mumlar[bi];
  double? en;
  var enU = kMiknatisYaricapi;
  for (final v in [m.acilis, m.enYuksek, m.enDusuk, m.kapanis]) {
    final u = (o.y(v) - ekran.dy).abs();
    if (u < enU) {
      enU = u;
      en = v;
    }
  }
  return en == null ? serbest : CizimNoktasi(m.t, en);
}
