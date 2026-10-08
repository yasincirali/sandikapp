import 'package:flutter/cupertino.dart';

import '../theme/sandik.dart';

/// Segment kontrolü — kayan seçim zeminli, uygulamanın ortak parçası.
///
/// ## Neden (animasyon denetimi 2026-10-01)
/// Uygulamada yedi ayrı segment kontrolü vardı; her biri seçimi kendi
/// yöntemiyle gösteriyordu (tek karede atlayan dolgu, yerinde solan dolgu,
/// kayan hap) ve süre/eğrileri farklıydı. Aynı iş — "birini seç" — yedi
/// lehçede konuşuyordu. Bu bileşen tek davranışı taşır:
///   · seçim zemini TEK katmandır ve yeni segmentin altına KAYAR
///     ([SandikMotion.state] + [SandikMotion.move]); göz seçimin nereden
///     nereye geçtiğini izler;
///   · yazı rengi zeminle aynı sürede geçer; kalınlık değişir ama
///     genişlik payı en kalın hâle göre verildiği için yer oynatmaz;
///   · segment genişlikleri [paylar] ile orantılıdır (verilmezse eşit);
///     zeminin yeri aynı paylardan hesaplanır — ölçüm, fazladan yerleşim
///     geçişi yok;
///   · dokunma hedefi görsel yükseklikten bağımsız ≥ 44 pt ([SandikTouch]);
///     kabuk 44'ten alçaksa bileşen yine 44pt yer kaplar, kabuk ortada
///     çizilir (`test/sandik_segment_test.dart` ölçer);
///   · hareketi azalt açıkken süre sıfır: zemin anında yerine oturur.
///
/// İçerik [oge] ile kurulur; metin rengi/kalınlığı etkin `DefaultTextStyle`
/// ile gelir, yani çağıran çoğunlukla yalnız `Text(etiket)` döndürür.
class SandikSegment extends StatelessWidget {
  const SandikSegment({
    super.key,
    required this.adet,
    required this.secili,
    required this.onSec,
    required this.oge,
    this.paylar,
    this.yukseklik = 36,
    this.icBosluk = 3,
    this.metinStili,
    this.semantik,
    this.onSeciliDokunus,
  });

  final int adet;

  /// Seçili segment; aralık dışıysa zemin çizilmez.
  final int secili;

  /// Seçili OLMAYAN segmente dokunulunca (seçiliye dokunuş yok sayılır).
  final ValueChanged<int> onSec;

  /// i. segmentin içeriği.
  final Widget Function(BuildContext context, int i, bool secili) oge;

  /// Segment genişlik payları (`flex`). `null`: eşit.
  final List<int>? paylar;

  /// Kabuğun görsel yüksekliği (dokunma hedefi her durumda ≥ 44 pt).
  final double yukseklik;
  final double icBosluk;

  /// Metnin taban stili; renk/kalınlık bileşen tarafından verilir.
  /// Varsayılan `bodyMedium`.
  final TextStyle? metinStili;

  /// Ekran okuyucu etiketi; verilirse segmentin kendi anlamı dışlanır ve
  /// bu cümle okunur (ör. "1A, +%3,2").
  final String Function(int i)? semantik;

  /// SEÇİLİ segmente dokunulunca (varsayılan: yok sayılır). Ortak seçicinin
  /// "Ortaklar" segmenti seçiliyken de listeyi yeniden açabilmesi için
  /// (`OrtakSecici`, 2026-10-04); öteki segmentlerde verilmez.
  final ValueChanged<int>? onSeciliDokunus;

  /// Seçili/seçisiz metin stili — segment dışı yerlerde de aynı tonda
  /// kalmak için.
  static TextStyle stil(BuildContext context, bool secili,
          {TextStyle? taban}) =>
      (taban ?? context.t.bodyMedium ?? const TextStyle()).copyWith(
        fontWeight: secili ? FontWeight.w600 : FontWeight.w500,
        color: secili ? context.c.amberText : context.c.text36,
      );

