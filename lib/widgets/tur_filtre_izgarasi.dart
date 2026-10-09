import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/tur_filtre_ozeti.dart';
import '../theme/sandik.dart';

/// Performans › Filtre alt sayfasının kategori seçimi (bayrak `goz_alici`).
///
/// Eski hâl tek renkte sarmalı metin çipleriydi: "Fon"u seçmeden önce
/// portföyde fon olup olmadığı, ne kadar yer tuttuğu görünmüyordu; boş türü
/// seçen kullanıcı boş grafikle karşılaşıyordu. Yeni hâl iki parça:
///   · "Tümü" döşemesi portföyün tür dağılımını tek şerit olarak çizer —
///     bir tür seçilince şeritte yalnız o parça yanar ("baktığım dilim bu").
///   · Türler ızgarada; her döşeme kendi tür renginde ikon, adı ve varlık
///     sayısını taşır, altında payı kadar ince bir çubuk. Elde olmayan tür
///     soluk ve "Yok" yazar ama SEÇİLEBİLİR kalır (işlev kaybı yok; derin
///     bağlantı ya da eski seçim yine çalışır).
///
/// Renk tür kimliğidir (grafikte, halkada aynı renk); amber yalnız "Tümü"
/// seçimini taşır — "sakin yüzey, amber vurgu" (TASARIM_DILI §1.6).
/// Döşeme sırası enum sırasıdır, ele göre yeniden SIRALANMAZ: kişi
/// değişince döşemeler yer değiştirseydi parmak yanlış yere giderdi.
class TurFiltreIzgarasi extends StatelessWidget {
  const TurFiltreIzgarasi({
    super.key,
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onSec,
  });

  final AssetType? secili;
  final TurFiltreOzeti ozet;

