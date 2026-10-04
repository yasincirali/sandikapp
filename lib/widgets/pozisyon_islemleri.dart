import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../theme/sandik.dart';
import 'dividend_dialog.dart';
import 'quick_adjust_dialog.dart';

/// Bir pozisyona yazılan üç işlem: alış, satış, temettü.
///
/// ## Tek kod yolu (Sadeleştirme 2, madde 6, 2026-10-04)
/// Bu üç işlem yıllarca yalnız Portföy kartını sola kaydırınca bulunuyordu;
/// varlık ekranına sabit bir çubuk eklendi (`varlik_islem_cubugu`
/// bayrağı). İki yüzey AYNI fonksiyonu çağırır ([pozisyonIslemiAc]) ve AYNI
/// listeden ([pozisyonIslemleri]) beslenir — biri "temettüyü fonlara da
/// açalım" diye değişip öteki eski kuralda kalırsa kullanıcı aynı varlıkta
/// iki ayrı davranış görürdü. Kayıt yolu yeni değildir: hızlı alış/satış
/// diyaloğu ve temettü diyaloğu (ikisi de demo kapısını kendi taşır).
enum PozisyonIslemi { al, sat, temettu }

/// Bu varlıkta sunulan işlemler, sırasıyla. Temettü yalnız nakit dağıtan
/// türlerde (`supportsDividend`) — altın/döviz/emtia'da anlamsız.
List<PozisyonIslemi> pozisyonIslemleri(Asset varlik) => [
      PozisyonIslemi.al,
      PozisyonIslemi.sat,
      if (varlik.supportsDividend) PozisyonIslemi.temettu,
    ];

/// İşlemin diyaloğunu açar; diyalog KAPANINCA tamamlanır (kaydırma paneli
/// ancak o zaman kapanır, bkz. `portfolio_screen` `_rowAction`).
///
/// [varlik] kullanıcının KENDİ pozisyonudur (`Position.asDisplayAsset`):
/// ortağın lot'una yazılamaz (RLS), çağıran bunu süzer.
Future<void> pozisyonIslemiAc(
  BuildContext context,
  WidgetRef ref, {
  required Asset varlik,
  required PozisyonIslemi islem,
}) =>
    switch (islem) {
      PozisyonIslemi.al => showQuickAdjustDialog(context, ref,
          asset: varlik, mode: QuickAdjustMode.add),
      PozisyonIslemi.sat => showQuickAdjustDialog(context, ref,
          asset: varlik, mode: QuickAdjustMode.remove),
      PozisyonIslemi.temettu => showDividendDialog(context, asset: varlik),
    };

/// Varlık ekranının altındaki sabit "Al · Sat · Temettü" çubuğu.
///
/// Görünüşü varlık sayfasının "Portföyüme ekle" çubuğunun eşi: aynı zemin,
/// üst kıl çizgisi, 48pt düğmeler, alt güvenli alan payı. Birincil eylem
/// (Al) amber dolgu; Sat ve Temettü çerçeveli — kaydırmadaki yeşil/kırmızı
/// dolgular burada üç büyük renk bloğu olurdu ve sayfanın sakin tonunu
/// bozardı. İkonlar kaydırmadakilerle aynı: iki yüzey aynı işlemi aynı
/// simgeyle tanıtır.
class PozisyonIslemCubugu extends StatelessWidget {
  const PozisyonIslemCubugu({
    super.key,
    required this.islemler,
    required this.onIslem,
  });

  final List<PozisyonIslemi> islemler;
  final ValueChanged<PozisyonIslemi> onIslem;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cocuklar = <Widget>[];
    for (final i in islemler) {
      if (cocuklar.isNotEmpty) {
        cocuklar.add(const SizedBox(width: SandikSpace.sm));
      }
      final (etiket, ikon) = switch (i) {
        PozisyonIslemi.al => (l.buyAction, Icons.trending_up_rounded),
        PozisyonIslemi.sat => (l.sellAction, Icons.trending_down_rounded),
        PozisyonIslemi.temettu => (l.dividend, Icons.savings_outlined),
      };
      cocuklar.add(Expanded(
        child: _Dugme(
          key: ValueKey('pozisyon-islemi-${i.name}'),
          etiket: etiket,
          ikon: ikon,
          birincil: i == PozisyonIslemi.al,
          onPressed: () => onIslem(i),
        ),
      ));
    }
    return Container(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.smd,
        SandikSpace.screenH(context),
        SandikSpace.smd + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.c.hairline)),
      ),
      child: Row(children: cocuklar),
    );
  }
}

class _Dugme extends StatelessWidget {
  const _Dugme({
    super.key,
    required this.etiket,
    required this.ikon,
    required this.birincil,
    required this.onPressed,
  });

  final String etiket;
  final IconData ikon;
  final bool birincil;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Etiket kırpılmaz, küçülür (metin tam okunur kuralı): üç düğme 320pt
    // ekranda ~90pt'ye iner, büyük yazı boyutunda "Temettü" sığmayabilir.
    final icerik = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 18),
          const SizedBox(width: SandikSpace.xs),
          Text(etiket, maxLines: 1),
        ],
      ),
    );
    final sekil = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SandikRadius.md));
    const dolgu = EdgeInsets.symmetric(horizontal: SandikSpace.sm);
    return SizedBox(
      height: 48,
      child: birincil
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: context.c.amberFill,
                foregroundColor: context.c.onAmber,
                padding: dolgu,
                textStyle:
                    context.t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                shape: sekil,
              ),
              child: icerik,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.c.text90,
                side: BorderSide(color: context.c.hairline),
                padding: dolgu,
                textStyle:
                    context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                shape: sekil,
              ),
              child: icerik,
            ),
    );
  }
}
