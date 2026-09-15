import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Grafik kartının köşesindeki "tam ekran" ikon çipi.
///
/// Performans ve tekil varlık ekranlarında birer kopyası vardı
/// (`_PortfolioFullscreenChip` / `_FullscreenChip`); tek fark kenarlık
/// rengiydi ve o da bilinçli bir ayrım değil, kopyanın sürüklenmesiydi.
/// Tek widget: `hairline` kenarlık (daha yeni olan sürüm).
class ChartFullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const ChartFullscreenChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // `Semantics(container: true)` ŞART — çip KENDİ düğümü olmalı.
    //
    // `Tooltip` + `InkWell` yapılandırması (ipucu + dokunma) tek başına bir
    // semantik sınırı değil; Flutter bunu, çakışan eylem/bayrak taşıyan bir
    // kardeş yoksa en yakın ata düğüme BİRLEŞTİRİR. 2026-09-15'e kadar
    // dönem satırında yanında `onTap`'lı grafik tipi seçici duruyordu ve o
    // çakışma çipi istemeden kendi düğümü yapıyordu. Seçici grafik kartının
    // dibine inince çakışma kalktı, çip ata düğüme karıştı ve beş dönem
    // düğmesi ekran okuyucuya "Grafiği tam ekran aç" kabının çocuğu olarak
    // duyuruldu (emülatör UI ağacında görüldü). Sınır çipin içinde: hangi
    // satıra konursa konsun komşusuna bağımlı olmasın.
    return Semantics(
      container: true,
      child: Tooltip(
      message: context.l10n.fullscreenChart,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        // Görsel kabuk 32pt, dokunma hedefi 44pt (HIG #37): şeffaf dolgu
        // hedefi büyütür, kabuk küçük kalır — dönem satırındaki grafik tipi
        // ikonuyla aynı sınıf denetim gibi görünsün diye.
        child: SizedBox(
          width: SandikTouch.min,
          height: SandikTouch.min,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: context.c.hairline),
              ),
              child: Icon(
                Icons.fullscreen_rounded,
                size: 16,
                color: context.c.text58,
              ),
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
