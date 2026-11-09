import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

/// Grafiğin zaman ekseninden FİYAT GELMEYEN aralıkları çıkaran eşleme.
///
/// ## Karar (yasin, 2026-10-12, TestFlight)
/// 1 hf · 5 dk ve 1 ay · 30 dk mumlarda borsanın kapalı olduğu geceler ve
/// hafta sonu kartın yarısından fazlasını boş kaplıyor, mumlar adacıklara
/// sıkışıyor, EMA boşluğa düz çizgi çekiyordu. TradingView kapalı saatleri
/// eksenden çıkarır; yasin "böyle yapalım" dedi, iki şartla:
///   · Takvim varsayımı YOK ("bazı varlıklar hafta sonu değerlenebiliyor"):
///     yalnız serinin kendisinde veri olmayan aralık sıkışır. Kripto (7/24),
///     hafta sonu yurt içi kotasyonu olan altın/döviz aynen çizilir.
///   · Uydurma nokta yok: boşluğa hiçbir şey eklenmez, yalnız X kısalır.
///
/// ## Nasıl
/// Ardışık iki veri anı arasındaki boşluk [kur]'un eşiğini aşarsa boşluğun
/// [hizalama]'nın TAM KATI kadarı kesilir; artan (< [hizalama]) kısım
/// gerçek süre olarak kalır. Tam saat kesildiği için sıkışmış eksende
/// yuvarlak saat tick'leri yine yuvarlak saatlere düşer (10:00 · 13:00);
/// etiket gerçek anı [geri] ile yazar.
///
/// Birim çağıranın X birimidir (varlık detayında kesirli gün, varlık
/// sayfasında epoch ms); [hizalama] ve eşikler aynı birimde verilir.
class SeansSikistirma {
  SeansSikistirma._(this._bosluklar);

  /// Sıralı boşluklar: gerçek [bas, son), kesilen miktar ve o boşluktan
  /// ÖNCE kesilmiş toplam.
  final List<({double bas, double son, double kesilen, double onceki})>
      _bosluklar;

  /// Eşlemeyi kurar; sıkıştırılacak boşluk yoksa `null` (çağıran eski
  /// ekseni birebir kullanır).
  ///
  /// [anlar] veri anları (sıralı olmak zorunda değil). [birGun] birimde bir
  /// gün: ortanca adım bir günden kısa değilse (günlük/haftalık çubuk)
  /// sıkıştırma yapılmaz — hafta sonu orada zaten tek adımdır. Boşluk
  /// eşiği ortanca adımın 3 katı ve en az [hizalama].
  static SeansSikistirma? kur(
    Iterable<double> anlar, {
    required double hizalama,
    required double birGun,
  }) {
    final xs = anlar.where((x) => x.isFinite).toList()..sort();
    if (xs.length < 3 || hizalama <= 0) return null;
    final adimlar = <double>[
      for (var i = 1; i < xs.length; i++)
        if (xs[i] > xs[i - 1]) xs[i] - xs[i - 1],
    ]..sort();
    if (adimlar.isEmpty) return null;
    final ortanca = adimlar[adimlar.length ~/ 2];
    if (ortanca >= birGun * 0.99) return null;
    final esik = math.max(ortanca * 3, hizalama);
    final bosluklar =
        <({double bas, double son, double kesilen, double onceki})>[];
    var toplam = 0.0;
    for (var i = 1; i < xs.length; i++) {
      final g = xs[i] - xs[i - 1];
      if (g <= esik) continue;
      // Boşluğun başı son verinin bir ADIM sonrası: son mum/nokta kendi
      // genişliğini korusun, kesilen yalnız gerçekten boş kalan süre olsun.
      final bas = xs[i - 1] + ortanca;
      final kesilen = ((xs[i] - bas) / hizalama).floor() * hizalama;
      if (kesilen <= 0) continue;
      bosluklar.add((bas: bas, son: xs[i], kesilen: kesilen, onceki: toplam));
      toplam += kesilen;
    }
    if (bosluklar.isEmpty) return null;
    return SeansSikistirma._(bosluklar);
  }

