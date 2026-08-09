import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';

/// Portföy hareketleri listesindeki tek satır.
///
/// `home_screen.dart` içinde private bir metottu; Riverpod + Supabase + auth
/// gerektirdiği için widget testiyle pump edilemiyordu ve taşma testi ağacın
/// yapısal kopyasını doğrulamak zorunda kalıyordu (kopya bayatlarsa test
/// yeşil kalırken uygulama taşar). Artık saf widget: veriyi parametre olarak
/// alır, provider okumaz — çağıran taraf okur.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.asset,
    required this.portfolioState,
    this.hideBalance = false,
  });

  final Asset asset;
  final PortfolioState portfolioState;
  final bool hideBalance;

  @override
  Widget build(BuildContext context) {
    // Portföy ekranındaki varlık kartlarıyla birebir tutar gösterimi için
    // 3 ondalıklı format (tryFmt3 ile aynı biçim).
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 3);
    final bool isSell = asset.isSell;
    final bool isDelete = asset.isDeleteLog;
    final bool isDividend = asset.isDividend;

    final unitPrice = asset.isSell
        ? (asset.sellPrice ?? asset.currentPrice)
        : asset.purchasePrice;
    // Temettüde miktar 0'dır; tutar `dividendAmount` alanında taşınır.
    final txValue =
        isDividend ? asset.dividendAmount : asset.quantity * unitPrice;
    final txValueTRY = portfolioState.toTRY(txValue, asset.currency);

    final Color accent = isDelete
        ? context.c.text58
        : (isSell ? context.c.loss : (isDividend ? context.c.amberText : context.c.gain));
    final IconData kindIcon = isDelete
        ? Icons.delete_outline_rounded
        : (isSell
            ? Icons.remove_rounded
            : (isDividend
                ? Icons.savings_outlined
                : Icons.add_rounded));
    final String kindLabel = isDelete
        ? 'Silindi'
        : (isSell ? 'Çıkarıldı' : (isDividend ? 'Temettü' : 'Eklendi'));
    final String sign = isSell || isDelete ? '−' : '+';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.7), width: 3),
            ),
          ),
          child: Row(
            // İkon, metin bloğu ve tutar kolonu ortak eksende hizalansın.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              asset.currencySymbol != null
                  ? Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: asset.type.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SandikRadius.sm),
                      ),
                      child: Center(
                        child: Text(
                          asset.currencySymbol!,
                          style: GoogleFonts.dmSans(
                            fontSize: asset.currencySymbol!.length > 1 ? 9 : 13,
                            fontWeight: FontWeight.w800,
                            color: asset.type.color,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : Icon(asset.type.icon, color: asset.type.color, size: 22),
              const SizedBox(width: SandikSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // Satır yüksekliği içeriğe göre belirlensin. Varsayılan
                  // `MainAxisSize.max` bu Column'u satırın (sağ kolonun
                  // belirlediği) yüksekliğine zorluyordu; iki satırlık fon
                  // başlığı + rozet satırı buna sığmayınca 3.9px taşıyordu.
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fon/hisse: başlık olarak yalnızca KOD (THYAO).
                    //
                    // Önceden kod bir rozette, tam ad da altında ayrı
                    // satırdaydı; uzun fon adları (45 karaktere kadar)
                    // satırı taşırıyordu. Artık kod başlığın kendisi —
                    // hem tekrar yok hem de tek satır garanti.
                    // Tam ad, varlığın detay ekranında görünür.
                    Text(
                        asset.showTicker ? asset.displayTicker! : asset.name,
                        maxLines: asset.showTicker ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight:
                                asset.showTicker ? FontWeight.w700 : FontWeight.w600,
                            height: 1.25,
                            letterSpacing: asset.showTicker ? 0.2 : null,
                            color: context.c.text90)),
                    const SizedBox(height: SandikSpace.xs),
                    // Rozet satırı dar ekranda yatayda taşıyordu (320pt'de
                    // 161px). `Wrap` sığmayanı alt satıra alır — kırpmak
                    // yerine sarmak, tarih ve miktar okunur kalsın.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: SandikSpace.sm,
                      runSpacing: SandikSpace.xs,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: asset.type.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                          child: Text(asset.type.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: asset.type.color,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          DateFormat('d MMM yyyy', 'tr_TR')
                              .format(asset.addedDate),
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text36),
                        ),
                        // Temettüde miktar 0'dır — "0 adet" rozeti anlamsız
                        // olurdu, o yüzden yalnızca miktarlı işlemlerde göster.
                        if (!isDividend)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.c.overlay,
                              borderRadius:
                                  BorderRadius.circular(SandikRadius.sm),
                            ),
                            child: Text(
                              asset.unitIsPrefix
                                  ? '${asset.unitLabel}${NumberFormat('#,##0.####', 'tr_TR').format(asset.quantity)}'
                                  : '${NumberFormat('#,##0.####', 'tr_TR').format(asset.quantity)} ${asset.unitLabel}',
                              style: context.t.labelMedium?.copyWith(
                                  letterSpacing: 0,
                                  color: context.c.text58,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              // Sağ kolon sabit genişlikte: sınırsız bırakılırsa genişliği
              // en uzun tutar belirler ve soldaki isim alanını yer. Sabit
              // tutmak hem bunu önler hem tüm satırların sağ kenarını
              // hizalar. Sığmayan tutar kırpılmaz, FittedBox ile küçülür.
              SizedBox(
                width: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(SandikRadius.sm),
                      ),
                      // Rozet 116pt'lik kolona sığmalı. "Eklendi" sığıyordu
                      // ama "Çıkarıldı" 19px taşıyordu — etiket uzunluğu
                      // işlem türüne göre değişiyor. FittedBox sığmayanı
                      // kırpmadan küçültür.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(kindIcon, size: 11, color: accent),
                            const SizedBox(width: SandikSpace.xs),
                            Text(kindLabel,
                                style: context.t.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                    color: accent)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: SandikSpace.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        hideBalance
                            ? '$sign₺••••'
                            : '$sign${tryFmt.format(txValueTRY)}',
                        maxLines: 1,
                        // İşlem tutarı — alt alta listelenir, tabular figür.
                        style: context.t.numSmall.copyWith(
                            fontSize: 15,
                            color: isDelete
                                ? context.c.text58
                                : (isSell ? context.c.loss : context.c.text90)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

}
