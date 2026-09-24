import 'package:fl_chart/fl_chart.dart';

/// X'e göre SIRALI bir `FlSpot` listesinde en yakın noktayı bulur.
///
/// Crosshair sürüklenirken (`crosshairSnapX` / `crosshairLabelBuilder`) her
/// dokunma karesinde çağrılır. Eskiden tüm listeyi doğrusal tarıyordu:
/// 1 yıllık günlük seride nokta başına 365 karşılaştırma, parmak hareket
/// ettikçe saniyede onlarca kez. İkili arama ile O(n) → O(log n).
///
/// Grafik segment'lerindeki spot'lar X'e göre artan üretilir
/// (`_convertHistoryToSegments` zaman damgalarını sıralayarak gezer), bu
/// yüzden ikili arama güvenlidir.
int nearestSpotIndex(List<FlSpot> spots, double x) {
  if (spots.isEmpty) return -1;
  if (spots.length == 1) return 0;

  // `x`'in ekleneceği konumu bul (lower bound).
  int lo = 0, hi = spots.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (spots[mid].x < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }

  // Aday: bulunan konum ve bir öncesi — hangisi daha yakınsa o.
  final int right = lo;
  final int left = lo > 0 ? lo - 1 : 0;
  final dRight = (spots[right].x - x).abs();
  final dLeft = (spots[left].x - x).abs();
  return dLeft <= dRight ? left : right;
}

/// [nearestSpotIndex]'in nokta döndüren hâli. Liste boşsa null.
FlSpot? nearestSpot(List<FlSpot> spots, double x) {
  final i = nearestSpotIndex(spots, x);
  return i < 0 ? null : spots[i];
}

/// X'e göre SIRALI listede, [x]'i KAPSAYAN spot'un indeksi: `spot.x <= x`
/// olan **son** nokta (yani lower bound'un bir soluna).
///
/// Neden ayrı bir arama: işlem noktalarını çizerken "en yakın" yetmez, doğru
/// olan "hangi bar'ın içine düşüyor" sorusudur. Grafik verisi her zaman gün
/// çözünürlüğünde değil — 6A/1Y periyotlarında `ResolutionTier.weekly` gelir
/// ve tüm noktalar haftanın PAZARTESİSİNE snap edilir. Çarşamba yapılan bir
/// alım hiçbir spot'un günüyle tam eşleşmez; kapsayan bar o haftanın
/// pazartesisidir. "En yakın" kullanılsaydı işlem bir SONRAKİ haftanın
/// noktasına kayabilirdi (çarşamba → cuma'ya 2, gelecek pazartesiye 5 gün;
/// ama perşembe/cuma alımları yanlış tarafa yuvarlanırdı).
///
/// [x]'ten önce hiç nokta yoksa (işlem serinin başlangıcından önce) -1 döner.
int coveringSpotIndex(List<FlSpot> spots, double x) {
  if (spots.isEmpty) return -1;
  if (spots.first.x > x) return -1;

  // `spots[lo].x <= x < spots[lo+1].x` olacak şekilde en büyük lo.
  int lo = 0, hi = spots.length - 1;
  while (lo < hi) {
    // Üst orta nokta: `mid` her zaman lo'dan büyük olur, sonsuz döngü olmaz.
    final mid = (lo + hi + 1) >> 1;
    if (spots[mid].x <= x) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// X'e göre SIRALI listede, düz (eğrisiz) çizginin [x]'teki YÜKSEKLİĞİ:
/// komşu iki nokta arasında doğrusal ara değer. Liste dışındaki [x] uçtaki
/// noktanın değerine yaslanır; liste boşsa null.
///
/// Varlık grafiğinin işlem işaretleri için (2026-09-24): işaret işlemin
/// gerçek ANINDA ama ÇİZGİNİN ÜZERİNDE durur. Çizgi `isCurved: false`
/// çizildiği için doğrusal ara değer noktayı tam çizginin üstüne koyar.
double? cizgiDegeri(List<FlSpot> spots, double x) {
  if (spots.isEmpty) return null;
  if (x <= spots.first.x) return spots.first.y;
  if (x >= spots.last.x) return spots.last.y;
  final i = coveringSpotIndex(spots, x);
  final a = spots[i];
  final b = spots[i + 1];
  final aralik = b.x - a.x;
  if (aralik <= 0) return a.y;
  return a.y + (b.y - a.y) * (x - a.x) / aralik;
}