  /// Sıkıştırılan boşluk sayısı (test ve ayraç sayısı için).
  int get boslukSayisi => _bosluklar.length;

  /// Gerçek X → sıkışmış X. Monoton artan (eşit olabilir).
  double ileri(double x) {
    var kesik = 0.0;
    for (final b in _bosluklar) {
      if (x <= b.bas) return x - b.onceki;
      if (x < b.son) {
        // Boşluğun içi: [bas, son) → [bas', bas' + kalan] doğrusal.
        final kalan = (b.son - b.bas) - b.kesilen;
        final oran = (x - b.bas) / (b.son - b.bas);
        return b.bas - b.onceki + kalan * oran;
      }
      kesik = b.onceki + b.kesilen;
    }
    return x - kesik;
  }

  /// Sıkışmış X → gerçek X. Tamamen kesilen boşluğun noktası seansın
  /// BAŞINA (boşluğun sonu) döner: o tick'in etiketi "10:00" okunur.
  double geri(double c) {
    var kesik = 0.0;
    for (final b in _bosluklar) {
      final basC = b.bas - b.onceki;
      final kalan = (b.son - b.bas) - b.kesilen;
      if (c < basC) return c + b.onceki;
      if (c <= basC + kalan) {
        if (kalan <= 0) return b.son;
        return b.bas + (c - basC) / kalan * (b.son - b.bas);
      }
      kesik = b.onceki + b.kesilen;
    }
    return c + kesik;
  }

  /// Her sıkıştırılmış boşluğun ardından başlayan seansın sıkışmış X'i —
  /// ince ayraç çizgileri buraya çizilir ("burada zaman atlandı").
  List<double> get seansBaslari => [for (final b in _bosluklar) ileri(b.son)];

  /// Gerçek X'te kurulmuş grafiği sıkışmış eksene taşır: çizgi/mum
  /// noktaları ve dikey çizgiler [ileri] ile, pencere [minX]–[maxX]
  /// (zaten sıkışmış). Nokta gösterme/boyama geri çağrıları GERÇEK noktayı
  /// görür — "şimdi" noktası ve işlem seyreltmesi gerçek X'le karşılaştırır.
  /// Eksen yazıları çağıranındır (sıkışmış eksende tick'i o kurar).
  LineChartData uygula(LineChartData d,
      {required double minX, required double maxX}) {
    LineChartBarData cubuk(LineChartBarData b) {
      final gercek = Map<FlSpot, FlSpot>.identity();
      final spots = <FlSpot>[
        for (final s in b.spots)
          if (s.isNull())
            s
          else
            () {
              final m = FlSpot(ileri(s.x), s.y);
              gercek[m] = s;
              return m;
            }(),
      ];
      final dot = b.dotData;
      FlSpot asil(FlSpot s) => gercek[s] ?? FlSpot(geri(s.x), s.y);
      return b.copyWith(
        spots: spots,
        dotData: FlDotData(
          show: dot.show,
          checkToShowDot: (s, bar) => dot.checkToShowDot(asil(s), bar),
          getDotPainter: (s, p, bar, i) =>
              dot.getDotPainter(asil(s), p, bar, i),
        ),
      );
    }

    final e = d.extraLinesData;
    return d.copyWith(
      minX: minX,
      maxX: maxX,
      lineBarsData: [for (final b in d.lineBarsData) cubuk(b)],
      extraLinesData: ExtraLinesData(
        horizontalLines: e.horizontalLines,
        extraLinesOnTop: e.extraLinesOnTop,
        verticalLines: [
          for (final v in e.verticalLines)
            VerticalLine(
              x: ileri(v.x),
              label: v.label,
              color: v.color,
              gradient: v.gradient,
              strokeWidth: v.strokeWidth,
              dashArray: v.dashArray,
              image: v.image,
              sizedPicture: v.sizedPicture,
              strokeCap: v.strokeCap,
            ),
        ],
      ),
    );
  }

