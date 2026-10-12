import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../models/ohlc.dart';
import '../theme/sandik.dart';
import 'sandik_cam.dart';

/// Fiyat grafiğinin araç çubuğu — [aralık ⌄] · MUM · LOG · ƒx / MA20 · EMA50 ·
/// EMA200. Aralık açılır menüsü (1 dk … ay) mum YA DA bir gösterge açıkken
/// görünür ([aralikGerekli]).
///
/// ## Sıklık neden yalnız mumda değil (yasin, 2026-10-11 TestFlight)
/// *"mum seçili değilken sıklık gelmiyor bu olması gereken mi?"* İlk sürümde
/// sıklık yalnız mumların aralığıydı. Artık MA20/EMA50/EMA200 ve kendi
/// göstergen de o sıklığın çubuklarıyla hesaplanıyor (TradingView:
/// gösterge grafiğin zaman diliminde; `cubukOrtalamasi`). Yani sıklık
/// göstergenin de ayarı: gösterge açıkken seçici görünür. Hiçbiri açık
/// değilken (yalnız fiyat çizgisi) seçicinin değiştireceği bir şey yok,
/// gizli kalır — işe yaramayan kontrol göstermeyiz.
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
    this.pencereDakika,
    this.kapanistan = false,
  });

  /// Grafiğin penceresi (dk): kullanıcının seçimi bu döneme yazılır
  /// (`mumAraligiSecimiProvider`); başka dönemde varsayılan açılır.
  final double? pencereDakika;

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

  /// Bu ölçeğin üstünde menü + çip satırı `Wrap` olur (gerekçe `build`'de).
  /// 1,3× = uygulama içi yazı ayarının tavanı (`KullaniciYaziOlcegi`).
  static const double _buyukYaziEsigi = 1.3;

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
    final pencere = pencereDakika;
    final secici = aralikGerekli(
          mum: mumAcik,
          ma20: ma20Acik,
          ema50: ema50Acik,
          ema200: ema200Acik,
          ozel: (o?.acikSayi ?? 0) > 0,
        ) &&
        ar != null &&
        gecerliAraliklar.length >= 2;
    final ortalamalar = <Widget>[
      ma20,
      GrafikCipi(
        label: 'EMA50',
        active: ema50Acik,
        renk: context.c.gain,
        onTap: () => ref.read(chartEma50Provider.notifier).set(!ema50Acik),
      ),
      GrafikCipi(
        label: 'EMA200',
        active: ema200Acik,
        renk: context.c.loss,
        onTap: () => ref.read(chartEma200Provider.notifier).set(!ema200Acik),
      ),
    ];
    final aciklama = mumAcik && kapanistan
        ? Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.chartCandleFromCloses,
              style: context.t.labelSmall?.copyWith(color: context.c.text58),
            ),
          )
        : null;
    // ── Tek sıra (bayrak `goz_alici`, cam/HIG incelemesi 2026-10-12) ──
    // Telefonda grafikten önce üç sıra kontrol vardı (dönem, görünüm,
    // ortalamalar); grafik ilk ekranın altına itiliyordu. Çipler AYNI sırada
    // ve aynı yerde kalır (bilinen kontrol saklanmaz, 9 Ekim kuralı), yalnız
    // tek satıra iner: sığarsa sağa yaslı, sığmazsa yatay kayar. Aralık
    // menüsü yine solda.
    if (SandikCam.acik) {
      final ayrac = Padding(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
        child: SizedBox(
          width: 1,
          height: SandikSpace.lg,
          child: ColoredBox(color: context.c.hairline),
        ),
      );
      final ciplar = <Widget>[
        for (var i = 0; i < ustSatir.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          ustSatir[i],
        ],
        ayrac,
        for (var i = 0; i < ortalamalar.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          ortalamalar[i],
        ],
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LayoutBuilder(
            builder: (context, kutu) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              // `min` boyutlu satır en az kutu genişliğinde: artan boşluk
              // `spaceBetween` ile menü ile çipler arasına gider (sığınca
              // çipler sağda, menü solda — iki satırlı düzenle aynı kenarlar).
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: kutu.maxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (secici)
                      Padding(
                        padding: const EdgeInsets.only(right: SandikSpace.sm),
                        child: MumAraligiMenusu(
                          aralik: ar,
                          gecerli: gecerliAraliklar,
                          onSec: (yeni) {
                            if (pencere == null) return;
                            ref
                                .read(mumAraligiSecimiProvider.notifier)
                                .sec(pencere, yeni);
                          },
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Row(mainAxisSize: MainAxisSize.min, children: ciplar),
                  ],
                ),
              ),
            ),
          ),
          if (aciklama != null) aciklama,
        ],
      );
    }
    // Cihazda büyük yazı açıkken (> 1,3×; uygulama ayarı bunu geçemez)
    // menü + çipler tek satıra sığmıyor, 3,1×'te 49 px taşıyordu (büyük
    // yazı taraması 2026-10-12). Orada satır `Wrap` olur: sığmayan çip alt
    // satıra iner. Normal yazıda aşağıdaki `Row` birebir korunur.
    final buyukYazi =
        MediaQuery.textScalerOf(context).scale(1) > _buyukYaziEsigi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Aralık menüsü sol başta (TradingView'de de zaman dilimi araç
        // çubuğunun başında); çipler sağda kalır, yerleri değişmez.
        if (buyukYazi)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            children: [
              if (secici)
                MumAraligiMenusu(
                  aralik: ar,
                  gecerli: gecerliAraliklar,
                  onSec: (yeni) {
                    if (pencere == null) return;
                    ref
                        .read(mumAraligiSecimiProvider.notifier)
                        .sec(pencere, yeni);
                  },
                ),
              ...ustSatir,
            ],
          )
        else
        Row(
          children: [
            if (secici)
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MumAraligiMenusu(
                    aralik: ar,
                    gecerli: gecerliAraliklar,
                    onSec: (yeni) {
                      if (pencere == null) return;
                      ref
                          .read(mumAraligiSecimiProvider.notifier)
                          .sec(pencere, yeni);
                    },
                  ),
                ),
              )
            else
              const Spacer(),
            for (var i = 0; i < ustSatir.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              ustSatir[i],
            ],
          ],
        ),
        // Satır arası boşluk yok: çiplerin 44pt dokunma payı (HIG,
        // 2026-10-10) zaten aralık bırakıyor. Wrap: 320pt ekranda (iPhone SE)
        // üç ortalama çipi tek satıra sığmıyor, 22–54 px taşıyordu
        // (`performance_screen_overflow_test`, 2026-10-11 mum/EMA herkese
        // açılınca görüldü); sığmayan çip alt satıra iner.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          children: [
            ma20,
            GrafikCipi(
              label: 'EMA50',
              active: ema50Acik,
              renk: context.c.gain,
              onTap: () =>
                  ref.read(chartEma50Provider.notifier).set(!ema50Acik),
            ),
            GrafikCipi(
              label: 'EMA200',
              active: ema200Acik,
              renk: context.c.loss,
              onTap: () =>
                  ref.read(chartEma200Provider.notifier).set(!ema200Acik),
            ),
          ],
        ),
        if (mumAcik && kapanistan)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.chartCandleFromCloses,
              style: context.t.labelSmall?.copyWith(color: context.c.text58),
            ),
          ),
      ],
    );
  }
}

