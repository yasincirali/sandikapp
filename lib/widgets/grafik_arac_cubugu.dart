import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../models/ohlc.dart';
import '../theme/sandik.dart';
import 'sandik_segment.dart';

/// Fiyat grafiğinin araç çubuğu — MUM · LOG · ƒx / MA20 · EMA50 · EMA200 ve
/// Mum açıkken aralık seçicisi (1 dk … ay).
///
/// ## Neden ortak (yasin, 2026-10-10)
/// *"ana sayfa aramadan gidilen varlık kartı, portföyden varlık performans
/// ekranı ve karşılaştırma ekranı: bu gösterge filtre, mum ve yenileme
/// sıklığı olmalı ve bu 3 ekran tutarlı olmalı."* Çubuk ilk sürümde
/// (#150, #161) yalnız varlık detayının part'ındaydı; üç ekran üç kopya
/// taşısaydı ilk düzeltmede ayrışırdı. Çipler, sıra, renkler, kilit ve
/// seçici artık tek yerde; tercihler de ortak (aynı sağlayıcılar), yani
/// bir ekranda açılan EMA50 ötekinde de açıktır.
///
/// Değerler çağırandan gelir (o ekranda ETKİN olan durum: karşılaştırma
/// açıkken LOG etkisiz sayılır, vb.); dokunuş tercihi tersine çevirir.
/// Hangi çipin bulunacağına da çağıran karar verir ([log], [ozel]).
class GrafikAracCubugu extends ConsumerWidget {
  const GrafikAracCubugu({
    super.key,
    required this.katmanlar,
    required this.ma20Acik,
    this.logAcik,
    this.mumAcik = false,
    this.ema50Acik = false,
    this.ema200Acik = false,
    this.ozel,
    this.aralik,
    this.gecerliAraliklar = const [],
    this.kapanistan = false,
  });

  /// Mum, EMA ve ƒx bu kullanıcıda görünür mü (`premiumOzellikleriGorunurProvider`;
  /// paywall kapalıyken yalnız admin). `false` → satır BİREBİR eskisi:
  /// yalnız MA20 · LOG (canlıdaki kullanıcı etkilenmez).
  final bool katmanlar;

  final bool ma20Acik;

  /// LOG çipi; `null` → bu ekranda yok (Karşılaştır: eksen yüzde, dönem
  /// başı %0, negatif değerin logaritması tanımsız).
  final bool? logAcik;

  final bool mumAcik;
  final bool ema50Acik;
  final bool ema200Acik;

  /// `ƒx` çipi (kendi göstergen); `null` → bu ekranda yok.
  final GrafikOzelCipi? ozel;

  /// Mum açıkken çizilen aralık; `null` ya da [gecerliAraliklar] tekse
  /// seçici kurulmaz.
  final MumAraligi? aralik;
  final List<MumAraligi> gecerliAraliklar;

  /// Mumlar kapanışlardan kuruluyor (fon, BES, eurobond): seçicinin altında
  /// tek satır açıklama.
  final bool kapanistan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ma20 = GrafikCipi(
      label: 'MA20',
      active: ma20Acik,
      onTap: () => ref.read(chartMA20Provider.notifier).set(!ma20Acik),
    );
    final log = logAcik == null
        ? null
        : GrafikCipi(
            label: 'LOG',
            active: logAcik!,
            onTap: () =>
                ref.read(chartLogScaleProvider.notifier).set(!logAcik!),
          );
    if (!katmanlar) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ma20,
          if (log != null) ...[const SizedBox(width: 6), log],
        ],
      );
    }
    final o = ozel;
    // Beş çip 375pt'ye tek satırda sığmıyor (Wrap LOG'u tek başına alta
    // düşürüyordu). İki anlamlı satır: üstte GÖRÜNÜM (mum, ölçek, kendi
    // göstergen), altta ORTALAMALAR (MA20, EMA50, EMA200).
    final ustSatir = <Widget>[
      GrafikCipi(
        label: context.l10n.chartCandleChip,
        active: mumAcik,
        onTap: () => ref.read(chartCandleProvider.notifier).set(!mumAcik),
      ),
      if (log != null) log,
      if (o != null)
        Semantics(
          label: context.l10n.ozgCipSemantik,
          child: GrafikCipi(
            label: o.acikSayi > 0 ? 'ƒx ${o.acikSayi}' : 'ƒx',
            active: o.acikSayi > 0,
            kilitli: o.kilitli,
            onTap: o.onTap,
          ),
        ),
    ];
    final ar = aralik;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < ustSatir.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              ustSatir[i],
            ],
          ],
        ),
        // Satır arası boşluk yok: çiplerin 44pt dokunma payı (HIG,
        // 2026-10-10) zaten aralık bırakıyor.
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ma20,
            const SizedBox(width: 6),
            GrafikCipi(
              label: 'EMA50',
              active: ema50Acik,
              renk: context.c.gain,
              onTap: () =>
                  ref.read(chartEma50Provider.notifier).set(!ema50Acik),
            ),
            const SizedBox(width: 6),
            GrafikCipi(
              label: 'EMA200',
              active: ema200Acik,
              renk: context.c.loss,
              onTap: () =>
                  ref.read(chartEma200Provider.notifier).set(!ema200Acik),
            ),
          ],
        ),
        if (mumAcik && ar != null && gecerliAraliklar.length >= 2)
          MumAraligiSecici(
            aralik: ar,
            gecerli: gecerliAraliklar,
            kapanistan: kapanistan,
          ),
      ],
    );
  }
}

