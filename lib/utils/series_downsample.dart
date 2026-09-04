import 'package:fl_chart/fl_chart.dart';

/// Çizgi grafiğin noktalarını ekranın taşıyabileceği yoğunluğa indirir.
///
/// ## Neden gerekli
/// Gün içi seri 5 dakikalık çözünürlükte gelir: bir günde ~288, bir haftada
/// ~2000 nokta. Telefonda grafiğin çizim alanı ~320px; yani nokta başına bir
/// pikselden az yer düşüyor ve çizgi kendi üstüne binerek okunamaz bir
/// karalamaya dönüşüyor (kullanıcı bulgusu: "üst üste çok basıyor").
///
/// ## Neden ORTALAMA değil, MIN/MAX
/// Naif seyreltme (her n'inci noktayı al) ya da hareketli ortalama, veride
/// GERÇEKTEN olan bir sıçramayı gizleyebilir — fiyat grafiğinde bu, grafiğin
/// yalan söylemesi demektir. Burada her kova için o kovanın **en düşük ve en
/// yüksek** noktası korunur ve X sırasında yayımlanır. Çizginin dış zarfı
/// birebir aynı kalır: tepe ve dipler yerinde durur, yalnızca aralarındaki
/// okunamayan salınım seyrelir.
///
/// İlk ve son nokta her zaman korunur — dönem başı `%0` referansı ve son
/// değer, serinin anlamını taşıyan iki uçtur.
///
/// [hedefNokta] kabaca çizim alanının piksel genişliği kadar verilmelidir.
/// Bu değerin altındaki seriler olduğu gibi döner.
List<FlSpot> seyreltSpots(List<FlSpot> spots, int hedefNokta) {
  if (hedefNokta < 4 || spots.length <= hedefNokta) return spots;

  // Her kova iki nokta (min + max) yayımladığı için kova sayısı hedefin
  // yarısı. Uçlar ayrıca korunuyor.
  final kovaSayisi = hedefNokta ~/ 2;
  final kovaBoyu = spots.length / kovaSayisi;

  final out = <FlSpot>[spots.first];

  for (var k = 0; k < kovaSayisi; k++) {
    final bas = (k * kovaBoyu).floor();
    final son = ((k + 1) * kovaBoyu).floor().clamp(bas, spots.length);
    if (bas >= son) continue;

    var minI = bas;
    var maxI = bas;
    for (var i = bas + 1; i < son; i++) {
      if (spots[i].y < spots[minI].y) minI = i;
      if (spots[i].y > spots[maxI].y) maxI = i;
    }

    // X SIRASINI KORU: aksi halde çizgi zamanda geri sıçrar ve fl_chart
    // ileri-geri giden bir zikzak çizer.
    final ilk = minI < maxI ? minI : maxI;
    final ikinci = minI < maxI ? maxI : minI;

    for (final i in [ilk, if (ikinci != ilk) ikinci]) {
      // Uçlar zaten eklendi/eklenecek; tekrar etme.
      if (i == 0 || i == spots.length - 1) continue;
      out.add(spots[i]);
    }
  }

  out.add(spots.last);
  return out;
}