  /// Sıkışmış eksenin tick planı. Eksen [adim] aralıklı tick'lerle
  /// çizilir (taban [taban]: gerçek saatin tam katına oturan sıkışmış X);
  /// burada hangi tick'e yazı düşeceği seçilir:
  ///   1. Seans başları (atlanan boşluğun ardından) ve gerçek gece yarısı
  ///      TARİH alır ("13 Eki") — sıkışmış eksende günü okutan budur.
  ///   2. Aralarına, yazılar [etiketPx]'ten sıkışmadıkça yuvarlak SAAT
  ///      (gerçek saatte 15 dk · 30 dk · 1 sa … 12 sa katları).
  /// Kenara %6'dan ya da yarım etiketten yakın yazı çizilmez (taşar).
  /// Dönüş: tick sırası (`((c - taban) / adim).round()`) → tarih mi.
  Map<int, bool> eksenYazilari({
    required double cMin,
    required double cMax,
    required double adim,
    required double taban,
    required double eksenPx,
    required double etiketPx,
    required DateTime Function(double gercekX) an,
    required double birDakika,
  }) {
    final out = <int, bool>{};
    final aralik = cMax - cMin;
    if (aralik <= 0 || adim <= 0 || eksenPx <= 0) return out;
    final pxBirim = eksenPx / aralik;
    // Etiket tick'e ortalanır: kenara yarım etiketten yakın olan kartın
    // dışına taşar ("13 Tem" sol kenara yapışıyordu).
    final kenar = math.max(aralik * 0.06, etiketPx / 2 / pxBirim);
    final ilk = ((cMin + kenar - taban) / adim).ceil();
    final son = ((cMax - kenar - taban) / adim).floor();
    if (son < ilk || son - ilk > 5000) return out;
    final secilen = <double>[];
    // Yazılar arası nefes payı: etiket kutusu kadar boşluk tarihleri
    // birbirine yapıştırıyordu ("13 Eyl 14 Eyl").
    final asgariPx = etiketPx * 1.5;
    bool sigar(double c) =>
        secilen.every((s) => (s - c).abs() * pxBirim >= asgariPx);

    // 1. Tarih: seans başı ya da gece yarısı. Tick seansın ilk tick'i.
    final tarihli = <int>{};
    for (final s in seansBaslari) {
      if (s < cMin || s > cMax) continue;
      tarihli.add(((s - taban) / adim - 1e-6).ceil());
    }
    int dakika(int k) {
      final t = an(geri(taban + k * adim));
      return t.hour * 60 + t.minute;
    }

    for (var k = ilk; k <= son; k++) {
      if (dakika(k) == 0) tarihli.add(k);
    }
    for (final k in tarihli.toList()..sort()) {
      if (k < ilk || k > son) continue;
      final c = taban + k * adim;
      if (sigar(c)) {
        out[k] = true;
        secilen.add(c);
      }
    }
    // 2. Saat: yazının sığdığı en küçük yuvarlak adım.
    final adimDk = (adim / birDakika).round();
    int? saatAdimi;
    for (final a in const [15, 30, 60, 120, 180, 240, 360, 720]) {
      if (a < adimDk || a % adimDk != 0) continue;
      if (a * birDakika * pxBirim >= asgariPx) {
        saatAdimi = a;
        break;
      }
    }
    if (saatAdimi != null) {
      for (var k = ilk; k <= son; k++) {
        if (out.containsKey(k) || dakika(k) % saatAdimi != 0) continue;
        final c = taban + k * adim;
        if (sigar(c)) {
          out[k] = false;
          secilen.add(c);
        }
      }
    }
    return out;
  }
}
