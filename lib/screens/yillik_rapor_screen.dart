import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/crash_reporter.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../services/disa_aktarim/rapor_belgeleri.dart';
import '../services/remote_config_service.dart';
import '../services/share_card_service.dart';
import '../services/yillik_rapor.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_segment.dart';

/// Yıllık kâr, temettü ve masraf raporu (Premium, yasin 2026-10-10).
///
/// Hesap `yillik_rapor.dart`'ta (saf, test edilir); ekran yalnız çizer ve
/// paylaşır. Girişi Performans › Raporlar kapısındaki satır. Paywall
/// açıkken Premium değilse ekranın tamamı tek kilit kartıdır — rapor
/// bütünüyle Premium'dur, parçası gösterilmez.
///
/// Yıl seçici yalnız kaydı olan yılları sunar (`raporYillari`); varsayılan
/// en yeni yıl. Rakam renkleri tek kuralla: kâr `gain`, zarar `loss`.
class YillikRaporScreen extends ConsumerStatefulWidget {
  const YillikRaporScreen({super.key});

  @override
  ConsumerState<YillikRaporScreen> createState() => _YillikRaporScreenState();
}

class _YillikRaporScreenState extends ConsumerState<YillikRaporScreen> {
  int? _yil;
  final _gonderKey = GlobalKey();
  final _pdfKey = GlobalKey();
  final _excelKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      // Kilit satırı kullanıcının kendi defteriyle konuşur: yalnız ADET
      // (satış/temettü), tutar yok (yasin 2026-11-13). Sayım servis
      // katmanında (`yillikKayitSayimi`); kaydı yoksa genel cümle.
      final sayim = yillikKayitSayimi(
          ref.watch(portfolioProvider).valueOrNull?.assets ?? const [],
          ref.watch(authProvider).valueOrNull?.id ?? '');
      return Scaffold(
        appBar: SandikAppBar(title: l.yrBaslik),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.receipt_long_rounded,
            baslik: l.yrKilitBaslik,
            govde: l.yrKilitGovde,
            kilitMetni: yillikRaporKilitMetni(l, sayim),
            kaynak: 'yillik_rapor',
          ),
        ),
      );
    }
    final uid = ref.watch(authProvider).valueOrNull?.id ?? '';
    final lotlar = ref.watch(portfolioProvider).valueOrNull?.assets ?? const [];
    final yillar = raporYillari(lotlar, uid);
    if (yillar.isEmpty) {
      return Scaffold(
        appBar: SandikAppBar(title: l.yrBaslik),
        body: SandikBosDurum(metin: l.yrBos, alt: l.yrBosAlt),
      );
    }
    final yil = yillar.contains(_yil) ? _yil! : yillar.first;
    final oran = RemoteConfigService.instance.temettuStopajOrani;
    final r = yillikRapor(
        lotlar: lotlar, userId: uid, yil: yil, bistStopajOrani: oran);
    final c = context.c;
    final t = context.t;
    final h = SandikSpace.screenH(context);

    return Scaffold(
      appBar: SandikAppBar(title: l.yrBaslik),
      body: ListView(
        padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
        children: [
          if (yillar.length > 1) ...[
            SandikSegment(
              adet: yillar.length,
              secili: yillar.indexOf(yil),
              onSec: (i) => setState(() => _yil = yillar[i]),
              // Stil segmentin `AnimatedDefaultTextStyle`'ından gelir; burada
              // sabit stil vermek rengi zeminle birlikte geçirmiyor, tek
              // karede atlatıyordu (seçici denetimi 2026-10-12).
              oge: (ctx, i, secili) => Text('${yillar[i]}'),
            ),
            const SizedBox(height: SandikSpace.md),
          ],
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OzetSatiri(
                    etiket: l.yrGerceklesen,
                    tutar: r.gerceklesenKarTry,
                    renkli: true,
                    buyuk: true),
                if (r.yurtDisiVar)
                  _OzetSatiri(
                      etiket: l.yrYurtDisi,
                      tutar: r.yurtDisiKarTry,
                      renkli: true),
                _OzetSatiri(etiket: l.yrTemettuNet, tutar: r.temettuNetTry),
                _OzetSatiri(
                  etiket: l.yrStopaj,
                  tutar: r.stopajTry,
                  yoksa: l.yrStopajBilinmiyor,
                ),
                _OzetSatiri(etiket: l.yrMasraf, tutar: r.masrafTry),
              ],
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          // Tek birincil eylem (müşteri raporu 6 Kas 15:15 #2): raporun asıl
          // gittiği yer mali müşavir; PDF + Excel tek paylaşımda, e-postada
          // iki ek. Tek biçim isteyen için altında küçük metin düğmeleri —
          // her biri ≥44 pt (SandikTouch). Paylaşım sayfası iPad'de basılan
          // düğmeye bağlanır (`originOf`).
          SandikAsyncButton(
            key: _gonderKey,
            tur: SandikAsyncTur.dolu,
            icon: const Icon(Icons.send_rounded),
            onPressed: () => _paylas(
                r,
                oran,
                const [DisaAktarimBicimi.pdf, DisaAktarimBicimi.excel],
                ShareCardService.originOf(_gonderKey.currentContext)),
            child: Text(l.yrMusavireGonder),
          ),
          const SizedBox(height: SandikSpace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SandikAsyncButton.kompakt(
                key: _pdfKey,
                tur: SandikAsyncTur.metin,
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: () => _paylas(r, oran, const [DisaAktarimBicimi.pdf],
                    ShareCardService.originOf(_pdfKey.currentContext)),
                child: Text(l.yrYalnizPdf),
              ),
              ExcludeSemantics(
                child: Text('·', style: t.bodySmall?.copyWith(color: c.text58)),
              ),
              SandikAsyncButton.kompakt(
                key: _excelKey,
                tur: SandikAsyncTur.metin,
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: () => _paylas(
                    r,
                    oran,
                    const [DisaAktarimBicimi.excel],
                    ShareCardService.originOf(_excelKey.currentContext)),
                child: Text(l.yrYalnizExcel),
              ),
            ],
          ),
          if (r.satislar.isNotEmpty) ...[
            const SizedBox(height: SandikSpace.lg),
            SandikSectionHeader(title: l.yrSatislarUpper),
            const SizedBox(height: SandikSpace.sm),
            SandikCard(
              child: Column(
                children: [
                  for (var i = 0; i < r.satislar.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.hairline),
                    _KayitSatiri(
                      tarih: r.satislar[i].tarih,
                      ad: r.satislar[i].ad,
                      alt: r.satislar[i].yurtDisi ? l.yrYurtDisiEtiket : null,
                      tutar: r.satislar[i].karTry,
                      renkli: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (r.temettuler.isNotEmpty) ...[
            const SizedBox(height: SandikSpace.lg),
            SandikSectionHeader(title: l.yrTemettulerUpper),
            const SizedBox(height: SandikSpace.sm),
            SandikCard(
              child: Column(
                children: [
                  for (var i = 0; i < r.temettuler.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.hairline),
                    _KayitSatiri(
                      tarih: r.temettuler[i].tarih,
                      ad: r.temettuler[i].ad,
                      alt: r.temettuler[i].stopajTry == null
                          ? null
                          : l.yrStopajSatir(
                              fmtTRY(r.temettuler[i].stopajTry!, digits: 2)),
                      tutar: r.temettuler[i].netTry,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: SandikSpace.lg),
          if (r.fiyatsizSatis > 0) ...[
            Text(l.yrFiyatsiz(r.fiyatsizSatis),
                style: t.bodySmall?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.sm),
          ],
          Text(l.yrDipnot, style: t.bodySmall?.copyWith(color: c.text58)),
        ],
      ),
    );
  }

  Future<void> _paylas(YillikRapor r, double? oran,
      List<DisaAktarimBicimi> bicimler, Rect? kaynak) async {
    final kullanici = ref.read(authProvider).valueOrNull;
    final belge = yillikRaporBelgesi(
      r,
      kim: kullanici?.username ?? kullanici?.email ?? '',
      olusturma: DateTime.now(),
      bistStopajOrani: oran,
    );
    try {
      await DisaAktarimService.instance.paylasBirlikte(belge,
          bicimler: bicimler, tur: 'yillik_rapor', kaynak: kaynak);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'YillikRapor.paylas');
      if (mounted) showAppError(context, e);
    }
  }
}

class _OzetSatiri extends StatelessWidget {
  const _OzetSatiri({
    required this.etiket,
    required this.tutar,
    this.renkli = false,
    this.buyuk = false,
    this.yoksa,
  });

  final String etiket;
  final double? tutar;

  /// Kâr yeşil, zarar kırmızı.
  final bool renkli;
  final bool buyuk;

  /// [tutar] `null` iken yazılacak metin.
  final String? yoksa;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = tutar;
    final renk =
        !renkli || v == null || v == 0 ? c.text90 : (v > 0 ? c.gain : c.loss);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(etiket,
                style: (buyuk ? context.t.bodyLarge : context.t.bodyMedium)
                    ?.copyWith(color: c.text58)),
          ),
          Text(
            v == null ? (yoksa ?? '—') : fmtTRY(v, digits: 2),
            style: (buyuk ? context.t.numMedium : context.t.numSmall)
                .copyWith(fontWeight: FontWeight.w700, color: renk),
          ),
        ],
      ),
    );
  }
}

