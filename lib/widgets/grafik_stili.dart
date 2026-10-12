import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart' hide TextDirection;

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
import '../utils/mum_turetici.dart';
import '../utils/seans_sikistirma.dart';

/// Fiyat ve değer grafiklerinin ORTAK görünümü — "Performans stili".
///
/// ## Karar (kullanıcı, 2026-09-28)
/// *"Diğer ekranlarda bulunan grafik tasarımıyla bu neden farklılaşıyor,
/// burada uygulama tutarlı olmalı."* Etkileşim zaten tekti
/// ([ZoomableChart]); görünüş üç ekranda ayrı ayrı yazılmış ve ayrışmıştı:
/// Performans kartta ve amber, varlık detayı kartta ama üstte tarih
/// çizgileri ve BAŞLANGIÇ etiketiyle, varlık sayfası çerçevesiz ve yöne
/// göre kırmızı/yeşil. Dört seçenekten **Performans stili** seçildi; kart,
/// çizgi, ızgara, eksen yazısı, "şimdi" işareti ve dolgu BURADAN gelir.
///
/// Daha önceki karar da aynı yöndeydi (2026-09-12, Performans): *"dönem
/// başının dikine kesikli çizgilerle gösterilmesini istemiyorum, tüm
/// grafikler aynı deneyimi sunmalı."* Dönem başı dikey işareti ve "orada
/// alım yapılmış" gibi okunan başlangıç noktası hiçbir grafikte yok.
///
/// Ekrana özgü ÖZELLİKLER (detayda MA20, LOG, Karşılaştır, işlem
/// noktaları; Performans'ta grafik tipi ve hacim) bu dosyanın konusu
/// değildir — onlar veridir, görünüş değil.
abstract final class GrafikStili {
  /// Sağdaki fiyat ekseni bandı — `rightTitles.reservedSize` ve
  /// [ZoomableChart.plotPaddingRight] AYNI değeri kullanır (crosshair bu
  /// banda girmez).
  static const yEkseniGenisligi = 60.0;

  /// Çizim alanının yüksekliği (eksenler dahil) — Performans'ın 296'sı
  /// (2026-09-15: "grafik layoutunun yüksekliği biraz azaltılabilir").
  static const grafikYuksekligi = 296.0;

  /// Kartın dış yüksekliği: çizim alanı + üst/alt dolgu. Yükleme ve hata
  /// durumları da bu yükseklikte çizilir — veri gelince yerleşim zıplamaz.
  static const kartYuksekligi =
      grafikYuksekligi + SandikSpace.lgs + SandikSpace.smd;

  /// Alttaki zaman ekseni bandı.
  static const altEksenYuksekligi = 40.0;

  /// Kartın iç boşluğu: sağ eksen etiketleri kartın kenarına yapışmasın,
  /// solda çizgi kartın kenarına kadar uzasın.
  static const kartDolgusu = EdgeInsets.fromLTRB(
      SandikSpace.xs, SandikSpace.lgs, SandikSpace.md, SandikSpace.smd);

