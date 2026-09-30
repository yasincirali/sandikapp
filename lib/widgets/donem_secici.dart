import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'donem_istatistik.dart' show donemDuzMu;

/// Uygulamanın TEK dönem seçicisi — Performans, Takip, Karşılaştır, varlık
/// sayfası ve portföy varlık detayı aynı bileşeni çizer.
///
/// ## Neden tek bileşen (kullanıcı kararı, 2026-09-28)
/// "Time interval seçimleri de aynı olmalı, data kaybı olmasın." Önceden
/// üç ayrı görünüş vardı: Performans'ın içerik oranlı bölümlü kabuğu,
/// Takip'in eşit paylı 44pt kopyası, Karşılaştır'ın amber dolgulu şeridi;
/// varlık ekranlarında da getirili dönem çipleri. Grafikte "Performans
/// stili" seçildiği için (GrafikStili) seçicide de Performans'ın kabuğu
/// esas alındı.
///
/// ## Getiri satırı — veri kaybı yok
/// Varlık ekranlarının çipleri her dönemin getirisini etiketin altında
/// gösteriyordu ("son bir yılda ne yaptı" dokunmadan okunuyordu). O satır
/// [getiriler] ile bu kabuğun içinde yaşamaya devam eder; verilmezse
/// (Performans, Takip, Karşılaştır) segment tek satırdır.
///
/// ## Neden içerik ORANI (Performans'tan taşınan karar, 2026-09-15)
/// Eşit pay (`Expanded`) 390pt'de altı harfli "GÜNLÜK"ü kırpıyordu
/// ("GÜNLÜ"); içerik genişliğinde kabuk ise üstteki satırlardan dar kalıp
/// asimetrik boşluk bırakıyordu. Kabuk satırı doldurur, pay her segmentin
/// ÖLÇÜLEN metin genişliğinden türetilir. Yedi dönemle 320pt'de toplam
/// pay satıra sığmayabilir: etiket o zaman kırpılmaz, `FittedBox` ile
/// küçülür.
class DonemSecici extends StatelessWidget {
  const DonemSecici({
    super.key,
    required this.donemler,
    required this.secili,
    required this.onSec,
    this.getiriler,
  });

  /// Gösterilecek dönemler — [SummaryPeriod.values] ya da (elle fiyatlanan
  /// varlıkta GÜNLÜK'süz) bir alt kümesi. Başka liste yazılmaz.
  final List<SummaryPeriod> donemler;

  /// [donemler] içindeki seçili indeks.
  final int secili;

  final ValueChanged<int> onSec;

  /// Verilirse her segmentin altında o dönemin getirisi (yüzde). `null`
  /// eleman → henüz yok; satır boş yer tutar, yerleşim zıplamaz.
  final List<double?>? getiriler;

  /// Kabuğun tek satırlı yüksekliği (Performans'ın 2026-09-15 ölçüsü).
  static const double tekSatirYukseklik = 36;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stil = context.t.bodyMedium;
    // Seçili segment w600 çizilir; ölçüm en GENİŞ hâlle yapılır ki seçim
    // değiştikçe segmentler yatay zıplamasın.
    final olcumStili = stil?.copyWith(fontWeight: FontWeight.w600);
    final olcek = MediaQuery.textScalerOf(context);
    final yon = Directionality.of(context);
    final getiri = getiriler;

    int pay(String etiket) {
      final tp = TextPainter(
        text: TextSpan(text: etiket, style: olcumStili),
        textDirection: yon,
        textScaler: olcek,
      )..layout();
      // + iki yandan 10pt: segmentin kendi nefes payı.
      return ((tp.width + 2 * SandikSpace.sm2) * 100).round();
    }

    return Container(
      // Getirili hâlde ikinci satır için dokunma hedefi kadar yükseklik.
      height: getiri == null ? tekSatirYukseklik : SandikTouch.min + SandikSpace.sm,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(donemler.length, (i) {
          final etiket = donemEtiketi(l, donemler[i].label);
          final seciliMi = i == secili;
          final g = getiri == null || i >= getiri.length ? null : getiri[i];
          return Flexible(
            flex: pay(etiket),
            child: Semantics(
              button: true,
              selected: seciliMi,
              label: g == null ? etiket : '$etiket, ${fmtPctIsaretli(g)}',
              excludeSemantics: true,
              child: CupertinoButton(
                minimumSize: SandikTouch.minSize,
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (seciliMi) return;
                  SandikHaptic.selection.perform();
                  onSec(i);
                },
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: seciliMi ? context.c.surface2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  // Tek FittedBox bütün sütunu küçültür: yedi segmentte
                  // dar genişlik ve büyük metin ölçeğinde (x2, x3) iki
                  // satır kabuğa sığmayabilir; kırpmak yerine küçülür.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          etiket,
                          maxLines: 1,
                          softWrap: false,
                          style: stil?.copyWith(
                            fontWeight:
                                seciliMi ? FontWeight.w600 : FontWeight.w500,
                            color: seciliMi
                                ? context.c.amberText
                                : context.c.text36,
                          ),
                        ),
                        if (getiri != null)
                          Text(
                            g == null
                                ? ' '
                                : fmtPctIsaretli(g, digits: 1),
                            maxLines: 1,
                            softWrap: false,
                            style: context.t.labelSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: g == null || donemDuzMu(g)
                                  ? context.c.text36
                                  : context.signColor(g),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
