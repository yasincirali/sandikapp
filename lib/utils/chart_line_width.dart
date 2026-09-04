/// Çizgi grafiklerin ORTAK kalınlık kuralı.
///
/// ## Neden ortak
/// Kural önce yalnızca performans ekranlarında yaşıyordu ve orada bile üç
/// ayrı kopyası vardı (`portfolio_performance_screen`, `performance_screen`
/// içinde iki yerde). Takip/Karşılaştır grafiği ise dönemden HABERSİZDİ:
/// her dönemde sabit 1,8px (vurgulu seri 3px) çiziyordu. Aynı portföyün aynı
/// dönemi iki ekranda farklı kalınlıkta görünüyordu — kullanıcı bulgusu:
/// "line kalınlıklarını takip grafiğindeki tüm varlıklar için performans
/// ekranındaki gibi zaman aralığına göre değişecek şekilde ayarla."
///
/// Tek fonksiyon = iki ekran birlikte değişir; biri düzelirken öteki geride
/// kalmaz.
library;

/// Dönemin temel çizgi kalınlığı (piksel).
///
/// **Neden dönem uzadıkça incelir.** Nokta yoğunluğu döneme bağlı: gün içi
/// seri 5 dakikalık (bir günde ~288 nokta), 1H saatlik (~168), 1A günlük
/// (~30), 1Y haftalık (~52). Kalın çizgi yoğun seride komşu noktaların
/// arasını doldurur ve zikzağı yutar — çizgi "tarak" gibi görünür. Seyrek
/// seride ise ince çizgi cılız kalır, çünkü doldurulacak bir şey yoktur.
///
/// 1A'nın (2,4px) en kalın olması kasıtlı: nokta sayısı orada en az, çizgi
/// de en çok nefes alan yerde en okunur hâline gelir.
///
/// [periodDays] `<= 1` gün içi demektir. Performans ekranı GÜNLÜK sekmesini
/// `days: 0, intraday: true` ile taşıyor, takip listesi aynı sekmeyi
/// `days: 1` ile — ikisi de bu dala düşer.
double donemCizgiKalinligi(int periodDays) {
  if (periodDays <= 1) return 1.6;
  if (periodDays <= 7) return 2.0;
  if (periodDays <= 30) return 2.4;
  if (periodDays <= 90) return 2.0;
  if (periodDays <= 180) return 1.8;
  return 1.5;
}

/// Kıyas (portföy) çizgisinin diğerlerinden ne kadar kalın olduğu.
///
/// Sabit bir EK, oran değil: oran kullanılsaydı 1Y'de fark 0,75px'e iner ve
/// gözle ayırt edilemezdi. 1px her dönemde görünür bir fark.
const double vurguKalinlikArtisi = 1.0;

/// Odaklanılan serinin ek kalınlığı.
///
/// Odak yalnızca diğerlerini soluklaştırmakla anlatılmamalı: renk körlüğünde
/// ve düşük parlaklıkta opaklık farkı silinir, kalınlık farkı kalır
/// ("Don't convey information by color alone").
const double odakKalinlikArtisi = 0.8;

/// Yüzde karşılaştırma grafiğindeki bir serinin kalınlığı.
///
/// Taban DÖNEMDEN gelir (performans ekranıyla birebir), vurgu ve odak
/// üstüne EKLENİR. Böylece dönem değiştiğinde tüm seriler birlikte incelir
/// ama aralarındaki hiyerarşi (kıyas çizgisi > diğerleri, odaktaki > geri
/// kalan) her dönemde korunur.
double kiyasCizgiKalinligi({
  required int periodDays,
  required bool vurgulu,
  required bool odakta,
}) =>
    donemCizgiKalinligi(periodDays) +
    (vurgulu ? vurguKalinlikArtisi : 0.0) +
    (odakta ? odakKalinlikArtisi : 0.0);
