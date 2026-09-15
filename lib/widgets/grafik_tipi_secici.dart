import 'package:flutter/material.dart';

import '../models/grafik_tipi.dart';
import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Grafik tipi seçici — açılır menü; üç görünümü var ([GrafikTipiGorunum]).
///
/// 2026-09-15: grafik kartının DİBİNE indi (`duz` görünüm). Kullanıcı
/// bildirimi: "çizgi göstergesi grafiğin dibinde olmalı" ve "butonu
/// bulunduğu layera uygun olmalı" — kartın içinde kabuklu çip yabancı
/// duruyordu.
///
/// Kullanıcı isteği (2026-09-12): TradingView'deki gibi bir liste; seçili
/// olanın yanında tik, seçim oturum boyunca korunuyor.
///
/// ## Neden `PopupMenuButton`, bottom sheet değil
/// Liste dört kısa satır ve chip'in hemen altında açılması konumsal
/// bağlamı koruyor. Bottom sheet ekranın yarısını kaplar ve grafikle
/// bağı kopar — kullanıcı seçtiği tipin etkisini göremeden sayfa örtülür.
class GrafikTipiSecici extends StatelessWidget {
  const GrafikTipiSecici({super.key, this.gorunum = GrafikTipiGorunum.cip});

  final GrafikTipiGorunum gorunum;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GrafikTipi>(
      valueListenable: grafikTipiNotifier,
      builder: (context, secili, _) {
        // `Material` ZORUNLU ve POPUP'IN DIŞINDA olmalı.
        //
        // Bu ekran `CupertinoPageScaffold` altında çiziliyor;
        // `PopupMenuButton`'ın KENDİ `InkWell`'i bir Material ata arıyor
        // ve bulamayınca `debugCheckHasMaterial` fırlatıyor. Sarmalayıcıyı
        // butonun İÇİNE koymak yetmedi — ölçüldü, hata aynen sürdü:
        // kontrol butonun kendi bağlamında yapılıyor.
        //
        // Bozulma sessiz değildi ama yanıltıcıydı: ağaç kırılınca boş
        // durum metni hiç render edilmiyor ve RenderFlex 98.674px
        // taşıyordu (20 test birden kırılmıştı).
        return Material(
          type: MaterialType.transparency,
          child: PopupMenuButton<GrafikTipi>(
          tooltip: context.l10n.chartTypeTooltip,
          position: PopupMenuPosition.under,
          color: context.c.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            side: BorderSide(color: context.c.hairline),
          ),
          onSelected: (t) => grafikTipiNotifier.value = t,
          itemBuilder: (_) => [
            for (final t in GrafikTipi.values)
              PopupMenuItem<GrafikTipi>(
                value: t,
                height: 48,
                child: Row(
                  children: [
                    Icon(t.ikon, size: 18, color: context.c.text58),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.etiket,
                        style: context.t.bodyMedium?.copyWith(
                          color: context.c.text90,
                          fontWeight: t == secili
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    // Tik YALNIZCA seçilide. Yer her zaman ayrılıyor ki
                    // satırlar seçim değiştikçe yatay kaymasın.
                    SizedBox(
                      width: 20,
                      child: t == secili
                          ? Icon(Icons.check_rounded,
                              size: 16, color: context.c.amberText)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
          child: switch (gorunum) {
            // Görsel kabuk 32pt, dokunma hedefi 44pt (HIG #37): şeffaf
            // dolgu hedefi büyütür. `PopupMenuButton`'ın kendi alanı
            // child'ın boyutunu alıyor, bu yüzden burada açıkça verilir.
            GrafikTipiGorunum.ikon => SizedBox(
                width: SandikTouch.min,
                height: SandikTouch.min,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.c.surface2,
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      border: Border.all(color: context.c.hairline),
                    ),
                    child:
                        Icon(secili.ikon, size: 16, color: context.c.text58),
                  ),
                ),
              ),
            // Kabuksuz: kartın içinde ikinci bir yüzey açmaz; ton ve punto
            // eksen etiketleriyle aynı sınıftan. Dokunma hedefi yine 44pt.
            GrafikTipiGorunum.duz => ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(secili.ikon, size: 15, color: context.c.text58),
                      const SizedBox(width: SandikSpace.xs),
                      Text(
                        secili.etiket,
                        style: context.t.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text58,
                        ),
                      ),
                      const SizedBox(width: SandikSpace.xxs),
                      Icon(Icons.expand_more_rounded,
                          size: 15, color: context.c.text36),
                    ],
                  ),
                ),
              ),
            GrafikTipiGorunum.cip => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.c.surface2,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(color: context.c.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(secili.ikon, size: 15, color: context.c.text58),
                    const SizedBox(width: SandikSpace.xs),
                    Text(
                      secili.etiket,
                      style: context.t.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text58,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded,
                        size: 15, color: context.c.text36),
                  ],
                ),
              ),
          },
        ),
        );
      },
    );
  }
}

/// Seçicinin görünümleri.
enum GrafikTipiGorunum {
  /// İkon + etiket + ok, surface2 kabuklu çip — bağımsız kullanım ve
  /// testlerin varsayılanı.
  cip,

  /// Yalnız ikon, 32pt kabuk. 2026-09-15'e kadar dönem satırının sağ ucu
  /// böyleydi; ikon seçili tipe göre değiştiği için durumu söylüyordu.
  ikon,

  /// Kabuksuz: ikon + etiket + ok, eksen etiketleriyle aynı tonda. Grafik
  /// kartının İÇİNDE kullanılır — kartın kendisi zaten bir yüzey.
  duz,
}
