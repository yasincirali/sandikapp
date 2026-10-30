import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../models/ohlc.dart';
import '../theme/sandik.dart';

/// Fiyat grafiğinin araç çubuğu — [aralık ⌄] · [Göstergeler · 2 açık ⌄];
/// düğme açılınca MUM · LOG · ƒx · MA20 · EMA50 · EMA200 çipleri
/// (2026-10-30, [GostergelerDugmesi]). Aralık açılır menüsü (1 dk … ay)
/// mum YA DA bir gösterge açıkken görünür ([aralikGerekli]).
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
class GrafikAracCubugu extends ConsumerStatefulWidget {
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
  ConsumerState<GrafikAracCubugu> createState() => _GrafikAracCubuguState();
}

class _GrafikAracCubuguState extends ConsumerState<GrafikAracCubugu> {
  /// Çip satırı açık mı. Varsayılan kapalı (rapor: "bilmeyen hiç görmez");
  /// yalnız bu grafiğin ömrü boyunca hatırlanır.
  bool _acik = false;

  bool get ma20Acik => widget.ma20Acik;
  bool? get logAcik => widget.logAcik;
  bool get mumAcik => widget.mumAcik;
  bool get ema50Acik => widget.ema50Acik;
  bool get ema200Acik => widget.ema200Acik;
  bool get katmanlar => widget.katmanlar;
  GrafikOzelCipi? get ozel => widget.ozel;
  MumAraligi? get aralik => widget.aralik;
  List<MumAraligi> get gecerliAraliklar => widget.gecerliAraliklar;
  double? get pencereDakika => widget.pencereDakika;
  bool get kapanistan => widget.kapanistan;

  @override
  Widget build(BuildContext context) {
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
    // Rozet sayısı: o ekranda ETKİN olan katmanlar (LOG çipi olmayan
    // ekranda LOG sayılmaz).
    final acikSayi = [
          mumAcik,
          logAcik ?? false,
          ma20Acik,
          ema50Acik,
          ema200Acik,
        ].where((b) => b).length +
        (o?.acikSayi ?? 0);
    final cipler = <Widget>[
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
    // ── Tek düğme (UX raporu 30 Eki §2, yasin "yap") ──
    // Dönem çiplerinin hemen altında MUM · LOG · MA20 · EMA50 · EMA200
    // yatay kayıyordu; 390 pt'de son çip kesikti ("EMA2") ve yeni kullanıcı
    // fiyatla grafik arasında beş teknik terim görüyordu. Artık tek
    // "Göstergeler" düğmesi; açık katman sayısı yanında ("2 açık"), çipler
    // düğmeye dokununca grafiğin ÜSTÜNDE açılır (sheet değil: seçimin
    // etkisi grafikte hemen görülsün). Bilen kullanıcı bir dokunuş fazla
    // yapar, bilmeyen hiç görmez.
    //
    // 9 Ekim kuralı ("bilinen kontrol saklanmaz") bu kararla değişti:
    // kontrol kalkmadı, bir kat geri itildi; açık olan katman rozetle
    // söylenir. Aralık menüsü dışarıda kalır — katman açıkken çizimin
    // ayarıdır, sık değişir.
    //
    // Eski iki düzen (cam: tek sıra yatay kaydırma; klasik: iki sıra)
    // birleşti: açılan satır `Wrap`, 320 pt'de ve 3,1× yazıda alta iner.
    final dugme = GostergelerDugmesi(
      acikSayi: acikSayi,
      acik: _acik,
      onTap: () => setState(() => _acik = !_acik),
    );
    final buyukYazi = MediaQuery.textScalerOf(context).scale(1) >
        GrafikAracCubugu._buyukYaziEsigi;
    final menu = secici
        ? MumAraligiMenusu(
            aralik: ar,
            gecerli: gecerliAraliklar,
            onSec: (yeni) {
              if (pencere == null) return;
              ref.read(mumAraligiSecimiProvider.notifier).sec(pencere, yeni);
            },
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Aralık menüsü sol başta (TradingView'de de zaman dilimi araç
        // çubuğunun başında); düğme sağda.
        if (buyukYazi)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            children: [if (menu != null) menu, dugme],
          )
        else
          Row(
            children: [
              if (menu != null)
                Flexible(
                  child: Align(alignment: Alignment.centerLeft, child: menu),
                )
              else
                const Spacer(),
              dugme,
            ],
          ),
        AnimatedSize(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          alignment: Alignment.topCenter,
          child: !_acik
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Satır arası boşluk yok: çiplerin 44pt dokunma payı
                    // (HIG, 2026-10-10) zaten aralık bırakıyor.
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      children: cipler,
                    ),
                    if (mumAcik && kapanistan)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          context.l10n.chartCandleFromCloses,
                          style: context.t.labelSmall
                              ?.copyWith(color: context.c.text58),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Göstergeler · 2 açık ⌄" — grafik katmanlarını açan tek düğme (UX
/// raporu 30 Eki §2). Görünüm [MumAraligiMenusu] ile aynı aile: nötr
/// zemin, değer, aşağı/yukarı ok; amber yalnız açık katman sayısında
/// (durum). Sayı yalnız renkle değil, metinle de söylenir.
class GostergelerDugmesi extends StatelessWidget {
  const GostergelerDugmesi({
    super.key,
    required this.acikSayi,
    required this.acik,
    required this.onTap,
  });

  /// Açık katman sayısı; 0 → rozet yok.
  final int acikSayi;

  /// Çip satırı açık mı (ok yönü, ekran okuyucu "genişletildi").
  final bool acik;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      button: true,
      expanded: acik,
      label: acikSayi > 0
          ? l.chartIndicatorsSemantics(acikSayi)
          : l.chartIndicatorsButton,
      hint: l.chartIndicatorsHint,
      excludeSemantics: true,
      child: GenisDokunma(
        onTap: onTap,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: context.c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 12, color: context.c.text58),
                  const SizedBox(width: SandikSpace.xs),
                  Flexible(
                    child: Text(
                      l.chartIndicatorsButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text90,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (acikSayi > 0) ...[
                    const SizedBox(width: SandikSpace.xs),
                    Text(
                      '· ${l.chartIndicatorsOn(acikSayi)}',
                      maxLines: 1,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.amberText,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                  const SizedBox(width: SandikSpace.xxs),
                  AnimatedRotation(
                    turns: acik ? 0.5 : 0,
                    duration: SandikMotion.stateOf(context),
                    curve: SandikMotion.enter,
                    child: Icon(Icons.expand_more_rounded,
                        size: 14, color: context.c.text58),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                  active ? Icons.check_rounded : Icons.horizontal_rule_rounded,
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