/// Sıklık seçicisi (ve onun çubukları) gerekiyor mu: mum ya da çubuklardan
/// hesaplanan bir gösterge açık. Üç ekran aynı kuralı buradan okur —
/// çubuk isteği de seçicinin görünürlüğü de aynı soruya bağlı.
bool aralikGerekli({
  required bool mum,
  required bool ma20,
  required bool ema50,
  required bool ema200,
  bool ozel = false,
}) =>
    mum || ma20 || ema50 || ema200 || ozel;

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

/// Aralık açılır menüsü — "15 dk ⌄" (yasin 2026-10-10 gece: "grafik
/// çizdirme sıklığı bir dropdown ile seçtirilebilir").
///
/// İlk sürüm sekiz düğmelik bir segment şeridiydi: 375 pt'de "15 dk"
/// sığmıyor, grafiğin üstünde tam bir satır kaplıyordu. Menü tek çip yer
/// tutar ve TradingView'in zaman dilimi menüsüyle aynı kalıp. Neden
/// `PopupMenuButton` (sheet değil): [GrafikTipiSecici] ile aynı gerekçe —
/// liste çipin altında açılır, grafik görünür kalır, seçimin etkisi hemen
/// görülür. Satırlar 48 pt, seçilide tik (yalnız renkle değil).
class MumAraligiMenusu extends StatelessWidget {
  const MumAraligiMenusu({
    super.key,
    required this.aralik,
    required this.gecerli,
    required this.onSec,
  });

