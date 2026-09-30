import 'package:flutter/cupertino.dart';

import '../l10n/l10n.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sandik_segment.dart';
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
///
/// ## Kayan seçim (animasyon denetimi 2026-10-01)
/// Seçili zemin eskiden her segmentin kendi dolgusuydu: seçim bir
/// segmentten ötekine TEK KAREDE atlıyordu. Artık zemin tek bir katman ve
/// yeni segmentin yerine KAYAR ([SandikMotion.state] + [SandikMotion.move]);
/// göz seçimin nereden nereye geçtiğini izler. Segment genişlikleri
/// `flex` payıyla orantılı olduğu için zeminin yeri aynı paylardan
/// hesaplanır — ölçüm yok, fazladan yerleşim geçişi yok. Hareketi azalt
/// açıkken süre sıfır: zemin anında yerine oturur.
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

    final etiketler = [for (final d in donemler) donemEtiketi(l, d.label)];

    // Kabuk, kayan zemin, dokunma, geçiş: ortak [SandikSegment]
    // (2026-10-01). Burada yalnız dönem içeriği ve getiri satırı kalır.
    return SandikSegment(
      adet: donemler.length,
      secili: secili,
      onSec: onSec,
      paylar: [for (final e in etiketler) pay(e)],
      metinStili: stil,
      // Getirili hâlde ikinci satır için dokunma hedefi kadar yükseklik.
      yukseklik: getiri == null
          ? tekSatirYukseklik
          : SandikTouch.min + SandikSpace.sm,
      semantik: (i) {
        final g = getiri == null || i >= getiri.length ? null : getiri[i];
        return g == null ? etiketler[i] : '${etiketler[i]}, ${fmtPctIsaretli(g)}';
      },
      // Tek FittedBox bütün sütunu küçültür: yedi segmentte dar genişlik ve
      // büyük metin ölçeğinde (x2, x3) iki satır kabuğa sığmayabilir;
      // kırpmak yerine küçülür.
      oge: (context, i, _) {
        final g = getiri == null || i >= getiri.length ? null : getiri[i];
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(etiketler[i], maxLines: 1, softWrap: false),
              if (getiri != null)
                Text(
                  g == null ? ' ' : fmtPctIsaretli(g, digits: 1),
                  maxLines: 1,
                  softWrap: false,
                  style: context.t.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: g == null || donemDuzMu(g)
                        ? context.c.text36
                        : context.signColor(g),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
