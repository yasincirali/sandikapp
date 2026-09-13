/// Grafik serisini çizilebilir nokta sayısına indirger (LTTB).
///
/// ## Neden gerekli
/// Dakikalık barlar açıldığında seri hacmi bir mertebe büyüyor: `1m` + `5d`
/// ölçüldüğünde 2526 nokta geldi (2026-09-13, THYAO.IS), `5m` + `1mo` ise
/// 2342. `fl_chart` bu yoğunlukta her pan/pinch karesinde binlerce segment
/// çizmeye çalışır ve kare düşürür — üstelik 400px genişlikte ekranda
/// noktaların çoğu zaten aynı piksele düşüyor, yani harcanan iş GÖRÜNMÜYOR.
///
/// ## Neden ortalama/atlama değil, LTTB
/// En basit iki yöntem de grafiği YANILTIR:
///   · **n'de bir atlama** — zirveleri ve dipleri rastgele ıskalar; kullanıcı
///     gerçekten olmuş bir sıçramayı hiç görmez.
///   · **bucket ortalaması** — uçları törpüler; volatil bir gün, sakin bir
///     güne benzer. Fiyat grafiğinde bu doğrudan yanlış bilgi.
///
/// LTTB (Largest-Triangle-Three-Buckets, Steinarsson 2013) her bucket'tan
/// SİLUETİ en iyi koruyan gerçek noktayı seçer: sentetik değer ÜRETMEZ,
/// döndürülen her nokta girdide fiilen vardır. Zirve ve dipler korunur.
/// Zaman serisi görselleştirmesinde fiilî standart (Grafana, Highcharts).
library;

/// [noktalar] serisini en fazla [hedef] noktaya indirger.
///
/// Girdi zamana göre SIRALI olmalı — çağıran (`ts → değer` map'inden
/// üretenler) bunu zaten yapıyor. Sıralı değilse çıktı anlamsızlaşır ama
/// çökmez.
///
/// [hedef] < 3 ise ya da seri zaten yeterince kısaysa girdi AYNEN döner
/// (kopya bile oluşturulmaz).
///
/// İlk ve son nokta HER ZAMAN korunur: grafiğin başı ve sonu dönem
/// sınırlarına oturmak zorunda, aksi halde eksen etiketleriyle veri ayrışır.
List<(int, double)> lttb(List<(int, double)> noktalar, int hedef) {
  final n = noktalar.length;
  if (hedef >= n || hedef < 3 || n < 3) return noktalar;

  final out = <(int, double)>[noktalar.first];

  // Uçlar sabit olduğu için aradaki (hedef - 2) noktaya bucket bölünür.
  final bucketBoyu = (n - 2) / (hedef - 2);
  var oncekiIdx = 0;

  for (var i = 0; i < hedef - 2; i++) {
    // Bu bucket'ın sınırları.
    final basla = (i * bucketBoyu).floor() + 1;
    var bitir = ((i + 1) * bucketBoyu).floor() + 1;
    if (bitir > n - 1) bitir = n - 1;

    // SONRAKİ bucket'ın ortalaması — üçgenin üçüncü köşesi.
    final sonrakiBasla = bitir;
    var sonrakiBitir = ((i + 2) * bucketBoyu).floor() + 1;
    if (sonrakiBitir > n) sonrakiBitir = n;

    var ortX = 0.0;
    var ortY = 0.0;
    var sayi = 0;
    for (var j = sonrakiBasla; j < sonrakiBitir; j++) {
      ortX += noktalar[j].$1.toDouble();
      ortY += noktalar[j].$2;
      sayi++;
    }
    if (sayi == 0) {
      // Son bucket boş kalabilir; son noktayı referans al.
      ortX = noktalar[n - 1].$1.toDouble();
      ortY = noktalar[n - 1].$2;
    } else {
      ortX /= sayi;
      ortY /= sayi;
    }

    final oncekiX = noktalar[oncekiIdx].$1.toDouble();
    final oncekiY = noktalar[oncekiIdx].$2;

    // Bucket içinde (önceki, aday, sonraki-ortalama) üçgeninin ALANI en
    // büyük olan aday kazanır — siluete en çok katkı veren nokta odur.
    var enIyiAlan = -1.0;
    var enIyiIdx = basla;
    for (var j = basla; j < bitir; j++) {
      final alan = ((oncekiX - ortX) * (noktalar[j].$2 - oncekiY) -
              (oncekiX - noktalar[j].$1.toDouble()) * (ortY - oncekiY))
          .abs();
      if (alan > enIyiAlan) {
        enIyiAlan = alan;
        enIyiIdx = j;
      }
    }

    out.add(noktalar[enIyiIdx]);
    oncekiIdx = enIyiIdx;
  }

  out.add(noktalar.last);
  return out;
}

/// Ekran genişliğine göre makul hedef nokta sayısı.
///
/// Bir noktayı iki pikselden sık çizmenin görsel karşılığı yok — 400px'lik
/// bir grafikte 2500 nokta, piksel başına altı nokta demek. Üst sınır 300,
/// `pickForSpan`'in zaten benimsediği ~30-300 aralığının tavanı.
int hedefNoktaSayisi(double genislikPx) {
  final yarim = (genislikPx / 2).round();
  if (yarim < 60) return 60;
  if (yarim > 300) return 300;
  return yarim;
}
