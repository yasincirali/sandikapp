import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../services/varlik_istatistik.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// İstatistik ızgarası ve dönem aralığı çubuğu — varlık sayfasıyla portföy
/// varlık detayının ORTAK parçaları. Dönem çipi (`DonemCipi`) 2026-09-28'de
/// kalktı: tüm ekranlar tek seçiciyi çiziyor (`donem_secici.dart`), getiri
/// satırı oraya taşındı.
///
/// ## Neden ayrı dosya (kullanıcı kararı, 2026-09-28)
/// Portföy › varlık detayı için dört tasarım dilinden **A (varlık sayfası
/// ailesi)** seçildi: aynı varlık aramadan da portföyden de açılınca aynı
/// düzeni göstermeli. İki ekran bu parçaların kopyasını taşısaydı ilk
/// düzeltmede ayrışırlardı (bu projede tekrar eden hata sınıfı). Sayılar
/// burada HESAPLANMAZ: her ekran kendi kaynağından hazır değeri verir —
/// varlık sayfası sembol serisinden, detay ekranı birim seriden.

/// Yuvarlanmış yüzde sıfırsa değişim nötr gösterilir
/// ([DonemIstatistigi.isFlat] ile aynı eşik).
bool donemDuzMu(double pct) => pct.abs() < 0.005;

/// 2×2 istatistik ızgarası: dönem getirisi, bugün, en büyük düşüş, oynaklık.
///
/// [donemPct] ve [bugunPct] çağırandan gelir: detay ekranı dönem yüzdesini
/// canlı birim fiyata göre ölçer (grafiğin sağ ucu ve başlıktaki sayı ile
/// aynı), varlık sayfası serinin son noktasına göre. `null` → "—".
class DonemIstatistikIzgarasi extends StatelessWidget {
  const DonemIstatistikIzgarasi({
    super.key,
    required this.ist,
    required this.gun,
    required this.donemPct,
    required this.bugunPct,
  });

  final DonemIstatistigi ist;

  /// Seçili dönemin gün sayısı — kısa dönemde oynaklık notu için.
  final int gun;
  final double donemPct;
  final double? bugunPct;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Color yon(double v) =>
        donemDuzMu(v) ? context.c.text58 : context.signColor(v);
    final bugun = bugunPct;

    final hucreler = <(String, String, Color)>[
      (
        l.vsPeriodReturnUpper,
        fmtPctIsaretli(donemPct),
        yon(donemPct),
      ),
      (
        l.vsTodayUpper,
        bugun == null ? '—' : fmtPctIsaretli(bugun),
        bugun == null ? context.c.text58 : yon(bugun),
      ),
      (
        l.vsMaxDrawdownUpper,
        fmtPctIsaretli(ist.enBuyukDususPct),
        ist.enBuyukDususPct.abs() < 0.005 ? context.c.text58 : context.c.loss,
      ),
      (
        l.vsVolatilityUpper,
        ist.oynaklikPct == null ? '—' : fmtPct(ist.oynaklikPct!),
        context.c.text90,
      ),
    ];

    Widget hucre((String, String, Color) h) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(SandikSpace.smd),
            decoration: context.surfaceCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: SandikSpace.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(h.$2,
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(color: h.$3)),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          hucre(hucreler[0]),
          const SizedBox(width: SandikSpace.sm),
          hucre(hucreler[1]),
        ]),
        const SizedBox(height: SandikSpace.sm),
        Row(children: [
          hucre(hucreler[2]),
          const SizedBox(width: SandikSpace.sm),
          hucre(hucreler[3]),
        ]),
        if (ist.oynaklikPct == null &&
            gun < DonemIstatistigi.oynaklikIcinAsgariDonemGun) ...[
          const SizedBox(height: SandikSpace.xs2),
          Text(l.vsVolatilityShortNote,
              style: context.t.bodySmall?.copyWith(color: context.c.text36)),
        ],
      ],
    );
  }
}

/// Dönem aralığı: dip ve zirve arasında bugünkü fiyatın yeri.
class DonemAralikCubugu extends StatelessWidget {
  const DonemAralikCubugu({
    super.key,
    required this.dusuk,
    required this.yuksek,
    required this.konum,
    required this.bicim,
  });

  final double dusuk;
  final double yuksek;

  /// 0 = dönem dibi, 1 = zirvesi.
  final double konum;
  final NumberFormat bicim;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final k = konum.clamp(0.0, 1.0);
    final konumYuzde = (k * 100).round();
    return Container(
      padding: const EdgeInsets.all(SandikSpace.smd),
      decoration: context.surfaceCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Büyük sistem yazı tipinde iki etiket 320pt'ye sığmaz.
          Row(
            children: [
              Expanded(
                child: Text(l.vsPeriodLow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall
                        ?.copyWith(color: context.c.text36)),
              ),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text(l.vsPeriodHigh,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: context.t.labelSmall
                        ?.copyWith(color: context.c.text36)),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xs2),
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: SandikSpace.smd,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: SandikSpace.xs2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                      gradient: LinearGradient(colors: [
                        context.c.loss.withValues(alpha: 0.7),
                        context.c.amberFill.withValues(alpha: 0.7),
                        context.c.gain.withValues(alpha: 0.7),
                      ]),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * k - SandikSpace.xs2)
                        .clamp(0.0, c.maxWidth - SandikSpace.smd),
                    child: Container(
                      width: SandikSpace.smd,
                      height: SandikSpace.smd,
                      decoration: BoxDecoration(
                        color: context.c.text90,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs2),
          // 320pt'de iki büyük tutar (ör. ₺1.234.567,89) yan yana sığmaz;
          // kırpılan fiyat yanlış okunur, küçülen okunur.
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(bicim.format(dusuk),
                      maxLines: 1,
                      style:
                          context.t.numSmall.copyWith(color: context.c.text90)),
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(bicim.format(yuksek),
                      maxLines: 1,
                      style:
                          context.t.numSmall.copyWith(color: context.c.text90)),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(l.vsRangePosition('$konumYuzde'),
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
        ],
      ),
    );
  }
}