  final MumAraligi aralik;
  final List<MumAraligi> gecerli;
  final ValueChanged<MumAraligi> onSec;

  @override
  Widget build(BuildContext context) {
    // Ata `Material` POPUP'IN DIŞINDA (CupertinoPageScaffold altında
    // `PopupMenuButton`'ın InkWell'i Material arar; [GrafikTipiSecici]).
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        label: context.l10n.chartIntervalSemantics(aralik.uzunAdi(context)),
        excludeSemantics: true,
        child: PopupMenuButton<MumAraligi>(
          tooltip: context.l10n.chartIntervalSemantics(aralik.uzunAdi(context)),
          position: PopupMenuPosition.under,
          color: context.c.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            side: BorderSide(color: context.c.hairline),
          ),
          initialValue: aralik,
          onSelected: onSec,
          itemBuilder: (_) => [
            for (final g in gecerli)
              PopupMenuItem<MumAraligi>(
                value: g,
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      // Uzun ad cümle içi için küçük harfli ("günlük");
                      // menü satırı başlık gibi okunur.
                      child: Text(
                        _basHarfBuyuk(g.uzunAdi(context)),
                        style: context.t.bodyMedium?.copyWith(
                          color: context.c.text90,
                          fontWeight:
                              g == aralik ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      child: g == aralik
                          ? Icon(Icons.check_rounded,
                              size: 16, color: context.c.amberText)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
          // Görsel çip GrafikCipi ile aynı ölçüde; dokunma alanı 44 pt.
          //
          // Görünüm (yasin 2026-10-11: "sıklık komponentini gözden geçir,
          // uygulama geneli tasarıma uygun olmalı"): ilk sürüm AÇIK çiple
          // aynı amber dolguyu taşıyordu ve bir aç/kapa anahtarı gibi
          // okunuyordu (dokununca kapanacak sanılıyordu). Artık uygulamanın
          // açılır seçicisi gibi ([GrafikTipiSecici]): nötr zemin, saat
          // simgesi + değer + aşağı ok. Amber yalnız AÇIK katmanların rengi
          // kalır; seçicinin değeri bir durum değil, bir ayar.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: SandikTouch.min, minHeight: SandikTouch.min),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.c.overlay,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(color: context.c.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 12, color: context.c.text58),
                    const SizedBox(width: SandikSpace.xs),
                    Flexible(
                      child: Text(
                        aralik.etiketi(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: SandikSpace.xxs),
                    Icon(Icons.expand_more_rounded,
                        size: 14, color: context.c.text58),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _basHarfBuyuk(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Aralığın kısa ve uzun adı (seçici ve ekran okuyucu).
extension MumAraligiAdi on MumAraligi {
  String etiketi(BuildContext context) => switch (this) {
        MumAraligi.dk1 => context.l10n.chartIntervalM1,
        MumAraligi.dk5 => context.l10n.chartIntervalM5,
        MumAraligi.dk15 => context.l10n.chartIntervalM15,
        MumAraligi.dk30 => context.l10n.chartIntervalM30,
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
        MumAraligi.dk30 => context.l10n.chartIntervalM30Long,
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
              // Flexible: 3,1× yazıda tek çip satır genişliğini aşabiliyor
              // (173 px taşma, büyük yazı taraması 2026-10-12); etiket
              // çipin içinde kırılır, çip kartın dışına çıkmaz.
              Flexible(
                child: Text(
                  label,
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: active ? context.c.amberText : context.c.text58,
                    letterSpacing: 0.4,
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
