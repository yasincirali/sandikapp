import 'package:fl_chart/fl_chart.dart';

import '../l10n/generated/app_localizations.dart';
import 'tr_format.dart';

/// Grafiğin GÖRÜNEN aralığının ekran okuyucu özeti (Ar-Ge 6 Kas 22:30).
///
/// Neden: grafik eskiden yalnız "Fiyat grafiği" diye okunuyordu; görmeyen
/// kullanıcı yönü ve aralığı hiç öğrenemiyordu. Özet tam seriden değil
/// görünen pencereden çıkar — yakınlaştırınca okunan şey ekrandakiyle aynı.
class GrafikOzeti {
  const GrafikOzeti({
    required this.degisimYuzde,
    required this.enDusuk,
    required this.enYuksek,
  });

  /// İlk görünen noktadan son görünene yüzde değişim; ilk değer ≤ 0 ise
  /// (portföyün boş başladığı dönem) oran tanımsız → `null`.
  final double? degisimYuzde;
  final double enDusuk;
  final double enYuksek;
}

/// [spots] X'e göre sıralı. [donustur] çizim Y'sini gerçek değere çevirir
/// (log ölçek, `0` tabanlı yüzde serisi → `100 + y`). Görünen pencerede iki
/// noktadan azı varsa özet yok: tek noktanın "yönü" uydurma olurdu.
GrafikOzeti? gorunenAralikOzeti(
  List<FlSpot> spots,
  double minX,
  double maxX, {
  double Function(double y)? donustur,
}) {
  double? ilk;
  double? son;
  var enDusuk = double.infinity;
  var enYuksek = double.negativeInfinity;
  var adet = 0;
  for (final s in spots) {
    if (s.x < minX) continue;
    if (s.x > maxX) break;
    if (s.y.isNaN || s.y.isInfinite) continue;
    final y = donustur == null ? s.y : donustur(s.y);
    ilk ??= y;
    son = y;
    if (y < enDusuk) enDusuk = y;
    if (y > enYuksek) enYuksek = y;
    adet++;
  }
  if (adet < 2 || ilk == null || son == null) return null;
  return GrafikOzeti(
    degisimYuzde: ilk > 0 ? (son / ilk - 1) * 100 : null,
    enDusuk: enDusuk,
    enYuksek: enYuksek,
  );
}

/// "Görünen aralıkta yüzde 4,2 arttı; en düşük ₺X, en yüksek ₺Y".
///
/// [tutar] `null` → yalnız yüzde: bakiye gizliyken tutar okunmaz (Ana ekran
/// kuralı) ve yüzde serilerinde (karşılaştırma) "en düşük" tutar değildir.
/// Yön kelimeyle söylenir, işaretle değil — ekran okuyucu "eksi"yi
/// "tire" diye okuyabiliyor.
String? grafikOzetMetni(
  AppLocalizations l,
  GrafikOzeti? o, {
  String Function(double v)? tutar,
}) {
  if (o == null) return null;
  final parcalar = <String>[];
  final d = o.degisimYuzde;
  if (d != null) {
    final yuzde = fmtNum(d.abs(), digits: 1);
    // 1 haneye yuvarlanınca 0,0 olan değişim "arttı" denmez.
    if (d.abs() < 0.05) {
      parcalar.add(l.chartSummaryFlat);
    } else {
      parcalar.add(d > 0 ? l.chartSummaryUp(yuzde) : l.chartSummaryDown(yuzde));
    }
  }
  if (tutar != null) {
    parcalar.add(l.chartSummaryRange(tutar(o.enDusuk), tutar(o.enYuksek)));
  }
  return parcalar.isEmpty ? null : parcalar.join('; ');
}

/// Karşılaştırma grafiği: "BIST 100: Görünen aralıkta yüzde 4,2 arttı; …".
/// Seriler "dönem başı 0" yüzdesidir; pencere içi oran `100 + y` ile
/// hesaplanır ki yakınlaştırınca dönem başına değil görünen başa göre okunsun.
String? karsilastirmaOzeti(
  AppLocalizations l,
  List<(String ad, List<FlSpot> spots)> seriler,
  double minX,
  double maxX,
) {
  final parcalar = <String>[
    for (final (ad, spots) in seriler)
      if (grafikOzetMetni(l,
              gorunenAralikOzeti(spots, minX, maxX, donustur: (y) => 100 + y))
          case final ozet?)
        l.chartSummarySeries(ad, ozet),
  ];
  return parcalar.isEmpty ? null : parcalar.join('; ');
}
