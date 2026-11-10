import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import '../l10n/l10n.dart';

/// Yasal uyarı — sinyal/analiz içeren her ekranın altına eklenir.
///
/// **Kısa biçim ([kisa]; Ar-Ge 2026-11-07 12:15 #5, yayılım 2026-11-10).**
/// Beş satırlık tam metin her girişte sayfanın sonunu kaplıyordu; Fon
/// karnesindeki dipnot gibi iki kısa cümleye iner ve sağında "Ayrıntı"
/// durur. Tam metin KAYBOLMAZ: aynı [disclaimerText] bir dokunuşla alt
/// sayfada açılır. İlk turda yalnız Performans'taydı; 2026-11-10'da
/// çan sayfası ve varlık ekranlarına da yayıldı (aynı tam metin beş
/// yerde kutuydu). Uzun biçim (varsayılan, birebir eskisi) yalnız sinyal
/// ayarında kalır: orası teknik sinyalin kendisini anlatan ekran.
///
/// Anahtarların `performans_` öneki tarihseldir (testler o adla bulur);
/// artık her kısa ibare aynı anahtarı taşır.
///
/// Kısa satır normal yazıda tek satırdır. Büyük yazıda (metin ölçeği
/// > [_tekSatirOlcegi]) sarmalanır: tek satıra zorlamak yasal cümleyi
/// üç noktayla keserdi; satır sayısı artar ama cümle bütün kalır.
class DisclaimerWidget extends StatelessWidget {
  const DisclaimerWidget({super.key, this.kisa = false});

  /// Tek satır + "Ayrıntı" (sinyal ayarı dışındaki her ekran).
  final bool kisa;

  static const double _tekSatirOlcegi = 1.3;

  /// Tam metnin alt sayfası — "Ayrıntı" ve testler aynı yolu kullanır.
  static Future<void> tamMetniAc(BuildContext context) => showSandikSheet<void>(
        context: context,
        baslik: context.l10n.disclaimerSheetTitle,
        builder: (ctx) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(ctx), 0,
                SandikSpace.screenH(ctx), SandikSpace.lg),
            child: Text(
              ctx.l10n.disclaimerText,
              style: ctx.t.bodyMedium?.copyWith(color: ctx.c.text58),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (kisa) return _kisaBicim(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: context.c.text36),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.disclaimerText,
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                color: context.c.text36,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Çerçevesiz tek satır: kutu ve ikon yok (kısa cümlenin etrafındaki
  /// kutu, içindekinden ağır görünürdü). "Ayrıntı" bir bağlantı: 44 pt
  /// dokunma alanı satırın boyunu belirler, görünen metin küçük kalır.
  Widget _kisaBicim(BuildContext context) {
    final l = context.l10n;
    final tekSatir =
        MediaQuery.textScalerOf(context).scale(1) <= _tekSatirOlcegi;
    final stil = context.t.labelMedium
        ?.copyWith(letterSpacing: 0, color: context.c.text36);
    return Row(
      children: [
        Expanded(
          child: Text(
            l.disclaimerShort,
            key: const ValueKey('performans_dipnot_kisa'),
            maxLines: tekSatir ? 1 : null,
            overflow: tekSatir ? TextOverflow.ellipsis : null,
            style: stil,
          ),
        ),
        const SizedBox(width: SandikSpace.sm),
        Semantics(
          button: true,
          label: l.disclaimerDetails,
          hint: l.disclaimerDetailsHint,
          child: ExcludeSemantics(
            child: CupertinoButton(
              key: const ValueKey('performans_dipnot_ayrinti'),
              minimumSize: SandikTouch.minSize,
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
              onPressed: () => tamMetniAc(context),
              child: Text(
                l.disclaimerDetails,
                style: stil?.copyWith(
                    color: context.c.text58, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
