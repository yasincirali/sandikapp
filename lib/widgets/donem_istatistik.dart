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

/// İstatistik ızgarası: dönem getirisi, bugün, en büyük düşüş, oynaklık.
/// Fiyatın altında zaten yazan sayı ve bilinmeyen oynaklık hücre almaz.
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
    this.donemGetirisiGizli = false,
    this.bugunGizli,
  });

  /// Izgarada kaç hücre çizilir — iskelet de aynı sayıyı kullanır, yoksa
  /// veri gelince kartın boyu zıplar (Ar-Ge 1 Kas 08:45 #3).
  static int hucreSayisi({
    required bool donemGetirisiGizli,
    required bool bugunGizli,
    required bool oynaklikVar,
  }) =>
      (donemGetirisiGizli ? 0 : 1) +
      (bugunGizli ? 0 : 1) +
      1 +
      (oynaklikVar ? 1 : 0);

  /// "Bugün" hücresi gizli mi. `null` → eski kural: dönem getirisi gizliyken
  /// GÜNLÜK seçiliyse ([gun] 0) bugün aynı sayıdır, düşer. Varlık sayfası
  /// GÜNLÜK'ü `gun == 1` ile taşıdığı için kendi kararını açıkça verir.
  final bool? bugunGizli;

  bool get _bugunGizli => bugunGizli ?? (donemGetirisiGizli && gun == 0);

  final DonemIstatistigi ist;

  /// Dönem yüzdesi ekranda zaten fiyatın altında yazıyorsa `true`: ızgara
  /// onu ikinci kez yazmaz (Sadeleştirme 2, madde 7, 2026-10-04 — yalnız
  /// portföy varlık detayı verir). GÜNLÜK seçiliyken "Bugün" hücresi de aynı
  /// sayıdır, o da düşer. Kalan hücreler ikişerli satırlara dizilir; tek
  /// kalan satırı doldurur. Varsayılan `false`: varlık sayfası (takip /
  /// arama) 2×2.
  final bool donemGetirisiGizli;

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
      if (!donemGetirisiGizli)
        (
          l.vsPeriodReturnUpper,
          fmtPctIsaretli(donemPct),
          yon(donemPct),
        ),
      if (!_bugunGizli)
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
      // Oynaklık bilinmiyorsa hücre hiç yok (Ar-Ge 1 Kas 08:45 #3, yasin
      // "yap"): "—" kutusu ve altındaki "kısa dönemde hesaplanmaz" notu yer
      // kaplayıp bir şey söylemiyordu. Uydurma sayı da yazılmaz.
      if (ist.oynaklikPct != null)
        (
          l.vsVolatilityUpper,
          fmtPct(ist.oynaklikPct!),
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

    final satirlar = <Widget>[
      for (var i = 0; i < hucreler.length; i += 2) ...[
        if (i > 0) const SizedBox(height: SandikSpace.sm),
        Row(children: [
          hucre(hucreler[i]),
          if (i + 1 < hucreler.length) ...[
            const SizedBox(width: SandikSpace.sm),
            hucre(hucreler[i + 1]),
          ],
        ]),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: satirlar,
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
    this.gunIci = false,
  });

  /// GÜNLÜK seçiliyken etiketler "Gün düşüğü/yükseği" der (Ar-Ge 1 Kas
  /// 08:45 #3): "Dönem" bir günlük aralıkta yabancı geliyordu.
  final bool gunIci;

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
                child: Text(gunIci ? l.vsDayLow : l.vsPeriodLow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall
                        ?.copyWith(color: context.c.text36)),
              ),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text(gunIci ? l.vsDayHigh : l.vsPeriodHigh,
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
          Text(
              gunIci
                  ? l.vsDayRangePosition('$konumYuzde')
                  : l.vsRangePosition('$konumYuzde'),
              style: context.t.bodySmall?.copyWith(color: context.c.text58)),
        ],
      ),
    );
  }
}
