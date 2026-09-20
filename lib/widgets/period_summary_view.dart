import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../models/yatirimci_seviyesi.dart';
import '../services/contribution_history_service.dart';
import '../services/daily_summary.dart' show DailySummary;
import '../services/insight_metrics_service.dart' show Concentration, Drawdown;
import '../services/period_summary_service.dart';
import '../services/recap_service.dart' show PortfolioCharacter, RecapAsset;
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

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

  /// Gösterim birimi (Faz 3.2). Varsayılan ₺; alt kartlara elle geçirilir
  /// ki widget'lar `ProviderScope`'suz testlerde de kurulabilsin.
  final BazPara baz;

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

  /// Birikim disiplini kartı — her dönemde gösterilir.
  ///
  /// **Neden döneme bağlı DEĞİL:** "düzenli biriktiriyor muyum" sorusu
  /// seçili pencereden bağımsız; kendi kova seçicisi var (haftalık/aylık/
  /// yıllık) ve onu ekran yönetiyor. Dönem anahtarına bağlansaydı kullanıcı
  /// aylık birikimini görmek için 1A sekmesine geçmek zorunda kalırdı.
  final Widget? katkiKarti;

  /// Portföy sağlığı kartı — 1Y bloğunda.
  ///
  /// Widget olarak alınıyor, ham metrik olarak değil: hesap ağa çıkıyor
  /// (`HistoryService` serisi) ve bu view SAF kalmalı. `_OzetYanVeri`
  /// kartı kurup buraya veriyor.
  final SaglikKarti? saglik;

  /// İleri seviye metrik kartı (Ayarlar › Görünüm › Yatırımcı seviyesi =
  /// İleri). Sağlık kartından SONRA çizilir; `null` ise yok.
  final Widget? ileriKarti;

  /// Para ağırlıklı yıllık getiri (%). `null` ise kart çizilmez.
  final double? xirr;

  /// TÜFE endeksi tabloda HİÇ YOK mu?
  ///
  /// `true` iken reel getiri yerine "veri bekleniyor" hâli çizilir. Sessiz
  /// kalmak yerine sebebi söylemek, `InflationService.isStale`
  /// notundaki gerekçeyle: dört ay sessizce çalışmayan bir cron bu projede
  /// zaten bir kez yaşandı.
  ///
  /// `false` VE reel getiri de yoksa (endeks var ama bu dönemin ucu yok)
  /// hiçbir şey çizilmez — o kullanıcıya özel ve geçici bir durum.
  final bool enflasyonVerisiBekleniyor;

  /// Derinlik bölümü (XIRR, sağlık, ileri metrikler, karakter, sabır,
  /// benchmark) başlangıçta açık mı? İleri seviye yatırımcıda açık, diğerinde
  /// katlı (2026-09-21 sadeleştirme). Testler varsayılanı açık görür.
  final bool derinlikAcik;

  const PeriodSummaryView({
    super.key,
    required this.summary,
    this.baz = const BazPara.lira(),
    this.uzunDonemPct,
    this.karakter,
    this.enSabirli,
    this.enSabirliGun,
    this.percentile,
    this.percentileKatilimci,
    this.onShare,
    this.katkiKarti,
    this.saglik,
    this.ileriKarti,
    this.xirr,
    this.enflasyonVerisiBekleniyor = false,
    this.derinlikAcik = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!summary.isMeaningful) return _BosDurum(period: summary.period);

    // 2026-09-21 sadeleştirme: on altı kart art arda değil, üç başlık.
    //   · BU DÖNEM  — ana rakam, köprü, reel getiri/TÜFE, gün sayımı, eğri,
    //                paylaş: dönemin kendisi.
    //   · VARLIKLAR — en iyi/en zayıf, dağılım, katkı: portföyün içi.
    //   · DERİNLİK  — XIRR, sağlık, ileri metrikler, karakter, sabır,
    //                benchmark: katlanır; ileri seviyede açık gelir.
    // Hiçbir kart kaldırılmadı; yalnızca yer ve sıra değişti.
    final g = _gruplar(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SandikSectionHeader(title: l10n.sectionThisPeriod),
        const SizedBox(height: SandikSpace.sm),
        _AnaRakamKarti(summary: summary, uzunDonemPct: uzunDonemPct, baz: baz),
        const SizedBox(height: SandikSpace.smd),
        _KopruKarti(summary: summary, baz: baz),
        ..._arali(g.buDonem, once: true),
        if (g.varliklar.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.md),
          SandikSectionHeader(title: l10n.sectionAssets),
          const SizedBox(height: SandikSpace.sm),
          ..._arali(g.varliklar),
        ],
        if (g.derinlik.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.md),
          _DerinlikBolumu(
            baslangictaAcik: derinlikAcik,
            cocuklar: _arali(g.derinlik),
          ),
        ],
      ],
    );
  }

  /// Blokların arasına standart boşluk; [once] true ise ilkinin önüne de.
  static List<Widget> _arali(List<Widget> bloklar, {bool once = false}) {
    final out = <Widget>[];
    for (var i = 0; i < bloklar.length; i++) {
      if (i > 0 || once) out.add(const SizedBox(height: SandikSpace.smd));
      out.add(bloklar[i]);
    }
    return out;
  }

  ({List<Widget> buDonem, List<Widget> varliklar, List<Widget> derinlik})
      _gruplar(BuildContext context) {
    final buDonem = <Widget>[];
    final varliklar = <Widget>[];
    final derinlik = <Widget>[];

    void reelYaDaTufe(String donemEtiketi) {
      if (summary.reelGetiriPct != null) {
        buDonem.add(_ReelGetiriKarti(
          reel: summary.reelGetiriPct!,
          nominal: summary.tufeNominalPct,
          tufe: summary.tufePct,
          fark: summary.tufeFarki,
          baslangic: summary.tufeBaslangic,
          bitis: summary.tufeBitis,
          donemEtiketi: donemEtiketi,
        ));
      } else if (summary.tufeFarki != null) {
        buDonem.add(_TufeKarti(fark: summary.tufeFarki!));
      } else if (enflasyonVerisiBekleniyor) {
        buDonem.add(const _EnflasyonBekleniyorKarti());
      }
    }

    void varlikKarti(String baslik) {
      if (summary.enIyi != null || summary.enZayif != null) {
        varliklar.add(_VarlikKarti(
          baslik: baslik,
          enIyi: summary.enIyi,
          enZayif: summary.enZayif,
        ));
      }
    }

    switch (summary.period) {
      case SummaryPeriod.gunluk:
        if (summary.sparkline.length >= 2) {
          buDonem.add(_GunIciEgriKarti(summary: summary));
        }
        varlikKarti(context.l10n.biggestMoverToday);

      case SummaryPeriod.birHafta:
        if (summary.gunSayimi != null) {
          buDonem.add(_GunSayimiKarti(sayim: summary.gunSayimi!));
        }
        varlikKarti(context.l10n.weekExtremes);

      case SummaryPeriod.birAy:
        reelYaDaTufe(context.l10n.lastMonthPeriod);
        if (summary.dagilimBasi != null && summary.dagilimSonu != null) {
          varliklar.add(_DagilimKarti(
            basi: summary.dagilimBasi!,
            sonu: summary.dagilimSonu!,
          ));
        }

      case SummaryPeriod.altiAy:
        reelYaDaTufe(context.l10n.last6MonthsPeriod);
        varlikKarti(context.l10n.sixMonthExtremes);
        if (percentile != null) {
          derinlik.add(_BenchmarkKarti(
            percentile: percentile!,
            katilimci: percentileKatilimci,
          ));
        }

      case SummaryPeriod.birYil:
        reelYaDaTufe(context.l10n.lastYearPeriod);
        if (summary.sparkline.length >= 2) {
          buDonem.add(_GunIciEgriKarti(
              summary: summary, baslik: context.l10n.yearCurve));
        }
        if (xirr != null) {
          derinlik.add(XirrKarti(
            xirr: xirr!,
            piyasaGetirisi: summary.getiriPct,
          ));
        }
        if (saglik != null) derinlik.add(saglik!);
        if (ileriKarti != null) derinlik.add(ileriKarti!);
        if (karakter != null) {
          derinlik.add(_KarakterKarti(karakter: karakter!));
        }
        if (enSabirli != null && enSabirliGun != null) {
          derinlik.add(_SabirKarti(varlik: enSabirli!, gun: enSabirliGun!));
        }
    }

    // Katkı kartı: gün içi hariç her dönemde, varlıklar bloğunda.
    if (katkiKarti != null && summary.period != SummaryPeriod.gunluk) {
      varliklar.add(katkiKarti!);
    }
    // Paylaş dönemin altında: kart paylaşılan şeyin hemen yanında.
    if (onShare != null) {
      buDonem.add(_PaylasButonu(onShare: onShare!));
    }

    return (buDonem: buDonem, varliklar: varliklar, derinlik: derinlik);
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
  final BazPara baz;

  const _AnaRakamKarti(
      {required this.summary, this.uzunDonemPct, required this.baz});

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
                  context.l10n.periodMarketReturn(
                      donemEtiketi(context.l10n, s.period.label)),
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
                            '${baz.fmt(piyasa.abs())}',
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
                      const SizedBox(width: SandikSpace.xxs),
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
  final BazPara baz;

  const _KopruKarti({required this.summary, required this.baz});

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
            context.l10n.whereItCameFrom,
            style: context.t.titleSmall?.copyWith(color: context.c.text58),
          ),
          const SizedBox(height: SandikSpace.smd),
          _CubukSatiri(
            baz: baz,
            etiket: context.l10n.periodStart,
            deger: bas,
            oran: bas.abs() / enBuyuk,
            renk: context.c.text36,
            isaretli: false,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            baz: baz,
            etiket: context.l10n.yourContribution,
            deger: katki,
            oran: katki.abs() / enBuyuk,
            // MAVİ — getiri değil, kullanıcının kendi parası.
            renk: context.c.info,
            isaretli: true,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            baz: baz,
            etiket: context.l10n.marketWord,
            deger: piyasa,
            oran: piyasa.abs() / enBuyuk,
            renk: piyasaRenk,
            isaretli: true,
          ),
          const SizedBox(height: SandikSpace.sm),
          _CubukSatiri(
            baz: baz,
            etiket: s.period.intraday
                ? context.l10n.todayWord
                : context.l10n.nowWord,
            deger: son,
            oran: son.abs() / enBuyuk,
            // Marka amberi METİN rengi olarak kullanılır; zemin amberFill
            // (bkz. design_token_leak_test — amberText zemin olamaz).
            renk: context.c.amberText,
            isaretli: false,
          ),
          // Temettü ve komisyon: ÇUBUK değil, alt satır.
          //
          // Çubuk olarak çizilselerdi köprünün "toplam = parçalar"
          // iddiasını kırardı — ikisi de zaten yukarıdaki çubukların
          // İÇİNDE (temettü piyasa çubuğunda erimiş, komisyon katkıya
          // dahil). Ayrı satır yalnızca görünürlük verir; toplama ikinci
          // kez eklenmezler ve bu ayrım burada yazılı durmalı, yoksa bir
          // sonraki değişiklik onları çubuğa çevirir.
          if (s.temettuTRY != null || s.komisyonTRY != null) ...[
            const SizedBox(height: SandikSpace.smd),
            Divider(color: context.c.hairline, height: 1),
            const SizedBox(height: SandikSpace.smd),
            if (s.temettuTRY != null)
              _KucukSatir(
                etiket: context.l10n.cashDividend,
                deger: baz.fmt(s.temettuTRY!),
                ton: context.c.gain,
              ),
            if (s.komisyonTRY != null) ...[
              if (s.temettuTRY != null) const SizedBox(height: SandikSpace.xs2),
              _KucukSatir(
                etiket: context.l10n.commissionPaid,
                deger: '−${baz.fmt(s.komisyonTRY!)}',
                ton: context.c.text58,
              ),
            ],
          ],

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
                  context.l10n.contributionNotReturn,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
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

  final BazPara baz;

  const _CubukSatiri({
    required this.etiket,
    required this.deger,
    required this.oran,
    required this.renk,
    required this.isaretli,
    required this.baz,
  });

  @override
  Widget build(BuildContext context) {
    final yazi = isaretli
        ? '${deger >= 0 ? '+' : '−'}'
            '${baz.fmt(deger.abs())}'
        : baz.fmt(deger.abs());

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
                  Container(
                      height: 10,
                      color: context.c.text20.withValues(alpha: 0.25)),
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

  /// `null` ise "Gün içi" (sözlükten). Varsayılan parametre olarak
  /// verilemez: `context` const bir başlangıç değerinde kullanılamaz.
  final String? baslik;

  const _GunIciEgriKarti({required this.summary, this.baslik});

  @override
  Widget build(BuildContext context) {
    final renk = summary.isFlat
        ? context.c.text36
        : (summary.isNegative ? context.c.loss : context.c.gain);

    return _BaglamKarti(
      baslik: baslik ?? context.l10n.intradayWord,
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
            yukari ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
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
        baslik: context.l10n.periodCourse,
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.greenDaysOfTotal(sayim.toplam, sayim.artida),
                style: context.t.bodyMedium?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
}

/// TÜFE farkı — 1A bloğu.
class _TufeKarti extends StatelessWidget {
  final double fark;

  const _TufeKarti({required this.fark});

  @override
  Widget build(BuildContext context) {
    final onde = fark >= 0;
    final ton = onde ? context.c.gain : context.c.loss;
    final mutlak = fmtNum(fark.abs(), digits: 1);

    return _BaglamKarti(
      baslik: context.l10n.againstInflation,
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
                  ? context.l10n.aheadOfInflationPeriod(mutlak)
                  : context.l10n.behindInflationPeriod(mutlak),
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reel getiri — ekranın en önemli kartı.
///
/// ## Neden ÜÇ sayı birden
/// Önceki hâli tek bir "puan farkı" gösteriyordu ve başlığı "Reel getiri"
/// idi — oysa gösterdiği şey reel getiri DEĞİLDİ, nominal ile TÜFE
/// arasındaki puan farkıydı. İkisi yüksek enflasyonda belirgin ayrışır:
/// %48,1 nominal / %36,7 TÜFE'de puan farkı 11,4 ama bileşik reel getiri
/// 8,34. Başlık ile içerik çelişiyordu.
///
/// Çözüm ikisinden birini silmek değil: ana rakam artık BİLEŞİK reel getiri
/// (matematiksel olarak doğru olan), altındaki satır üç girdiyi de açıkça
/// yazıyor (nominal, TÜFE, fark). Kullanıcı TÜİK'in açıkladığı rakamla
/// doğrulayabilmeli — yoksa kart bir kara kutu olur ve bu ekranın bütün
/// değeri güvenilir olmasından geliyor.
/// TÜFE penceresinin uçlarını AY olarak yazar ("Ağustos 2025").
///
/// Gün yazılmaz: endeks aylık bir ölçüm ve "31 Ağustos" yazmak, o gün
/// yapılmış bir ölçüm varmış izlenimi verirdi. Locale delegate yoksa
/// `context.l10n` Türkçe'ye düştüğü gibi biçim de 'tr_TR'ye düşer.
String _ayEtiketi(BuildContext context, DateTime t) =>
    DateFormat('MMMM yyyy', Localizations.localeOf(context).toString())
        .format(t);

class _ReelGetiriKarti extends StatelessWidget {
  /// Bileşik reel getiri (%). Ana rakam.
  final double reel;

  /// Nominal getiri (%) — ham girdi, doğrulama için.
  final double? nominal;

  /// Dönemin kümülatif TÜFE'si (%) — ham girdi.
  final double? tufe;

  /// Puan farkı (nominal − TÜFE). Gündelik dilin okuduğu sayı.
  final double? fark;

  /// Dönem etiketi ("Son 1 yılda"). Hangi pencere olduğu YAZILMALI:
  /// dönemsiz bir enflasyon karşılaştırması doğrulanamaz.
  final String donemEtiketi;

  /// Karşılaştırmanın GERÇEK uçları.
  ///
  /// Etiket ("son 1 yıl") yaklaşık; TÜFE aylık yayımlandığı için pencere
  /// son açıklanmış ayda biter ve bugüne kadar gelmez. Tarihleri yazmak o
  /// farkı görünür kılar — yazmazsak kullanıcı rakamı bugüne kadarki bir
  /// aralık sanır ve TÜİK'le kıyasladığında tutmadığını görür.
  final DateTime? baslangic;
  final DateTime? bitis;

  const _ReelGetiriKarti({
    required this.reel,
    required this.donemEtiketi,
    this.nominal,
    this.tufe,
    this.fark,
    this.baslangic,
    this.bitis,
  });

  @override
  Widget build(BuildContext context) {
    final onde = reel >= 0;
    final ton = onde ? context.c.gain : context.c.loss;
    final c = context.c;

    return _BaglamKarti(
      baslik: context.l10n.realReturnPeriod(donemEtiketi),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Yön RENKLE anlatılmaz — ok her zaman yanında.
              Text(
                onde ? '▲' : '▼',
                style: context.t.labelLarge
                    ?.copyWith(color: ton, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: SandikSpace.sm),
              Text(
                fmtPct(reel),
                style: context.t.numMedium.copyWith(color: ton),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            onde
                ? context.l10n.realReturnPositive
                : context.l10n.realReturnNegative,
            style: context.t.bodySmall?.copyWith(color: c.text58),
          ),
          // Ham girdiler: kullanıcı sayıyı TÜİK'le doğrulayabilmeli.
          if (nominal != null && tufe != null) ...[
            const SizedBox(height: SandikSpace.smd),
            Divider(color: c.hairline, height: 1),
            const SizedBox(height: SandikSpace.smd),
            _KucukSatir(
                etiket: context.l10n.nominalReturn, deger: fmtPct(nominal!)),
            const SizedBox(height: SandikSpace.xs2),
            _KucukSatir(etiket: context.l10n.periodCpi, deger: fmtPct(tufe!)),
            if (fark != null) ...[
              const SizedBox(height: SandikSpace.xs2),
              _KucukSatir(
                etiket: context.l10n.pointDifference,
                deger: '${fark! >= 0 ? '+' : '−'}'
                    '${fmtNum(fark!.abs(), digits: 1)} puan',
                ton: fark! >= 0 ? c.gain : c.loss,
              ),
            ],
            if (baslangic != null && bitis != null) ...[
              const SizedBox(height: SandikSpace.xs2),
              Text(
                context.l10n.cpiWindowRange(
                  _ayEtiketi(context, baslangic!),
                  _ayEtiketi(context, bitis!),
                ),
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// TÜFE endeksi henüz yok — reel getirinin YERİNE çizilir.
///
/// **Neden sessiz kalmıyoruz.** `inflation_index` boş doğuyor ve
/// doldurulması bir kurulum adımına bağlı (`EVDS_API_KEY`). Kart hiç
/// çizilmediğinde iki taraf da kör kalıyordu: kullanıcı özelliğin var
/// olduğunu bilmiyor, geliştirici de kurulumun eksik kaldığını fark
/// etmiyordu. Bu projede tam olarak bu hata sınıfı dört ay boyunca sessizce
/// yaşandı (bkz. `0054_cron_auth_header.sql`).
///
/// Ton dikkatli: bu bir HATA mesajı değil. Kullanıcının yaptığı bir şeyle
/// ilgili değil, düzeltebileceği bir şey de yok — bilgilendirir ve geçer.
/// Uyarı ikonu ya da kırmızı renk kullanılmaz.
class _EnflasyonBekleniyorKarti extends StatelessWidget {
  const _EnflasyonBekleniyorKarti();

  @override
  Widget build(BuildContext context) => _BaglamKarti(
        baslik: context.l10n.realReturn,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule_rounded, size: 15, color: context.c.text36),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.cpiNotLoaded,
                    style:
                        context.t.bodyMedium?.copyWith(color: context.c.text58),
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    context.l10n.cpiNotLoadedBody,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Kart içi `etiket … değer` satırı — ham girdileri listelemek için.
class _KucukSatir extends StatelessWidget {
  final String etiket;
  final String deger;
  final Color? ton;

  const _KucukSatir({required this.etiket, required this.deger, this.ton});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              etiket,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Text(
            deger,
            style: context.t.numSmall
                .copyWith(color: ton ?? context.c.text58, fontSize: null),
          ),
        ],
      );
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
      ..sort((a, b) =>
          ((sonu[b] ?? 0) / sonToplam).compareTo((sonu[a] ?? 0) / sonToplam));

    return _BaglamKarti(
      baslik: context.l10n.allocationChange,
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
            tur.labelOf(context.l10n),
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
    final kova = ((percentile - 1) / (100 / _kovaSayisi))
        .floor()
        .clamp(0, _kovaSayisi - 1);
    final ustundeOlduklari = 100 - percentile;

    return _BaglamKarti(
      baslik: context.l10n.sixMonthComparison,
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
            '${context.l10n.percentileSentence(ustundeOlduklari)}'
            '${katilimci != null ? ' ${context.l10n.nPeopleParen(katilimci!)}' : ''}',
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
        baslik: context.l10n.portfolioCharacter,
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
        baslik: context.l10n.mostPatientAsset,
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
              context.l10n.nDays(gun),
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
            context.l10n.shareSummary,
            style: context.t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.c.amberText,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: context.c.surface1,
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
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

// ═══════════════════════════════════════════════════════════════════════
// BLOK 4 — birikim disiplini, portföy sağlığı, para ağırlıklı getiri
//
// Bu üçü döneme DEĞİL kullanıcıya ait sorular:
//   · "düzenli biriktiriyor muyum?"      → ContributionKarti
//   · "yumurtalar tek sepette mi?"       → SaglikKarti
//   · "zamanlamam işe yaradı mı?"        → XirrKarti
// Hepsi verisi geldiğinde çizilir, gelmediğinde HİÇ çizilmez — bu ekranın
// baştan beri taşıdığı "ölçülmeyen sayı uydurulmaz" kuralı.
// ═══════════════════════════════════════════════════════════════════════

/// Birikim disiplini — haftalık / aylık / yıllık net katkı çubukları.
///
/// Kartın taşıdığı argüman: **piyasa senin kontrolünde değil, birikim
/// senin kontrolünde.** Kayıp dönemde bile doğru ve kullanıcıyı işlem
/// yapmaya değil devam etmeye yönlendiren tek sayı bu.
///
/// Negatif kova KIRMIZI çizilir ve "birikim" sayılmaz: para çekilen bir ayı
/// yeşil göstermek, kullanıcının kendi davranışı hakkında yanlış bilgi
/// vermek olurdu.
class ContributionKarti extends StatelessWidget {
  final ContributionSummary ozet;
  final ContributionInterval aralik;

  /// Aralık değiştirildiğinde. `null` ise seçici çizilmez.
  final ValueChanged<ContributionInterval>? onAralik;

  /// Gösterim birimi (Faz 3.2); varsayılan ₺.
  final BazPara baz;

  const ContributionKarti({
    super.key,
    required this.ozet,
    required this.aralik,
    this.onAralik,
    this.baz = const BazPara.lira(),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enBuyuk = ozet.enBuyukMutlak;

    return _BaglamKarti(
      baslik: context.l10n.savingDiscipline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onAralik != null) ...[
            _AralikSecici(secili: aralik, onSec: onAralik!),
            const SizedBox(height: SandikSpace.smd),
          ],

          // Hiç katkı yoksa çubuk çizmenin anlamı yok — dürüst boş hâl.
          if (ozet.bos)
            Text(
              context.l10n.noNewMoney,
              style: context.t.bodyMedium?.copyWith(color: c.text58),
            )
          else ...[
            Text(
              baz.fmt(ozet.toplamTRY),
              style: context.t.numMedium.copyWith(
                color: ozet.toplamTRY >= 0 ? c.amberText : c.loss,
              ),
            ),
            const SizedBox(height: SandikSpace.xxs),
            Text(
              aralik.sonNDonem(context.l10n, ozet.kovalar.length),
              style: context.t.bodySmall?.copyWith(color: c.text36),
            ),
          ],

          if (enBuyuk > 0) ...[
            const SizedBox(height: SandikSpace.md),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < ozet.kovalar.length; i++) ...[
                    if (i > 0) const SizedBox(width: SandikSpace.xs2),
                    Expanded(
                      child: _KatkiCubugu(
                        baz: baz,
                        kova: ozet.kovalar[i],
                        oran: ozet.kovalar[i].netTRY.abs() / enBuyuk,
                        aralik: aralik,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: SandikSpace.smd),
          Divider(color: c.hairline, height: 1),
          const SizedBox(height: SandikSpace.smd),

          if (ozet.ortalamaTRY != null)
            _KucukSatir(
              etiket: aralik.ortalamaBasligi(context.l10n),
              deger: baz.fmt(ozet.ortalamaTRY!),
            ),
          if (ozet.zirve != null) ...[
            const SizedBox(height: SandikSpace.xs2),
            _KucukSatir(
              etiket: context.l10n.highestWord,
              deger: baz.fmt(ozet.zirve!.netTRY),
            ),
          ],
          const SizedBox(height: SandikSpace.xs2),
          _KucukSatir(
            etiket: context.l10n.contributingPeriods,
            deger: '${ozet.katkiliKovaSayisi} / ${ozet.kovalar.length}',
          ),
          if (ozet.sonFarkTRY != null) ...[
            const SizedBox(height: SandikSpace.xs2),
            _KucukSatir(
              etiket: aralik.gecenDonemeGore(context.l10n),
              deger: '${ozet.sonFarkTRY! >= 0 ? '+' : '−'}'
                  '${baz.fmt(ozet.sonFarkTRY!.abs())}',
              ton: ozet.sonFarkTRY! >= 0 ? c.gain : c.loss,
            ),
          ],

          if (ozet.trend != null) ...[
            const SizedBox(height: SandikSpace.smd),
            Text(
              aralik.trendCumlesi(
                  context.l10n,
                  switch (ozet.trend!) {
                    ContributionTrend.artiyor => 1,
                    ContributionTrend.sabit => 0,
                    ContributionTrend.azaliyor => -1,
                  }),
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tek bir birikim çubuğu — yükseklik oranla, renk işaretle.
class _KatkiCubugu extends StatelessWidget {
  final ContributionBucket kova;
  final double oran;
  final ContributionInterval aralik;

  final BazPara baz;

  const _KatkiCubugu({
    required this.kova,
    required this.oran,
    required this.aralik,
    required this.baz,
  });

  /// Kova altındaki kısa etiket — pencereye göre değişir.
  String get _etiket => switch (aralik) {
        ContributionInterval.haftalik => '${kova.start.day}',
        ContributionInterval.aylik => _ayKisa[kova.start.month - 1],
        ContributionInterval.yillik => "'${kova.start.year % 100}",
      };

  static const _ayKisa = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Katkı AMBER: `_KopruKarti`'nda mavi olan "senin paran" fikri burada
    // markanın vurgu rengiyle taşınıyor — bu kartın tamamı zaten katkıyla
    // ilgili, mavi/yeşil ayrımına gerek yok. Negatif kova kırmızı.
    final renk = kova.bos
        ? c.text20.withValues(alpha: 0.35)
        : (kova.pozitif ? c.amberFill : c.loss);

    return Semantics(
      label: '$_etiket ${baz.fmt(kova.netTRY)}'
          '${kova.kismi ? aralik.devamEden(context.l10n) : ""}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              // Sıfır kova görünmez olmasın: ölçüldüğü belli olmalı.
              heightFactor: oran.clamp(0.04, 1.0),
              child: AnimatedContainer(
                duration: SandikMotion.surfaceOf(context),
                curve: SandikMotion.enter,
                decoration: BoxDecoration(
                  color: renk,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                  // Devam eden dönem KESİKLİ kenarla ayrılır: yarım ayı
                  // tam aylarla aynı görünümde çizmek, düşen bir çubuğu
                  // "birikimin azaldı" diye okuturdu.
                  border: kova.kismi
                      ? Border.all(color: context.c.amberText, width: 1)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            _etiket,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: context.t.bodySmall?.copyWith(
              color: kova.kismi ? context.c.amberText : context.c.text36,
            ),
          ),
        ],
      ),
    );
  }
}

/// Haftalık / Aylık / Yıllık anahtarı.
class _AralikSecici extends StatelessWidget {
  final ContributionInterval secili;
  final ValueChanged<ContributionInterval> onSec;

  const _AralikSecici({required this.secili, required this.onSec});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          for (final a in ContributionInterval.values)
            Expanded(
              child: Semantics(
                selected: a == secili,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSec(a),
                  child: AnimatedContainer(
                    duration: SandikMotion.surfaceOf(context),
                    curve: SandikMotion.enter,
                    decoration: BoxDecoration(
                      color: a == secili ? c.amberFill : Colors.transparent,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      a.labelOf(context.l10n),
                      style: context.t.labelMedium?.copyWith(
                        color: a == secili ? c.onAmber : c.text58,
                        fontWeight:
                            a == secili ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Portföy sağlığı — düşüş, oynaklık, yoğunlaşma.
///
/// ## Neden hiçbir yerde "riskli" yazmıyor
/// Üç metrik de OLAN BİTENİ bildirir, yorum yapmaz. "Portföyün riskli"
/// demek kullanıcının risk toleransı hakkında bir varsayım yapmaktır —
/// aynı %60 tek-varlık ağırlığı, 25 yaşındaki biri için makul, emekli için
/// değil ve bu ekran hangisi olduğunu bilmiyor. Sayı verilir, cümle
/// tanımlayıcıdır ("portföyünün %X'i tek varlıkta"), hüküm içermez.
class SaglikKarti extends StatelessWidget {
  final Drawdown? drawdown;
  final double? volatilite;
  final Concentration? yogunlasma;

  /// Metriklerin hesaplandığı pencere ("son 1 yıl").
  final String donemEtiketi;

  const SaglikKarti({
    super.key,
    required this.donemEtiketi,
    this.drawdown,
    this.volatilite,
    this.yogunlasma,
  });

  /// Tek bir metrik bile yoksa kart hiç çizilmemeli.
  bool get hasData =>
      drawdown != null || volatilite != null || yogunlasma != null;

  @override
  Widget build(BuildContext context) {
    if (!hasData) return const SizedBox.shrink();
    final c = context.c;
    final d = drawdown;
    final y = yogunlasma;

    return _BaglamKarti(
      baslik: context.l10n.portfolioHealthPeriod(donemEtiketi),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d != null) ...[
            _SaglikSatiri(
              baslik: context.l10n.maxDrawdown,
              deger: d.isFlat ? '—' : '%${fmtNum(d.yuzde, digits: 1)}',
              aciklama: d.isFlat
                  ? context.l10n.noDrawdown
                  : context.l10n.drawdownBody(
                      fmtNum(d.yuzde, digits: 1),
                      d.toparlandi
                          ? context.l10n.recoveredInDays(d.toparlanmaGun ?? 0)
                          : context.l10n.notRecoveredYet),
              ton: d.isFlat ? c.text58 : c.loss,
            ),
          ],
          if (volatilite != null) ...[
            if (d != null) const SizedBox(height: SandikSpace.smd),
            _SaglikSatiri(
              baslik: context.l10n.volatility,
              deger: '%${fmtNum(volatilite!, digits: 1)}',
              aciklama: context.l10n.volatilityBody,
              ton: c.text58,
            ),
          ],
          if (y != null) ...[
            if (d != null || volatilite != null)
              const SizedBox(height: SandikSpace.smd),
            _SaglikSatiri(
              baslik: context.l10n.concentration,
              deger: '%${fmtNum(y.enBuyukPay, digits: 0)}',
              aciklama: context.l10n.concentrationBody(
                  fmtNum(y.enBuyukPay, digits: 0),
                  y.enBuyukEtiket,
                  y.pozisyonSayisi,
                  y.tekVarlikAgir ? ' ${context.l10n.singleAssetHeavy}' : ''),
              ton: y.tekVarlikAgir ? c.amberText : c.text58,
            ),
          ],
        ],
      ),
    );
  }
}

/// Sağlık kartının tek satırı: `başlık · büyük değer` + açıklama.
class _SaglikSatiri extends StatelessWidget {
  final String baslik;
  final String deger;
  final String aciklama;
  final Color ton;

  const _SaglikSatiri({
    required this.baslik,
    required this.deger,
    required this.aciklama,
    required this.ton,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  baslik,
                  style: context.t.labelMedium?.copyWith(
                    color: context.c.text58,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              Text(deger, style: context.t.numSmall.copyWith(color: ton)),
            ],
          ),
          const SizedBox(height: SandikSpace.xxs),
          Text(
            aciklama,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ],
      );
}

/// Para ağırlıklı getiri (XIRR) — "zamanlaman işe yaradı mı".
///
/// Nominal getirinin YANINDA gösterilir ve ikisinin farklı sayılar olması
/// beklenen bir durumdur. Kart bunu açıkça yazmak zorunda: iki farklı yüzde
/// gören ve hangisinin "gerçek" olduğunu bilmeyen kullanıcı ikisine de
/// güvenmez.
class XirrKarti extends StatelessWidget {
  final double xirr;

  /// Karşılaştırma için saf piyasa getirisi (%). `null` ise tek sayı çizilir.
  final double? piyasaGetirisi;

  const XirrKarti({super.key, required this.xirr, this.piyasaGetirisi});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final onde = xirr >= 0;
    final ton = onde ? c.gain : c.loss;

    return _BaglamKarti(
      baslik: context.l10n.moneyReturnAnnual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                onde ? '▲' : '▼',
                style: context.t.labelLarge
                    ?.copyWith(color: ton, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: SandikSpace.sm),
              Text(fmtPct(xirr),
                  style: context.t.numMedium.copyWith(color: ton)),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            context.l10n.xirrBody,
            style: context.t.bodySmall?.copyWith(color: c.text58),
          ),
          if (piyasaGetirisi != null) ...[
            const SizedBox(height: SandikSpace.smd),
            Divider(color: c.hairline, height: 1),
            const SizedBox(height: SandikSpace.smd),
            _KucukSatir(
              etiket: context.l10n.periodMarketReturnLabel,
              deger: fmtPct(piyasaGetirisi!),
            ),
            const SizedBox(height: SandikSpace.xs2),
            Text(
              context.l10n.xirrVsMarketBody,
              style: context.t.bodySmall?.copyWith(color: c.text36),
            ),
          ],
        ],
      ),
    );
  }
}

/// İleri seviye metrikleri — risk-ayarlı getiri, zamanlama etkisi, toparlanma.
///
/// Yalnızca Yatırımcı seviyesi = İleri'de çizilir (`seviyeGorunurlugu`).
/// Üç sayı da zaten hesaplanan girdilerden türetilir (`IleriMetrikler`);
/// kart yeni veri ÇEKMEZ. Her satırın altında bir cümlelik tanım var:
/// "risk-ayarlı" gibi terimleri ileri kullanıcı bilir ama TANIMIN hangisi
/// olduğunu (risksiz oransız Sharpe) ancak yazarsak bilir.
class IleriMetrikKarti extends StatelessWidget {
  final IleriMetrikler metrikler;

  const IleriMetrikKarti({super.key, required this.metrikler});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = metrikler;
    if (!m.hasData) return const SizedBox.shrink();

    final satirlar = <Widget>[];
    void satir(String etiket, String deger, String aciklama, {Color? ton}) {
      if (satirlar.isNotEmpty) {
        satirlar.add(const SizedBox(height: SandikSpace.smd));
      }
      satirlar.add(_KucukSatir(etiket: etiket, deger: deger, ton: ton));
      satirlar.add(const SizedBox(height: SandikSpace.xs2));
      satirlar.add(Text(aciklama,
          style: context.t.bodySmall?.copyWith(color: c.text36)));
    }

    final risk = m.riskAyarliGetiri;
    if (risk != null) {
      satir(
        context.l10n.riskAdjustedReturn,
        fmtNum(risk),
        context.l10n.riskAdjustedBody,
        ton: context.signColor(risk),
      );
    }
    final zamanlama = m.zamanlamaEtkisi;
    if (zamanlama != null) {
      satir(
        context.l10n.timingEffect,
        '${zamanlama >= 0 ? '+' : ''}${fmtNum(zamanlama, digits: 1)} puan',
        context.l10n.timingEffectBody,
        ton: context.signColor(zamanlama),
      );
    }
    if (m.toparlanmaGun != null) {
      satir(
        context.l10n.recoveryWord,
        context.l10n.recoveryDays(m.toparlanmaGun!),
        context.l10n.recoveryBody,
      );
    } else if (m.toparlanmadi) {
      satir(
        context.l10n.recoveryWord,
        context.l10n.notYet,
        context.l10n.notRecoveredBody,
        ton: c.loss,
      );
    }

    return _BaglamKarti(
      baslik: context.l10n.advancedMetricsYear,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: satirlar,
      ),
    );
  }
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
              context.l10n
                  .notEnoughHistory(donemEtiketi(context.l10n, period.label)),
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              context.l10n.notEnoughHistoryBody,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
          ],
        ),
      );
}

/// Derinlik — katlanır bölüm (2026-09-21).
///
/// Başlık satırı her zaman görünür ("DERİNLİK · XIRR, sağlık…"), içerik
/// dokununca açılır. `AnimatedSize` yalnızca yükseklik geçişi yapar; kapalı
/// durumda çocuklar ağaçta DEĞİLDİR — kapalıyken hesaplama/çizim maliyeti
/// sıfır (CPU/GPU kaygısı). Açık/kapalı durumu oturum içi, tercih değil.
class _DerinlikBolumu extends StatefulWidget {
  const _DerinlikBolumu({
    required this.baslangictaAcik,
    required this.cocuklar,
  });

  final bool baslangictaAcik;
  final List<Widget> cocuklar;

  @override
  State<_DerinlikBolumu> createState() => _DerinlikBolumuState();
}

class _DerinlikBolumuState extends State<_DerinlikBolumu> {
  late bool _acik = widget.baslangictaAcik;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _acik,
          label: l10n.sectionDepth,
          // Performans sekmesi CupertinoPageScaffold altında; InkWell'in
          // mürekkep katmanı için Material atası şart, yoksa cihazda kırmızı
          // "No Material widget found" (2026-09-21, ekran görüntüsü).
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() => _acik = !_acik),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: SandikTouch.min),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SandikSectionHeader(title: l10n.sectionDepth),
                          Text(
                            l10n.sectionDepthHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall
                                ?.copyWith(color: context.c.text58),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _acik ? 0.5 : 0,
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      child: Icon(Icons.expand_more_rounded,
                          color: context.c.text58),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: SandikMotion.surfaceOf(context),
          curve: SandikMotion.move,
          alignment: Alignment.topCenter,
          child: _acik
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: SandikSpace.sm),
                    ...widget.cocuklar,
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
