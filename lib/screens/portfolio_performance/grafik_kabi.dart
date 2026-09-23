part of '../portfolio_performance_screen.dart';

/// Grafik kabı: `LineChartData` üretimi, çubuk/mum/taban tipleri, hacim
/// çubukları. `portfolio_performance_screen.dart`'tan bölündü (2026-09-14):
/// part = aynı kütüphane, private alanlara erişim ve davranış AYNEN; yalnızca
/// dosya sınırı değişti. `setState` yerine `_guncelle` (bkz. ana dosya).
extension _PerformansGrafikKabi on _PortfolioPerformanceScreenState {
  Widget _buildChartContainer(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets,
      {bool intraday = false, List<Asset>? allTargetAssets}) {
    if (segments.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg)),
        child: Center(
            child: Text(context.l10n.noData, style: TextStyle(color: context.c.text36))),
      );
    }

    // İşlem kaynağı — TEK TANIM. Hem nokta çizimi (`_buyDayKeys`) hem
    // crosshair detayları bunu kullanır. İkisi ayrı listelerden beslendiğinde
    // "grafikte nokta var ama basınca alım/satım yazmıyor" tutarsızlığı
    // çıkıyordu: nokta `chartAssets`'ten, tooltip `allTargetAssets`'ten
    // geliyordu ve simülasyonda `chartAssets` sentetik `addedDate` taşır.
    final txAssets = allTargetAssets ?? assets;

    // Y ekseni scale'i — SADECE en kalın segmentin (aktif sarı çizgi)
    // değerlerine göre hesaplanır. Passive segment (alım öncesi 0 çizgisi)
    // Y aralığına dahil edilirse min hep 0'a çekilir ve aktif değerler
    // ezik görünür. Bu yüzden en kalın segmenti "ana" kabul edip diğerleri
    // clipData ile alta düşer.
    final primarySeg =
        segments.reduce((a, b) => (a.thickness >= b.thickness) ? a : b);

    // ── Crosshair'in tarayacağı noktalar ────────────────────────────────
    //
    // `primarySeg` Y ekseni için doğru kaynak (en kalın = ana çizgi) ama
    // DOKUNMA için yanlış: piyasa kapalı kuyruğu ayrı ve daha ince bir
    // segment olduğundan (bkz. `TransactionSegment.piyasaKapali`) oraya
    // düşmüyor. Sonuç: kullanıcı uzun bastığında crosshair kapanışta
    // duruyor, hafta sonu/tatil bölgesinde tarih ve değer okunamıyordu
    // (kullanıcı bildirimi 2026-09-12).
    //
    // Dokunma tüm çizilmiş noktaları görmeli. Segmentler zaten X'e göre
    // sıralı üretiliyor; sınırda tek nokta çakışabildiği için birleştirme
    // sonrası tekilleştiriliyor — `nearestSpotIndex` ikili arama yapıyor
    // ve sıralı+tekil dizi bekliyor.
    final List<FlSpot> crosshairSpots;
    if (segments.length == 1) {
      crosshairSpots = primarySeg.spots;
    } else {
      final birlesik = [for (final s in segments) ...s.spots]
        ..sort((a, b) => a.x.compareTo(b.x));
      crosshairSpots = [
        for (var i = 0; i < birlesik.length; i++)
          if (i == 0 || birlesik[i].x != birlesik[i - 1].x) birlesik[i],
      ];
    }

    // Görünür X aralığındaki spot'lara göre Y sınırlarını hesapla. Zoom
    // sırasında X daraldıkça Y ekseni otomatik yeniden fit olur — kullanıcı
    // dar bir zaman diliminde küçük dalgalanmayı okuyabilir.
    ({double minY, double maxY, double interval}) computeY(
        double viewMinX, double viewMaxX) {
      double minY = double.infinity;
      double maxY = -double.infinity;
      double sumY = 0;
      int countY = 0;
      for (final spot in primarySeg.spots) {
        if (spot.x < viewMinX || spot.x > viewMaxX) continue;
        if (spot.y > maxY) maxY = spot.y;
        if (spot.y < minY) minY = spot.y;
        sumY += spot.y;
        countY++;
      }
      if (minY == double.infinity) minY = 0;
      if (maxY == -double.infinity) maxY = 1000;

      // Çubuk tipinde taban (dönem başı) Y aralığına DAHİL olmalı: çubuklar
      // o değerden başlıyor ve taban pencerenin dışında kalırsa alt uçları
      // kırpılır — yarım çubuklar "veri yok" gibi okunur. Diğer tiplerde
      // aralık dokunulmadan kalır (dar bant gün içi hassasiyeti için şart).
      if (grafikTipiNotifier.value == GrafikTipi.bar &&
          segments.isNotEmpty &&
          segments.first.spots.isNotEmpty) {
        final taban = segments.first.spots.first.y;
        if (taban < minY) minY = taban;
        if (taban > maxY) maxY = taban;
      }

      final avgY = countY > 0 ? sumY / countY : (minY + maxY) / 2;
      // Bandın cebri `chart_axis.dart`'ta — saf ve testli.
      //
      // Asgari bant oranı gün içinde ÇOK DARDIR (%0,5). Bir portföyün
      // günlük hareketi tipik olarak ±%0,5–2'dir; buradaki eski %8'lik
      // taban o hareketi grafik yüksekliğinin onda birine sıkıştırıyor ve
      // seans boyunca gerçek dalgalanma varken çizgi DÜMDÜZ görünüyordu
      // (kullanıcı bildirimi 2026-09-07: "yüksek precision ile göstermesi
      // gerekirdi"). Widget/Live Activity grafiği aynı dersi daha önce
      // öğrenmiş ve %0,5'e inmişti; artık iki yüzey tek sabitten besleniyor.
      //
      // Uzun periyotlarda %8 nadiren bağlayıcıdır (bir ay zaten daha çok
      // oynar) — orada dokunulmadı.
      return gorunurYBandi(
        dataMinY: minY,
        dataMaxY: maxY,
        avgY: avgY,
        asgariBantOrani: intraday ? gunIciAsgariBantOrani : 0.08,
      );
    }

    // Serinin son noktasının gün başından uzaklığı (dakika). Bugünü
    // çizerken bu zaten "şimdi"ye eşittir; geçmiş seansta kapanış anıdır.
    // TÜM segmentlerin en sağdaki noktası — `primarySeg` DEĞİL.
    //
    // `primarySeg` "en kalın segment" olarak seçiliyor ve bu SEANS
    // segmentidir (3.5); piyasa kapalı kuyruğu daha ince (2.5) olduğu
    // için dışarıda kalıyordu. Sonuç: "ŞİMDİ" dikey çizgisi ve son nokta
    // işaretçisi kapanışta duruyor, kuyruk boyunca uzanmıyordu
    // (kullanıcı bildirimi 2026-09-12, ekran görüntüsüyle).
    //
    // Kuyruk varsa en sağdaki nokta ONUN son noktasıdır — yani "şimdi".
    final gunIciSonNoktaDk = !intraday
        ? 0.0
        : segments
            .expand((s) => s.spots)
            .fold<double>(0.0, (m, s) => s.x > m ? s.x : m);

    // X ekseni — aktif segment çok sıkışıksa (örn. tek gün alım + bugün)
    // viewport'u aktif segment başlangıcından biraz öncesine daralt.
    // Böylece "12 Tem'de aldım, bugün 13" senaryosu tüm 1H window'da
    // dikey çubuk gibi değil, geniş bir eğri gibi görünür. AYRICA
    // başlangıç ve bitiş noktaları hep viewport'un içinde kalmalı —
    // dot çizim yarıçapı (~6px) sınırda clip'lenmesin diye her iki
    // uca minimum yarım günlük pay bırakılır.
    double fullMaxX;
    if (intraday) {
      // Şimdi noktasını viewport'un sağında **hep içeride** tut ki her
      // tick'te güncellenirken görünsün. Nokta viewport'un yaklaşık
      // %82'sinde olacak şekilde fullMaxX'i genişletiyoruz. Alt sınır
      // 1440 (tam gün) — sabahın ilk saatlerinde grafiğin çok dar
      // görünmesini engeller.
      // Kural `chart_axis.dart`'ta — takip listesi grafiği de aynı
      // fonksiyondan besleniyor. İki ekran aynı günü aynı ölçekte çizmeli;
      // kopyalandığında biri düzelirken öteki geride kalıyordu.
      //
      // Referans nokta `DateTime.now()` DEĞİL, serinin SON NOKTASIDIR:
      // çizilen gün bugün olmayabilir (hafta sonu/tatilde son seans
      // çizilir) ve o durumda "şu anki saat" bu eksende bir yere karşılık
      // gelmez — 1440'ı aşan bir sağ uç üretip seansı sola ezerdi.
      fullMaxX = gunIciEksenSonuDk(gunIciSonNoktaDk);
    } else {
      // Kesirli gün — saatlik veride son X ~6.83, integer olsa 7 kalırdı
      // ve son nokta grafiğin sağında boşta kalırdı.
      fullMaxX = (end.difference(start).inMinutes / (60.0 * 24.0))
          .clamp(1.0, double.infinity);
    }
    // Eksenin sol ucu VERİNİN başladığı yer — sabit 0 değil.
    //
    // `startDate` ile ilk veri noktası nadiren çakışır: dönem başı takvim
    // gününe çekiliyor ama seri o gün borsanın açıldığı saatte başlıyor,
    // ayrıca hafta sonu/tatilde ilk kova günler sonraya düşebiliyor.
    // Eksen 0'dan başlayınca soldaki o fark BOŞ bir şerit olarak kalıyor
    // ve çizgi grafiğin başından değil içeriden başlıyor görünüyordu
    // (kullanıcı bildirimi 2026-09-12, 1H sekmesi — ölçüldü: ilk nokta
    // X = 0,917, yani neredeyse bir gün içeride).
    //
    // Çözüm: ekseni veriye oturt. Sağ uç zaten son noktada bitiyor.
    final veriXs = primarySeg.spots.map((s) => s.x);
    final ilkVeriX =
        veriXs.isEmpty ? 0.0 : veriXs.reduce((a, b) => a < b ? a : b);
    double minX = intraday ? 0.0 : ilkVeriX;
    double maxX = fullMaxX;
    final activeSpotXs = primarySeg.spots.map((s) => s.x).toList()..sort();
    if (activeSpotXs.isNotEmpty && !intraday) {
      final firstActiveX = activeSpotXs.first;
      final lastActiveX = activeSpotXs.last;
      final activeSpan = lastActiveX - firstActiveX;
      final fullSpan = fullMaxX;
      // Aktif segment tüm periyodun %25'inden azsa viewport'u daralt.
      if (activeSpan < fullSpan * 0.25) {
        // İlk & son noktanın iki tarafına eşit ve cömert bağlam bırak
        // (en az 1 gün, en çok aktif span kadar). Böylece başlangıç
        // ve bitiş noktaları grafiğin ortasında değil, kenardan güvenli
        // bir mesafede görünür.
        final pad = (activeSpan.clamp(1.0, double.infinity)) * 0.8;
        minX = (firstActiveX - pad).clamp(0.0, fullMaxX);
        // clamp(lower, upper) kuralı: lower <= upper olmalı. Aktif segment
        // fullMaxX'e yakınsa "minX + 1" fullMaxX'i geçebilir → crash. O yüzden
        // önce üst sınırı belirle, sonra minX + 1'i onunla clamp'la.
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + pad).clamp(lower, upper);
      }
      // Son güvenlik payı: dot yarıçapı viewport sınırında clip olmasın.
      // Toplam aralığın %3'ü kadar minimum pay bırak.
      final safety = ((maxX - minX) * 0.03).clamp(0.15, double.infinity);
      if (firstActiveX - minX < safety) {
        minX = (firstActiveX - safety).clamp(0.0, fullMaxX);
      }
      if (maxX - lastActiveX < safety) {
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + safety).clamp(lower, upper);
      }
      // Son bir güvenlik: minX ile maxX çakışmışsa hafifçe aç.
      if (maxX <= minX) {
        maxX = (minX + 1).clamp(0.0, fullMaxX);
        if (maxX <= minX) minX = (maxX - 1).clamp(0.0, fullMaxX);
      }
    }

    // Zoom durumunda tekrar üretilen LineChartData'yı bir closure'a al.
    // ZoomableChart pinch/pan sırasında minX/maxX değiştirdikçe bu builder
    // yeniden çağrılır; Y ekseni görünür pencereye göre re-fit olur.
    LineChartData buildData(double viewMinX, double viewMaxX) {
      final y = computeY(viewMinX, viewMaxX);
      // Çizim alanının genişliği — ekran eksi sağ Y rezervi (60px) ve yatay
      // kenar boşlukları (40px). Hem işlem noktası seyreltmesi hem çubuk
      // yoğunluğu bunu kullanır; iki ayrı formül iki farklı yoğunluk demekti.
      final double plotWidthPx =
          (MediaQuery.of(context).size.width - 60 - 40).clamp(120.0, 2000.0);
      final double viewMinY = y.minY;
      final double viewMaxY = y.maxY;
      final double yInterval = y.interval;
      // X ekseni için uygun aralık. Intraday'de 4 saatlik (240 dk) etiketler
      // → 00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00 gibi.
      // Gün içi eksende adım, ETİKET UZUNLUĞUNA göre açılır.
      //
      // Sabit 240 dk (4 saat) tek günlük eksende doğruydu: etiket "04:00"
      // gibi kısa. Ama piyasa kapalıyken eksen birden çok günü kapsıyor ve
      // etiket "11 Eyl 04:00"a uzuyor (bkz. `zamanEtiketi`) — aynı adımda
      // yan yana altı etiket ÜST ÜSTE BİNİYORDU (kullanıcı bildirimi
      // 2026-09-12, ekran görüntüsüyle).
      //
      // Çok günlü eksende adım gün sayısıyla ölçekleniyor: eksen ne kadar
      // uzarsa etiketler o kadar seyrekleşir, sayıları sabit kalır.
      final gunIciSpanGun = (viewMaxX - viewMinX).abs() / 1440.0;
      final xInterval = intraday
          ? (gunIciSpanGun > 1
              // Çok günlü eksende etiket "11 Eyl 04:00"a uzuyor (~88px).
              // Hedef ÜÇ etiket: ölçüldü, 5 etiket ~330px genişlikte
              // sığmıyordu ve yan yana yapışıyordu (kullanıcı bildirimi
              // 2026-09-12, iki tur üst üste).
              //
              // 3 saatin katına yuvarlanıyor: tick'ler hem yuvarlak
              // saatlere düşsün hem de kaba adımlarda 09:00/12:00 gibi
              // okunur değerler çıksın.
              ? (((viewMaxX - viewMinX).abs() / 3 / 180).ceilToDouble() * 180)
                  .clamp(gunIciEksenAdimiDk, double.infinity)
              : gunIciEksenAdimiDk)
          : yuvarlakAdim((viewMaxX - viewMinX) / 5).clamp(1.0, double.infinity);

      // Alım dot'ları için piksel bazlı seyreltme. Arka arkaya yapılan
      // alımlarda noktalar birkaç piksel arayla düşüp üst üste biniyor ve
      // tek bir yığın gibi görünüyordu. Aynı X uzayında minimum 16px mesafe
      // şartı koyuyoruz; zoom yapıldıkça viewport daralır, noktalar açılır
      // ve gizlenenler tek tek ortaya çıkar.
      // Simülasyonda işlem noktası YOKTUR (miktar tüm dönem sabit sayılır,
      // "o gün alım yapıldı" bilgisi o modelde anlamsız). Gün içi seride ise
      // noktalar GÖSTERİLİR: sıçrama tüm portföy ölçeğinde görünmediğinde
      // işlemin izini taşıyan tek şey odur.
      final DotThinner dotThinner = _simulate
          ? DotThinner.build(
              candidates: const [],
              viewMinX: viewMinX,
              viewMaxX: viewMaxX,
            )
          : () {
              return DotThinner.build(
                // `buyDayKeys` viewport'a bağlı DEĞİL — zoom/pan her karede
                // yeniden hesaplanması saf israftı (spot × varlık döngüsü +
                // her çift için DateTime aritmetiği). Artık segment/varlık
                // kümesi başına bir kez hesaplanıp cache'leniyor.
                //
                // Kaynak liste crosshair ile AYNI olmalı (`txAssets`), aksi
                // halde nokta bir kümeden, tooltip başka kümeden beslenir ve
                // "noktası var ama işlemi yok" tutarsızlığı doğar.
                candidates:
                    _buyDayKeys(segments, txAssets, start, intraday: intraday),
                viewMinX: viewMinX,
                viewMaxX: viewMaxX,
                plotWidthPx: plotWidthPx,
                // Nokta çapı 8.5px'ten ~7.2px'e indi (r=3 + 1.2 halka), bu
                // yüzden ayrım eşiği de 16'dan 11'e çekilebiliyor: daha az
                // nokta gizlenir, üst üste binme yine olmaz.
                minSeparationPx: 11,
                // Uç noktalara yakın işlemler kalıcı olarak gizlenmesin —
                // "şimdi" dot'u r=6 olduğu için 8px yeter (bkz. DotThinner).
                anchorSeparationPx: 8,
                // İlk ve son nokta her zaman görünür (anchor / "şimdi").
                alwaysKeep: {
                  primarySeg.spots.first.x,
                  primarySeg.spots.last.x,
                },
              );
            }();

      // Seçili grafik tipi — oturum boyunca yaşar (bkz. `grafikTipiNotifier`).
      // `ValueListenableBuilder` dışarıda: burada okumak yeterli çünkü
      // seçim değiştiğinde builder tüm grafiği yeniden kuruyor.
      final tip = grafikTipiNotifier.value;

      return LineChartData(
        minX: viewMinX,
        maxX: viewMaxX,
        minY: viewMinY,
        maxY: viewMaxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: intraday,
          verticalInterval: intraday ? gunIciEksenAdimiDk : null,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.c.overlay,
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: context.c.overlay,
            strokeWidth: 1,
          ),
        ),
        // Sağ Y ekseni band'ı görsel olarak plot area'dan ayrılsın diye
        // sadece sağ kenara ince dikey çizgi. TradingView'de plot | Y ayrık.
        borderData: FlBorderData(
          show: true,
          border: Border(
            right: BorderSide(
              color: context.c.overlay,
              width: 1,
            ),
          ),
        ),
        extraLinesData: intraday
            // Gün içi grafikte dikey "ŞİMDİ" çizgisi KALDIRILDI
            // (kullanıcı isteği 2026-09-12): X ekseni etiketleriyle
            // çakışıyordu ve bilgi zaten iki yerde daha var — serinin
            // ucundaki nokta (piyasa kapalıyken gri) ve üstteki kartın
            // "11 Eyl → bugün · PİYASA KAPALI" başlığı.
            ? const ExtraLinesData(verticalLines: [])
            : ExtraLinesData(
                verticalLines: primarySeg.spots.isEmpty
                    ? const []
                    : [
                        // Dönem başı için dikey kesikli işaret KALDIRILDI
                        // (kullanıcı isteği 2026-09-12): "başlangıcın
                        // dikine kesikli çizgilerle gösterilmesini
                        // istemiyorum, tüm grafikler aynı deneyimi
                        // sunmalı."
                        //
                        // Dönem başı bilgisi kaybolmadı — üstteki değişim
                        // kartı "5 Eyl → 12 Eyl" aralığını zaten yazıyor
                        // ve X ekseninin ilk etiketi de aynı tarihi
                        // gösteriyor.
                        // Son nokta (bugün / şimdi) için dashed marker.
                        // Etiket çizginin SOLUNA (grafik içine) yaslanır.
                        VerticalLine(
                          x: primarySeg.spots.last.x,
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
                            labelResolver: (_) => 'ŞİMDİ',
                          ),
                        ),
                      ],
              ),
        titlesData: FlTitlesData(
          show: true,
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // TradingView tarzı: fiyat scale SAĞDA, tarih ekseni ALTTA ayrı bant.
          // leftTitles kapatıldı, rightTitles dolduruldu. Rezerv alanları
          // grafik alanına girmesin diye cömert (Y sağda 60, X altta 40).
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              interval: yInterval,
              getTitlesWidget: (val, meta) {
                if (val == meta.min || val == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    _fmtY(val),
                    textAlign: TextAlign.left,
                    style: context.t.numSmall.copyWith(
                      color: context.c.text58,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: xInterval,
              getTitlesWidget: (val, meta) {
                // Etiket tick'in ÜZERİNDE ortalanır; kenara çok yakın bir
                // tick'in etiketi plot alanının dışına taşar. Zoom'da
                // interval artık sınırlara denk gelmediği için `val ==
                // meta.min/max` kontrolü yetmiyordu — bunun yerine viewport
                // genişliğinin %6'sı kadar bir kenar payı bırakıyoruz.
                final span = (meta.max - meta.min).abs();
                final edge = span * 0.06;
                if (val <= meta.min + edge || val >= meta.max - edge) {
                  return const SizedBox.shrink();
                }
                // Dinamik format — dar viewport'ta gün+ay, geniş
                // viewport'ta (365+ gün) sadece "MMM yy". Çok dar (<3 gün)
                // görünümde saat de göster.
                // Biçim kuralı `chart_axis.dart`'ta — takip listesi grafiği
                // de aynı fonksiyonu çağırır.
                //
                // Gün içi etiket eskiden dakikadan elle kuruluyor ve saat
                // `clamp(0, 23)` ile sıkıştırılıyordu: eksen günü aştığında
                // (19:41'den sonra, bkz. `gunIciEksenSonuDk`) gece yarısı
                // tick'i "00:00" yerine "23:00" yazıyor, yani var olmayan bir
                // saati işaretliyordu.
                final label = zamanEtiketi(
                  intraday
                      ? start.add(Duration(minutes: val.round()))
                      : start.add(Duration(minutes: (val * 24 * 60).round())),
                  // `spanGun` adı GÜN demek ama gün içi eksende X
                  // DAKİKA cinsinden. Dönüştürülmezse eşik karşılaştırması
                  // saçmalar: 1 günlük eksen 1440 "gün" gibi okunur.
                  spanGun: intraday
                      ? (meta.max - meta.min).abs() / 1440.0
                      : (meta.max - meta.min).abs(),
                  gunIci: intraday,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  // Sabit genişlik + ortalama: fl_chart etiketi tick'te
                  // ortalar, taşan metin ellipsis olur ve komşu etiketle
                  // çakışmaz.
                  //
                  // Genişlik etiketin EN UZUN hâline göre: çok günlü gün
                  // içi eksende "11 Eyl 04:00" yazılıyor ve 74px'e
                  // sığmayıp kırpılıyordu.
                  child: SizedBox(
                    width: intraday && (meta.max - meta.min).abs() > 1440
                        ? 88
                        : 74,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: context.t.numSmall.copyWith(
                        color: context.c.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // ── Bar tipi: her nokta için dikey çubuk ──────────────────
        //
        // `fl_chart`'ın `BarChart`'ı kullanılamıyor: orada X data-space
        // değil GRUP indeksi, yani zoom/pan ve tarih ekseni bozulurdu.
        // Bunun yerine her nokta iki spot'lu ayrı bir `LineChartBarData`
        // olarak çiziliyor — aynı teknik ekranın karşılaştırma bölümünde
        // de kullanılıyor.
        //
        // Yoğun serilerde (169 nokta) çubuklar birbirine girmesin diye
        // seyreltiliyor; sınır grafiğin okunabilir kaldığı yoğunluk.
        //
        // Taban DÖNEM BAŞI (ilk noktanın değeri), pencere dibi değil —
        // gerekçe `_cubukSegmentleri` doküman yorumunda.
        lineBarsData: tip == GrafikTipi.bar
            ? _cubukSegmentleri(
                context,
                segments,
                segments.isEmpty || segments.first.spots.isEmpty
                    ? viewMinY
                    : segments.first.spots.first.y,
                plotWidthPx,
                viewMinX,
                viewMaxX,
              )
            : tip == GrafikTipi.candle
            ? _mumSegmentleri(
                context,
                segments,
                plotWidthPx,
                viewMinX,
                viewMaxX,
                start: start,
                intraday: intraday,
              )
            : segments.map((seg) {
                final isActive = seg.thickness > 2.0;
                // Nokta yoğunluğu arttıkça çizgi inceltilir — intraday ve haftalık
                // (saatlik) yüzlerce nokta içerir, kalın çizgi zigzag'i yutar.
                // Trading uygulamalarındaki gibi ince ve okunaklı bir hat için:
                //
                // Merdivenin kendisi `chart_line_width.dart`'ta: takip/karşılaştır
                // grafiği de AYNI fonksiyonu çağırıyor. Kopyalanmış üç merdiven,
                // iki ekranın aynı dönemi farklı kalınlıkta çizmesinin sebebiydi.
                //
                // Gün içi sekmesi `days: 0` taşır; fonksiyon `<= 1` dalında zaten
                // gün içi kalınlığını verir, ayrıca `intraday` sormaya gerek yok.
                final periodDays = _PortfolioPerformanceScreenState._periods[_selectedPeriodIdx].days;
                final activeBarWidth = donemCizgiKalinligi(periodDays);
                final effectiveBarWidth =
                    isActive ? activeBarWidth : seg.thickness;
                // İlk/son X'i closure dışında bir kez oku. Bu callback'ler
                // fl_chart tarafından NOKTA BAŞINA çağrılıyor; içeride
                // `seg.spots.first`/`.last` demek her nokta için tekrar
                // erişim + karşılaştırma demekti.
                final firstX =
                    seg.spots.isEmpty ? double.nan : seg.spots.first.x;
                final lastX = seg.spots.isEmpty ? double.nan : seg.spots.last.x;

                // ── Baseline: dönem başına göre kazanç/kayıp rengi ─────────
                //
                // `fl_chart` tek bir çizgiyi iki renge bölemiyor; renk geçişi
                // gradyan stop'larıyla kuruluyor. Taban, dönemin İLK değeri:
                // "bugün nerede başladım, şimdi neredeyim" sorusu bu.
                //
                // Kapalı kuyruk bu boyamanın DIŞINDA — orası nötr kalmalı.
                final tabanY = seg.spots.isEmpty ? 0.0 : seg.spots.first.y;
                final baselineAktif =
                    tip == GrafikTipi.baseline && !seg.piyasaKapali && isActive;

                return LineChartBarData(
                  spots: seg.spots,
                  isCurved: false,
                  color: baselineAktif ? null : seg.lineColor,
                  // Baseline'da renk gradyanla veriliyor; `color` ile birlikte
                  // kullanılamaz (fl_chart ikisini birden kabul etmez).
                  gradient: baselineAktif
                      ? _baselineGradient(context, seg.spots, tabanY)
                      : null,
                  // Bar tipinde çizgi GİZLİ: çubuklar ayrı katmanda çiziliyor
                  // ve üstüne bir de çizgi binmesi grafiği okunamaz yapardı.
                  barWidth: tip == GrafikTipi.bar ? 0.0 : effectiveBarWidth,
                  // Piyasa kapalıyken taşınan fiyat KESİKLİ çizilir. Rengi
                  // `lineColor` zaten nötr geliyor (bkz. `_convertHistoryToSegments`);
                  // desen, renk körlüğünde de ayırt edilebilsin diye ikinci bir
                  // sinyal olarak ekleniyor.
                  dashArray: seg.piyasaKapali ? const [4, 4] : null,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, barData) {
                      if (!isActive) return false;
                      // Simülasyonda nokta yok — sadece süreklilik çizgisi.
                      if (_simulate) return false;
                      // Intraday: sadece ilk ve son noktada dot göster (5 dk
                      // aralıklı yüzlerce nokta olduğu için hepsini işaretlemek
                      // grafiği bulanıklaştırır).
                      if (intraday) {
                        // "Şimdi" noktası her zaman görünür.
                        if (spot.x == lastX) return true;
                        // Gün içi İŞLEM noktaları da görünür.
                        //
                        // Sebep: sıçramanın görünürlüğü mutlak tutara değil ORANA
                        // bağlı. Tüm portföy görünümünde küçük bir alım Y ekseninde
                        // kaybolur (500.000 TL'nin %1'i düz görünür), tür filtresi
                        // uygulanınca aynı alım belirgin basamak olur. Nokta,
                        // sıçrama görünmediğinde bile "burada işlem yapıldı"
                        // bilgisini taşır ve tooltip'e bağlanır.
                        return dotThinner.shows(spot.x);
                      }
                      // İlk/son nokta her zaman görünür; alım dot'ları ise
                      // piksel bazlı seyreltmeden geçer (bkz. `dotThinner`) —
                      // yoğun alım günlerinde üst üste binip yığın oluşmasın.
                      if (spot.x == firstX || spot.x == lastX) {
                        return true;
                      }
                      return dotThinner.shows(spot.x);
                    },
                    getDotPainter: (spot, percent, barData, index) {
                      final isFirst = spot.x == firstX;
                      final isLast = spot.x == lastX;
                      // Intraday'de sadece "şimdi" noktasını canlı bir amber
                      // dot ile göster — trading uygulaması hissiyatı için
                      // ince halka ile.
                      if (intraday && isLast) {
                        // "Şu an" noktası.
                        //
                        // Piyasa KAPALIYKEN gri: o noktada canlı bir fiyat yok,
                        // son kapanış taşınıyor. Yeşil bırakmak "şu anda işlem
                        // görüyor" derdi (kullanıcı isteği 2026-09-12: "şu an
                        // noktası piyasa kapalı andaysa gri şekilde kesikli
                        // çizginin ucunda konumlanmalı").
                        final kapali = seg.piyasaKapali;
                        return FlDotCirclePainter(
                          radius: 5.0,
                          color: kapali ? context.c.text36 : context.c.gain,
                          strokeColor: context.c.text90,
                          strokeWidth: 1.6,
                        );
                      }
                      // Başlangıç dot'u kaldırıldı — "orada alım yapılmış" gibi
                      // yanıltıcı görünüyordu. Başlangıç zaten dashed marker +
                      // label ile işaretli. Son nokta (şimdi) canlı vurgusu için
                      // büyük yeşil dot ile kalır.
                      if (isFirst) {
                        return FlDotCirclePainter(
                          radius: 0,
                          color: Colors.transparent,
                          strokeWidth: 0,
                        );
                      }
                      if (isLast) {
                        return FlDotCirclePainter(
                          radius: 6.0,
                          color: context.c.gain,
                          strokeColor: context.c.text90,
                          strokeWidth: 2.5,
                        );
                      }
                      // Ortadaki işlem noktaları — "şimdi" noktasından belirgin
                      // şekilde küçük. Önceki 4.5px + 2px halka (toplam ~8.5px çap)
                      // yoğun alım yapılan aylarda çizgiyi boncuk dizisine
                      // çeviriyordu. Halka da inceltildi: küçük yarıçapta 2px'lik
                      // kenar dolgunun yarısını yiyip noktayı içi boş gösteriyordu.
                      return FlDotCirclePainter(
                        radius: 3.0,
                        color: context.c.amberText,
                        strokeColor: context.c.text90,
                        strokeWidth: 1.2,
                      );
                    },
                  ),
                  // ── Dolgu: grafik TİPİNE göre ───────────────────────────
                  //
                  // `line`      → dolgu yok, yalnızca çizgi.
                  // `mountain`  → gradyan dolgu (eski varsayılan görünüm).
                  // `baseline`  → dönem başına göre üstü kazanç / altı kayıp.
                  // `bar`       → çizgi gizli, çubuklar ayrı katmanda.
                  //
                  // Kapalı kuyruk HER TİPTE dolgusuz: o bölge birikim değil,
                  // taşınan son fiyat (bkz. `TransactionSegment.piyasaKapali`).
                  belowBarData: (tip == GrafikTipi.mountain &&
                          !seg.piyasaKapali)
                      ? BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: intraday
                                ? [
                                    context.c.amberFill.withValues(alpha: 0.22),
                                    context.c.amberFill.withValues(alpha: 0.06),
                                    Colors.transparent,
                                  ]
                                : [seg.areaGradientStart, Colors.transparent],
                            stops: intraday ? const [0.0, 0.5, 1.0] : null,
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        )
                      : BarAreaData(show: false),
                );
              }).toList(),
        // fl_chart'ın built-in touch'ı kapalı — crosshair TEK KAYNAK.
        // Kullanıcı uzun bastığında `ZoomableChart` snap edilmiş X'te dikey
        // çizgi + pill (fiyat/tarih/getiri/hareketler) gösterir. Tooltip ve
        // crosshair paralel çalışınca X hesabı farklı olup değerler
        // uyumsuz görünüyordu — tek kaynağa çektik.
        //
        // `enabled: false` de şart: `handleBuiltInTouches` yalnızca tooltip'i
        // kapatır, dokunma işleme katmanı açık kalır. `asset_detail_screen`
        // ikisini birden veriyordu, burası vermiyordu — aynı jest iki ekranda
        // farklı davranıyordu.
        lineTouchData: LineTouchData(
          enabled: false,
          handleBuiltInTouches: false,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.c.surface2,
            tooltipRoundedRadius: 10,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            getTooltipItems: (spots) {
              final tryFmt0 = ref.read(bazParaProvider).formatter(digits: 0);
              // Primary segmentteki ilk ve son x — anchor / bugün tespiti.
              final firstX = primarySeg.spots.first.x;
              final lastX = primarySeg.spots.last.x;
              final firstY = primarySeg.spots.first.y;
              final lastY = primarySeg.spots.last.y;

              return spots.map((s) {
                // Non-intraday: s.x kesirli gün → dakika cinsinden ekle.
                // `.toInt()` kullanılırsa saat/dakika kısmı düşer ve tooltip
                // etiketi yakınlardaki tarihe kayıyor.
                final date = intraday
                    ? start.add(Duration(minutes: s.x.toInt()))
                    : start.add(Duration(minutes: (s.x * 24 * 60).round()));
                final isFirst = s.x == firstX;
                final isLast = s.x == lastX;

                // O gün YAPILAN alım/satım hareketleri (Gerçek modda).
                double dayBuyTRY = 0, daySellTRY = 0;
                // İlk noktadan (anchor) bugüne kadar KÜMÜLATİF hareketler.
                double cumBuyTRY = 0, cumSellTRY = 0;
                if (!_simulate && !intraday) {
                  final spotDayMs = dayKey(date)
                      .millisecondsSinceEpoch;
                  for (final a in assets) {
                    if (!a.isActive) continue;
                    final aDay = DateTime(a.addedDate.year, a.addedDate.month,
                            a.addedDate.day)
                        .millisecondsSinceEpoch;
                    final onSameDay = aDay == spotDayMs;
                    final onOrBefore = aDay <= spotDayMs;
                    if (a.isBuy) {
                      if (onSameDay) dayBuyTRY += a.totalCostTRY;
                      if (onOrBefore) cumBuyTRY += a.totalCostTRY;
                    } else if (a.isSell) {
                      if (onSameDay) daySellTRY += a.totalCostTRY;
                      if (onOrBefore) cumSellTRY += a.totalCostTRY;
                    }
                  }
                }

                final dayNet = dayBuyTRY - daySellTRY;
                final hasActivity = dayBuyTRY > 0 || daySellTRY > 0;

                // Anchor'a göre net getiri (bugüne kadarki maliyet vs
                // portföy değeri). Sadece son nokta için göster.
                final gainVsAnchor = lastY - firstY;

                final children = <TextSpan>[
                  TextSpan(
                    text: tryFmt0.format(s.y),
                    style: context.t.numSmall.copyWith(
                      color: context.c.gold,
                      fontSize: 15,
                    ),
                  ),
                ];

                // Bugün (son nokta) → getiri
                if (isLast && !_simulate && gainVsAnchor.abs() > 0.5) {
                  final positive = gainVsAnchor >= 0;
                  children.add(TextSpan(
                    text:
                        '${context.l10n.tooltipReturn}${positive ? '+' : '−'}${tryFmt0.format(gainVsAnchor.abs())}',
                    style: context.t.numSmall.copyWith(
                      color: positive ? context.c.gain : context.c.loss,
                      fontSize: 11,
                    ),
                  ));
                }

                // O gün yapılan hareketler
                if (hasActivity) {
                  if (dayBuyTRY > 0) {
                    children.add(TextSpan(
                      text: '${context.l10n.tooltipBuy}${tryFmt0.format(dayBuyTRY)}',
                      style: context.t.numSmall.copyWith(
                        color: context.c.gain,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ));
                  }
                  if (daySellTRY > 0) {
                    children.add(TextSpan(
                      text: '${context.l10n.tooltipSell}${tryFmt0.format(daySellTRY)}',
                      style: context.t.numSmall.copyWith(
                        color: context.c.loss,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ));
                  }
                  if (dayBuyTRY > 0 && daySellTRY > 0) {
                    children.add(TextSpan(
                      text:
                          '${context.l10n.tooltipNet}${dayNet >= 0 ? '+' : '−'}${tryFmt0.format(dayNet.abs())}',
                      style: context.t.numSmall.copyWith(
                        color: context.signColor(dayNet),
                        fontSize: 11,
                      ),
                    ));
                  }
                }

                // İlk nokta (anchor) — birikmiş yatırım toplamı bilgisi
                // (bu döneme kadar tüm buy - sell). Kullanıcı "grafik
                // buradan başlıyor, ne kadar para koydum?" sorusuna
                // cevap alsın.
                if (isFirst && !_simulate && cumBuyTRY > 0) {
                  final cumNet = cumBuyTRY - cumSellTRY;
                  children.add(TextSpan(
                    text: '${context.l10n.tooltipInvested}${tryFmt0.format(cumNet)}',
                    style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0,
                      color: context.c.text58,
                    ),
                  ));
                }

                // Saatlik çubukta ve "şimdi" noktasında saat de yazılır
                // (kullanıcı isteği 2026-09-24, `fmtTarihSaat`).
                final headerLabel = intraday
                    ? DateFormat('HH:mm', 'tr_TR').format(date)
                    : fmtTarihSaat(date);
                return LineTooltipItem(
                  '$headerLabel\n',
                  context.t.bodySmall!.copyWith(
                      color: context.c.text58, fontWeight: FontWeight.w500),
                  children: children,
                );
              }).toList();
            },
          ),
        ),
      );
    }

    // Volume subchart için sync viewport. Aynı controller ZoomableChart ve
    // ZoomableBarChart tarafından paylaşılır → üstte pinch/pan yapılınca
    // alt panel de aynı X aralığına oturur.
    final viewport = _ensureViewport(
      key:
          '${_zoomKey ?? "n/a"}|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$intraday',
      fullMinX: minX,
      fullMaxX: maxX,
    );

    // Volume verisi: gün-bazlı buy/sell TRY. Intraday'de bar chart mantıklı
    // değil (gün içi işlem yoğunluğu farklı bir metrik) → sadece intraday
    // olmayan periyotlarda çizilir.
    final volumeBars = intraday
        ? const <_VolumeBar>[]
        : _computeVolumeBars(allTargetAssets ?? const [], start);
    final showVolume = volumeBars.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 20, 16, 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      // Stack: grafik araçları kartın köşelerinde, akışın dışında. Tam
      // ekran sağ üstte (2026-09-15, "vertical butonu da grafiğin sağ
      // üstünde olmalı"), tip seçici altta. `clipBehavior: none` — çip
      // kartın dolgusuna taşar, plot alanından yer yemez.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
        children: [
          ZoomableChart(
            fullMinX: minX,
            fullMaxX: maxX,
            // 328'den 296'ya (2026-09-15, "grafik layoutunun yüksekliği
            // biraz azaltılabilir"). Daha azı Y ekseninde iki etiketi
            // birbirine yaklaştırıp gün içi bandı (%0,5) okunmaz yapar.
            height: 296,
            builder: buildData,
            viewportController: viewport,
            // Sağdaki Y ekseni rezervi (rightTitles.reservedSize ile aynı).
            // Crosshair bu alana **girmez** — plot area net sınırlı.
            plotPaddingRight: 60,
            onViewportChanged: intraday
                ? null
                : (viewMinX, viewMaxX) {
                    final controller = _zoomController;
                    if (controller == null) return;
                    final from =
                        start.add(Duration(minutes: (viewMinX * 1440).round()));
                    final to =
                        start.add(Duration(minutes: (viewMaxX * 1440).round()));
                    controller.updateViewport(from, to);
                  },
            crosshairSnapX: (x) {
              // Kuyruk dahil TÜM noktalar: piyasa kapalı bölgesinde de
              // crosshair kaymalı (bkz. `crosshairSpots`).
              final spots = crosshairSpots;
              if (spots.isEmpty) return x;
              final clamped = x.clamp(spots.first.x, spots.last.x);
              // Spot'lar X'e göre sıralı → ikili arama (bkz. nearestSpotIndex).
              // Bu callback parmak her kaydığında çağrılıyor.
              return spots[nearestSpotIndex(spots, clamped)].x;
            },
            crosshairLabelBuilder: (x) {
              // x zaten crosshairSnapX ile snap edildi — burada eşleşen spot'u bul.
              // Kaynak `crosshairSnapX` ile AYNI olmalı: farklı listelerde
              // arayınca snap edilen X ile gösterilen değer ayrışırdı.
              final spots = crosshairSpots;
              if (spots.isEmpty) return null;
              final snapped = spots[nearestSpotIndex(spots, x)];
              final date = intraday
                  ? dayKey(start)
                      .add(Duration(minutes: snapped.x.round()))
                  : start.add(Duration(minutes: (snapped.x * 1440).round()));
              final title = ref.read(bazParaProvider).fmt(snapped.y);
              // Gün içi etiket normalde yalnızca saat yazar — tek gün
              // çizildiği için tarih gereksiz gürültüydü. Ama piyasa
              // kapalıyken seri BİRDEN ÇOK günü kapsıyor (Cuma→Pazar) ve
              // saat tek başına "Cmt 14:00" ile "Cuma 14:00"ı ayırt
              // ettirmez. Kullanıcı isteği (2026-09-12): "grafik
              // detaylarını gün ve tarih bilgisiyle görebilmeliyim."
              final cokGunlu = intraday && segments.any((s) => s.piyasaKapali);
              final subtitle = intraday
                  ? (cokGunlu
                      ? DateFormat('d MMM · HH:mm', 'tr_TR').format(date)
                      : DateFormat('HH:mm', 'tr_TR').format(date))
                  // Kullanıcı isteği (2026-09-24): "grafik üzerinde gezinirken
                  // hangi saatteyim görmeliyim." 1H saatlik çubuk ve "şimdi"
                  // noktası saat taşır; günlük/haftalık çubuk 00:00'dır ve
                  // `fmtTarihSaat` orada yalnızca tarih yazar.
                  : fmtTarihSaat(date);
              return (title, subtitle);
            },
            crosshairDetailsBuilder: (x) {
              // Snap edilmiş spot'u bul (crosshairSnapX zaten uyguladı).
              // Kaynak diğer iki callback ile AYNI liste olmalı.
              final spots = crosshairSpots;
              if (spots.isEmpty || _simulate || intraday) return const [];
              // Diğer crosshair callback'leriyle aynı ikili arama.
              final snapped = spots[nearestSpotIndex(spots, x)];
              final tryFmt0 = ref.read(bazParaProvider).formatter(digits: 0);
              final firstY = spots.first.y;
              final gain = snapped.y - firstY;
              final date =
                  start.add(Duration(minutes: (snapped.x * 1440).round()));
              final spotDayMs = dayKey(date)
                  .millisecondsSinceEpoch;
              double dayBuy = 0, daySell = 0;
              for (final a in txAssets) {
                if (!a.isActive) continue;
                final addMid = DateTime(
                        a.addedDate.year, a.addedDate.month, a.addedDate.day)
                    .millisecondsSinceEpoch;
                if (addMid != spotDayMs) continue;
                if (a.isBuy) dayBuy += a.totalCostTRY;
                if (a.isSell) daySell += a.totalCostTRY;
              }
              final out = <(String, Color)>[];
              if (gain.abs() > 0.5) {
                final positive = gain >= 0;
                out.add((
                  'Getiri ${positive ? '+' : '−'}${tryFmt0.format(gain.abs())}',
                  positive ? context.c.gain : context.c.loss,
                ));
              }
              if (dayBuy > 0) {
                out.add((
                  'Alım +${tryFmt0.format(dayBuy)}',
                  context.c.gain,
                ));
              }
              if (daySell > 0) {
                out.add((
                  'Satış −${tryFmt0.format(daySell)}',
                  context.c.loss,
                ));
              }
              return out;
            },
          ),
          if (showVolume) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Text(
                context.l10n.tradeVolumeUpper,
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.text58,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 70,
              child: ListenableBuilder(
                listenable: viewport,
                builder: (_, __) {
                  final vp = viewport;
                  final maxY = volumeBars.fold<double>(
                      0, (m, b) => b.total > m ? b.total : m);
                  // Her bar için 2 spot'lu ayrı bir LineChartBarData → dikey
                  // çubuk. fl_chart'ın BarChart'ında X data-space değil, group
                  // index olduğu için sync viewport için LineChart hilesi kullanıyoruz.
                  final chartMaxY = maxY == 0 ? 1.0 : maxY * 1.15;
                  // En küçük çubuk bile görünür kalsın. Tek büyük alım
                  // ölçeği belirlediğinde küçük işlemler 1px'in altına
                  // düşüp "kırıntı" gibi görünüyordu — panelin %6'sı kadar
                  // bir taban yüksekliği veriyoruz. Ölçek yine gerçek: bu
                  // yalnızca ÇİZİM tabanı, `b.total` değeri değişmiyor.
                  final minVisibleY = chartMaxY * 0.06;
                  final bars = <LineChartBarData>[];
                  for (final b in volumeBars) {
                    final buyPositive = b.buy >= b.sell;
                    final color = buyPositive ? context.c.gain : context.c.loss;
                    final drawY = b.total < minVisibleY ? minVisibleY : b.total;
                    bars.add(LineChartBarData(
                      spots: [FlSpot(b.x, 0), FlSpot(b.x, drawY)],
                      isCurved: false,
                      color: color.withValues(alpha: 0.85),
                      barWidth: 3,
                      isStrokeCapRound: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ));
                  }
                  return LineChart(
                    LineChartData(
                      minX: vp.minX,
                      maxX: vp.maxX,
                      minY: 0,
                      maxY: chartMaxY,
                      clipData: const FlClipData.all(),
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      // ⚠️ Ana grafik sağda 60px'i Y-ekseni etiketlerine
                      // ayırıyor (`rightTitles.reservedSize`). Bu panel hiç
                      // rezerv ayırmazsa AYNI X değeri iki panelde farklı
                      // piksele düşer — çubuklar fiyat grafiğine göre sağa
                      // kayar. Etiketleri gizli ama aynı genişlikte bir
                      // rezerv koyarak iki plot area'yı hizalıyoruz.
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 60,
                            // Etiket yok — yalnızca hizalama rezervi.
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      lineBarsData: bars,
                    ),
                    // Ana grafikle aynı motion token'ları — hacim paneli
                    // periyot değişiminde onunla birlikte morf'lansın, kendi
                    // başına (fl_chart varsayılanı 150ms/linear) kaymasın.
                    duration: SandikMotion.state,
                    curve: SandikMotion.enter,
                  );
                },
              ),
            ),
          ],
          // Grafik tipi seçici — kabın DİBİNDE, etkilediği şeyin yanında.
          //
          // 2026-09-15'e kadar dönem satırının sağ ucundaydı; kullanıcı
          // bildirimi: "chart çizgi göstergesi de grafiğin dibinde olmalı".
          // Kontrolü uzaktan değil, sonucunun yanından değiştirmek doğru:
          // tip değişiminin etkisi hemen üstteki seride görünüyor.
          //
          // `duz` görünüm: kabuksuz, eksen etiketleriyle aynı tonda. İlk
          // deneme surface2 + kenarlıklı çipti ve kartın içinde yabancı
          // duruyordu ("bulunduğu layera uygun olmalı") — kart zaten bir
          // yüzey, içine ikinci bir yüzey koymak katman hiyerarşisini bozar.
          const Align(
            alignment: Alignment.centerLeft,
            child: GrafikTipiSecici(gorunum: GrafikTipiGorunum.duz),
          ),
        ],
          ),
          // Tam ekran çipi KALDIRILDI (kullanıcı kararı, 2026-09-17): "çok
          // da bir avantajı yok gibi, ilerde talep edilirse yaparız."
          // Uygulaması git geçmişinde (ea7bc0a).
        ],
      ),
    );
  }

  /// Chart + wrap widget'ları — hem intraday hem controller-based data için.
  ///
  /// [waiting] yeni veri yükleniyor (üstte ince progress bar).
  /// [hasData] çizilebilir bir seri var mı. False iken SADECE grafik alanı
  /// spinner'a döner; ortak sekmesi, tip çipleri ve periyot toggle'ı ekranda
  /// ve tıklanabilir kalır. Bu metod her durumda çağrılmalıdır — çağıranın
  /// erken return etmesi filtreleri de siler.
  /// [stale] eldeki seri bir ÖNCEKİ periyoda/filtreye ait mi. Grafik soluk
  /// çizilir ve sayısal özet kartı gizlenir: eski rakamlar yeni periyodun
  /// rakamı sanılmasın. Spinner yerine soluk grafik göstermek periyot
  /// değişiminde çok daha akıcı hissettiriyor.
  /// [settled] veri isteği sonuçlandı mı (başarı ya da hata farketmez).
  /// `!hasData && settled` → beklenecek bir şey yok; spinner yerine
  /// "alınamadı" durumu çizilir.
  /// Bar tipi: her noktayı tabandan yukarı uzanan dikey çubuk yapar.
  ///
  /// Çubuk yüksekliği görünür Y tabanından (`tabanY`) noktanın değerine
  /// kadar. Mutlak sıfırdan başlamak yanlış olurdu: portföy 2,5 milyon
  /// TL'de gezinirken çubukların tamamı ekranı doldurur ve aralarındaki
  /// fark görünmez olurdu.
  ///
  /// Çubuk grafiği: her çubuk DÖNEM BAŞINDAN o ana kadarki değişimi gösterir.
  ///
  /// Taban neden `viewMinY` değil: çubuklar görünür pencerenin alt kenarından
  /// başlayınca, değerler birbirine yakın olduğunda (portföy ₺2,49M–₺2,51M
  /// arası gezerken) hepsi neredeyse eşit yükseklikte çıkıyor ve grafik
  /// taralı bir duvara dönüyordu — ₺12.794'lük düşüş grafikte görünmüyordu.
  /// Dönem başı taban alınınca çubuk yukarı (kazanç) ya da aşağı (kayıp)
  /// büyür; bar grafiğinin anlattığı şey değişimin YÖNÜ ve BÜYÜKLÜĞÜ olur.
  /// `baseline` tipi de aynı tabanı kullanıyor (`seg.spots.first.y`).
  ///
  /// Çubuk sayısı ve kalınlığı, verinin GERÇEKTE kapladığı piksel
  /// genişliğinden hesaplanır — grafiğin tamamından değil. Gün içi eksen
  /// 00:00–24:00 gösterirken seans yalnızca 10:00–18:00 arası olduğu için
  /// çubuklar grafiğin üçte birine sıkışıyor; tam genişliği varsayan hesap
  /// onları üst üste bindiriyordu. Eski kod ayrıca segment BAŞINA 60 çubuk
  /// çiziyordu; sınır artık toplam nokta üzerinden.
  List<LineChartBarData> _cubukSegmentleri(
    BuildContext context,
    List<TransactionSegment> segments,
    double tabanY,
    double grafikGenisligi,
    double viewMinX,
    double viewMaxX,
  ) {
    // Çubuk + boşluk için piksel bütçesi: 6px altında çubuklar bitişik
    // görünüyor, 22px üstünde seyrek ve kaba duruyor.
    const minAralikPx = 6.0;
    const maksAralikPx = 22.0;

    final toplamNokta =
        segments.fold<int>(0, (t, s) => t + s.spots.length);
    if (toplamNokta == 0) return const [];

    final genislik = grafikGenisligi.isFinite && grafikGenisligi > 0
        ? grafikGenisligi
        : 320.0;

    // Kalınlık, verinin GERÇEKTE kapladığı piksel genişliğinden hesaplanır —
    // grafiğin tamamından değil.
    //
    // Gün içi eksen 00:00–24:00 gösterir ama seans yalnızca 10:00–18:00
    // arasıdır: çubuklar grafiğin ~üçte birine sıkışır. Genişliğin tamamına
    // yayıldıklarını varsayan hesap, aralarındaki mesafeyi olduğundan büyük
    // sanıp çubukları ÜST ÜSTE bindiriyordu (kullanıcı bildirimi, ekran
    // görüntüsüyle: günlükte dolu kırmızı blok).
    var veriMinX = double.infinity;
    var veriMaxX = double.negativeInfinity;
    for (final seg in segments) {
      for (final s in seg.spots) {
        if (s.x < veriMinX) veriMinX = s.x;
        if (s.x > veriMaxX) veriMaxX = s.x;
      }
    }
    final gorunurAralik = viewMaxX - viewMinX;
    final veriAralik = veriMaxX - veriMinX;
    // Veri, görünür pencerenin ne kadarını kaplıyor? (0…1]
    final kaplamaOrani =
        (gorunurAralik.isFinite && gorunurAralik > 0 && veriAralik > 0)
            ? (veriAralik / gorunurAralik).clamp(0.05, 1.0)
            : 1.0;
    final veriGenisligiPx = genislik * kaplamaOrani;

    final maksCubuk = (veriGenisligiPx / minAralikPx).floor().clamp(8, 240);
    final adim = (toplamNokta / maksCubuk).ceil().clamp(1, 1 << 30);

    // Gerçekte kaç çubuk çizileceğinden kalınlığı türet: seyrek veride
    // kalın ve okunaklı, yoğun veride ince ama bitişik değil.
    final cizilecek = (toplamNokta / adim).ceil().clamp(1, maksCubuk);
    final aralikPx =
        (veriGenisligiPx / cizilecek).clamp(minAralikPx, maksAralikPx);
    // Çubuklar arasında en az ~%35 boşluk kalsın — bitişik çubuklar
    // bar grafiğini alan grafiğine çevirir.
    final cubukKalinligi = (aralikPx * 0.65).clamp(2.0, 14.0);

    final out = <LineChartBarData>[];
    // Sayaç segmentler ARASINDA sürüyor: her segment kendi başına
    // seyreltilirse kısa segmentler orantısız çok çubuk alır.
    var sayac = 0;

    for (final seg in segments) {
      if (seg.spots.isEmpty) continue;

      final secilen = <FlSpot>[];
      for (final s in seg.spots) {
        if (sayac % adim == 0) secilen.add(s);
        sayac++;
      }
      // Son nokta ("şimdi") seyreltmeye kurban gitmemeli.
      if (secilen.isEmpty || secilen.last.x != seg.spots.last.x) {
        secilen.add(seg.spots.last);
      }

      for (final s in secilen) {
        // Renk değişimin yönünden: taban üstü kazanç, altı kayıp. Kapalı
        // piyasa segmenti kendi soluk rengini korur (veri yok, tahmin var).
        final renk = seg.piyasaKapali
            ? context.c.text36
            : (s.y >= tabanY ? context.c.gain : context.c.loss);

        out.add(LineChartBarData(
          spots: [FlSpot(s.x, tabanY), FlSpot(s.x, s.y)],
          isCurved: false,
          color: renk,
          barWidth: cubukKalinligi,
          // Yuvarlak uç modern bar grafiklerinin okunabilirliğini artırır;
          // ince çubukta fark etmez, kalın çubukta belirgin.
          isStrokeCapRound: cubukKalinligi >= 5,
          dashArray: seg.piyasaKapali ? const [3, 3] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ));
      }
    }
    return out;
  }

  /// Baseline tipi için dikey gradyan: taban ÜSTÜ kazanç, ALTI kayıp.
  ///
  /// `fl_chart` bir çizgiyi iki renge bölemiyor. Çözüm, çizginin kapladığı
  /// Y aralığında tabanın nereye düştüğünü oran olarak hesaplayıp
  /// gradyan stop'unu tam oraya koymak. İki stop AYNI noktada olduğu için
  /// geçiş yumuşamaz — keskin bir sınır oluşur.
  ///
  /// Taban aralığın dışındaysa (çizgi tamamen tabanın üstünde ya da
  /// altında) tek renk döner; yoksa `stops` sıralaması bozulur ve
  /// `fl_chart` assert atar.
  /// Mum tipi — kova bazlı OHLC (bkz. `utils/mum_turetici.dart`).
  ///
  /// Her mum İKİ `LineChartBarData`: ince FİTİL (en düşük → en yüksek) ve
  /// kalın GÖVDE (açılış → kapanış). Çubuk tipiyle aynı yaklaşım: fl_chart
  /// 0.68'de mum çizimi yok, aynı x'te iki noktalı dikey çizgi mumun
  /// kendisidir. Doji (açılış = kapanış) yuvarlak uçlu sıfır uzunluklu
  /// gövde, yani bir nokta olarak görünür.
  ///
  /// Noktalar segment sınırına göre DEĞİL, piyasa durumuna göre gruplanır:
  /// işlem segmentleri (kalınlık değişimi) bir kovayı ortadan bölerdi ve aynı
  /// x'te iki mum üst üste binerdi. Kapalı piyasa noktaları ayrı gruptur ki
  /// gri/kesikli çizilsin.
  ///
  /// Kova görünen aralığa göre seçilir (`mumKovasiSec`): gün içi 5 dk'lık
  /// seride 30 dk, 1Y'de 7 gün. Gövde genişliği kovanın piksel karşılığının
  /// %65'i (2–14 px) — çubuk tipiyle aynı oran.
  List<LineChartBarData> _mumSegmentleri(
    BuildContext context,
    List<TransactionSegment> segments,
    double grafikGenisligi,
    double viewMinX,
    double viewMaxX, {
    required DateTime start,
    required bool intraday,
  }) {
    final genislik = grafikGenisligi.isFinite && grafikGenisligi > 0
        ? grafikGenisligi
        : 320.0;
    final gorunurAralik =
        (viewMaxX - viewMinX).isFinite && viewMaxX > viewMinX
            ? viewMaxX - viewMinX
            : null;

    // Ekran X'i epoch DEĞİL: gün içi DAKİKA, diğer dönemler KESİRLİ GÜN
    // (`seriler.dart`). Türetici epoch ms bekler; dönüşüm
    // `mumlariGrafikUzayinda`'da ve mumlar ekran biriminde döner.
    //
    // 2026-09-15'e kadar noktalar dönüştürülmeden veriliyordu: 0–720 "ms"
    // 1970'in ilk dakikasına düşüyor, tek mum üretiliyor ve merkezi
    // görünür aralığın çok dışında kalıyordu — "mum çalışmıyor". Saf
    // fonksiyon testleri ms ile beslendiği için yakalanmamıştı.
    final birimMs = intraday ? 60 * 1000.0 : 24 * 60 * 60 * 1000.0;
    final baslangicMs = start.millisecondsSinceEpoch.toDouble();

    final acikSpots = <FlSpot>[];
    final kapaliSpots = <FlSpot>[];
    for (final seg in segments) {
      (seg.piyasaKapali ? kapaliSpots : acikSpots).addAll(seg.spots);
    }

    final out = <LineChartBarData>[];
    for (final (spots, kapali) in [(acikSpots, false), (kapaliSpots, true)]) {
      final mumlar = mumlariGrafikUzayinda(spots,
          baslangicMs: baslangicMs, birimMs: birimMs);
      for (final m in mumlar) {
        // Gövde: kovanın piksel karşılığının %65'i (2–14 px) — çubuk tipiyle
        // aynı oran. Kova artık görünür aralıkla aynı birimde; aylık kova
        // ay uzunluğuna göre değiştiği için mum başına hesaplanır.
        final kovaPx = gorunurAralik == null
            ? 8.0
            : genislik * (m.kovaMs / gorunurAralik);
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
    }
    return out;
  }

  LinearGradient _baselineGradient(
    BuildContext context,
    List<FlSpot> spots,
    double tabanY,
  ) {
    final kazanc = context.c.gain;
    final kayip = context.c.loss;

    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    // Düz çizgi ya da bozuk aralık: bölmeye gerek yok.
    if (!minY.isFinite || !maxY.isFinite || (maxY - minY).abs() < 1e-9) {
      final renk = spots.isNotEmpty && spots.last.y >= tabanY ? kazanc : kayip;
      return LinearGradient(colors: [renk, renk]);
    }

    if (tabanY >= maxY) {
      return LinearGradient(colors: [kayip, kayip]);
    }
    if (tabanY <= minY) {
      return LinearGradient(colors: [kazanc, kazanc]);
    }

    // Gradyan yukarıdan aşağı akar: 0.0 = maxY, 1.0 = minY.
    final oran = ((maxY - tabanY) / (maxY - minY)).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [kazanc, kazanc, kayip, kayip],
      stops: [0.0, oran, oran, 1.0],
    );
  }

  /// Gün-bazlı buy/sell TRY hacim. X price chart ile aynı gün-fraction
  /// birimde.
  List<_VolumeBar> _computeVolumeBars(List<Asset> assets, DateTime start) {
    // Ana chart'ın X birimi ile birebir aynı: kesirli gün (1 saat = 1/24).
    //
    // ⚠️ `start` bir DUVAR SAATİ damgasıdır (`endDate.subtract(days)`), yani
    // içinde bugünün saati vardır — gece yarısı değildir. İşlem tarihleri ise
    // gece yarısına normalize. İkisinin farkı bu yüzden negatif-kesirli çıkar
    // ve `~/` sıfıra doğru kırptığı için çubuklar bir gün kayıyor, aynı güne
    // düşenler tamamen eleniyordu ("kesik" görünen hacim paneli).
    //
    // Ana grafik bu hatayı yapmıyor: o `date.difference(startDate).inMinutes /
    // (60*24)` ile KESİRLİ gün üretiyor. Hacim paneli de aynı tabana oturmalı,
    // aksi halde iki panel farklı X uzayında çizilir.
    final startMidnight = dayKey(start);
    // Grafiğin X'i `start`'a göre; gece yarısı ile arasındaki kayma sabit.
    final startOffsetDays =
        startMidnight.difference(start).inMinutes / (60.0 * 24.0);

    final Map<int, ({double buy, double sell})> perDay = {};
    for (final a in assets) {
      if (!a.isActive) continue;
      final dayMidnight =
          dayKey(a.addedDate);
      // Gece yarısı ↔ gece yarısı farkı — tam gün, kırpma sorunu yok.
      final dayIdx = dayMidnight.difference(startMidnight).inDays;
      if (dayIdx < 0) continue;
      final prev = perDay[dayIdx] ?? (buy: 0.0, sell: 0.0);
      if (a.isBuy) {
        perDay[dayIdx] = (buy: prev.buy + a.totalCostTRY, sell: prev.sell);
      } else if (a.isSell) {
        perDay[dayIdx] = (buy: prev.buy, sell: prev.sell + a.totalCostTRY);
      }
    }
    final out = <_VolumeBar>[];
    perDay.forEach((day, tot) {
      if (tot.buy + tot.sell <= 0) return;
      // ⚠️ Çubuk GÜN ORTASINA (+0.5) DEĞİL, günün BAŞINA konur.
      //
      // Fiyat serisinin noktaları `ResolutionTier.normalizeTs` ile GECE
      // YARISINA snap edilir (daily tier'da `DateTime(y, m, d)`), X ekseni
      // tarih etiketleri de aynı anlara düşer. Çubuğu gün ortasına koymak
      // onu fiyat noktasından yarım gün sağa kaydırıyordu — ekranda
      // "çubuklar timeline ile örtüşmüyor" görüntüsünün sebebi buydu.
      //
      // `startOffsetDays` gece yarısı tabanını grafiğin `start` tabanına
      // taşır; ikisi birlikte, çubuğu o günün fiyat noktasıyla BİREBİR
      // aynı X'e oturtur.
      out.add(_VolumeBar(
        x: startOffsetDays + day.toDouble(),
        buy: tot.buy,
        sell: tot.sell,
      ));
    });
    return out;
  }

  Set<double> _buyDayKeys(
      List<TransactionSegment> segments, List<Asset> assets, DateTime start,
      {required bool intraday}) {
    // Cache anahtarı: başlangıç + varlık kimlikleri + segment imzası.
    // Segment imzası nokta SAYISI ile yetinmemeli — periyot/veri değişince
    // sayı aynı kalıp X aralığı kayabilir (örn. 30 günlük iki farklı
    // pencere). İlk/son X de anahtara giriyor ki bayat cache dönmesin.
    //
    // `id` tek başına yetmez: yumuşak silme `isActive`'i çevirir ama id'yi
    // değiştirmez — anahtar sabit kalır ve silinen lot'un noktası cache'ten
    // dönmeye devam ederdi. Aşağıdaki filtre alanları anahtara giriyor.
    // `intraday` anahtara GİRER: aynı segment kümesi için gün içi mod saati
    // korur, diğer modlar gece yarısına kırpar. Anahtarda olmasaydı sekme
    // değişince bayat X'ler dönerdi.
    final sig = StringBuffer()
      ..write(intraday ? 'i|' : 'd|')
      ..write(start.millisecondsSinceEpoch)
      ..write('|')
      ..write(assets
          .map((a) =>
              '${a.id}:${a.isActive ? 1 : 0}${a.isBuy ? 'b' : a.isSell ? 's' : 'x'}')
          .join(','));
    for (final s in segments) {
      sig
        ..write('|')
        ..write(s.spots.length);
      if (s.spots.isNotEmpty) {
        sig
          ..write(':')
          ..write(s.spots.first.x)
          ..write('-')
          ..write(s.spots.last.x);
      }
    }
    final key = sig.toString();
    if (_buyDayKeysCacheKey == key && _buyDayKeysCache != null) {
      return _buyDayKeysCache!;
    }

    // Varlıkların alım günlerini bir kez "gün damgası" set'ine indir; sonra
    // her spot için O(1) lookup. İç içe `assets.any(...)` taraması gitti.
    //
    // FİLTRE ŞART: bu set noktanın çizilip çizilmeyeceğine karar veriyor,
    // dolayısıyla tooltip/crosshair'in "o gün işlem var mı" testiyle AYNI
    // kümeden beslenmeli (bkz. `crosshairDetailsBuilder`). Filtresiz haliyle
    // temettü kayıtları (ne buy ne sell), deleteLog mezar taşları ve yumuşak
    // silinmiş lot'lar da nokta üretiyordu: grafikte nokta görünüyor, ama
    // basınca "Alım/Satış" satırı çıkmıyordu.
    // İşlem günlerini grafiğin X birimine (kesirli gün) çevir.
    final startMidnight = dayKey(start);
    final txXs = <double>[];
    for (final a in assets) {
      if (!a.isActive) continue;
      if (!a.isBuy && !a.isSell) continue;
      final d = a.addedDate;
      // Gün içi ("GÜNLÜK") seride SAAT KORUNUR.
      //
      // Burada eskiden koşulsuz `dayKey(d)` vardı —
      // işlemin saati kırpılıp gece yarısına çekiliyordu. Günlük/haftalık
      // seride bu doğrudur (bar zaten güne snap edilir), ama gün içi seride
      // 5 dakikalık slotlarla çalışılır: 14:00'te yapılan alım 00:00'a
      // düşünce grafiğin görünür aralığının DIŞINA çıkıyor ve nokta hiç
      // doğmuyordu. Sıçramanın ölçek yüzünden görünmediği durumda
      // (tüm portföy görünümü) geriye hiçbir işaret kalmıyordu.
      final anchor = intraday ? d : dayKey(d);
      txXs.add(anchor.difference(startMidnight).inMinutes / (60.0 * 24.0));
    }

    // ── İşlemi KAPSAYAN spot'a bağla, tam gün eşleşmesi ARAMA ──────────────
    //
    // Eski hâli `spot.günü == işlem.günü` eşitliği arıyordu ve 6A/1Y'de
    // noktaların kaybolmasının sebebi buydu: o periyotlarda veri
    // `ResolutionTier.weekly` gelir ve her nokta haftanın PAZARTESİSİNE snap
    // edilir (bkz. `ResolutionTierMeta.normalizeTs`). Çarşamba yapılan alımın
    // günü hiçbir spot'a eşit olmadığı için aday bile üretilmiyordu — yani
    // seyreltme değil, noktanın kendisi hiç doğmuyordu. Aynı sorun 1H'de
    // saatlik snap yüzünden hafta sonu/kapanış sonrası işlemlerde çıkıyordu.
    //
    // Artık her işlem, X'i kendisine eşit veya kendisinden küçük olan son
    // spot'a (içine düştüğü bar'a) bağlanır.
    final keys = <double>{};
    for (final seg in segments) {
      if (seg.thickness <= 2.0) continue;
      final spots = seg.spots;
      if (spots.isEmpty) continue;
      for (final txX in txXs) {
        final i = coveringSpotIndex(spots, txX);
        // -1: işlem serinin başlangıcından önce — o nokta grafikte yok.
        if (i < 0) continue;
        keys.add(spots[i].x);
      }
    }

    _buyDayKeysCacheKey = key;
    _buyDayKeysCache = keys;
    return keys;
  }
}
