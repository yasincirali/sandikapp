import 'package:fl_chart/fl_chart.dart';

import '../models/asset.dart';

/// Bir grafik noktasına düşen alım/satımların özeti.
///
/// [x] grafiğin X birimindedir (gün içinde dakika, diğer dönemlerde kesirli
/// gün — bkz. `_convertHistoryToSegments`). [alim]/[satis] TL tutar.
class IslemNoktasi {
  const IslemNoktasi({
    required this.x,
    this.alim = 0,
    this.satis = 0,
    this.alimSayisi = 0,
    this.satisSayisi = 0,
  });

  final double x;
  final double alim;
  final double satis;
  final int alimSayisi;
  final int satisSayisi;

  /// Alım − satış: noktada portföye giren net para.
  double get net => alim - satis;

  /// Aynı noktada hem alım hem satış var mı? Varsa yüzeyler NET'i yazar.
  bool get karisik => alimSayisi > 0 && satisSayisi > 0;

  int get islemSayisi => alimSayisi + satisSayisi;

  IslemNoktasi _ekle(Asset a) => IslemNoktasi(
        x: x,
        alim: alim + (a.isBuy ? a.totalCostTRY : 0),
        satis: satis + (a.isSell ? a.totalCostTRY : 0),
        alimSayisi: alimSayisi + (a.isBuy ? 1 : 0),
        satisSayisi: satisSayisi + (a.isSell ? 1 : 0),
      );
}

/// Performans grafiğinin işlem noktaları — TEK KAYNAK.
///
/// Nokta işareti, crosshair'ın alım/satım satırı ve hacim çubuğu bu haritadan
/// beslenir; her işlem, motorun onu SERİYE KATTIĞI noktaya bağlanır.
///
/// ## Neden "kapsayan" değil "basamağın göründüğü" nokta (2026-09-24)
/// Kullanıcı: *"Düğüm noktalarından kontrol ettiğimde − ya da + yaratmasına
/// rağmen sıçrama / dik düşüş yaşanmıyor; alım-satım noktaları ile hacim
/// çizgileri timeline'da tam eşleşmeli."*
///
/// Üç yüzey üç ayrı kurala bağlıydı:
///   * İşaret, işlemin GÜNÜNÜ gece yarısına çekip (`dayKey`) o anı kapsayan
///     noktaya (`coveringSpotIndex`, sola yuvarlama) bağlanıyordu.
///   * Crosshair aynı TAKVİM GÜNÜNÜN tüm alım/satımını her noktada
///     yazıyordu — 09:00 çubuğunda 17:08'in satışı görünüyor, çizgi ise
///     düşmüyordu.
///   * Hacim çubuğu günün BAŞINA çiziliyordu.
///
/// Motor ise (`getPortfolioHistoryBreakdownAtResolution`, `signedQtyOnSlot`)
/// lot'u ham damgayla `addedDate <= slotBaşı` olan İLK slota katar: 22 Eyl
/// 17:08'lik satış saatlik seride 18:00, günlük seride 23 Eyl 00:00
/// noktasında düşer. Yani basamak, işaretten bir (günlükte on yedi) nokta
/// sonra çıkıyordu; kullanıcı "+ var ama sıçrama yok" görüyordu. Gün içi
/// motor farklı: lot'u 5 dk'lık kovaya AŞAĞI yuvarlar (`normalizeSlot`),
/// 14:32'lik alım 14:30 noktasındadır.
///
/// Kural şimdi motorla aynı: nokta = X'i işlem anından (gün içinde 5 dk'ya
/// yuvarlanmış anından) büyük veya eşit İLK nokta. Öyle nokta yoksa işlem
/// son noktadan (canlı uç) sonradır ve orada zaten canlı toplamın içindedir.
/// Pencere başından önceki işlem bu dönemin işlemi değildir.
///
/// X ekseni `startDate`'e göre ölçülür — gece yarısına değil. Eski işaret
/// kodu gece yarısını taban alıyordu; `startDate` gün ortasındaysa işaret
/// o kadar kayıyordu.
Map<double, IslemNoktasi> islemNoktalari({
  required List<FlSpot> spots,
  required List<Asset> lotlar,
  required DateTime startDate,
  required bool intraday,
}) {
  final out = <double, IslemNoktasi>{};
  if (spots.isEmpty) return out;
  for (final a in lotlar) {
    if (!a.isActive) continue;
    if (!a.isBuy && !a.isSell) continue;
    final d = a.addedDate;
    final double txX;
    if (intraday) {
      // Gün içi motorun kovası: 5 dakikaya aşağı yuvarla.
      final kova = DateTime(d.year, d.month, d.day, d.hour, d.minute - d.minute % 5);
      txX = kova.difference(startDate).inMilliseconds / 60000.0;
    } else {
      txX = d.difference(startDate).inMilliseconds / (60000.0 * 60 * 24);
    }
    if (txX < spots.first.x) continue;
    var i = _ilkBuyukEsit(spots, txX);
    if (i >= spots.length) i = spots.length - 1;
    final x = spots[i].x;
    out[x] = (out[x] ?? IslemNoktasi(x: x))._ekle(a);
  }
  return out;
}

/// X'e göre SIRALI listede `spot.x >= x` olan İLK indeks (lower bound);
/// hepsi küçükse `spots.length`.
int _ilkBuyukEsit(List<FlSpot> spots, double x) {
  int lo = 0, hi = spots.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (spots[mid].x < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}