  /// Gösterilecek türler (bayrakla kapalı tür çağıranda elenir).
  final List<AssetType> turlar;
  final ValueChanged<AssetType?> onSec;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TumuDosemesi(
          secili: secili,
          ozet: ozet,
          turlar: turlar,
          onTap: () => onSec(null),
        ),
        const SizedBox(height: SandikSpace.sm),
        LayoutBuilder(builder: (context, k) {
          // 3 sütun 340pt'ye kadar; altında (320pt telefon, büyük yazı)
          // "Eurobond" iki satıra kırılıyordu → 2 sütun.
          final sutun = k.maxWidth >= 340 ? 3 : 2;
          final w = (k.maxWidth - SandikSpace.sm * (sutun - 1)) / sutun;
          return Wrap(
            spacing: SandikSpace.sm,
            runSpacing: SandikSpace.sm,
            children: [
              for (final t in turlar)
                SizedBox(
                  width: w,
                  child: _TurDosemesi(
                    tur: t,
                    secili: secili == t,
                    adet: ozet.adet[t] ?? 0,
                    pay: ozet.pay(t),
                    payVar: ozet.payVar,
                    onTap: () => onSec(t),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

/// Seçim kabuğu — iki döşeme aynı sınırı/dolguyu paylaşır.
BoxDecoration _kabuk(BuildContext context, {required bool secili, required Color renk}) =>
    BoxDecoration(
      color: secili ? renk.withValues(alpha: 0.14) : context.c.surface2,
      borderRadius: SandikRadius.mdAll,
      border: Border.all(
        color: secili ? renk : context.c.hairline,
        width: secili ? 1.5 : 1,
      ),
    );

class _TumuDosemesi extends StatelessWidget {
  const _TumuDosemesi({
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onTap,
  });

  final AssetType? secili;
  final TurFiltreOzeti ozet;
  final List<AssetType> turlar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tumuSecili = secili == null;
    final renk = context.c.amberText;
    final n = ozet.toplamAdet;
    return SandikTappable(
      onTap: onTap,
      selected: tumuSecili,
      semanticLabel: '${l.allTypes}, ${l.s2FiltreVarlikSayisi(n)}',
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        padding: const EdgeInsets.all(SandikSpace.smd),
        decoration: _kabuk(context, secili: tumuSecili, renk: context.c.amberFill),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IkonDairesi(
                    ikon: Icons.dashboard_rounded,
                    renk: context.c.amberFill,
                    ikonRengi: renk),
                const SizedBox(width: SandikSpace.sm2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.allTypes,
                          style: context.t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.text90)),
                      Text(l.s2FiltreVarlikSayisi(n),
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text58)),
                    ],
                  ),
                ),
                _SecimIsareti(gorunur: tumuSecili, renk: renk),
              ],
            ),
            // Dağılım şeridi — yalnız fiyatlar biliniyorsa (uydurma pay yok).
            if (ozet.payVar) ...[
              const SizedBox(height: SandikSpace.sm2),
              ClipRRect(
                borderRadius: SandikRadius.smAll,
                child: SizedBox(
                  height: SandikSpace.sm,
                  child: Row(
                    children: [
                      for (final t in turlar)
                        if (ozet.pay(t) > 0)
                          Expanded(
                            // Binde bir çözünürlük: %0,4'lük dilim de çizilir.
                            flex: (ozet.pay(t) * 1000).round().clamp(1, 1000),
                            child: AnimatedOpacity(
                              duration: SandikMotion.stateOf(context),
                              curve: SandikMotion.enter,
                              opacity: secili == null || secili == t ? 1 : 0.22,
                              child: ColoredBox(
                                  color: t.color,
                                  child: const SizedBox.expand()),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TurDosemesi extends StatelessWidget {
  const _TurDosemesi({
    required this.tur,
    required this.secili,
    required this.adet,
    required this.pay,
    required this.payVar,
    required this.onTap,
  });

  final AssetType tur;
  final bool secili;
  final int adet;
  final double pay;
  final bool payVar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final yok = adet == 0;
    final ad = tur.labelOf(l);
    final alt = yok ? l.s2FiltreYok : l.s2FiltreVarlikSayisi(adet);
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: '$ad, $alt',
      child: AnimatedOpacity(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        // Seçiliyse soluk değil: seçtiği şey görünür olmalı.
        opacity: yok && !secili ? 0.5 : 1,
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.sm, SandikSpace.sm, SandikSpace.sm, SandikSpace.xs2),
          decoration: _kabuk(context, secili: secili, renk: tur.color),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Seçim işareti ikonun köşesinde: renk körü kullanıcı
                  // seçimi yalnız çerçeve renginden okumak zorunda kalmasın.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _IkonDairesi(
                          ikon: tur.icon,
                          renk: tur.color,
                          ikonRengi: tur.onSurface(context)),
                      Positioned(
                        right: -SandikSpace.xs,
                        bottom: -SandikSpace.xs,
                        child: _SecimIsareti(
                            gorunur: secili, renk: tur.onSurface(context)),
                      ),
                    ],
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.c.text90)),
                        Text(alt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall
                                ?.copyWith(color: context.c.text58)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.xs2),
              // Pay çubuğu: boyu hep aynı (döşemeler hizalı kalsın), dolgu
              // payı kadar. Pay bilinmiyorsa yalnız zemin.
              ClipRRect(
                borderRadius: SandikRadius.smAll,
                child: SizedBox(
                  height: SandikSpace.xxs + 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: ColoredBox(color: context.c.overlay)),
                      if (payVar && pay > 0)
                        FractionallySizedBox(
                          widthFactor: pay.clamp(0.04, 1.0),
                          heightFactor: 1,
                          alignment: AlignmentDirectional.centerStart,
                          child: ColoredBox(color: tur.color),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IkonDairesi extends StatelessWidget {
  const _IkonDairesi(
      {required this.ikon, required this.renk, required this.ikonRengi});
  final IconData ikon;
  final Color renk;
  final Color ikonRengi;

  @override
  Widget build(BuildContext context) => Container(
        width: SandikSpace.xl,
        height: SandikSpace.xl,
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(ikon, size: 17, color: ikonRengi),
      );
}

/// Seçim işareti — ölçekle gelir (0,6'dan; sıfırdan değil), yer tutar ki
/// metin kaymasın.
class _SecimIsareti extends StatelessWidget {
  const _SecimIsareti({required this.gorunur, required this.renk});
  final bool gorunur;
  final Color renk;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        scale: gorunur ? 1 : 0.6,
        child: AnimatedOpacity(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          opacity: gorunur ? 1 : 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: context.c.surface1, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_rounded, size: 16, color: renk),
          ),
        ),
      );
}