class _KayitSatiri extends StatelessWidget {
  const _KayitSatiri({
    required this.tarih,
    required this.ad,
    required this.tutar,
    this.alt,
    this.renkli = false,
  });

  final DateTime tarih;
  final String ad;
  final String? alt;
  final double tutar;
  final bool renkli;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final renk =
        !renkli || tutar == 0 ? c.text90 : (tutar > 0 ? c.gain : c.loss);
    final altMetin = [
      DateFormat('d MMM y', dil).format(tarih),
      if (alt != null) alt!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ad,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.xxs),
                Text(altMetin,
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Text(fmtTRY(tutar, digits: 2),
              style: context.t.numSmall
                  .copyWith(fontWeight: FontWeight.w700, color: renk)),
        ],
      ),
    );
  }
}

/// Kilitli ekranın satırı. Sıfır olan parça yazılmaz ("0 temettün" bir
/// şey söylemez); ikisi de sıfırsa ya da sayım yoksa bugünkü genel cümle.
/// Yıl `String` geçer: `int` placeholder'ı "2.026" diye biçimlenirdi.
String yillikRaporKilitMetni(
    AppLocalizations l, ({int yil, int satis, int temettu})? sayim) {
  if (sayim == null) return l.yrKilitSatir;
  final parcalar = [
    if (sayim.satis > 0) l.yrKilitSatisParca(sayim.satis),
    if (sayim.temettu > 0) l.yrKilitTemettuParca(sayim.temettu),
  ];
  if (parcalar.isEmpty) return l.yrKilitSatir;
  final kayitlar = parcalar.length == 2
      ? l.yrKilitVe(parcalar[0], parcalar[1])
      : parcalar[0];
  return l.yrKilitSayim('${sayim.yil}', kayitlar);
}
