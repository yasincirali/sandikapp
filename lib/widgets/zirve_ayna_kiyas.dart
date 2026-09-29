import 'package:flutter/material.dart';

import '../models/asset_type.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'zirve_dagilim_seridi.dart';

/// Seninki ile bir zirve portföyünün ayna kıyası (kullanıcı seçimi
/// 2026-09-29, "A + 1": "zirvedeki portföyle kendiminkini net ve basit
/// şekilde karşılaştırmalıyım").
///
/// Ortada tür, SOLA sen, SAĞA o; aynı ölçek (0–100, iki yarım), aynı sıra
/// (`AssetType`). Fon satırının altında fon fon aynı ayna — fon kodları
/// (0084). Üstte tek cümle en büyük farkı ve getiri farkını söyler.
///
/// ## Neden renk yok
/// Dağılım farkı iyi ya da kötü değildir (bkz. `ZirveKiyas`); sen amber,
/// o fildişi. Yalnız getiri cümlesindeki sayı yön söyler.
///
/// ## Hareket
/// Karşı taraf değişince çubuklar akarak yeni genişliğe geçer
/// ([SandikMotion.flow] + [SandikMotion.glide]); "hareketi azalt" açıkken
/// anında.
class ZirveAynaKiyas extends StatelessWidget {
  const ZirveAynaKiyas({
    super.key,
    required this.senPay,
    required this.senFon,
    required this.zirvePay,
    required this.zirveFon,
    required this.zirveAd,
    required this.senRoi,
    required this.zirveRoi,
  });

  final Map<String, double> senPay;
  final Map<String, double> senFon;
  final Map<String, double> zirvePay;
  final Map<String, double> zirveFon;

  /// Sağ sütun başlığı: "2. portföy".
  final String zirveAd;
  final double? senRoi;
  final double zirveRoi;

  static const double _orta = 64;

  @override
  Widget build(BuildContext context) {
    final turler = [
      for (final t in AssetType.values)
        if ((senPay[t.name] ?? 0) > 0.5 || (zirvePay[t.name] ?? 0) > 0.5)
          t.name,
    ];
    final fonlar = ZirveKiyas.fonKiyasSirasi(senFon, zirveFon);
    final cumle = [
      ZirveKiyas.enBuyukFarkCumlesi(senPay, zirvePay),
      ZirveKiyas.getiriFarkiCumlesi(senRoi: senRoi, zirveRoi: zirveRoi),
    ].where((e) => e.isNotEmpty).join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(SandikSpace.smd),
          decoration: BoxDecoration(
            color: context.c.amberFill.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
          child: Text(
            cumle,
            style: context.t.bodyMedium?.copyWith(
              color: context.c.text90,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'SEN',
                textAlign: TextAlign.right,
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: context.c.amberText,
                ),
              ),
            ),
            const SizedBox(width: _orta),
            Expanded(
              child: Text(
                trBuyuk(zirveAd),
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: context.c.text90,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.sm),
        for (final t in turler) ...[
          ZirveAynaSatiri(
            key: ValueKey('ayna-$t'),
            etiket: ZirveDagilimSeridi.etiket(context, t),
            sen: senPay[t] ?? 0,
            zirve: zirvePay[t] ?? 0,
            senRengi: context.c.amberFill,
            zirveRengi: context.c.text90.withValues(alpha: 0.85),
          ),
          const SizedBox(height: SandikSpace.sm),
          if (t == 'fon')
            for (final f in fonlar) ...[
              ZirveAynaSatiri(
                key: ValueKey('ayna-fon-$f'),
                etiket: f == ZirveKiyas.fonDiger ? 'Diğer' : f,
                sen: senFon[f] ?? 0,
                zirve: zirveFon[f] ?? 0,
                senRengi: AssetType.fon.color,
                zirveRengi: AssetType.fon.color.withValues(alpha: 0.6),
                alt: true,
              ),
              const SizedBox(height: SandikSpace.xs2),
            ],
        ],
      ],
    );
  }

  /// "2. portföy" → "2. PORTFÖY" (Türkçe i/İ).
  static String trBuyuk(String s) => s.replaceAll('i', 'İ').toUpperCase();
}

/// Tek ayna satırı: sol çubuk sen, orta etiket, sağ çubuk o.
class ZirveAynaSatiri extends StatelessWidget {
  const ZirveAynaSatiri({
    super.key,
    required this.etiket,
    required this.sen,
    required this.zirve,
    required this.senRengi,
    required this.zirveRengi,
    this.alt = false,
  });

  final String etiket;
  final double sen;
  final double zirve;
  final Color senRengi;
  final Color zirveRengi;

  /// Fon kodu satırı: ince çubuk, küçük yazı.
  final bool alt;

  static const double _deger = 38;

  String _yaz(double v) {
    if (v < 0.05) return '—';
    return '%${fmtNum(v, digits: alt && v < 10 ? 1 : 0)}';
  }

  @override
  Widget build(BuildContext context) {
    final yukseklik = alt ? 8.0 : 14.0;
    final degerStili = (alt ? context.t.labelSmall : context.t.labelMedium)
        ?.copyWith(letterSpacing: 0, color: context.c.text58);
    Widget cubuk(double v, Color renk, double enFazla) => AnimatedContainer(
          duration: SandikMotion.flowOf(context),
          curve: SandikMotion.glide,
          width: enFazla * (v.clamp(0, 100) / 100),
          height: yukseklik,
          decoration: BoxDecoration(
            color: renk,
            borderRadius: BorderRadius.circular(SandikRadius.sm / 2),
          ),
        );

    return Semantics(
      label: '$etiket: sende ${_yaz(sen)}, onda ${_yaz(zirve)}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: _deger,
                      child: Text(_yaz(sen),
                          textAlign: TextAlign.right, style: degerStili),
                    ),
                    const SizedBox(width: SandikSpace.xs2),
                    cubuk(sen, senRengi,
                        c.maxWidth - _deger - SandikSpace.xs2),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: ZirveAynaKiyas._orta,
              child: Text(
                etiket,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (alt ? context.t.labelSmall : context.t.labelMedium)
                    ?.copyWith(
                  letterSpacing: 0,
                  fontWeight: alt ? FontWeight.w600 : FontWeight.w700,
                  color: alt ? context.c.text58 : context.c.text90,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  children: [
                    cubuk(zirve, zirveRengi,
                        c.maxWidth - _deger - SandikSpace.xs2),
                    const SizedBox(width: SandikSpace.xs2),
                    SizedBox(
                      width: _deger,
                      child: Text(_yaz(zirve), style: degerStili),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
