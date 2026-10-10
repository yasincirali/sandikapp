import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/asset_type.dart';
import '../models/ozel_gosterge.dart';
import '../models/ohlc.dart';
import '../providers/ozel_gosterge_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/premium_provider.dart';
import '../screens/ozel_gosterge_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/gosterge_betigi/betik.dart';
import '../services/history_service.dart' show FiyatKaynagi;
import '../services/mum_verisi.dart';
import '../services/mum_yukleyici.dart';
import '../services/ozel_gosterge_calistirici.dart';
import '../services/technical_analysis_service.dart';
import '../theme/sandik.dart';
import '../utils/hareketli_ortalama.dart';
import '../utils/mum_turetici.dart';
import 'fiyat_grafigi.dart';
import 'gosterge_cizimi.dart';
import 'grafik_arac_cubugu.dart';

/// Varlık sayfasının (aramadan, takipten, ekleme seçicisinden açılan;
/// portföyde olmayan sembol) fiyat grafiği + araç çubuğu.
///
/// ## Neden (yasin, 2026-10-10 gece)
/// *"ana sayfa aramadan gidilen varlık kartı, portföyden varlık performans
/// ekranı ve karşılaştırma ekranı: bu gösterge filtre, mum ve yenileme
/// sıklığı olmalı ve bu 3 ekran tutarlı olmalı."* Varlık detayının
/// katmanları (#150 EMA/mum, #160 Pine, #161 gerçek mum) burada da:
/// aynı araç çubuğu ([GrafikAracCubugu]), aynı tercihler, aynı mum kaynağı
/// ([FiyatKaynagi.mumKaynagi] — sembol [FiyatKaynagi.gozlemVarligi] ile),
/// aynı Pine çalıştırıcısı ve çizimi.
///
/// ## Kim görür (yeni bayrak YOK)
/// Varlık detayıyla aynı kapı: `premiumOzellikleriGorunurProvider`
/// (paywall kapalıyken yalnız admin) + seviye (`grafikAraclari`, sade
/// Başlangıç'ta yok) + mevduat değil. Görünmüyorsa grafik BİREBİR eskisi:
/// araç çubuğu yok, düz [FiyatGrafigi] (canlıdaki kullanıcı etkilenmez).
/// `ƒx` ücretsizde kilitli (paywall, kaynak `grafik_ozel_gosterge`); mum,
/// aralık, MA20, EMA50/200 ve LOG ücretsiz.
///
/// ## Veri
///  · Çizgi, MA20 ve EMA sayfanın sembol serisinden (`getSymbolHistory`) —
///    başlıktaki fiyatla aynı kaynak.
///  · EMA ısınması [onSeri]: sayfa altı dönemi birlikte yüklüyor; bir üst
///    dönemin serisi bu dönemin öncesini taşır, ayrı istek yok.
///  · Gerçek mumlar [MumYukleyici] ile; son kapanış başlıktaki fiyata
///    hizalanır (`canliyaHizala`). Gelene kadar ya da kaynağı yoksa mum
///    çizginin noktalarından türetilir — ekran boş kalmaz.
class KatmanliFiyatGrafigi extends ConsumerStatefulWidget {
  const KatmanliFiyatGrafigi({
    super.key,
    required this.ticker,
    required this.type,
    required this.currency,
    this.subCategory,
    required this.sembolEtiketi,
    required this.seri,
    required this.periodDays,
    required this.bicim,
    required this.semanticLabel,
    this.onSeri,
    this.imlecEtiketi,
    this.ucTitresimi = false,
  });

  final String ticker;
  final AssetType type;
  final String currency;
  final String? subCategory;

  /// Pine `syminfo.ticker` ve göstergeler sayfasındaki ad.
  final String sembolEtiketi;

  /// `epoch ms → fiyat` (seçili dönem).
  final Map<int, double> seri;
  final int periodDays;
  final NumberFormat bicim;
  final String semanticLabel;

  /// Dönemin öncesini taşıyan daha uzun seri (EMA ve Pine ısınması);
  /// yalnız ilk noktadan önceki kısmı kullanılır.
  final Map<int, double>? onSeri;

  final ValueNotifier<(String, String)?>? imlecEtiketi;
  final bool ucTitresimi;

  @override
  ConsumerState<KatmanliFiyatGrafigi> createState() =>
      _KatmanliFiyatGrafigiState();
}

