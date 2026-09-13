import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../services/daily_summary.dart' show DailySummary;
import '../services/period_summary_service.dart';
import '../services/recap_service.dart' show PortfolioCharacter, RecapAsset;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Özet sekmesinin gövdesi — üç blok, her dönemde aynı iskelet.
///
/// ## Neden üç blok ve neden bu sırayla
/// 1. **Tek ana rakam** — kullanıcı ekrana bakınca tek bir sayı görmeli.
///    İki eşit ağırlıklı sayı gösteren bir özet, özet değildir.
/// 2. **"Nereden geldi" köprüsü** — bu ekranın en ayırt edici parçası.
///    Dönem başı / katkı / piyasa / bugün dört çubuk olarak yan yana
///    durur. Katkı çubuğu MAVİ (info) çünkü getiri DEĞİL; yalnızca piyasa
///    çubuğu yeşil/kırmızı olur. Renk burada bir süs değil, ekranın
///    taşıdığı tek argüman.
/// 3. **Döneme özgü bağlam** — GÜNLÜK'te gün içi eğri, 1H'de en iyi/en
///    zayıf, 1A'da TÜFE, 6A'da benchmark, 1Y'de karakter + reel getiri.
///
/// ## Ton (`RETENTION_STRATEJISI.md` §8 ve §9 — pazarlıksız)
/// * Kayıptaki dönemde kutlama dili YOK (Monzo Wrapped'in eleştirildiği
///   hata: kötü haberi kutlama formatında sunmak).
/// * "Portföyün düştü!" gibi uyarı dili de YOK — kayıp anındaki bildirim
///   panik satışı tetikler. Yerine daha uzun pencere bağlamı verilir.
/// * Öneri/eylem dili YOK (SPK): durum bildirilir, eylem önerilmez.
///   "Portföyünün %38'i altında" ✅ — "Altın al" ❌.
/// * Emoji yağmuru, streak rozeti, geri sayım, FOMO yok.
///
/// ## Tasarım jetonları
/// Renk `context.c`, tipografi `context.t`, süre `SandikMotion`. Elle
/// `TextStyle` ya da ham `Duration` yazılmaz: `context.t` sistem "Kalın
/// Metin" erişilebilirlik ayarını tek noktada çözüyor ve elle yazılan bir
/// stil o yolu atlıyor (bkz. `bold_text_support_test`,
/// `design_token_leak_test`).
class PeriodSummaryView extends StatelessWidget {
  final PeriodSummary summary;

  /// Daha uzun pencerenin getirisi — kayıp döneminde bağlam cümlesi için.
  ///
  /// "Bu ay ekside. Yıl hâlâ +%31,8." cümlesinin ikinci yarısı buradan
  /// gelir. `null` ise cümle yalnızca durumu bildirir.
  final double? uzunDonemPct;

  /// 1Y bloğunda gösterilen portföy karakteri.
  final PortfolioCharacter? karakter;

  /// 1Y bloğunda "en sabırlı varlık".
  final RecapAsset? enSabirli;
  final int? enSabirliGun;

  /// 6A bloğundaki yüzdelik dilim (1 = en üst, 100 = en alt).
  final int? percentile;
  final int? percentileKatilimci;

  /// 1Y paylaş butonu. `null` ise buton çizilmez.
  final VoidCallback? onShare;

  const PeriodSummaryView({
    super.key,
    required this.summary,
    this.uzunDonemPct,
    this.karakter,
    this.enSabirli,
    this.enSabirliGun,
    this.percentile,
    this.percentileKatilimci,
    this.onShare,
  });