/// `ƒx` çipinin durumu. Kilitliyse [onTap] paywall'u açar (çağıran karar
/// verir, kaynak `grafik_ozel_gosterge`).
class GrafikOzelCipi {
  const GrafikOzelCipi({
    required this.acikSayi,
    required this.kilitli,
    required this.onTap,
  });
  final int acikSayi;
  final bool kilitli;
  final VoidCallback onTap;
}

/// Aralık seçicisi — tek seçim, ortak [SandikSegment] (kayan zemin, 44 pt
/// dokunma, hareketi azalt). Kapanıştan kurulan mumlarda altında tek satır
/// açıklama: mumun ne olduğunu söyler.
class MumAraligiSecici extends ConsumerWidget {
  const MumAraligiSecici({
    super.key,
    required this.aralik,
    required this.gecerli,
    this.kapanistan = false,
  });

  final MumAraligi aralik;
  final List<MumAraligi> gecerli;
  final bool kapanistan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SandikSegment(
          adet: gecerli.length,
          secili: gecerli.indexOf(aralik),
          yukseklik: 32,
          metinStili: context.t.labelLarge,
          onSec: (i) =>
              ref.read(chartMumAraligiProvider.notifier).set(gecerli[i].index),
          oge: (_, i, __) => Text(gecerli[i].etiketi(context),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          semantik: (i) => context.l10n
              .chartIntervalSemantics(gecerli[i].uzunAdi(context)),
        ),
        if (kapanistan) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            context.l10n.chartCandleFromCloses,
            style: context.t.labelSmall?.copyWith(color: context.c.text58),
          ),
        ],
      ],
    );
  }
}

/// Aralığın kısa ve uzun adı (seçici ve ekran okuyucu).
extension MumAraligiAdi on MumAraligi {
  String etiketi(BuildContext context) => switch (this) {
        MumAraligi.dk1 => context.l10n.chartIntervalM1,
        MumAraligi.dk5 => context.l10n.chartIntervalM5,
        MumAraligi.dk15 => context.l10n.chartIntervalM15,
        MumAraligi.saat1 => context.l10n.chartIntervalH1,
        MumAraligi.saat4 => context.l10n.chartIntervalH4,
        MumAraligi.gun1 => context.l10n.chartIntervalD1,
        MumAraligi.hafta1 => context.l10n.chartIntervalW1,
        MumAraligi.ay1 => context.l10n.chartIntervalMo1,
      };

  String uzunAdi(BuildContext context) => switch (this) {
        MumAraligi.dk1 => context.l10n.chartIntervalM1Long,
        MumAraligi.dk5 => context.l10n.chartIntervalM5Long,
        MumAraligi.dk15 => context.l10n.chartIntervalM15Long,
        MumAraligi.saat1 => context.l10n.chartIntervalH1Long,
        MumAraligi.saat4 => context.l10n.chartIntervalH4Long,
        MumAraligi.gun1 => context.l10n.chartIntervalD1Long,
        MumAraligi.hafta1 => context.l10n.chartIntervalW1Long,
        MumAraligi.ay1 => context.l10n.chartIntervalMo1Long,
      };
}

/// Grafik çipi (MA20, LOG, MUM, EMA, ƒx).
class GrafikCipi extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Katmanın grafikteki rengi (EMA50 yeşil, EMA200 kırmızı). Verilirse
  /// açıkken tik yerine o renkte kısa bir çizgi çizilir: çip aynı zamanda
  /// lejanttır — iki renkli çizginin hangisi hangisi, grafiğe bakarken
  /// çipten okunur.
  final Color? renk;

  /// Premium kilidi (paywall açık, kullanıcı Premium değil): kilit simgesi,
  /// dokunuş paywall'u açar (çağıran karar verir).
  final bool kilitli;

  const GrafikCipi({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.renk,
    this.kilitli = false,
  });

  @override
  Widget build(BuildContext context) {
    // Görsel çip ~26pt; dokunma alanı [GenisDokunma] ile 44pt (HIG
    // denetimi 2026-10-10). `toggled`: VoiceOver "MA20, açık/kapalı" okur;
    // kilitliyken anahtar değil, paywall'u açan düğmedir.
    return GenisDokunma(
      onTap: onTap,
      child: Semantics(toggled: kilitli ? null : active, child: _cip(context)),
    );
  }

  Widget _cip(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: active
                  ? context.c.amberFill.withValues(alpha: 0.55)
                  : context.c.overlay,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kilitli)
                Icon(Icons.lock_rounded, size: 12, color: context.c.text58)
              else if (active && renk != null)
                Container(
                  width: 12,
                  height: 3,
                  decoration: BoxDecoration(
                    color: renk,
                    borderRadius: SandikRadius.smAll,
                  ),
                )
              else
                Icon(
                  active
                      ? Icons.check_rounded
                      : Icons.horizontal_rule_rounded,
                  size: 12,
                  color: active ? context.c.amberText : context.c.text58,
                ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? context.c.amberText : context.c.text58,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Görseli büyütmeden dokunma alanını 44pt'ye çıkarır (HIG denetimi
/// 2026-10-10). Çipin kendi `InkWell`'i içte kalır ve kendi alanında
/// kazanır; çevresindeki şeffaf pay aynı eylemi çağırır. Semantik düğüm
/// içteki öğeden gelir, burada ikinci bir düğme üretilmez.
class GenisDokunma extends StatelessWidget {
  const GenisDokunma({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: SandikTouch.min,
          minHeight: SandikTouch.min,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: child),
      ),
    );
  }
}