class _KatmanliFiyatGrafigiState extends ConsumerState<KatmanliFiyatGrafigi> {
  late final _mum = MumYukleyici(
      onDegisti: _yenile, neden: 'VarlikSayfasi.ohlc');
  late final _betikMum = MumYukleyici(
      onDegisti: _yenile, neden: 'VarlikSayfasi.betikOhlc');
  final _gorunum = ValueNotifier<({double min, double max})?>(null);
  BetikVerisi? _ozelVeri;

  void _yenile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mum.kapat();
    _betikMum.kapat();
    _gorunum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final araclar = ref.watch(seviyeGorunurlukProvider).grafikAraclari;
    final gorunur = araclar &&
        ref.watch(premiumOzellikleriGorunurProvider) &&
        widget.type != AssetType.mevduat;
    if (!gorunur) return _duz();

    final spots = [
      for (final k in (widget.seri.keys.toList()..sort()))
        FlSpot(k.toDouble(), widget.seri[k]!),
    ];
    if (spots.length < 2) return _duz();

    final a = FiyatKaynagi.gozlemVarligi(
      ticker: widget.ticker,
      type: widget.type,
      currency: widget.currency,
      subCategory: widget.subCategory,
      name: widget.sembolEtiketi,
    );
    final kaynak = FiyatKaynagi.mumKaynagi(a);
    final canli = spots.last.y;
    final gunIci = widget.periodDays <= 1;
    final bas = DateTime.fromMillisecondsSinceEpoch(spots.first.x.round());
    final son = DateTime.now();

    final ma20On = ref.watch(chartMA20Provider);
    final logOn = ref.watch(chartLogScaleProvider);
    final mumOn = ref.watch(chartCandleProvider);
    final ema50On = ref.watch(chartEma50Provider);
    final ema200On = ref.watch(chartEma200Provider);

    // Isınma: daha uzun dönemin dönem öncesi noktaları. Yalnız AYNI
    // çözünürlükteyse (ortanca nokta aralığı ±%50): saatlik serinin önüne
    // günlük noktalar eklemek EMA'yı iki ayrı çubuk sıklığında hesaplardı.
    // GÜNLÜK'te istenmez — varlık detayında olduğu gibi tek seans.
    final ilkX = spots.first.x;
    final onAday = <FlSpot>[
      if (!gunIci && widget.onSeri != null)
        for (final k in (widget.onSeri!.keys.toList()..sort()))
          if (k < ilkX) FlSpot(k.toDouble(), widget.onSeri![k]!),
    ];
    final onSpots = _ayniSiklik(onAday, spots) ? onAday : const <FlSpot>[];

    final ortalamalar = <FiyatOrtalamasi>[
      if (ma20On && spots.length >= 20) _ma20(spots, context.c.text58),
      for (final (acik, periyot, renk) in [
        (ema50On, kEmaKisa, context.c.gain),
        (ema200On, kEmaUzun, context.c.loss),
      ])
        if (acik)
          FiyatOrtalamasi(
            spots: emaNoktalari(spots, periyot: periyot, onSeri: onSpots),
            cizgiRengi: renk,
          ),
    ];

    // Mum ve aralık — varlık detayıyla aynı karar (`etkinAralik`).
    final span = gunIci
        ? 1440.0
        : son.difference(bas).inMinutes.toDouble();
    final secim = MumAraligi.sirayla(ref.watch(chartMumAraligiProvider));
    final aralik = mumOn ? etkinAralik(a, span, secim) : null;
    final gecerli =
        mumOn ? gecerliAraliklar(a, span) : const <MumAraligi>[];
    var mumlar = const <Mum>[];
    if (mumOn) {
      final barlar = aralik == null
          ? null
          : _mum.mumlar(
              a: a,
              aralik: aralik,
              bas: bas,
              son: son,
              canliBirim: canli,
              gunIci: gunIci,
            );
      mumlar = (barlar != null && aralik != null)
          ? grafikMumlari(barlar,
              aralik: aralik, baslangicMs: 0, birimMs: 1)
          : mumlariGrafikUzayinda(spots, baslangicMs: 0, birimMs: 1);
    }