  /// Grafik kartı.
  static BoxDecoration kart(BuildContext context) => BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      );

  /// Ana çizginin rengi. Yön rengi (yeşil/kırmızı) çizgide DEĞİL, sayıda:
  /// başlıktaki yüzde ve çiplerin getirisi söyler. Çizgi her grafikte aynı
  /// renk olunca kullanıcı "bu kırmızı neden" diye sormaz.
  static Color cizgi(BuildContext context) => context.c.amberText;

  /// Çizginin altındaki yumuşak dolgu.
  static BarAreaData dolgu(BuildContext context) => BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.c.amberFill.withValues(alpha: 0.12),
            context.c.amberFill.withValues(alpha: 0),
          ],
        ),
      );

  /// Yatay (ve gün içinde dikey) ızgara çizgisi.
  static FlLine izgara(BuildContext context) =>
      FlLine(color: context.c.overlay, strokeWidth: 1);

  /// Sağ fiyat ekseni ile çizim alanı arasındaki ince ayraç.
  static FlBorderData eksenAyraci(BuildContext context) => FlBorderData(
        show: true,
        border: Border(right: BorderSide(color: context.c.overlay, width: 1)),
      );

  /// Eksen etiketi — tabular rakam, değer değişince kaymaz.
  static TextStyle eksenYazisi(BuildContext context) =>
      context.t.numSmall.copyWith(
        color: context.c.text58,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      );

  /// Değer (Y) ekseni etiketi — TEK SATIR, asla sarmaz, asla kırpılmaz.
  ///
  /// ## Neden (kullanıcı, 2026-09-29: "tüm grafiklerde labellar aşağı
  /// sarkmamalı, kaymamalı — garanti altına aldık mı?")
  /// Almamıştık: X ekseni Performans'ta ve varlık detayında korunuyordu
  /// (`eksen_etiket_cakismasi_test`) ama Y ekseni hiçbir grafikte değil.
  /// Etiketin yeri [yEkseniGenisligi] − dolgu ≈ 52pt; "₺12,5 Mn" büyük yazı
  /// ayarında buna sığmaz ve `Text` ikinci satıra kırılır — etiket
  /// tick'inden aşağı sarkar, altındaki etiketle çakışır.
  ///
  /// Sığmayan sayı KÜÇÜLÜR (`FittedBox.scaleDown`), kırpılmaz: "₺12,5 M…"
  /// bir değeri yanlış okuturdu; biraz küçük ama tam sayı okunur.
  /// `softWrap: false` sarmayı, `maxLines: 1` satır sonu içeren metni de
  /// kapatır. Sola hizalı + tabular rakam: değer değişince yatayda kaymaz.
  ///
  /// Her `getTitlesWidget` bu ya da [xEtiketi]'nden geçer —
  /// `grafik_eksen_etiketi_test` kaynakta tarar. `BuildContext` almaz:
  /// takip listesi grafiği renkleri hazır paletten okur, context'i yok.
  /// Stil çoğu yerde [eksenYazisi].
  static Widget yEtiketi(
    String metin, {
    required TextStyle stil,
    EdgeInsets dolgu = const EdgeInsets.only(left: SandikSpace.sm),
  }) =>
      Padding(
        padding: dolgu,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            metin,
            textAlign: TextAlign.left,
            maxLines: 1,
            softWrap: false,
            style: stil,
          ),
        ),
      );

  /// [xEtiketi] kutusunun varsayılan genişliği.
  static const xEtiketGenisligi = 74.0;

  /// İki X etiketinin çakışmaması için tick'ler arasında gereken piksel —
  /// `xEtiketiAtlanir`'ın `etiketPx`'i (bkz. `chart_axis.dart`).
  ///
  /// Metin [olcek] (kullanıcının yazı boyutu) ile ÖLÇÜLÜR: büyük yazı
  /// ayarında aynı etiket daha geniştir ve seyreltme bunu hesaba katmalı.
  /// Kutu [genislik]'ten geniş metni "…" ile keser; o yüzden üst sınır
  /// kutu. Aradaki [SandikSpace.sm] etiketlerin birbirine değmemesi için.
  static double xEtiketAraligi(
    String ornek, {
    required TextStyle stil,
    required TextScaler olcek,
    double genislik = xEtiketGenisligi,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: ornek, style: stil),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: olcek,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return (w < genislik ? w : genislik) + SandikSpace.sm;
  }

  /// Zaman (X) ekseni etiketi — SABİT genişlikte kutu, tick'e ortalı, tek
  /// satır; sığmayan metin "…" olur.
  ///
  /// Sabit genişlik "kaymama"nın kendisi: fl_chart etiketi tick'in
  /// ortasına koyar, genişlik metne göre değişseydi her etiketin merkezi
  /// başka yere düşerdi. Y ekseninden farkı: burada metin küçülmez —
  /// yan yana etiketlerin punto farkı ekseni dalgalı gösterirdi; tarih
  /// etiketi zaten kısalır (`zamanEtiketi`), "…" nadir ve bilgi kaybı az.
  static Widget xEtiketi(
    String metin, {
    required TextStyle stil,
    double genislik = xEtiketGenisligi,
    EdgeInsets dolgu = const EdgeInsets.only(top: SandikSpace.sm2),
  }) =>
      Padding(
        padding: dolgu,
        child: SizedBox(
          width: genislik,
          child: Text(
            metin,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: stil,
          ),
        ),
      );

  /// Dönem başı: yatay kesikli çizgi. Yüzde bu çizgiye göre okunur.
  ///
  /// Etiket ("AÇILIŞ · 00:00 · 6.644,05 ₺") artık çizginin ÜSTÜNDE, çizim
  /// alanının içinde DEĞİL: yasin 2026-10-12 (TestFlight, Gram Altın):
  /// "açılış yazısını grafiği engellemeyecek şekilde gösterelim." Çizgi
  /// verinin ortasından geçtiği için yazı mumların ve EMA'nın üstüne
  /// biniyordu. Tarih ve değer kaybolmaz ("grafik üzeri data kaybı
  /// olmamalı", 2026-09-28): kartın üst boşluğunda, çizgiyle aynı kesikli
  /// işaretle [donemBasiUstte] yazar.
  static HorizontalLine donemBasi(BuildContext context, double y) =>
      HorizontalLine(
        y: y,
        color: context.c.text36.withValues(alpha: 0.6),
        strokeWidth: 1,
        dashArray: const [4, 4],
      );

  /// [grafik]'in üstüne, kartın üst dolgusuna ([kartDolgusu] üstü,
  /// [SandikSpace.lgs]) dönem başı açıklamasını koyar: kesikli çizgi
  /// işareti + [etiket]. Çizim alanına girmez; grafiğin boyu değişmez.
  /// [etiket] boşsa grafik aynen döner.
  static Widget donemBasiUstte(BuildContext context,
      {required Widget grafik, String? etiket}) {
    if (etiket == null || etiket.isEmpty) return grafik;
    final renk = context.c.text58;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        grafik,
        Positioned(
          top: -SandikSpace.lgs,
          left: SandikSpace.sm,
          right: yEkseniGenisligi,
          height: SandikSpace.lgs,
          child: IgnorePointer(
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(14, 1),
                  painter: _KesikliCizgi(context.c.text36),
                ),
                const SizedBox(width: SandikSpace.xs2),
                Flexible(
                  child: Text(
                    etiket,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0,
                      fontWeight: FontWeight.w600,
                      color: renk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Dönem başı etiketinin metni — üç grafikte AYNI biçim: gün içinde
  /// "AÇILIŞ · 09:55 · değer", diğer dönemlerde "BAŞLANGIÇ · 21 Eyl · değer".
  static String donemBasiEtiketi(BuildContext context,
      {required DateTime an, required String deger, required bool gunIci}) {
    final l = context.l10n;
    // Tarih dili sözlükten: delegate yoksa sözlük Türkçe'ye düşer, tarih de.
    final tag = l.localeName.startsWith('en') ? 'en_US' : 'tr_TR';
    return gunIci
        ? l.chartOpenLabel(DateFormat('HH:mm', tag).format(an), deger)
        : l.chartStartLabel(DateFormat('d MMM', tag).format(an), deger);
  }

  /// "Şimdi" noktası — canlı fiyat. Piyasa kapalıyken GRİ (taşınan son
  /// kapanış; yeşil "şu an işlem görüyor" derdi — 2026-09-12).
  static FlDotCirclePainter simdiNoktasi(BuildContext context,
          {bool piyasaKapali = false}) =>
      FlDotCirclePainter(
        radius: 6,
        color: piyasaKapali ? context.c.text36 : context.c.gain,
        strokeColor: context.c.text90,
        strokeWidth: 2.5,
      );

  /// "ŞİMDİ" dikey işareti — gün içi DIŞINDAKİ dönemlerde. Gün içinde
  /// çizilmez (2026-09-12): saat ekseniyle çakışıyordu.
  static VerticalLine simdiCizgisi(BuildContext context, double x) =>
      VerticalLine(
        x: x,
        color: context.c.gain.withValues(alpha: 0.55),
        strokeWidth: 1.2,
        dashArray: const [4, 4],
        label: VerticalLineLabel(
          show: true,
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.only(bottom: 8, right: 6),
          style: context.t.labelMedium?.copyWith(
            letterSpacing: 0,
            fontWeight: FontWeight.w700,
            color: context.c.gain,
          ),
          labelResolver: (_) => context.l10n.chartNowLabel,
        ),
      );

  /// Mum çubukları — Performans ve varlık detayı AYNI çizimi kullanır
  /// (2026-10-10; önce yalnız Performans'ta `_mumSegmentleri` içindeydi).
  ///
  /// Her mum İKİ `LineChartBarData`: ince FİTİL (en düşük → en yüksek) ve
  /// kalın GÖVDE (açılış → kapanış). fl_chart 0.68'de mum çizimi yok, aynı
  /// x'te iki noktalı dikey çizgi mumun kendisidir. Doji (açılış = kapanış)
  /// yuvarlak uçlu sıfır uzunluklu gövde, yani bir nokta olarak görünür.
  ///
  /// Gövde kovanın piksel karşılığının %65'i (2–14 px); [gorunurAralik]
  /// [mumlar] ile aynı X biriminde. [kapali] piyasa kapalı noktalarının
  /// mumları: gri ve kesikli.
  static List<LineChartBarData> mumCubuklari(
    BuildContext context,
    List<Mum> mumlar, {
    required double genislik,
    required double? gorunurAralik,
    bool kapali = false,
  }) {
    final out = <LineChartBarData>[];
    for (final m in mumlar) {
      final kovaPx =
          gorunurAralik == null ? 8.0 : genislik * (m.kovaMs / gorunurAralik);
      final govde = (kovaPx * 0.65).clamp(2.0, 14.0);
      final fitil = (govde * 0.25).clamp(1.0, 2.0);
      final renk = kapali
          ? context.c.text36
          : (m.yukselen ? context.c.gain : context.c.loss);
      out.add(LineChartBarData(
        spots: [FlSpot(m.merkezX, m.enDusuk), FlSpot(m.merkezX, m.enYuksek)],
        isCurved: false,
        color: renk,
        barWidth: fitil,
        dashArray: kapali ? const [3, 3] : null,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
      out.add(LineChartBarData(
        spots: [FlSpot(m.merkezX, m.acilis), FlSpot(m.merkezX, m.kapanis)],
        isCurved: false,
        color: renk,
        barWidth: govde,
        isStrokeCapRound: m.doji,
        dashArray: kapali ? const [3, 3] : null,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    return out;
  }

  /// [mumCubuklari]'nın çok mumlu hâli — gerçek OHLC mumları (aralık
  /// seçicisi, 2026-10-10). Mum başına iki çubuk yerine TOPLAM beş seri:
  /// yükselen/düşen fitil, yükselen/düşen gövde, doji. Mumlar aynı serinin
  /// içinde `FlSpot.nullSpot` ile ayrılır (fl_chart boş noktada çizgiyi
  /// keser). 1.500 mumda 3.000 yerine 5 seri: GÜNLÜK × 1 dk kriptoda da
  /// akıcı kalır.
  ///
  /// Gövde genişliği mumların ORTANCA kovasından (ay 28–31 gün; tek bir
  /// kısa ay bütün gövdeleri inceltmesin). Yoğun aralıkta gövde 1 px'e kadar
  /// incelir: 2 px tabanı 1 dk mumlarını birbirine yapıştırıyordu.
  /// Görünüm [mumCubuklari] ile aynı renk ve oran.
  static List<LineChartBarData> mumCubuklariToplu(
    BuildContext context,
    List<Mum> mumlar, {
    required double genislik,
    required double? gorunurAralik,
  }) {
    if (mumlar.isEmpty) return const [];
    final kovalar = [for (final m in mumlar) m.kovaMs]..sort();
    final kova = kovalar[kovalar.length ~/ 2];
    final kovaPx = gorunurAralik == null || gorunurAralik <= 0
        ? 8.0
        : genislik * (kova / gorunurAralik);
    final govde = (kovaPx * 0.65).clamp(1.0, 14.0);
    final fitil = (govde * 0.25).clamp(0.8, 2.0);

    final fitilArtan = <FlSpot>[], fitilAzalan = <FlSpot>[];
    final govdeArtan = <FlSpot>[], govdeAzalan = <FlSpot>[];
    final dojiler = <FlSpot>[];
    void ekle(List<FlSpot> l, double x, double a, double b) {
      if (l.isNotEmpty) l.add(FlSpot.nullSpot);
      l
        ..add(FlSpot(x, a))
        ..add(FlSpot(x, b));
    }

    for (final m in mumlar) {
      final x = m.merkezX;
      ekle(m.yukselen ? fitilArtan : fitilAzalan, x, m.enDusuk, m.enYuksek);
      if (m.doji) {
        ekle(dojiler, x, m.acilis, m.kapanis);
      } else {
        ekle(m.yukselen ? govdeArtan : govdeAzalan, x, m.acilis, m.kapanis);
      }
    }
    LineChartBarData seri(List<FlSpot> spots, Color renk, double kalinlik,
            {bool yuvarlak = false}) =>
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: renk,
          barWidth: kalinlik,
          isStrokeCapRound: yuvarlak,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        );
    return [
      if (fitilArtan.isNotEmpty) seri(fitilArtan, context.c.gain, fitil),
      if (fitilAzalan.isNotEmpty) seri(fitilAzalan, context.c.loss, fitil),
      if (govdeArtan.isNotEmpty) seri(govdeArtan, context.c.gain, govde),
      if (govdeAzalan.isNotEmpty) seri(govdeAzalan, context.c.loss, govde),
      // Doji yükselen sayılır (kapanış ≥ açılış): yeşil nokta.
      if (dojiler.isNotEmpty)
        seri(dojiler, context.c.gain, govde, yuvarlak: true),
    ];
  }

  /// Seans boşlukları sıkışmış grafik (yasin 2026-10-12, `SeansSikistirma`):
  /// gerçek X'te kurulmuş [gercek] veriyi sıkışmış [cMin]–[cMax] eksenine
  /// taşır ve alt ekseni yeniden yazar. Varlık detayı (kesirli gün) ve
  /// varlık sayfası (epoch ms) AYNI kuralı kullanır; birim [birDakika] ve
  /// [an] (gerçek X → yerel saat) ile verilir.
  ///
  /// Eksen: tick'ler gerçek saatin tam katına oturur ([taban]; kesilen her
  /// boşluk tam saat olduğundan sıkışmış eksende de öyle kalır). Seans
  /// başı TARİH ("13 Eki"), arası yuvarlak SAAT yazar; sığmayan yazı
  /// çizilmez (`SeansSikistirma.eksenYazilari`). Atlanan her boşluğun
  /// yerinde ince kesikli ayraç: zamanın orada sıçradığını gösterir —
  /// renksiz okunur, yalnız çizgi biçimi (HIG: anlam yalnız renkte değil).
  /// Ayraçlar birbirine [_ayracAsgariPx]'ten yakınsa çizilmez (1 ay ·
  /// 30 dk'da 22 çizgi ızgara gibi okunurdu).
  static LineChartData seansEkseni(
    BuildContext context,
    LineChartData gercek,
    SeansSikistirma sik, {
    required double cMin,
    required double cMax,
    required double taban,
    required double birDakika,
    required DateTime Function(double gercekX) an,
    required double eksenPx,
  }) {
    final aralik = cMax - cMin;
    final adimDk =
        aralik <= 0 ? 60.0 : gunIciTickDk(aralik / birDakika).clamp(5.0, 60.0);
    final adim = adimDk * birDakika;
    final stil = eksenYazisi(context);
    final olcek = MediaQuery.textScalerOf(context);
    final etiketPx = xEtiketAraligi(
        DateFormat('d MMM', 'tr_TR').format(DateTime(2026, 8, 28)),
        stil: stil,
        olcek: olcek);
    final yazilar = sik.eksenYazilari(
      cMin: cMin,
      cMax: cMax,
      adim: adim,
      taban: taban,
      eksenPx: eksenPx,
      etiketPx: etiketPx,
      an: an,
      birDakika: birDakika,
    );
    final ayraclar = [
      for (final s in sik.seansBaslari)
        if (s > cMin && s < cMax) s,
    ];
    final ayracGoster = ayraclar.isNotEmpty &&
        eksenPx / (ayraclar.length + 1) >= _ayracAsgariPx;
    final m = sik.uygula(gercek, minX: cMin, maxX: cMax);
    final b = gercek.titlesData.bottomTitles.sideTitles;
    return m.copyWith(
      baselineX: taban,
      extraLinesData: ExtraLinesData(
        horizontalLines: m.extraLinesData.horizontalLines,
        extraLinesOnTop: m.extraLinesData.extraLinesOnTop,
        // Ekranın kendi çizgileri ("şimdi") ÖNCE: fl_chart çizgileri sıra
        // ile lerp eder; ayraç başa girince "şimdi"nin etiketi ayracınkiyle
        // karışıp TextStyle lerp hatası veriyordu.
        verticalLines: [
          ...m.extraLinesData.verticalLines,
          if (ayracGoster)
            for (final x in ayraclar)
              VerticalLine(
                x: x,
                // OPAK: fl_chart `extraLinesOnTop`ta dikey çizgileri her
                // çubuktan sonra YENİDEN çizer; mum başına bir çubuk olan
                // grafikte yarı saydam ayraç onlarca kat üst üste binip
                // beyaz bir çizgiye dönüyordu (görsel denetim 2026-10-12).
                color: Color.alphaBlend(context.c.hairline, context.c.surface1),
                strokeWidth: 1,
                dashArray: const [2, 4],
              ),
        ],
      ),
      titlesData: m.titlesData.copyWith(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: b.showTitles,
            reservedSize: b.reservedSize,
            interval: adim,
            getTitlesWidget: (value, meta) {
              final k = ((value - taban) / adim).round();
              final tarih = yazilar[k];
              if (tarih == null) return const SizedBox.shrink();
              final t = an(sik.geri(value));
              return GrafikStili.xEtiketi(
                  DateFormat(tarih ? 'd MMM' : 'HH:mm', 'tr_TR').format(t),
                  stil: stil);
            },
          ),
        ),
      ),
    );
  }

  /// Seans ayraçlarının ortalama en az aralığı (piksel).
  static const _ayracAsgariPx = 24.0;
}

/// Dönem başı açıklamasının işareti — çizimdeki kesikli çizginin aynısı.
class _KesikliCizgi extends CustomPainter {
  const _KesikliCizgi(this.renk);
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = renk
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(0, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_KesikliCizgi old) => old.renk != renk;
}