  @override
  Widget build(BuildContext context) {
    final pay = paylar ?? List<int>.filled(adet, 1);
    final toplam = pay.fold<int>(0, (a, b) => a + b);
    final gecerli = secili >= 0 && secili < adet && toplam > 0;
    final solPay = gecerli ? pay.take(secili).fold<int>(0, (a, b) => a + b) : 0;

    // Dokunma hedefi GÖRSEL kabuktan bağımsız (tek seçici, 2026-10-08 —
    // yol haritası 2.12). Eskiden düğmeler kabuğun İÇİNDEYDİ: 36pt kabuk −
    // 2×3pt iç boşluk = 30pt hedef; `CupertinoButton.minimumSize` ebeveynin
    // sıkı kısıtını aşamıyor, yani yukarıdaki "44 pt" sözü tutmuyordu ve
    // hiçbir test ölçmüyordu (`touch_target_size_test` kaynak tarar). Şimdi
    // bileşen en az 44pt yer kaplar, görsel kabuk ortada [yukseklik] kadar
    // çizilir, düğmeler tüm yüksekliği alır — Material'in `padded` tap
    // target kuralının aynısı. Bedeli: 36pt'lik kullanımlar yerleşimde 8pt
    // fazla yer tutar (üst/alt 4pt şeffaf pay).
    final boy = yukseklik < SandikTouch.min ? SandikTouch.min : yukseklik;
    final dikeyPay = (boy - yukseklik) / 2;

    return SizedBox(
      height: boy,
      child: LayoutBuilder(builder: (context, kutu) {
        final w = kutu.maxWidth - 2 * icBosluk;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: dikeyPay,
              bottom: dikeyPay,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.c.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                ),
              ),
            ),
            if (gecerli)
              AnimatedPositioned(
                duration: SandikMotion.stateOf(context),
                curve: SandikMotion.move,
                left: icBosluk + w * solPay / toplam,
                width: w * pay[secili] / toplam,
                top: dikeyPay + icBosluk,
                bottom: dikeyPay + icBosluk,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.c.surface2,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: icBosluk),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < adet; i++)
                    Flexible(
                      flex: pay[i],
                      child: _Segment(
                        secili: i == secili,
                        semantik: semantik?.call(i),
                        onTap: () {
                          if (i == secili) {
                            onSeciliDokunus?.call(i);
                            return;
                          }
                          SandikHaptic.selection.perform();
                          onSec(i);
                        },
                        child: AnimatedDefaultTextStyle(
                          duration: SandikMotion.stateOf(context),
                          curve: SandikMotion.enter,
                          style: stil(context, i == secili, taban: metinStili),
                          child: oge(context, i, i == secili),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.secili,
    required this.onTap,
    required this.child,
    this.semantik,
  });

  final bool secili;
  final VoidCallback onTap;
  final Widget child;
  final String? semantik;

  @override
  // `MergeSemantics`: etiket verilmeyen segmentte `CupertinoButton` kendi
  // düğüm(ün)ü açıyordu; "seçili" bayrağı üstteki boş düğümde, metin alttaki
  // düğümde kalıyor, ekran okuyucu "Grafik, düğme" deyip seçili olduğunu
  // söylemiyordu (2026-10-08, `test/sandik_segment_test.dart`). Birleşince
  // etiket + seçili + eylem tek düğümde.
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
          button: true,
          selected: secili,
          label: semantik,
          excludeSemantics: semantik != null,
          // Dokunma eylemi AÇIKÇA: `excludeSemantics` alttaki düğmenin kendi
          // eylemini de siliyor, düğüm okunur ama TalkBack'te etkinleştirilemez
          // (2026-09-29 emülatör testi #28 — aynı tuzak `OrtakSecici`'de
          // düzeltilmişti). Etiket verilmeyince düğmenin eylemi zaten yerinde.
          onTap: semantik != null ? onTap : null,
          child: CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: Container(
              height: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
              child: child,
            ),
          ),
        ),
      );
}