    // Kendi göstergen: kilitliyse hiç çalışmaz.
    final kilitli = ref.watch(premiumKilitliProvider);
    final acik = kilitli
        ? const <OzelGosterge>[]
        : grafiktekiGostergeler(
            ref.watch(ozelGostergelerProvider).valueOrNull ?? const []);
    final betikAr = acik.isEmpty || !kaynak.gercekOhlc
        ? null
        : (aralik ?? etkinAralik(a, span, secim));
    final betikBarlar = betikAr == null
        ? null
        : _betikMum.mumlar(
            a: a,
            aralik: betikAr,
            bas: bas,
            son: son,
            canliBirim: canli,
            gunIci: gunIci,
            isinma: betikIsinmaCubugu,
          );
    _ozelVeri = (betikBarlar != null && betikAr != null)
        ? betikVerisiMumdan(betikBarlar, betikAr,
            x: [
              for (final m in grafikMumlari(betikBarlar,
                  aralik: betikAr, baslangicMs: 0, birimMs: 1))
                m.merkezX
            ],
            sembol: widget.sembolEtiketi)
        : _kapanisVerisi([...onSpots, ...spots]);
    final sonuclar = acik.isEmpty || _ozelVeri == null
        ? const <OzelSonuc>[]
        : ozelGostergeleriCalistir(acik, _ozelVeri!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GrafikAracCubugu(
          katmanlar: true,
          ma20Acik: ma20On,
          logAcik: logOn,
          mumAcik: mumOn,
          ema50Acik: ema50On,
          ema200Acik: ema200On,
          ozel: GrafikOzelCipi(
            acikSayi: sonuclar.length,
            kilitli: kilitli,
            onTap: () {
              if (kilitli) {
                PaywallScreen.show(context, source: 'grafik_ozel_gosterge');
                return;
              }
              showOzelGostergeSayfasi(context,
                  onizleme: _ozelVeri, varlikAdi: widget.sembolEtiketi);
            },
          ),
          aralik: aralik,
          gecerliAraliklar: gecerli,
          kapanistan: !kaynak.gercekOhlc,
        ),
        const SizedBox(height: SandikSpace.sm),
        FiyatGrafigi(
          seri: widget.seri,
          periodDays: widget.periodDays,
          bicim: widget.bicim,
          imlecEtiketi: widget.imlecEtiketi,
          ucTitresimi: widget.ucTitresimi,
          semanticLabel: widget.semanticLabel,
          onViewportChanged: (mn, mx) => _gorunum.value = (min: mn, max: mx),
          katmanlar: FiyatKatmanlari(
            log: logOn,
            mumlar: mumlar,
            ortalamalar: ortalamalar,
            ozelCizim: sonuclar.isEmpty
                ? null
                : (toY, ofset) =>
                    fiyatUstuCizimleri(context, sonuclar, toY, ofset: ofset),
            ozelBant: sonuclar.isEmpty
                ? null
                : (toY) => fiyatUstuBantNoktalari(sonuclar, toY, enAzX: ilkX),
          ),
        ),
        OzelGostergeAltBolumu(sonuclar: sonuclar, gorunum: _gorunum),
      ],
    );
  }

  static double _ortancaAralik(List<FlSpot> s) {
    if (s.length < 3) return double.nan;
    final f = [for (var i = 1; i < s.length; i++) s[i].x - s[i - 1].x]..sort();
    return f[f.length ~/ 2];
  }

  static bool _ayniSiklik(List<FlSpot> a, List<FlSpot> b) {
    final x = _ortancaAralik(a), y = _ortancaAralik(b);
    if (!x.isFinite || !y.isFinite || x <= 0 || y <= 0) return false;
    final oran = x / y;
    return oran > 0.66 && oran < 1.5;
  }

  Widget _duz() => FiyatGrafigi(
        seri: widget.seri,
        periodDays: widget.periodDays,
        bicim: widget.bicim,
        imlecEtiketi: widget.imlecEtiketi,
        ucTitresimi: widget.ucTitresimi,
        semanticLabel: widget.semanticLabel,
      );

  FiyatOrtalamasi _ma20(List<FlSpot> spots, Color renk) {
    final sma = TechnicalAnalysisService.smaSeries(
        [for (final s in spots) s.y], 20);
    return FiyatOrtalamasi(
      spots: [
        for (var i = 0; i < sma.length; i++)
          if (!sma[i].isNaN) FlSpot(spots[i].x, sma[i]),
      ],
      cizgiRengi: renk,
      kesikli: true,
    );
  }

  /// Gerçek mum yoksa betik çizginin noktalarında çalışır (açılış/yüksek/
  /// düşük/hacim `na`; düzenleyici bunu söyler — uydurma yok).
  BetikVerisi? _kapanisVerisi(List<FlSpot> noktalar) {
    final temiz = [
      for (final s in noktalar)
        if (s.y.isFinite && s.y > 0) s
    ];
    if (temiz.length < 2) return null;
    final zaman = [for (final s in temiz) s.x];
    return BetikVerisi.yalnizKapanis(
      zaman,
      [for (final s in temiz) s.y],
      zaman: zaman,
      zamanDilimi: BetikVerisi.aralikTahmini(zaman),
      sembol: widget.sembolEtiketi,
    );
  }
}