  static final _tryFmt =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    if (!summary.isMeaningful) return _BosDurum(period: summary.period);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnaRakamKarti(summary: summary, uzunDonemPct: uzunDonemPct),
        const SizedBox(height: SandikSpace.smd),
        _KopruKarti(summary: summary),
        const SizedBox(height: SandikSpace.smd),
        ..._baglamBloklari(context),
      ],
    );
  }

  /// Blok 3 — döneme göre değişen tek parça.
  List<Widget> _baglamBloklari(BuildContext context) {
    final bloklar = <Widget>[];

    switch (summary.period) {
      case SummaryPeriod.gunluk:
        if (summary.sparkline.length >= 2) {
          bloklar.add(_GunIciEgriKarti(summary: summary));
        }
        if (summary.enIyi != null || summary.enZayif != null) {
          bloklar.add(_VarlikKarti(
            baslik: 'Günün en çok hareket edeni',
            enIyi: summary.enIyi,
            enZayif: summary.enZayif,
          ));
        }

      case SummaryPeriod.birHafta:
        if (summary.enIyi != null || summary.enZayif != null) {
          bloklar.add(_VarlikKarti(
            baslik: 'Haftanın uçları',
            enIyi: summary.enIyi,
            enZayif: summary.enZayif,
          ));
        }
        if (summary.gunSayimi != null) {
          bloklar.add(_GunSayimiKarti(sayim: summary.gunSayimi!));
        }

      case SummaryPeriod.birAy:
        if (summary.tufeFarki != null) {
          bloklar.add(_TufeKarti(
            fark: summary.tufeFarki!,
            getiriPct: summary.getiriPct,
          ));
        }
        if (summary.dagilimBasi != null && summary.dagilimSonu != null) {
          bloklar.add(_DagilimKarti(
            basi: summary.dagilimBasi!,
            sonu: summary.dagilimSonu!,
          ));
        }

      case SummaryPeriod.altiAy:
        if (percentile != null) {
          bloklar.add(_BenchmarkKarti(
            percentile: percentile!,
            katilimci: percentileKatilimci,
          ));
        }
        if (summary.enIyi != null || summary.enZayif != null) {
          bloklar.add(_VarlikKarti(
            baslik: 'Altı ayın uçları',
            enIyi: summary.enIyi,
            enZayif: summary.enZayif,
          ));
        }

      case SummaryPeriod.birYil:
        if (summary.tufeFarki != null) {
          bloklar.add(_ReelGetiriKarti(
            fark: summary.tufeFarki!,
            getiriPct: summary.getiriPct,
          ));
        }
        if (karakter != null) {
          bloklar.add(_KarakterKarti(karakter: karakter!));
        }
        if (enSabirli != null && enSabirliGun != null) {
          bloklar.add(_SabirKarti(varlik: enSabirli!, gun: enSabirliGun!));
        }
        if (summary.sparkline.length >= 2) {
          bloklar.add(_GunIciEgriKarti(summary: summary, baslik: 'Yıl eğrisi'));
        }
        if (onShare != null) {
          bloklar.add(_PaylasButonu(onShare: onShare!));
        }
    }

    // Aralar burada verilir; her kart kendi dışına boşluk koymaz.
    final out = <Widget>[];
    for (var i = 0; i < bloklar.length; i++) {
      out.add(bloklar[i]);
      if (i < bloklar.length - 1) {
        out.add(const SizedBox(height: SandikSpace.smd));
      }
    }
    return out;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BLOK 1 — tek ana rakam
// ═══════════════════════════════════════════════════════════════════════

/// Dönemin tek ana rakamı.
///
/// `_buildPeriodChangeCard` deseni: dönem adı üstte, tarih aralığı altında,
/// büyük tutar, yüzde rozeti ▲/▼. Değişim yoksa "Değişim yok" nötr hâli.
///
/// **Grafik sekmesindeki kartla aynı DEĞİL** ve olmaması kasıtlı: orası ham
/// "birikim" değişimini gösteriyor (alımlar dahil), burası saf piyasa
/// getirisini. Başlık hangisini gösterdiğini yazıyor, yoksa iki sekmede
/// farklı iki rakam gören kullanıcı hangisine güveneceğini bilemezdi.
class _AnaRakamKarti extends StatelessWidget {
  final PeriodSummary summary;
  final double? uzunDonemPct;

  const _AnaRakamKarti({required this.summary, this.uzunDonemPct});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final piyasa = s.piyasaTRY;
    final pct = s.getiriPct;

    // Sıfır bir YÖN taşımaz: yeşil bir "+₺0" olmayan bir hareketi varmış
    // gibi gösterir ve kırmızı gören kullanıcı "kaybettim" diye okur.
    final renk = s.isFlat
        ? context.c.text36
        : (s.isNegative ? context.c.loss : context.c.gain);
    final pozitif = !s.isNegative;

    final dateFmt = DateFormat(
      s.start.year == s.end.year ? 'd MMM' : 'd MMM y',
      'tr_TR',
    );
    final aralik = s.period.intraday
        ? DateFormat('d MMMM', 'tr_TR').format(s.start)
        : '${dateFmt.format(s.start)} → ${dateFmt.format(s.end)}';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.md2),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '${s.period.label} piyasa getirisi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.t.titleSmall?.copyWith(color: context.c.text58),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            aralik,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
          const SizedBox(height: SandikSpace.smd),
          Row(
            children: [
              // FittedBox: milyonluk portföyde 320pt'de punto düşsün ama
              // satır kırılmasın (taşma testi bunu kovalıyor).
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (s.isFlat || piyasa == null)
                        ? 'Değişim yok'
                        : '${pozitif ? '+' : '−'}'
                            '${PeriodSummaryView._tryFmt.format(piyasa.abs())}',
                    maxLines: 1,
                    style: context.t.numLarge.copyWith(color: renk),
                  ),
                ),
              ),
              if (pct != null && !s.isFlat) ...[
                const SizedBox(width: SandikSpace.sm),
                // Yön ikonu renge EK bir sinyal: renk körlüğünde de okunur.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm2, vertical: 5),
                  decoration: BoxDecoration(
                    color: renk.withValues(alpha: 0.14),
                    borderRadius: SandikRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pozitif
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: renk,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        fmtPct(pct.abs(), digits: 2),
                        style: context.t.numSmall.copyWith(color: renk),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          // Ton anahtarı: kayıpta kutlama da uyarı da yok, bağlam var.
          Text(
            PeriodSummaryService.tonCumlesi(s, uzunDonemPct: uzunDonemPct),
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BLOK 2 — "nereden geldi" köprüsü
// ═══════════════════════════════════════════════════════════════════════

/// Dönem başı → katkı → piyasa → bugün köprüsü.
///
/// **Ekranın en ayırt edici parçası ve var olma sebebi.** Dört çubuk, hepsi
/// aynı ölçekte (en büyük mutlak değere göre normalize). Kullanıcı tek
/// bakışta "portföyüm büyüdü ama ne kadarı benim paramdı" sorusunu
/// yanıtlayabilmeli.
///
/// **Renk kuralı pazarlıksız:** katkı çubuğu `info` mavisi — getiri DEĞİL,
/// kullanıcının kendi parası. Yalnızca piyasa çubuğu `gain`/`loss` alır.
/// Dördünü de yeşil yapmak ekranın taşıdığı tek argümanı yok ederdi.
class _KopruKarti extends StatelessWidget {
  final PeriodSummary summary;

  const _KopruKarti({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final bas = s.baslangicTRY;
    final son = s.sonTRY;
    final katki = s.katkiTRY;
    final piyasa = s.piyasaTRY;

    // Köprü ancak dört ucun hepsi ölçülebildiyse anlam taşır. Eksik bir
    // çubukla çizilen köprü "toplam = parçalar" iddiasını kırar.
    if (bas == null || son == null || katki == null || piyasa == null) {
      return const SizedBox.shrink();
    }

    final enBuyuk = [bas.abs(), son.abs(), katki.abs(), piyasa.abs()]
        .reduce((a, b) => a > b ? a : b);
    if (enBuyuk <= 0) return const SizedBox.shrink();

    final piyasaRenk = s.isFlat
        ? context.c.text36
        : (s.isNegative ? context.c.loss : context.c.gain);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.md2),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nereden geldi',
            style: context.t.titleSmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.smd),
          _CubukSatiri(
            etiket: 'Dönem başı',
            deger: bas,
            oran: bas.abs() / enBuyuk,
            renk: context.c.text36,
            isaretli: false,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            etiket: 'Katkın',
            deger: katki,
            oran: katki.abs() / enBuyuk,
            // MAVİ — getiri değil, kullanıcının kendi parası.
            renk: context.c.info,
            isaretli: true,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            etiket: 'Piyasa',
            deger: piyasa,
            oran: piyasa.abs() / enBuyuk,
            renk: piyasaRenk,
            isaretli: true,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            etiket: s.period.intraday ? 'Bugün' : 'Şimdi',
            deger: son,
            oran: son.abs() / enBuyuk,
            // Marka amberi METİN rengi olarak kullanılır; zemin amberFill
            // (bkz. design_token_leak_test — amberText zemin olamaz).
            renk: context.c.amberText,
            isaretli: false,
          ),
          const SizedBox(height: SandikSpace.smd),
          Divider(color: context.c.hairline, height: 1),
          const SizedBox(height: SandikSpace.smd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 13, color: context.c.text36),
              const SizedBox(width: SandikSpace.xs2),
              Expanded(
                child: Text(
                  'Mavi çubuk senin paran — getiri sayılmaz. '
                  'Yüzde yalnızca piyasa çubuğundan hesaplanır.',
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Köprünün tek satırı: `[etiket] [yatay çubuk] [değer]`.
class _CubukSatiri extends StatelessWidget {
  final String etiket;
  final double deger;

  /// 0…1 — en büyük mutlak değere göre.
  final double oran;
  final Color renk;

  /// Değer `+`/`−` işaretiyle mi yazılsın? Dönem başı ve şimdiki değer
  /// birer SEVİYE, işaret taşımazlar; katkı ve piyasa birer DEĞİŞİM.
  final bool isaretli;

  const _CubukSatiri({
    required this.etiket,
    required this.deger,
    required this.oran,
    required this.renk,
    required this.isaretli,
  });

  @override
  Widget build(BuildContext context) {
    final yazi = isaretli
        ? '${deger >= 0 ? '+' : '−'}'
            '${PeriodSummaryView._tryFmt.format(deger.abs())}'
        : PeriodSummaryView._tryFmt.format(deger.abs());

    return Semantics(
      label: '$etiket $yazi',
      child: Row(
        children: [
          // Etiket sütunu sabit: dört çubuğun sol kenarı hizalanmalı,
          // yoksa uzunluk farkı çubukları kaydırır ve karşılaştırma bozulur.
          SizedBox(
            width: 86,
            child: Text(
              etiket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              child: Stack(
                children: [
                  Container(height: 10, color: context.c.text20
                      .withValues(alpha: 0.25)),
                  FractionallySizedBox(
                    // Sıfır genişlikte çubuk görünmez olur; okunur bir
                    // asgari bırakılır ki "ölçüldü ve sıfıra yakın"
                    // bilgisi kaybolmasın.
                    widthFactor: oran.clamp(0.02, 1.0),
                    child: AnimatedContainer(
                      duration: SandikMotion.surfaceOf(context),
                      curve: SandikMotion.enter,
                      height: 10,
                      color: renk,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          // Değer sütunu da sabit genişlikte: sağ kenar hizalanınca göz
          // rakamları dikey olarak karşılaştırabiliyor.
          SizedBox(
            width: 92,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                yazi,
                maxLines: 1,
                style: context.t.numSmall.copyWith(color: renk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BLOK 3 — döneme özgü bağlam
// ═══════════════════════════════════════════════════════════════════════

/// Gün içi / yıl eğrisi — `DailySummary.normalizeForSparkline` ile aynı
/// normalize kuralından beslenir, böylece widget ve kilit ekranıyla aynı
/// eğri çizilir.
class _GunIciEgriKarti extends StatelessWidget {
  final PeriodSummary summary;
  final String baslik;

  const _GunIciEgriKarti({required this.summary, this.baslik = 'Gün içi'});

  @override
  Widget build(BuildContext context) {
    final renk = summary.isFlat
        ? context.c.text36
        : (summary.isNegative ? context.c.loss : context.c.gain);

    return _BaglamKarti(
      baslik: baslik,
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklinePainter(
            // ORTAK katmanın normalize kuralı — ikinci bir ölçek YAZILMAZ.
            //
            // `normalizeForSparkline` saf ve statik; eksen sınırlarını
            // `niceAxisBounds` üzerinden kuruyor. Burada kendi min/max'ımızı
            // almak aynı portföyü widget'ta, kilit ekranında ve bu kartta
            // farklı gösterirdi — üç yüzeyin ayrışma sebebi tam olarak bu
            // sınıf hataydı (bkz. daily_summary.dart "Neden ayrı bir dosya").
            noktalar: DailySummary.normalizeForSparkline(summary.sparkline),
            renk: renk,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> noktalar;
  final Color renk;

  const _SparklinePainter({required this.noktalar, required this.renk});

  @override
  void paint(Canvas canvas, Size size) {
    if (noktalar.length < 2) return;

    final path = Path();
    final dx = size.width / (noktalar.length - 1);
    for (var i = 0; i < noktalar.length; i++) {
      // Normalize 0…1 geliyor; 0 ALT kenar olduğu için y ters çevrilir.
      final y = size.height - noktalar[i].clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(dx * i, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = renk,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.renk != renk || old.noktalar != noktalar;
}

/// En iyi / en zayıf varlık satırları.
class _VarlikKarti extends StatelessWidget {
  final String baslik;
  final RecapAsset? enIyi;
  final RecapAsset? enZayif;

  const _VarlikKarti({required this.baslik, this.enIyi, this.enZayif});

  @override
  Widget build(BuildContext context) => _BaglamKarti(
        baslik: baslik,
        child: Column(
          children: [
            if (enIyi != null)
              _VarlikSatiri(varlik: enIyi!, renk: context.c.gain, yukari: true),
            if (enIyi != null && enZayif != null)
              const SizedBox(height: SandikSpace.sm),
            if (enZayif != null)
              _VarlikSatiri(
                  varlik: enZayif!, renk: context.c.loss, yukari: false),
          ],
        ),
      );
}

class _VarlikSatiri extends StatelessWidget {
  final RecapAsset varlik;
  final Color renk;
  final bool yukari;

  const _VarlikSatiri({
    required this.varlik,
    required this.renk,
    required this.yukari,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            yukari
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
            color: renk,
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              varlik.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(color: context.c.text90),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Text(
            '${varlik.changePct >= 0 ? '+' : '−'}'
            '${fmtPct(varlik.changePct.abs(), digits: 1)}',
            style: context.t.numSmall.copyWith(color: renk),
          ),
        ],
      );
}

/// "5 işlem gününün 3'ü artıda" — dönem dalgalılığı bağlamı.
class _GunSayimiKarti extends StatelessWidget {
  final ({int artida, int toplam}) sayim;

  const _GunSayimiKarti({required this.sayim});

  @override
  Widget build(BuildContext context) => _BaglamKarti(
        baslik: 'Dönem içi seyir',
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${sayim.toplam} işlem gününün ${sayim.artida}\'ü artıda '
                'kapandı.',
                style:
                    context.t.bodyMedium?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
}

/// TÜFE farkı — 1A bloğu.
class _TufeKarti extends StatelessWidget {
  final double fark;
  final double? getiriPct;

  const _TufeKarti({required this.fark, this.getiriPct});

  @override
  Widget build(BuildContext context) {
    final onde = fark >= 0;
    final ton = onde ? context.c.gain : context.c.loss;
    final mutlak = fark.abs().toStringAsFixed(1).replaceAll('.', ',');

    return _BaglamKarti(
      baslik: 'Enflasyona karşı',
      child: Row(
        children: [
          // Yön RENKLE anlatılmaz — ok her zaman yanında (RealReturnStrip
          // ile aynı kural).
          Text(
            onde ? '▲' : '▼',
            style: context.t.labelLarge
                ?.copyWith(color: ton, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              onde
                  ? 'Bu dönem enflasyonun $mutlak puan önünde.'
                  : 'Bu dönem enflasyonun $mutlak puan gerisinde.',
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reel getiri — 1Y bloğu (bileşik, puan farkından ayrı).
class _ReelGetiriKarti extends StatelessWidget {
  final double fark;
  final double? getiriPct;

  const _ReelGetiriKarti({required this.fark, this.getiriPct});

  @override
  Widget build(BuildContext context) {
    final onde = fark >= 0;
    final ton = onde ? context.c.gain : context.c.loss;
    final mutlak = fark.abs().toStringAsFixed(1).replaceAll('.', ',');

    return _BaglamKarti(
      baslik: 'Reel getiri',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${onde ? '+' : '−'}$mutlak puan',
            style: context.t.numMedium.copyWith(color: ton),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            onde
                ? 'Alım gücün bu dönem arttı.'
                : 'Alım gücün bu dönem geriledi.',
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ),
    );
  }
}

/// Tür dağılımı değişimi — 1A bloğu.
class _DagilimKarti extends StatelessWidget {
  final Map<AssetType, double> basi;
  final Map<AssetType, double> sonu;

  const _DagilimKarti({required this.basi, required this.sonu});

  @override
  Widget build(BuildContext context) {
    final basToplam = basi.values.fold<double>(0, (a, b) => a + b);
    final sonToplam = sonu.values.fold<double>(0, (a, b) => a + b);
    if (basToplam <= 0 || sonToplam <= 0) return const SizedBox.shrink();

    // İki uçtaki türlerin BİRLEŞİMİ: dönem içinde girilen ya da tamamen
    // çıkılan tür de görünmeli.
    final turler = <AssetType>{...basi.keys, ...sonu.keys}.toList()
      ..sort((a, b) => ((sonu[b] ?? 0) / sonToplam)
          .compareTo((sonu[a] ?? 0) / sonToplam));

    return _BaglamKarti(
      baslik: 'Dağılım değişimi',
      child: Column(
        children: [
          for (final t in turler.take(5)) ...[
            _DagilimSatiri(
              tur: t,
              basPay: (basi[t] ?? 0) / basToplam * 100,
              sonPay: (sonu[t] ?? 0) / sonToplam * 100,
            ),
            if (t != turler.take(5).last)
              const SizedBox(height: SandikSpace.sm),
          ],
        ],
      ),
    );
  }
}

class _DagilimSatiri extends StatelessWidget {
  final AssetType tur;
  final double basPay;
  final double sonPay;

  const _DagilimSatiri({
    required this.tur,
    required this.basPay,
    required this.sonPay,
  });

  @override
  Widget build(BuildContext context) {
    final delta = sonPay - basPay;
    // Yarım puanın altı gürültüdür; ok göstermek "değişti" sinyali verirdi.
    final anlamli = delta.abs() >= 0.5;

    return Row(
      children: [
        Expanded(
          child: Text(
            tur.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodyMedium?.copyWith(color: context.c.text90),
          ),
        ),
        Text(
          '${fmtPct(basPay, digits: 0)} → ${fmtPct(sonPay, digits: 0)}',
          style: context.t.numSmall.copyWith(color: context.c.text58),
        ),
        if (anlamli) ...[
          const SizedBox(width: SandikSpace.xs2),
          // Dağılım kayması bir KAZANÇ değil; yeşil/kırmızı vermek
          // "altına kayman iyi oldu" gibi bir yargı üretirdi (SPK: durum
          // bildir, eylem/yargı önerme). Nötr ton.
          Icon(
            delta > 0
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 12,
            color: context.c.text36,
          ),
        ],
      ],
    );
  }
}

/// Benchmark şeridi — 6A bloğu.
///
/// **Renk kuralı:** bütün çubuklar sessiz `text20`; YALNIZCA kullanıcının
/// çubuğu `amberFill`. Beş kategorik renk (kırmızıdan yeşile bir duvar)
/// sinyali öldürür — göz tek vurguyu arıyor.
class _BenchmarkKarti extends StatelessWidget {
  /// 1 = en üst dilim, 100 = en alt.
  final int percentile;
  final int? katilimci;

  const _BenchmarkKarti({required this.percentile, this.katilimci});

  /// Beş kova: ilk %20, %20-40, … Kullanıcının kovası vurgulanır.
  static const _kovaSayisi = 5;

  @override
  Widget build(BuildContext context) {
    final kova = ((percentile - 1) / (100 / _kovaSayisi)).floor()
        .clamp(0, _kovaSayisi - 1);
    final ustundeOlduklari = 100 - percentile;

    return _BaglamKarti(
      baslik: 'Altı aylık karşılaştırma',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _kovaSayisi; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: SandikMotion.surfaceOf(context),
                    curve: SandikMotion.enter,
                    height: 28,
                    decoration: BoxDecoration(
                      color: i == kova
                          ? context.c.amberFill
                          : context.c.text20.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
                if (i < _kovaSayisi - 1) const SizedBox(width: SandikSpace.xs),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            'Katılımcıların %$ustundeOlduklari kadarının üstündesin.'
            '${katilimci != null ? ' ($katilimci kişi)' : ''}',
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ],
      ),
    );
  }
}

/// Portföy karakteri — 1Y bloğu.
class _KarakterKarti extends StatelessWidget {
  final PortfolioCharacter karakter;

  const _KarakterKarti({required this.karakter});

  @override
  Widget build(BuildContext context) => _BaglamKarti(
        baslik: 'Portföyünün karakteri',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              karakter.label,
              style: context.t.numMedium.copyWith(color: context.c.amberText),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              karakter.tagline,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ],
        ),
      );
}

/// En sabırlı varlık — 1Y bloğu.
class _SabirKarti extends StatelessWidget {
  final RecapAsset varlik;
  final int gun;

  const _SabirKarti({required this.varlik, required this.gun});

  @override
  Widget build(BuildContext context) => _BaglamKarti(
        baslik: 'En sabırlı varlığın',
        child: Row(
          children: [
            Expanded(
              child: Text(
                varlik.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodyMedium?.copyWith(color: context.c.text90),
              ),
            ),
            Text(
              '$gun gün',
              style: context.t.numSmall.copyWith(color: context.c.text58),
            ),
          ],
        ),
      );
}

/// Paylaş butonu — 1Y bloğu.
///
/// Paylaşım kartı TUTAR İÇERMEZ (yüzde + etiket yeter): tutarlı bir kart
/// paylaşılmaz, tutarsız kart paylaşılır. Metni `RecapService.shareText`
/// üretir; buton yalnızca tetikler.
class _PaylasButonu extends StatelessWidget {
  final VoidCallback onShare;

  const _PaylasButonu({required this.onShare});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: onShare,
          icon: Icon(Icons.ios_share_rounded,
              size: 16, color: context.c.amberText),
          label: Text(
            'Özetini paylaş',
            style: context.t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.c.amberText,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: context.c.surface1,
            padding:
                const EdgeInsets.symmetric(vertical: SandikSpace.smd),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
          ),
        ),
      );
}

/// Bağlam bloklarının ortak kabuğu.
class _BaglamKarti extends StatelessWidget {
  final String baslik;
  final Widget child;

  const _BaglamKarti({required this.baslik, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.md2),
        decoration: context.surfaceCard(radius: SandikRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              baslik,
              style: context.t.titleSmall?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.smd),
            child,
          ],
        ),
      );
}

/// Veri yetersizse — sayı UYDURULMAZ.
///
/// `RecapData.isMeaningful` ile aynı disiplin: tek bir gerçek sayı olmadan
/// özet gösterilmez. Boş bir kutlama gören kullanıcı özelliği ciddiye almaz.
class _BosDurum extends StatelessWidget {
  final SummaryPeriod period;

  const _BosDurum({required this.period});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.lg),
        decoration: context.surfaceCard(radius: SandikRadius.lg),
        child: Column(
          children: [
            Icon(Icons.timelapse_rounded, size: 28, color: context.c.text36),
            const SizedBox(height: SandikSpace.smd),
            Text(
              '${period.label} için yeterli geçmiş yok',
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              'Bu dönem dolduğunda özet kendiliğinden görünür.',
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
          ],
        ),
      );
}
